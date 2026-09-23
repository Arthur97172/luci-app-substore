-- core.lua — 订阅源元数据、节点数据与状态管理（纯 Lua，无 luci.* 依赖）
-- luci-app-substore

local util = require("substore.util")
local http = require("substore.http")
local parser = require("substore.parser")

local M = {}

M.version = "0.1.0"
M.DATA_DIR = "/etc/substore"
M.LIST_FILE = M.DATA_DIR .. "/subscriptions.json"
M.NODES_DIR = M.DATA_DIR .. "/nodes"

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

function M.add(name, url)
	name = util.trim(name or "")
	url = util.trim(url or "")
	if name == "" or url == "" then return nil, "名称/URL 不能为空" end
	local seq, items = load()
	seq = seq + 1
	local id = string.format("s%08x", seq)
	items[id] = {
		name = name, url = url, enabled = true,
		node_count = 0, last_update = nil, error = "", format = "",
		token = util.rnd_hex(16),
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

-- 下载并解析订阅，写入节点文件并更新状态。成功返回 node_count，失败返回 nil, err
function M.sync(id)
	local log = function(msg) os.execute("logger -t luci-app-substore " .. string.format("%q", msg)) end
	log("Sync start id="..tostring(id))
	local meta = M.get(id)
	if not meta then log("Sync fail: subscription not found"); return nil, "订阅不存在" end
	if not meta.url or meta.url == "" then log("Sync fail: no URL"); return nil, "无订阅 URL" end

	local content, err = http.download(meta.url, { max_size = M.MAX_SIZE, timeout = M.TIMEOUT })
	if not content then
		log("Download fail: " .. tostring(err))
		M.save_meta(id, { error = err, last_update = os.time() })
		return nil, err
	end
	log("Download ok size="..#content)

	local res, perr = parser.parse(content)
	if not res or not res.nodes then
		log("Parse fail: " .. tostring(perr))
		M.save_meta(id, { error = perr or "解析失败", node_count = 0, last_update = os.time() })
		return nil, perr or "解析失败"
	end
	log("Parse ok nodes="..#res.nodes)

	local nodes = res.nodes
	if not M.write_nodes(id, nodes) then
		M.save_meta(id, { error = "写入节点数据失败", last_update = os.time() })
		return nil, "写入节点数据失败"
	end

	local ok = M.save_meta(id, {
		node_count = #nodes, format = res.format, error = "", last_update = os.time(),
	})
	if not ok then return nil, "更新状态失败" end
	return #nodes
end

-- 读取 UCI 规则
local function load_rules()
	local uci = require("luci.model.uci").cursor()
	local r = {}
	r.proto_filter = uci:get("substore", "default", "proto_filter") or ""
	r.keyword_include = uci:get("substore", "default", "keyword_include") or ""
	r.keyword_exclude = uci:get("substore", "default", "keyword_exclude") or ""
	r.dedup = uci:get("substore", "default", "dedup") or "0"
	r.rename_map = uci:get("substore", "default", "rename_map") or ""
	return r
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
	-- 应用 UCI 规则
	local rules = load_rules()
	all = node_mod.apply_rules(all, rules)
	-- 再应用 opts 过滤
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

return M