# Testing — luci-app-substore

> Placeholder. Testing strategy will be defined and executed starting in stage 1,
> where the pure-Lua core libraries (parser, node) become testable in isolation.

Notes:
- The pure-Lua core (`/usr/share/substore/`) is designed to be testable without LuCI.
- Parser must have test fixtures for supported protocols and formats.
- Integration validation happens on the target OpenWrt device.