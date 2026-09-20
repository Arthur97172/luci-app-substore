# luci-app-substore

Native OpenWrt / ImmortalWrt LuCI application for managing airport subscriptions.

参考 [Sub-Store](https://github.com/sub-store-org/Sub-Store) 的功能与用户体验，独立设计与实现，不使用 Docker，不依赖外部云端服务。

## Features

- Subscription management: add / edit / delete / update multiple subscription sources
- Node parsing for common proxy protocols
- Node filtering, deduplication, renaming, sorting
- Multi-subscription merge
- Output formats: Mihomo/Clash YAML, Base64/URI, JSON
- LuCI web interface with status and logs

> Status: under active development. See [docs/PLAN.md](docs/PLAN.md) for the staged roadmap.

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