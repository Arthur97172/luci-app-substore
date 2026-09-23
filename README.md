# luci-app-substore

Native OpenWrt / ImmortalWrt LuCI application for managing airport subscriptions.

参考 [Sub-Store](https://github.com/sub-store-org/Sub-Store) 的功能与用户体验，独立设计与实现，不使用 Docker，不依赖外部云端服务。

## Features

- Subscription management: add / edit / delete / update multiple subscription sources
- Input sources: URI / Base64 / JSON subscriptions, Clash YAML, sing-box JSON, V2Ray JSON, Surge / Loon / QX client configs, LAN subscription links
- Node parsing for common proxy protocols (vmess / vless / trojan / shadowsocks / hysteria2 / tuic / socks …)
- Node filtering, deduplication, renaming (regex / template), grouping, tags
- Protocol conversion: any node type → any other type
- Output formats (13, all implemented): Plain JSON, Stash, Clash.Meta/Mihomo, Surfboard, Surge, SurgeMac, Loon, Egern, Shadowrocket, Quantumult X, sing-box, V2Ray, V2Ray URI
- Subscription links: converted nodes served as links (e.g. `/substore/download?token=<token>&target=ClashMeta`) usable by Passwall / OpenClash
- LuCI web interface with status and logs

> Status: under active development. See [docs/PLAN.md](docs/PLAN.md) for the staged roadmap.

## Manual Install / 手动安装

> 包名中的版本号需与 [Makefile](Makefile) 的 `PKG_VERSION` / `PKG_RELEASE` 保持同步。

opkg (OpenWrt / ImmortalWrt 24.10 及更早):

```bash
opkg install luci-app-substore-0.2.0-r2.ipk
```

apk (OpenWrt / ImmortalWrt 25.12+):

```bash
apk add --allow-untrusted luci-app-substore-0.2.0-r2.apk
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — architecture design
- [docs/PLAN.md](docs/PLAN.md) — staged development plan
- [docs/BUILD.md](docs/BUILD.md) — building
- [docs/INSTALL.md](docs/INSTALL.md) — installation
- [docs/SECURITY.md](docs/SECURITY.md) — security model
- [docs/TESTING.md](docs/TESTING.md) — testing
- [CHANGELOG.md](CHANGELOG.md) — changelog

## License

GNU GENERAL PUBLIC LICENSE