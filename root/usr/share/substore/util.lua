-- util.lua — 通用工具（纯 Lua 5.1，无外部依赖）
-- luci-app-substore

local M = {}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 安全 require：模块不存在时返回 nil 而不报错
function M.try_require(name)
	local ok, mod = pcall(require, name)
	if ok and mod then return mod end
	return nil
end

-- ---------- Base64 ----------
function M.base64_encode(s)
	if type(s) ~= "string" then return "" end
	local out = {}
	for i = 1, #s, 3 do
		local b1 = s:byte(i)
		local b2 = s:byte(i + 1)
		local b3 = s:byte(i + 2)
		local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
		out[#out + 1] = B64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
		out[#out + 1] = B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
		out[#out + 1] = b2 and B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
		out[#out + 1] = b3 and B64:sub(n % 64 + 1, n % 64 + 1) or "="
	end
	return table.concat(out)
end

function M.base64_decode(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("[^%w%+/=]", "")
	local out = {}
	local n, bits = 0, 0
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "=" then break end
		local v = B64:find(c, 1, true)
		if v then
			n = n * 64 + (v - 1)
			bits = bits + 6
			if bits >= 8 then
				bits = bits - 8
				out[#out + 1] = string.char(math.floor(n / (2 ^ bits)) % 256)
			end
		end
	end
	return table.concat(out)
end

-- ---------- URL ----------
function M.url_decode(s)
	if type(s) ~= "string" then return "" end
	return s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
end

-- 从 query string 提取字段（接受 URL 片段，如 "…?a=1&b=2#frag"）
function M.url_extract(s, field)
	if type(s) ~= "string" then return nil end
	local q = s:match("[^#?]*%?([^#]*)")
	if not q then return nil end
	for k, v in q:gmatch("([^&=]+)=([^&]*)") do
		if k == field then return M.url_decode(v) end
	end
	return nil
end

-- 拆分 host:port，支持 [ipv6]:port
function M.split_hostport(s)
	if type(s) ~= "string" then return nil, nil end
	s = M.trim(s)
	if s:sub(1, 1) == "[" then
		local close = s:find("]", 1, true)
		if not close then return nil, nil end
		local host = s:sub(2, close - 1)
		local port = s:sub(close + 1):match("^:(%d+)$")
		return host, port
	else
		local host, port = s:match("^([^:]+):(%d+)$")
		if host then return host, port end
		return s, nil
	end
end

-- ---------- JSON ----------
local function utf8_char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000),
			0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	else
		return string.char(0xF0 + math.floor(cp / 0x40000),
			0x80 + math.floor(cp / 0x1000) % 0x40,
			0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
end

local function is_array(t)
	local i = 0
	for k in pairs(t) do
		i = i + 1
		if t[i] == nil then return false end
	end
	return i == #t
end

function M.json_encode(v)
	local function enc(v)
		local t = type(v)
		if v == nil then
			return "null"
		elseif t == "string" then
			return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
				if c == '"' then return '\\"'
				elseif c == "\\" then return "\\\\"
				elseif c == "\n" then return "\\n"
				elseif c == "\r" then return "\\r"
				elseif c == "\t" then return "\\t"
				elseif c == "\b" then return "\\b"
				elseif c == "\f" then return "\\f"
				else return string.format("\\u%04x", c:byte()) end
			end) .. '"'
		elseif t == "number" then
			if v ~= v then return "null" end
			return string.format("%.14g", v)
		elseif t == "boolean" then
			return v and "true" or "false"
		elseif t == "table" then
			if is_array(v) then
				local a = {}
				for i = 1, #v do a[#a + 1] = enc(v[i]) end
				return "[" .. table.concat(a, ",") .. "]"
			else
				local a = {}
				for k, val in pairs(v) do
					a[#a + 1] = enc(tostring(k)) .. ":" .. enc(val)
				end
				return "{" .. table.concat(a, ",") .. "}"
			end
		end
		return "null"
	end
	return enc(v)
end

function M.json_decode(s)
	if type(s) ~= "string" then return nil, "not a string" end
	local i = 1
	local len = #s

	local function skip_ws()
		while true do
			local c = s:sub(i, i)
			if c == " " or c == "\t" or c == "\n" or c == "\r" then i = i + 1 else break end
		end
	end

	local function parse()
		skip_ws()
		if i > len then return nil, "unexpected end" end
		local c = s:sub(i, i)

		if c == "{" then
			i = i + 1
			local obj = {}
			skip_ws()
			if s:sub(i, i) == "}" then i = i + 1 return obj end
			while true do
				skip_ws()
				local k, ke = parse()
				if not k or type(k) ~= "string" then return nil, "expected string key" end
				skip_ws()
				if s:sub(i, i) ~= ":" then return nil, "expected ':'" end
				i = i + 1
				local val = parse()
				obj[k] = val
				skip_ws()
				local cc = s:sub(i, i)
				if cc == "," then
					i = i + 1
				elseif cc == "}" then
					i = i + 1
					return obj
				else
					return nil, "expected ',' or '}'"
				end
			end

		elseif c == "[" then
			i = i + 1
			local arr = {}
			skip_ws()
			if s:sub(i, i) == "]" then i = i + 1 return arr end
			while true do
				local val = parse()
				arr[#arr + 1] = val
				skip_ws()
				local cc = s:sub(i, i)
				if cc == "," then
					i = i + 1
				elseif cc == "]" then
					i = i + 1
					return arr
				else
					return nil, "expected ',' or ']'"
				end
			end

		elseif c == '"' then
			i = i + 1
			local out = {}
			while true do
				local ch = s:sub(i, i)
				if ch == "" then return nil, "unterminated string" end
				if ch == '"' then i = i + 1 return table.concat(out) end
				if ch == "\\" then
					i = i + 1
					local e = s:sub(i, i)
					i = i + 1
					local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
						b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
					if e == "u" then
						local hex = s:sub(i, i + 3)
						i = i + 4
						local cp = tonumber(hex, 16)
						if not cp then return nil, "bad unicode" end
						if cp >= 0xD800 and cp <= 0xDBFF then
							if s:sub(i, i) == "\\" and s:sub(i + 1, i + 1) == "u" then
								local hex2 = s:sub(i + 2, i + 5)
								local cp2 = tonumber(hex2, 16)
								if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
									i = i + 6
									cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00)
								end
							end
						end
						out[#out + 1] = utf8_char(cp)
					else
						out[#out + 1] = map[e] or e
					end
				else
					out[#out + 1] = ch
					i = i + 1
				end
			end

		elseif c == "t" and s:sub(i, i + 3) == "true" then
			i = i + 4
			return true
		elseif c == "f" and s:sub(i, i + 4) == "false" then
			i = i + 5
			return false
		elseif c == "n" and s:sub(i, i + 3) == "null" then
			i = i + 4
			return nil
		elseif c:match("[%-%d]") then
			local num = s:match("^-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
			if not num or num == "" then return nil, "bad number" end
			i = i + #num
			local n = tonumber(num)
			if not n then return nil, "bad number value" end
			return n
		else
			return nil, "unexpected char " .. c
		end
	end

	local v = parse()
	return v
end

-- ---------- 文件 ----------
function M.read_file(path)
	local f, e = io.open(path, "rb")
	if not f then return nil, e end
	local data = f:read("*a")
	f:close()
	return data
end

function M.file_size(path)
	local f = io.open(path, "rb")
	if not f then return 0 end
	local data = f:read("*a")
	f:close()
	return #data
end

-- 原子写：先写临时文件再重命名，避免写一半损坏
function M.atomic_write(path, content)
	local tmp = path .. ".tmp"
	local f, e = io.open(tmp, "wb")
	if not f then return false, e end
	f:write(content)
	f:close()
	local ok, e2 = os.rename(tmp, path)
	if not ok then
		os.remove(tmp)
		return false, e2
	end
	return true
end

function M.ensure_dir(path)
	os.execute("mkdir -p " .. string.format("%q", path))
end

return M