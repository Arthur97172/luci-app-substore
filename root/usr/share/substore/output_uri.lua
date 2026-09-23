-- output_uri.lua — 分享链接（URI）输出：Shadowrocket / V2Ray URI（纯 Lua）
-- luci-app-substore
-- 生成 vmess:// / vless:// / trojan:// / ss:// / hysteria2:// / tuic:// / ssr:// 分享链接

local util = require("substore.util")

local M = {}

-- URL 编码：保留字母数字 - . _ ~，其余转 %XX
local function url_encode(s)
	s = tostring(s or "")
	return (s:gsub("([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

-- 生成单节点分享链接；无法生成时返回 nil
function M.to_share_uri(n)
	if type(n) ~= "table" or not n.server or not n.port then return nil end
	local server = n.server
	local port = tonumber(n.port) or 0
	local name = url_encode(n.name or (server .. ":" .. tostring(port)))
	local proto = (n.proto or ""):lower()

	if proto == "ss" then proto = "shadowsocks" end

	if proto == "shadowsocks" then
		local method = n.method or n.cipher or "aes-256-gcm"
		local password = n.password or ""
		local userinfo = util.base64_encode(method .. ":" .. password)
		return "ss://" .. userinfo .. "@" .. server .. ":" .. tostring(port) .. "#" .. name
	end

	if proto == "vmess" then
		local json = {
			v = "2",
			ps = n.name or (server .. ":" .. tostring(port)),
			add = server,
			port = tostring(port),
			id = n.uuid or "",
			aid = tostring(n.alterId or n.aid or 0),
			scy = n.security or "auto",
			net = n.net or n.network or "tcp",
			type = n.type or n.headerType or "none",
			host = n.host or "",
			path = n.path or "",
			tls = (n.tls and n.tls ~= "none" and n.tls ~= false) and "tls" or "",
		}
		return "vmess://" .. util.base64_encode(util.json_encode(json))
	end

	if proto == "vless" then
		local q = {}
		q[#q + 1] = "encryption=none"
		q[#q + 1] = "type=" .. url_encode(n.net or n.network or "tcp")
		q[#q + 1] = "security=" .. url_encode(n.security or "none")
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		if n.fp then q[#q + 1] = "fp=" .. url_encode(n.fp) end
		if n.alpn then
			local alpn = type(n.alpn) == "table" and table.concat(n.alpn, ",") or n.alpn
			q[#q + 1] = "alpn=" .. url_encode(alpn)
		end
		if n.path then q[#q + 1] = "path=" .. url_encode(n.path) end
		if n.host then q[#q + 1] = "host=" .. url_encode(n.host) end
		if n.flow then q[#q + 1] = "flow=" .. url_encode(n.flow) end
		return "vless://" .. (n.uuid or "") .. "@" .. server .. ":" .. tostring(port)
			.. "?" .. table.concat(q, "&") .. "#" .. name
	end

	if proto == "trojan" then
		local q = {}
		q[#q + 1] = "security=" .. url_encode(n.security or "tls")
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		if n.alpn then q[#q + 1] = "alpn=" .. url_encode(n.alpn) end
		if n.fp then q[#q + 1] = "fp=" .. url_encode(n.fp) end
		return "trojan://" .. url_encode(n.password or "") .. "@" .. server .. ":" .. tostring(port)
			.. "?" .. table.concat(q, "&") .. "#" .. name
	end

	if proto == "hysteria2" or proto == "hysteria" then
		local q = {}
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		if n.insecure ~= nil then q[#q + 1] = "insecure=" .. tostring(n.insecure) end
		local suffix = #q > 0 and ("?" .. table.concat(q, "&")) or ""
		return (proto == "hysteria2" and "hysteria2://" or "hysteria://")
			.. url_encode(n.password or "") .. "@" .. server .. ":" .. tostring(port)
			.. suffix .. "#" .. name
	end

	if proto == "tuic" then
		local userinfo = (n.uuid or "") .. ":" .. url_encode(n.password or "")
		local q = {}
		if n.congestion_control then q[#q + 1] = "congestion_control=" .. url_encode(n.congestion_control) end
		if n.alpn then q[#q + 1] = "alpn=" .. url_encode(n.alpn) end
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		local suffix = #q > 0 and ("?" .. table.concat(q, "&")) or ""
		return "tuic://" .. userinfo .. "@" .. server .. ":" .. tostring(port)
			.. suffix .. "#" .. name
	end

	if proto == "socks5" or proto == "socks" then
		local userinfo = ""
		if n.username then userinfo = url_encode(n.username)
			if n.password then userinfo = userinfo .. ":" .. url_encode(n.password) end
			userinfo = userinfo .. "@"
		end
		return "socks5://" .. userinfo .. server .. ":" .. tostring(port) .. "#" .. name
	end

	return nil
end

-- 生成 URI 列表（每行一条，丢弃无法生成 URI 的节点）
function M.to_uri_list(nodes)
	local out = {}
	for _, n in ipairs(nodes or {}) do
		local u = M.to_share_uri(n)
		if u then out[#out + 1] = u end
	end
	return table.concat(out, "\n")
end

-- Shadowrocket 订阅：base64 编码的 URI 列表
function M.to_shadowrocket(nodes)
	return util.base64_encode(M.to_uri_list(nodes))
end

-- V2Ray URI 订阅：明文 URI 列表
function M.to_v2ray_uri(nodes)
	return M.to_uri_list(nodes)
end

return M