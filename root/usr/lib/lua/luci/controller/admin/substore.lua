-- controller/admin/substore.lua — LuCI 路由注册（Lua 兼容模式）

module("luci.controller.admin.substore", package.seeall)

local function back_to_list()
	local http = require("luci.http")
	http.redirect(luci.dispatcher.build_url("admin", "services", "substore", "list"))
end

function index()
	entry({"admin", "services", "substore"}, alias("admin", "services", "substore", "list"), nil)
	entry({"admin", "services", "substore", "list"}, template("substore/subscriptions"), _("Subscriptions"), 10)
	entry({"admin", "services", "substore", "form"}, template("substore/form"), nil)
	entry({"admin", "services", "substore", "nodes"}, template("substore/nodes"), nil)
	entry({"admin", "services", "substore", "output"}, template("substore/output"), nil)
	entry({"admin", "services", "substore", "create"}, call("action_create"), nil)
	entry({"admin", "services", "substore", "save"}, call("action_save"), nil)
	entry({"admin", "services", "substore", "delete"}, call("action_delete"), nil)
	entry({"admin", "services", "substore", "update"}, call("action_update"), nil)
	-- 公开订阅下载端点（无登录态，靠随机 token 访问控制），供 Passwall/OpenClash 等客户端拉取
	entry({"substore", "download"}, call("action_download"), nil)
end

local function post_ok()
	-- 拒绝缺失 CSRF token 的 POST
	local http = require("luci.http")
	return http.formvalue("token") ~= nil
end

-- 从表单读取按订阅的定时更新字段，校验 cron 表达式（防注入），返回 cron_enable, cron_time
local function read_cron_fields()
	local http = require("luci.http")
	local core = require("substore.core")
	local cron_enable = http.formvalue("cron_enable") or "0"
	local m = http.formvalue("cron_min") or "0"
	local h = http.formvalue("cron_hour") or "3"
	local dom = http.formvalue("cron_dom") or "*"
	local mon = http.formvalue("cron_mon") or "*"
	local dow = http.formvalue("cron_dow") or "*"
	local cron_time = table.concat({m,h,dom,mon,dow}, " ")
	if not core.cron_time_valid(cron_time) then
		cron_enable = "0"
		cron_time = ""
	end
	if cron_enable ~= "1" then cron_enable = "0" end
	return cron_enable, cron_time
end

-- 从表单读取订阅级规则字段，返回规则表
local function read_rules_fields()
	local http = require("luci.http")
	local proto_list = {}
	for _, p in ipairs({"vmess","vless","trojan","shadowsocks","hysteria2","tuic"}) do
		if http.formvalue("proto_filter_"..p) then proto_list[#proto_list+1]=p end
	end
	local rules_enable = http.formvalue("rules_enable") or "0"
	if rules_enable ~= "1" then rules_enable = "0" end
	return {
		rules_enable = rules_enable,
		proto_filter = table.concat(proto_list, ","),
		keyword_include = http.formvalue("keyword_include") or "",
		keyword_exclude = http.formvalue("keyword_exclude") or "",
		dedup = http.formvalue("dedup") or "0",
		rename_map = http.formvalue("rename_map") or "",
	}
end

function action_create()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local url = (http.formvalue("url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" and url ~= "" then
			local cron_enable, cron_time = read_cron_fields()
			local rules = read_rules_fields()
			core.add(name, url, {
				cron_enable = cron_enable, cron_time = cron_time,
				rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
				keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
				dedup = rules.dedup, rename_map = rules.rename_map,
			})
			core.write_cron()
		end
	end
	back_to_list()
end

function action_save()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = http.formvalue("id") or ""
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local url = (http.formvalue("url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" and url ~= "" then
			local cron_enable, cron_time = read_cron_fields()
			local rules = read_rules_fields()
			core.save_meta(id, {
				name = name, url = url,
				cron_enable = cron_enable, cron_time = cron_time,
				rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
				keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
				dedup = rules.dedup, rename_map = rules.rename_map,
			})
			core.write_cron()
		end
	end
	back_to_list()
end

function action_delete()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		core.remove(http.formvalue("id") or "")
		core.write_cron()
	end
	back_to_list()
end

function action_update()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = http.formvalue("id") or ""
		-- pcall 兜底：解析/写入异常不会让 LuCI 页面 500，错误落库后在列表页状态列展示
		local ok, err = pcall(function()
			return core.sync(id)
		end)
		if not ok then
			core.save_meta(id, { error = tostring(err), last_update = os.time() })
		end
	end
	back_to_list()
end

-- 公开下载端点：GET /substore/download?token=<token>&target=<format>
function action_download()
	local http = require("luci.http")
	local core = require("substore.core")
	local util = require("substore.util")
	local token = util.trim(http.formvalue("token") or "")
	local target = util.trim(http.formvalue("target") or "ClashMeta")

	local content, ct, filename, err = core.generate_link(token, target)
	if not content then
		http.status(404, "Not Found")
		http.prepare_content("text/plain; charset=utf-8")
		http.write(err or "not found")
		return
	end

	http.prepare_content(ct)
	-- 文件名白名单：剥离引号/换行/控制字符，防 HTTP 头注入
	local safe_name = (filename or "subscription.txt"):gsub("[^%w%-%._]", "_")
	http.header("Content-Disposition",
		"attachment; filename=\"" .. safe_name .. "\"")
	http.write(content)
end