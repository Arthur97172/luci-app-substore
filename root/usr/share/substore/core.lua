-- core.lua — 订阅源元数据、节点数据与状态管理（纯 Lua，无 luci.* 依赖）
-- luci-app-substore

local util = require("substore.util")
local http = require("substore.http")
local parser = require("substore.parser")

local M = {}

M.version = "0.2.0"
M.DATA_DIR = "/etc/substore"
M.LIST_FILE = M.DATA_DIR .. "/subscriptions.json"
M.NODES_DIR = M.DATA_DIR .. "/nodes"
M.CRON_FILE = "/etc/cron.d/substore"

M.MAX_SIZE = 10 * 1024 * 1024 -- 10MB
M.TIMEOUT = 20

local function id_is_valid(id)
	return type(id) == "string" and id ~= "" and id:match("^[A-Za-z0-9_%-]+$") ~= nil
end

function M.ensure_dirs()
	util.ensure_dir(M.DATA_DIR)
	util.ensure_dir(M.NODES_DIR)
end

local function load()
	M.ensure_dirs()
	local raw = util.read_file(M.LIST_FILE)
	if not raw or raw == "" then return 0, {} end
	local data = util.json_decode(raw)
	if type(data) ~= "table" then return 0, {} end
	local seq = tonumber(data._seq) or 0
	local items = type(data.items) == "table" and data.items or {}
	return seq, items
end

local function save(seq, items)
	M.ensure_dirs()
	return util.atomic_write(M.LIST_FILE, util.json_encode({ _seq = seq, items = items }))
end

