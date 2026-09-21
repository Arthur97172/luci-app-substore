-- parser.lua — 订阅格式解析 → 统一节点模型（纯 Lua）
-- luci-app-substore

local util = require("substore.util")
local node = require("substore.node")

local M = {}

local SUPPORTED = { vmess = true, vless = true, trojan = true, ss = true }

local function split_lines(content)
	local out = {}
	for line in content:gmatch("[^\r\n]+") do
		out[#out + 1] = line
	end
	return out
end

-- 检测订阅格式：uri / base64 / json / empty / unknown
function M.detect(content)
	content = util.trim(content or "")
	if content == "" then return "empty" end
	local stripped = content:gsub("%s+", "")
	if stripped:sub(1, 1) == "{" then return "json" end
	if stripped:find("vmess://", 1, true) or stripped:find("vless://", 1, true)
		or stripped:find("trojan://", 1, true) or stripped:find("ss://", 1, true)
		or content:find("://", 1, true) then
		return "uri"
	end
	if stripped:match("^[A-Za-z0-9%+/]+=*$") and #stripped > 10 then
		return "base64"
	end
	return "unknown"
end

-- ---------- 协议解析 ----------
local function parse_ss(body)
	-- ss:// 兼容多种变体：base64(method:password@host:port)、method:password@host:port、
	-- base64(method:password)@host:port；可选 ?plugin=、#name
	local fragment, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		fragment = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	if hp == "" then return nil, "bad ss" end

	local userinfo, hostport
	local at = hp:find("@", 1, true)
	if at then
		userinfo, hostport = hp:sub(1, at - 1), hp:sub(at + 1)
	else
		-- 整体可能是 base64(method:password@host:port)
		local decoded = util.base64_decode(hp)
		local d = decoded:find("@", 1, true)
		if d then
			userinfo, hostport = decoded:sub(1, d - 1), decoded:sub(d + 1)
		else
			return nil, "bad ss (no @)"
		end
	end
	-- userinfo 可能是 base64(method:password)
	if not userinfo:find(":", 1, true) then
		userinfo = util.base64_decode(userinfo) or ""
	end
	local method, password = userinfo:match("^([^:]+):(.*)$")
	local host, port = util.split_hostport(hostport)
	if not (method and password and host) then return nil, "bad ss" end
	local name = fragment ~= "" and fragment or (host .. ":" .. tostring(port or ""))
	local out = node.normalize({
		proto = "shadowsocks", name = name, server = host, port = tonumber(port),
		method = method, password = password, raw = ("ss://" .. body),
	})
	if query.plugin then out.plugin = query.plugin end
	return out
end

local function parse_vless(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	local at = hp:find("@", 1, true)
	if not at then return nil, "bad vless" end
	local uuid = hp:sub(1, at - 1)
	local host, port = util.split_hostport(hp:sub(at + 1))
	local out = node.normalize({
		proto = "vless", name = name, server = host, port = tonumber(port), uuid = uuid, raw = uri,
	})
	if query.type then out.net = query.type end
	if query.security then out.security = query.security end
	if query.sni then out.sni = query.sni end
	if query.fp then out.fp = query.fp end
	if query.alpn then out.alpn = query.alpn end
	if query.headerType then out.headerType = query.headerType end
	return out
end

local function parse_trojan(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	local at = hp:find("@", 1, true)
	if not at then return nil, "bad trojan" end
	local password = hp:sub(1, at - 1)
	local host, port = util.split_hostport(hp:sub(at + 1))
	local out = node.normalize({
		proto = "trojan", name = name, server = host, port = tonumber(port),
		password = password, raw = uri,
	})
	if query.sni then out.sni = query.sni end
	if query.security then out.security = query.security end
	if query.alpn then out.alpn = query.alpn end
	return out
end

local function parse_vmess(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	-- v2rayN 新格式：vmess://uuid@host:port?type=tcp&security=none#name
	if rest:find("@", 1, true) then
		local query = {}
		local qpos = rest:find("?", 1, true)
		local hp = rest
		if qpos then
			hp = rest:sub(1, qpos - 1)
			for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
				query[k] = util.url_decode(v)
			end
		end
		local at = hp:find("@", 1, true)
		local uuid = hp:sub(1, at - 1)
		local host, port = util.split_hostport(hp:sub(at + 1))
		local out = node.normalize({
			proto = "vmess", name = name, server = host, port = tonumber(port),
			uuid = uuid, raw = uri,
		})
		if query.type then out.net = query.type end
		if query.security then out.security = query.security end
		if query.sni then out.sni = query.sni end
		return out
	end
	-- 经典格式：vmess://base64(json)
	local decoded = util.base64_decode(rest)
	if decoded == "" then return nil, "bad vmess b64" end
	local j = util.json_decode(decoded)
	if type(j) ~= "table" or not j.add then return nil, "bad vmess json" end
	local out = node.normalize({
		proto = "vmess",
		name = j.ps or (j.add .. ":" .. tostring(j.port)),
		server = j.add, port = tonumber(j.port),
		uuid = j.id, aid = tonumber(j.aid),
		net = j.net, type = j.type, security = j.scy or j.security, tls = j.tls,
		raw = uri,
	})
	return out
end

-- 解析单条节点 URI，返回节点表或 nil, err
function M.parse_uri(uri)
	uri = util.trim(uri)
	local proto, body = uri:match("^([%w]+)://(.*)$")
	if not proto then return nil, "no scheme" end
	proto = proto:lower()
	if not SUPPORTED[proto] then return nil, "unsupported proto " .. proto end
	if proto == "ss" then return parse_ss(body) end
	if proto == "vless" then return parse_vless(uri, body) end
	if proto == "trojan" then return parse_trojan(uri, body) end
	if proto == "vmess" then return parse_vmess(uri, body) end
	return nil, "unsupported"
end

local function parse_lines(lines)
	local nodes = {}
	for _, line in ipairs(lines) do
		line = util.trim(line)
		if line ~= "" and line:find("://", 1, true) then
			local n = M.parse_uri(line)
			if n then nodes[#nodes + 1] = n end
		end
	end
	return nodes
end

local function parse_json_content(content)
	local data = util.json_decode(content)
	if type(data) ~= "table" then return nil, "JSON 解析失败" end
	local list
	if data[1] then list = data else list = { data } end
	local nodes = {}
	for _, o in ipairs(list) do
		if type(o) == "table" and o.server and o.port then
			nodes[#nodes + 1] = node.normalize({
				proto = o.proto or "vmess",
				name = o.name or (o.server .. ":" .. o.port),
				server = o.server, port = tonumber(o.port),
				uuid = o.uuid, password = o.password, method = o.method,
				net = o.net, security = o.security, sni = o.sni,
				raw = o.raw,
			})
		end
	end
	return nodes
end

-- 解析订阅内容，返回 { nodes = {...}, format = "..." } 或 nil, err
function M.parse(content)
	if not content or content == "" then return { nodes = {}, format = "empty" } end
	local format = M.detect(content)
	if format == "uri" then
		return { nodes = parse_lines(split_lines(content)), format = "uri" }
	elseif format == "base64" then
		local decoded = util.base64_decode(content)
		if decoded == "" then return nil, "Base64 解码失败" end
		return { nodes = parse_lines(split_lines(decoded)), format = "base64" }
	elseif format == "json" then
		local nodes, err = parse_json_content(content)
		if not nodes then return nil, err end
		return { nodes = nodes, format = "json" }
	end
	return nil, "无法识别的订阅格式"
end

return M