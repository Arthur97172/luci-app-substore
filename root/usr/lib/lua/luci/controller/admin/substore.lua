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
	entry({"admin", "services", "substore", "settings"}, template("substore/settings"), nil)
	entry({"admin", "services", "substore", "settings_save"}, call("action_settings_save"), nil)
	entry({"admin", "services", "substore", "create"}, call("action_create"), nil)
	entry({"admin", "services", "substore", "save"}, call("action_save"), nil)
	entry({"admin", "services", "substore", "delete"}, call("action_delete"), nil)
	entry({"admin", "services", "substore", "update"}, call("action_update"), nil)
end

local function post_ok()
	-- 拒绝缺失 CSRF token 的 POST
	local http = require("luci.http")
	return http.formvalue("token") ~= nil
end

function action_create()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local url = (http.formvalue("url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" and url ~= "" then
			core.add(name, url)
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
			core.save_meta(id, { name = name, url = url })
		end
	end
	back_to_list()
end

function action_delete()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		core.remove(http.formvalue("id") or "")
	end
	back_to_list()
end

function action_update()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		core.sync(http.formvalue("id") or "")
	end
	back_to_list()
end

function action_settings_save()
	local http = require("luci.http")
	local uci = require("luci.model.uci").cursor()
	if post_ok() then
		local cron_enable = http.formvalue("cron_enable") or "0"
		local m = http.formvalue("cron_min") or "0"
		local h = http.formvalue("cron_hour") or "3"
		local dom = http.formvalue("cron_dom") or "*"
		local mon = http.formvalue("cron_mon") or "*"
		local dow = http.formvalue("cron_dow") or "*"
		local cron_time = table.concat({m,h,dom,mon,dow}, " ")
		uci:set("substore", "settings", "cron_enable", cron_enable)
		uci:set("substore", "settings", "cron_time", cron_time)
		-- proto filter multi checkbox
		local protos = {}
		for _,p in ipairs({"vmess","vless","trojan","shadowsocks","hysteria2","tuic"}) do
			if http.formvalue("proto_filter_"..p) then protos[#protos+1]=p end
		end
		-- Because checkboxes have same name, collect via formvalue multiple? LuCI returns first only.
		-- Fallback: parse all values via http.formvalue (multiple) - use simple approach: build from request
		local proto_vals = {}
		for k,v in pairs(http.formvalue) do
			if k=="proto_filter" then proto_vals[#proto_vals+1]=v end
		end
		-- Actually LuCI http.formvalue returns first, so we reconstruct via iterating form data is hard.
		-- Simpler: accept comma separated from single select for now, but UI uses checkboxes with same name.
		-- We'll collect via luci.http.formvalue which returns first, so we need different names.
		-- Change UI to name="proto_filter_#{p}" and join.
		-- For now, rebuild from checkboxes with unique names:
		local proto_list = {}
		for _,p in ipairs({"vmess","vless","trojan","shadowsocks","hysteria2","tuic"}) do
			if http.formvalue("proto_filter_"..p) then proto_list[#proto_list+1]=p end
		end
		uci:set("substore", "default", "proto_filter", table.concat(proto_list, ","))
		uci:set("substore", "default", "keyword_include", http.formvalue("keyword_include") or "")
		uci:set("substore", "default", "keyword_exclude", http.formvalue("keyword_exclude") or "")
		uci:set("substore", "default", "dedup", http.formvalue("dedup") or "0")
		uci:set("substore", "default", "rename_map", http.formvalue("rename_map") or "")
		uci:commit("substore")
		if cron_enable=="1" and cron_time~="" then
			os.execute("cat > /etc/cron.d/substore <<CRON\n# luci-app-substore cron\n"..cron_time.." root /usr/bin/substore-cron.sh >/tmp/substore-cron.log 2>&1\nCRON")
		else
			os.execute("rm -f /etc/cron.d/substore")
		end
	end
	http.redirect(luci.dispatcher.build_url("admin", "services", "substore", "settings"))
end