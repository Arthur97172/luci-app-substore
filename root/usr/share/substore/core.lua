-- core.lua — luci-app-substore 纯 Lua 核心库（不依赖 luci.*）
-- 阶段 0：仅数据路径常量与骨架，后续阶段扩展。

local M = {}

-- 数据存储目录（订阅元数据、节点数据、处理规则）
M.DATA_DIR = "/etc/substore"
-- 订阅源元数据文件
M.SUBSCRIPTIONS_FILE = M.DATA_DIR .. "/subscriptions.json"
-- 节点数据文件
M.NODES_FILE = M.DATA_DIR .. "/nodes.json"

M.version = "0.1.0"

return M