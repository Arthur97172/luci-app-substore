-- model/cbi/substore/settings.lua — 订阅设置（阶段 0 占位）

local m = Map("substore", "Subscriptions", "Airport subscription manager (Sub-Store like).")

local s = m:section(NamedSection, "settings", "settings", "Global settings")
local enabled = s:option(Flag, "enabled", "Enable", "Enable subscription management.")

return m