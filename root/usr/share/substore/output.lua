-- output.lua — 订阅输出生成（Clash YAML / Base64 / JSON）
-- luci-app-substore

local util = require("substore.util")
local node = require("substore.node")

local M = {}

local function esc_yaml(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n")
	if s:find("[ :#{}[\],&*?|>'\"%@`]", 1, true) or s:match("^[-?]*:") then
		return '"' .. s .. '"'
	end
	return s
end

function M.to_clash_yaml(nodes)
	local out = {}
	out[#out + 1] = "proxies:"
	for _, n in ipairs(nodes) do
		local proto = n.proto or "vmess"
		local name = esc_yaml(n.name or "")
		out[#out + 1] = "- name: " .. name
		out[#out + 1] = "  type: " .. proto
		out[#out + 1] = "  server: " .. esc_yaml(n.server or "")
		out[#out + 1] = "  port: " .. tostring(n.port or 0)
		if n.uuid then out[#out + 1] = "  uuid: " .. esc_yaml(n.uuid) end
		if n.password then out[#out + 1] = "  password: " .. esc_yaml(n.password) end
		if n.method then out[#out + 1] = "  cipher: " .. esc_yaml(n.method) end
		if n.net then out[#out + 1] = "  network: " .. esc_yaml(n.net) end
		if n.security then out[#out + 1] = "  tls: " .. tostring(n.security ~= "none") end
		if n.sni then out[#out + 1] = "  sni: " .. esc_yaml(n.sni) end
	end
	out[#out + 1] = ""
	out[#out + 1] = "proxy-groups:"
	out[#out + 1] = "- name: ALL"
	out[#out + 1] = "  type: select"
	out[#out + 1] = "  proxies: [REJECT]"
	return table.concat(out, "\n")
end

function M.to_json(nodes)
	return util.json_encode(nodes)
end

function M.to_base64(nodes)
	local yaml = M.to_clash_yaml(nodes)
	return util.base64_encode(yaml)
end

function M.generate(nodes, format)
	format = (format or "clash")
	if type(format) ~= "string" then format = "clash" end
	format = format:lower()
	if format == "clash" or format == "yaml" then
		return M.to_clash_yaml(nodes)
	elseif format == "json" then
		return M.to_json(nodes)
	elseif format == "base64" then
		return M.to_base64(nodes)
	else
		return nil, "unsupported format"
	end
end

return M