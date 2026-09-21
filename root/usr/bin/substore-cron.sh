#!/bin/sh
# substore cron job — update all enabled subscriptions

DATA_DIR="/etc/substore"
LIST_FILE="$DATA_DIR/subscriptions.json"

[ -f "$LIST_FILE" ] || exit 0

# Simple Lua one-liner to sync enabled subscriptions
lua5.1 -e '
local util = require("substore.util")
local core = require("substore.core")
local items = core.list()
for _, it in ipairs(items) do
    if it.enabled then
        local ok, err = pcall(function() core.sync(it.id) end)
        if not ok then
            io.stderr:write("Failed sync " .. tostring(it.id) .. ": " .. tostring(err) .. "\n")
        end
    end
end
'
