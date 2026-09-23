-- parser_json_config.lua — JSON 配置解析 → 统一节点模型（纯 Lua）
-- luci-app-substore
-- 支持 Sing-box、V2Ray、Clash JSON 配置解析（Lua 5.1 兼容，无 goto）

local util = require("substore.util")
local node = require("substore.node")

local M = {}

-- 协议映射
local proto_map = {
	vmess = "vmess",
	vless = "vless",
	trojan = "trojan",
	shadowsocks = "shadowsocks",
	ss = "shadowsocks",
}

local SUPPORTED = { vmess = true, vless = true, trojan = true, shadowsocks = true }

-- ---------- Sing-box JSON 解析 ----------
function M.parse_singbox_json(content)
	if not content or content == "" then return {} end

	local data = util.json_decode(content)
	if type(data) ~= "table" then return {} end

	local nodes = {}
	local outbounds = data.outbounds or {}

	for _, outbound in ipairs(outbounds) do
		if type(outbound) == "table" then
			local proto = proto_map[outbound.type] or outbound.type
			if proto and SUPPORTED[proto] then
				local server = outbound.server
				local port = outbound.server_port
				if server and port then
					local node_data = {
						proto = proto,
						name = outbound.tag or (server .. ":" .. tostring(port)),
						server = server,
						port = tonumber(port),
					}

					if proto == "vmess" or proto == "vless" then
						node_data.uuid = outbound.uuid
						if outbound.flow then node_data.flow = outbound.flow end
					elseif proto == "trojan" then
						node_data.password = outbound.password
					elseif proto == "shadowsocks" then
						node_data.method = outbound.method
						node_data.password = outbound.password
					end

					if outbound.tls and type(outbound.tls) == "table" then
						if outbound.tls.server_name then
							node_data.sni = outbound.tls.server_name
						end
						if outbound.tls.enabled ~= nil then
							node_data.tls = outbound.tls.enabled
						end
					end

					if outbound.security then
						node_data.security = outbound.security
					end
					if outbound.network then
						node_data.net = outbound.network
					end

					nodes[#nodes + 1] = node.normalize(node_data)
				end
			end
		end
	end

	return nodes
end

-- ---------- V2Ray JSON 解析 ----------
function M.parse_v2ray_json(content)
	if not content or content == "" then return {} end

	local data = util.json_decode(content)
	if type(data) ~= "table" then return {} end

	local nodes = {}
	local outbounds = data.outbounds or {}

	for _, outbound in ipairs(outbounds) do
		if type(outbound) == "table" then
			local proto = proto_map[outbound.protocol] or outbound.protocol
			if proto and SUPPORTED[proto] then
				local settings = outbound.settings
				if type(settings) == "table" then
					local server, port, uuid, password, method, flow

					if proto == "vmess" or proto == "vless" then
						local vnext = settings.vnext
						if type(vnext) == "table" and #vnext > 0 then
							local sc = vnext[1]
							server = sc.address
							port = sc.port
							if type(sc.users) == "table" and #sc.users > 0 then
								local user = sc.users[1]
								uuid = user.id
								if user.flow then flow = user.flow end
							end
						end
					elseif proto == "trojan" then
						local servers = settings.servers
						if type(servers) == "table" and #servers > 0 then
							server = servers[1].address
							port = servers[1].port
							password = servers[1].password
						end
					elseif proto == "shadowsocks" then
						local servers = settings.servers
						if type(servers) == "table" and #servers > 0 then
							server = servers[1].address
							port = servers[1].port
							method = servers[1].method
							password = servers[1].password
						end
					end

					if server and port then
						local node_data = {
							proto = proto,
							name = outbound.tag or (server .. ":" .. tostring(port)),
							server = server,
							port = tonumber(port),
							uuid = uuid,
							password = password,
							method = method,
							flow = flow,
						}

						local ss2 = outbound.streamSettings
						if type(ss2) == "table" then
							if ss2.network then node_data.net = ss2.network end
							if ss2.security then node_data.security = ss2.security end
							if ss2.tlsSettings and type(ss2.tlsSettings) == "table" then
								if ss2.tlsSettings.serverName then node_data.sni = ss2.tlsSettings.serverName end
							end
							if ss2.realitySettings and type(ss2.realitySettings) == "table" then
								if ss2.realitySettings.serverName then node_data.sni = ss2.realitySettings.serverName end
							end
						end

						nodes[#nodes + 1] = node.normalize(node_data)
					end
				end
			end
		end
	end

	return nodes
end

-- ---------- Clash JSON 解析 ----------
function M.parse_clash_json(content)
	if not content or content == "" then return {} end

	local data = util.json_decode(content)
	if type(data) ~= "table" then return {} end

	local nodes = {}
	local proxies = data.proxies or {}

	for _, proxy in ipairs(proxies) do
		if type(proxy) == "table" then
			local proto = proto_map[proxy.type] or proxy.type
			if proto and SUPPORTED[proto] then
				local server = proxy.server
				local port = proxy.port
				if server and port then
					local node_data = {
						proto = proto,
						name = proxy.name or (server .. ":" .. tostring(port)),
						server = server,
						port = tonumber(port),
					}

					if proto == "vmess" or proto == "vless" then
						node_data.uuid = proxy.uuid
						if proxy.alterId then node_data.alterId = tonumber(proxy.alterId) end
					elseif proto == "trojan" then
						node_data.password = proxy.password
					elseif proto == "shadowsocks" then
						node_data.method = proxy.cipher or proxy.method
						node_data.password = proxy.password
					end

					if proxy.network then node_data.net = proxy.network end
					if proxy.sni then
						node_data.sni = proxy.sni
					elseif proxy.servername then
						node_data.sni = proxy.servername
					end
					if proxy.tls then node_data.tls = proxy.tls end

					nodes[#nodes + 1] = node.normalize(node_data)
				end
			end
		end
	end

	return nodes
end

return M