function M.list()
	local _, items = load()
	local arr = {}
	for id, meta in pairs(items) do
		local m = {}
		for k, v in pairs(meta) do m[k] = v end
		m.id = id
		arr[#arr + 1] = m
	end
	table.sort(arr, function(a, b) return (a.name or "") < (b.name or "") end)
	return arr
end

function M.get(id)
	if not id_is_valid(id) then return nil end
	local _, items = load()
	local meta = items[id]
	if not meta then return nil end
	local m = {}
	for k, v in pairs(meta) do m[k] = v end
	m.id = id
	return m
end

function M.add(name, url, opts)
	name = util.trim(name or "")
	url = util.trim(url or "")
	opts = opts or {}
	if name == "" or url == "" then return nil, "名称/URL 不能为空" end
	local seq, items = load()
	seq = seq + 1
	local id = string.format("s%08x", seq)
	local cron_time = util.trim(opts.cron_time or "")
	if not M.cron_time_valid(cron_time) then cron_time = "" end
	items[id] = {
		name = name, url = url, enabled = true,
		node_count = 0, last_update = nil, error = "", format = "",
		token = util.rnd_hex(16),
		proxy_enable = (opts.proxy_enable == true or opts.proxy_enable == "1") and "1" or "0",
		proxy = util.trim(opts.proxy or ""),
		cron_enable = (opts.cron_enable == true or opts.cron_enable == "1") and cron_time ~= "",
		cron_time = cron_time,
		rules_enable = (opts.rules_enable == true or opts.rules_enable == "1") and true or false,
		proto_filter = util.trim(opts.proto_filter or ""),
		keyword_include = util.trim(opts.keyword_include or ""),
		keyword_exclude = util.trim(opts.keyword_exclude or ""),
		dedup = (opts.dedup == true or opts.dedup == "1") and "1" or "0",
		rename_map = opts.rename_map or "",
	}
	if not save(seq, items) then return nil, "写入失败" end
	return id
end

-- 获取订阅的下载 token；若不存在则生成并持久化
function M.ensure_token(id)
	if not id_is_valid(id) then return nil end
	local seq, items = load()
	local meta = items[id]
	if not meta then return nil end
	if not meta.token or meta.token == "" then
		meta.token = util.rnd_hex(16)
		save(seq, items)
	end
	return meta.token
end

-- 依据 token 查找订阅 ID
local function id_by_token(token)
	if type(token) ~= "string" or token == "" then return nil end
	local _, items = load()
	for id, meta in pairs(items) do
		if meta.token == token then return id end
	end
	return nil
end

-- 生成订阅下载内容：按 target 格式转换节点。返回 content, content_type, filename, err
function M.generate_link(token, target, opts)
	opts = opts or {}
	local id = id_by_token(token)
	if not id then return nil, nil, nil, "无效的订阅 token" end
	local meta = M.get(id)
	local nodes = M.read_nodes(id)
	if #nodes == 0 then return nil, nil, nil, "暂无可用的节点（请先更新订阅）" end

	local output = require("substore.output")
	local content, err = output.generate(nodes, target, opts)
	if not content then return nil, nil, nil, err or "无法生成目标格式" end

	local ct = opts.content_type or output.content_type_for(target) or "text/plain; charset=utf-8"
	local ext = output.extension_for(target) or "txt"
	local base = (meta and meta.name and meta.name ~= "") and meta.name or id
	local filename = base .. "." .. ext
	return content, ct, filename, nil
end

function M.save_meta(id, patch)
	if not id_is_valid(id) then return false, "非法 ID" end
	local seq, items = load()
	local meta = items[id]
	if not meta then return false, "订阅不存在" end
	for k, v in pairs(patch or {}) do
		if v == nil then meta[k] = nil else meta[k] = v end
	end
	return save(seq, items)
end

function M.remove(id)
	if not id_is_valid(id) then return false end
	local seq, items = load()
	if not items[id] then return false end
	items[id] = nil
	save(seq, items)
	os.remove(M.nodes_file(id))
	return true
end

function M.nodes_file(id)
	return M.NODES_DIR .. "/" .. id .. ".json"
end

function M.write_nodes(id, nodes)
	M.ensure_dirs()
	return util.atomic_write(M.nodes_file(id), util.json_encode(nodes))
end

function M.read_nodes(id)
	if not id_is_valid(id) then return {} end
	local raw = util.read_file(M.nodes_file(id))
	if not raw or raw == "" then return {} end
	local nodes = util.json_decode(raw)
	if type(nodes) ~= "table" then return {} end
	return nodes
end

-- 解析 subscription-userinfo 响应头（upload/download/total/expire），返回数字表或 nil
function M.parse_userinfo(s)
	if type(s) ~= "string" or s == "" then return nil end
	local u = {}
	for k, v in s:gmatch("([%w_%-]+)%s*=%s*([^;]+)") do
		local key = k:lower()
		if key == "upload" or key == "download" or key == "total" or key == "expire" then
			local num = tonumber(util.trim(v))
			if num then u[key] = num end
		end
	end
	if next(u) == nil then return nil end
	return u
end

-- 下载并解析订阅，写入节点文件并更新状态。成功返回 node_count，失败返回 nil, err
function M.sync(id)
	local log = function(msg) os.execute("logger -t luci-app-substore " .. string.format("%q", msg)) end
	log("Sync start id="..tostring(id))
	local meta = M.get(id)
	if not meta then log("Sync fail: subscription not found"); return nil, "订阅不存在" end
	if not meta.url or meta.url == "" then log("Sync fail: no URL"); return nil, "无订阅 URL" end

	-- 订阅代理：开启且代理地址有效时，通过代理下载订阅
	local proxy = ""
	if meta.proxy_enable == true or meta.proxy_enable == "1" then
		local p, perr = http.parse_proxy(meta.proxy or "")
		if p and p ~= "" then
			proxy = p
		elseif perr then
			log("Proxy ignored: " .. tostring(perr))
		end
	end
	if proxy ~= "" then log("Using proxy " .. proxy) end

	local content, headers, err = http.download(meta.url, { max_size = M.MAX_SIZE, timeout = M.TIMEOUT, proxy = proxy })
	if not content then
		log("Download fail: " .. tostring(err))
		M.save_meta(id, { error = err, last_update = os.time() })
		return nil, err
	end
	log("Download ok size="..#content)

	local ui = M.parse_userinfo(headers and headers["subscription-userinfo"])
	if ui then log("Userinfo total="..tostring(ui.total).." expire="..tostring(ui.expire)) end

	local res, perr = parser.parse(content)
	if not res or not res.nodes then
		log("Parse fail: " .. tostring(perr))
		M.save_meta(id, { error = perr or "解析失败", node_count = 0, last_update = os.time() })
		return nil, perr or "解析失败"
	end
	log("Parse ok nodes="..#res.nodes)

	local nodes = M.apply_rules(res.nodes, meta)
	if not M.write_nodes(id, nodes) then
		M.save_meta(id, { error = "写入节点数据失败", last_update = os.time() })
		return nil, "写入节点数据失败"
	end

	local ok = M.save_meta(id, {
		node_count = #nodes, format = res.format, error = "", last_update = os.time(),
		upload = ui and ui.upload, download = ui and ui.download, total = ui and ui.total, expire = ui and ui.expire,
	})
	if not ok then return nil, "更新状态失败" end
	return #nodes
end

-- 对节点应用订阅级规则（rules_enable 为真时生效）；纯函数，便于测试
function M.apply_rules(nodes, meta)
	meta = meta or {}
	if not (meta.rules_enable == true or meta.rules_enable == "1") then return nodes end
	local node_mod = require("substore.node")
	local rules = {
		proto_filter = meta.proto_filter or "",
		keyword_include = meta.keyword_include or "",
		keyword_exclude = meta.keyword_exclude or "",
		dedup = meta.dedup or "0",
		rename_map = meta.rename_map or "",
	}
	return node_mod.apply_rules(nodes, rules)
end

-- 合并多个订阅的节点
function M.merge(ids, opts)
	opts = opts or {}
	local all = {}
	local node_mod = require("substore.node")
	for _, id in ipairs(ids) do
		local nodes = M.read_nodes(id)
		for _, n in ipairs(nodes) do
			all[#all + 1] = n
		end
	end
	-- 规则已在各订阅 sync 时按订阅级配置应用；此处仅应用 opts 过滤
	if opts.proto then
		all = node_mod.filter(all, { proto = opts.proto })
	end
	if opts.keyword and opts.keyword ~= "" then
		all = node_mod.filter(all, { keyword = opts.keyword })
	end
	if opts.dedup then
		all = node_mod.dedup(all)
	end
	if opts.sort then
		all = node_mod.sort(all, opts.sort, opts.desc)
	end
	return all
end

-- 校验 cron 表达式：5 个字段，每个为数字或 *，防 cron 文件命令注入
function M.cron_time_valid(ct)
	if type(ct) ~= "string" then return false end
	local fields = {}
	for f in ct:gmatch("%S+") do fields[#fields + 1] = f end
	if #fields ~= 5 then return false end
	for _, f in ipairs(fields) do
		if f ~= "*" and not f:match("^%d+$") then return false end
	end
	return true
end

-- 依据各订阅的 cron 设置生成 /etc/cron.d/substore；无启用项则移除该文件
function M.write_cron()
	local lines = { "# luci-app-substore cron (per-subscription)" }
	for _, it in ipairs(M.list()) do
		local en = (it.cron_enable == true or it.cron_enable == "1")
		local ct = util.trim(it.cron_time or "")
		if en and M.cron_time_valid(ct) then
			lines[#lines + 1] = ct .. " root /usr/bin/substore-cron.sh " .. it.id .. " >/tmp/substore-cron.log 2>&1"
		end
	end
	if #lines == 1 then
		os.remove(M.CRON_FILE)
		return true
	end
	return util.atomic_write(M.CRON_FILE, table.concat(lines, "\n") .. "\n")
end

return M