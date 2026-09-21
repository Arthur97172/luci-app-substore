-- http.lua — 订阅下载（SSRF 防护、超时、大小限制）（纯 Lua）
-- luci-app-substore

local util = require("substore.util")

local M = {}

M.DEFAULT_MAX_SIZE = 10 * 1024 * 1024 -- 10MB
M.DEFAULT_TIMEOUT = 20
M.MAX_REDIRECTS = 4

-- ---------- 私网 / 保留地址判断 ----------
local function is_private_ipv4(ip)
	local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if not (a and b and c and d) then return true end
	if a == 0 then return true end
	if a == 10 then return true end
	if a == 127 then return true end
	if a == 100 and b >= 64 and b <= 127 then return true end -- 100.64/10 CGNAT
	if a == 169 and b == 254 then return true end            -- link-local
	if a == 172 and b >= 16 and b <= 31 then return true end  -- 172.16/12
	if a == 192 and b == 168 then return true end             -- 192.168/16
	if a >= 224 then return true end                          -- multicast + reserved
	return false
end

local function is_private_ipv6(ip)
	if ip == "::" or ip == "::1" then return true end
	local l = ip:lower()
	if l:match("^0*:") and not l:match("^0*::?0*$") and l ~= "0" then return true end
	if l:sub(1, 2) == "fc" or l:sub(1, 2) == "fd" then return true end -- ULA fc00/7
	local ll = l:sub(1, 4)
	if ll == "fe80" or ll == "fe81" or ll == "fe82" or ll == "fe83"
		or ll == "fe84" or ll == "fe85" or ll == "fe86" or ll == "fe87"
		or ll == "fe88" or ll == "fe89" or ll == "fe8a" or ll == "fe8b"
		or ll == "fe8c" or ll == "fe8d" or ll == "fe8e" or ll == "fe8f"
		or ll == "fe90" or ll == "fe91" or ll == "fe92" or ll == "fe93"
		or ll == "fe94" or ll == "fe95" or ll == "fe96" or ll == "fe97"
		or ll == "fe98" or ll == "fe99" or ll == "fe9a" or ll == "fe9b"
		or ll == "fe9c" or ll == "fe9d" or ll == "fe9e" or ll == "fe9f"
		or ll == "fea0" or ll == "fea1" or ll == "fea2" or ll == "fea3"
		or ll == "fea4" or ll == "fea5" or ll == "fea6" or ll == "fea7"
		or ll == "fea8" or ll == "fea9" or ll == "feaa" or ll == "feab"
		or ll == "feac" or ll == "fead" or ll == "feae" or ll == "feaf"
		or ll == "feb0" or ll == "feb1" or ll == "feb2" or ll == "feb3"
		or ll == "feb4" or ll == "feb5" or ll == "feb6" or ll == "feb7"
		or ll == "feb8" or ll == "feb9" or ll == "feba" or ll == "febb"
		or ll == "febc" or ll == "febd" or ll == "febe" or ll == "febf" then
		return true -- link-local fe80::/10
	end
	if l:sub(1, 2) == "ff" then return true end -- multicast
	return false
end

local function is_private(ip)
	ip = ip or ""
	if ip:find(":", 1, true) then return is_private_ipv6(ip) end
	return is_private_ipv4(ip)
end

-- ---------- URL 解析 ----------
function M.parse_url(url)
	url = util.trim(url or "")
	local scheme, rest = url:match("^([%w%+%-%.]+)://(.*)$")
	if not scheme then return nil, "无效 URL" end
	scheme = scheme:lower()
	if scheme ~= "http" and scheme ~= "https" then return nil, "仅支持 http/https" end
	local hostport = rest:gsub("/.*$", "")
	local host, port
	if hostport:sub(1, 1) == "[" then
		local close = hostport:find("]", 1, true)
		if not close then return nil, "无效主机名" end
		host = hostport:sub(2, close - 1)
		port = hostport:sub(close + 1):match("^:(%d+)$") or (scheme == "https" and "443" or "80")
	else
		local h, p = hostport:match("^([^:]+):(%d+)$")
		if h then
			host, port = h, p
		else
			host, port = hostport, (scheme == "https" and "443" or "80")
		end
	end
	if not host or host == "" then return nil, "无效主机名" end
	return { scheme = scheme, host = host, port = port }
end

