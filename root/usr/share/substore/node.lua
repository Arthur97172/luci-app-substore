-- node.lua — 统一节点模型（纯 Lua）
-- luci-app-substore

local M = {}

M.PROTOS = {
	"vmess", "vless", "trojan", "shadowsocks", "hysteria2", "tuic", "hysteria", "wireguard", "socks",
}

-- 协议默认值，用于补全缺省字段
local DEFAULTS = {
	vmess = { net = "tcp", security = "none" },
	vless = { net = "tcp", security = "none" },
	trojan = { security = "tls" },
}

-- 归一化：协议别名统一、补默认值、保证 name 非空
function M.normalize(node)
	if type(node) ~= "table" then return node end
	if node.proto == "ss" then node.proto = "shadowsocks" end
	local d = DEFAULTS[node.proto] or {}
	for k, v in pairs(d) do
		if node[k] == nil then node[k] = v end
	end
	if node.name == nil or node.name == "" then
		node.name = (node.server or "") .. ":" .. tostring(node.port or "")
	end
	return node
end

return M