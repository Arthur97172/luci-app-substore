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
		uci:set("substore", "settings", "cron_enable", http.formvalue("cron_enable") or "0")
		uci:set("substore", "settings", "cron_time", http.formvalue("cron_time") or "0 3 * * *")
		uci:set("substore", "default", "proto_filter", http.formvalue("proto_filter") or "")
		uci:set("substore", "default", "keyword_include", http.formvalue("keyword_include") or "")
		uci:set("substore", "default", "keyword_exclude", http.formvalue("keyword_exclude") or "")
		uci:set("substore", "default", "dedup", http.formvalue("dedup") or "0")
		uci:set("substore", "default", "rename_map", http.formvalue("rename_map") or "")
		uci:commit("substore")
		-- Regenerate cron file
		local enable = uci:get("substore", "settings", "cron_enable")
		local time = uci:get("substore", "settings", "cron_time")
		if enable == "1" and time and time ~= "" then
			os.execute("cat > /etc/cron.d/substore <<CRON\n# luci-app-substore cron\n$time root /usr/bin/substore-cron.sh >/tmp/substore-cron.log 2>&1\nCRON")
		else
			os.execute("rm -f /etc/cron.d/substore")
		end
	end
	http.redirect(luci.dispatcher.build_url("admin", "services", "substore", "settings"))
end