-- 解析主机 → IP 列表；无法解析时返回 nil
local function resolve(host)
	local nixio = util.try_require("nixio")
	if not nixio then return nil end
	local ok, addrs = pcall(function() return nixio.getaddrinfo(host) end)
	if not ok or type(addrs) ~= "table" then return nil end
	local ips = {}
	for _, a in ipairs(addrs) do
		if a and a.addr then ips[#ips + 1] = a.addr end
	end
	if #ips == 0 then return nil end
	return ips
end

-- SSRF 预检：拒绝 localhost / 私网 / 保留地址。返回 ok, reason
function M.check_public(host)
	host = util.trim(host or "")
	if host == "" then return false, "空主机名" end
	if host:match("^%d+%.%d+%.%d+%.%d+$") or host:find(":", 1, true) then
		if is_private(host) then return false, "目标为内网/保留地址" end
		return true
	end
	if host:lower() == "localhost" then return false, "目标为 localhost" end
	local ips = resolve(host)
	if not ips then
		-- 无 DNS 解析能力：放行，交由下载工具处理（尽力而为）
		return true
	end
	for _, ip in ipairs(ips) do
		if not is_private(ip) then return true end
	end
	return false, "目标仅解析到内网/保留地址"
end

-- ---------- 下载 ----------
local function have(cmd)
	return os.execute("command -v " .. cmd .. " >/dev/null 2>&1") == 0
end

local function detect_tool()
	if have("curl") then return "curl" end
	if have("wget") then return "wget" end
	return nil
end

local function location_from_headers(path)
	local raw = util.read_file(path)
	if not raw then return nil end
	for line in raw:gmatch("[^\r\n]+") do
		local v = line:match("^%s*[Ll]ocation:%s*(.+)$")
		if v then return util.trim(v) end
	end
	return nil
end

local function resolve_url(base, loc)
	if loc:find("://", 1, true) then return loc end
	local scheme, host = base:match("^([%w]+)://([^/]+)")
	if not scheme then return loc end
	if loc:sub(1, 1) == "/" then return scheme .. "://" .. host .. loc end
	local base_path = base:match("^[%w]+://[^/]+(.*)$") or "/"
	local dir = base_path:match("^(.*)/[^/]*$") or ""
	return scheme .. "://" .. host .. dir .. "/" .. loc
end

local function fetch_curl(url, parsed, opts)
	local max, t = opts.max_size, opts.timeout
	local cur = url
	for redirect = 0, M.MAX_REDIRECTS do
		local tmp = "/tmp/substore_dl_" .. redirect .. ".tmp"
		local hdr = tmp .. ".hdr"
		local errf = tmp .. ".err"
		os.remove(tmp); os.remove(hdr); os.remove(errf)
		local cmd = string.format(
			"curl -sS -o %q --max-time %d --connect-timeout %d --max-redirs 0 --max-filesize %d -D %q -w \"%%{http_code}\" %q 2>%q",
			tmp, t, math.min(t, 10), max, hdr, cur, errf)
		local p = io.popen(cmd)
		local code = p and p:read("*a") or ""
		if p then p:close() end
		code = util.trim(code)
		if code == "" or code == "000" then
			return nil, util.trim(util.read_file(errf) or "下载失败")
		end
		if code:match("^[23]%d%d$") then
			local size = util.file_size(tmp)
			if size > max then return nil, "响应超过大小限制 (" .. max .. " 字节)" end
			local content = util.read_file(tmp)
			os.remove(tmp); os.remove(hdr); os.remove(errf)
			if not content then return nil, "读取响应失败" end
			return content
		end
		if code:match("^3%d%d$") then
			local loc = location_from_headers(hdr)
			if not loc then return nil, "重定向无 Location" end
			local next_url = resolve_url(cur, loc)
			local np = M.parse_url(next_url)
			if not np then return nil, "重定向目标无效" end
			local ok, re = M.check_public(np.host)
			if not ok then return nil, "重定向目标不安全: " .. (re or "") end
			cur = next_url
		else
			return nil, "HTTP 错误 " .. code
		end
	end
	return nil, "重定向次数过多"
end

local function fetch_wget(url, parsed, opts)
	local max, t = opts.max_size, opts.timeout
	local tmp = "/tmp/substore_dl_wget.tmp"
	os.remove(tmp)
	local cmd = string.format("wget -q -T %d -O %q %q 2>/dev/null", t, tmp, url)
	os.execute(cmd)
	local size = util.file_size(tmp)
	if size > max then os.remove(tmp); return nil, "响应超过大小限制 (" .. max .. " 字节)" end
	if size == 0 then os.remove(tmp); return nil, "下载失败或内容为空" end
	local content = util.read_file(tmp)
	os.remove(tmp)
	if not content then return nil, "读取响应失败" end
	return content
end

local function fetch(tool, url, parsed, opts)
	if tool == "curl" then return fetch_curl(url, parsed, opts) end
	return fetch_wget(url, parsed, opts)
end

-- 下载订阅内容。成功返回字符串；失败返回 nil, err
function M.download(url, opts)
	opts = opts or {}
	local max_size = opts.max_size or M.DEFAULT_MAX_SIZE
	local timeout = opts.timeout or M.DEFAULT_TIMEOUT
	local parsed = M.parse_url(url)
	if not parsed then return nil, "无效 URL" end
	local ok, reason = M.check_public(parsed.host)
	if not ok then return nil, reason end
	local tool = detect_tool()
	if not tool then return nil, "无可用下载工具 (curl/wget)" end
	return fetch(tool, url, parsed, { max_size = max_size, timeout = timeout })
end

return M