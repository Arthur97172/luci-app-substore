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

-- 过滤：支持 proto、keyword（name/server）、server、port
function M.filter(nodes, opts)
	opts = opts or {}
	local out = {}
	for _, n in ipairs(nodes) do
		if opts.proto and n.proto ~= opts.proto then
		else
			local ok = true
			if opts.keyword and opts.keyword ~= "" then
				local kw = opts.keyword:lower()
				if not ( (n.name or ""):lower():find(kw, 1, true) or (n.server or ""):lower():find(kw, 1, true) ) then
					ok = false
				end
			end
			if ok and opts.server and n.server ~= opts.server then ok = false end
			if ok and opts.port and tonumber(n.port) ~= tonumber(opts.port) then ok = false end
			if ok then out[#out + 1] = n end
		end
	end
	return out
end

-- 去重：按 proto+server+port 唯一
function M.dedup(nodes)
	local seen = {}
	local out = {}
	for _, n in ipairs(nodes) do
		local key = (n.proto or "") .. "|" .. (n.server or "") .. "|" .. tostring(n.port or "")
		if not seen[key] then
			seen[key] = true
			out[#out + 1] = n
		end
	end
	return out
end

-- 排序：by = "name"|"server"|"proto"|"port"
function M.sort(nodes, by, desc)
	by = by or "name"
	desc = desc and true or false
	table.sort(nodes, function(a, b)
		local av = a[by] or ""
		local bv = b[by] or ""
		if by == "port" then av, bv = tonumber(av) or 0, tonumber(bv) or 0 end
		if av == bv then return false end
		if desc then return av > bv else return av < bv end
	end)
	return nodes
end

-- 重命名单个节点
function M.rename(node, new_name)
	if type(node) == "table" and new_name then
		node.name = new_name
	end
	return node
end

return M