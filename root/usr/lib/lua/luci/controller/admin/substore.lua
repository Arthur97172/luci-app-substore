-- controller/admin/substore.lua — LuCI 路由注册（Lua 兼容模式）

module("luci.controller.admin.substore", package.seeall)

function index()
    entry({"admin", "services", "substore"}, alias("admin", "services", "substore", "settings"), _("Subscriptions"), 60)
    entry({"admin", "services", "substore", "settings"}, cbi("substore/settings"), _("Subscriptions"), 10)
    entry({"admin", "services", "substore", "status"}, template("substore/status"), _("Status"), 20)
end