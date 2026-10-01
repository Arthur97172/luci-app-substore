# luci-app-substore

**English** | [简体中文](README.md)

Native **OpenWrt / ImmortalWrt** LuCI application for managing airport / proxy
subscriptions. Parse nodes from a subscription, filter, deduplicate, rename and
group them, then re-emit them in a format your client can consume.

![Screenshot](screenshot.png)

## Features

**Subscription management**
- Add / edit / delete / update multiple subscription sources, with manual and
  per-subscription scheduled (cron) updates; an overview shows node counts, last
  update time and error messages
- Remaining traffic / expiry per subscription (parsed from the `subscription-userinfo`
  response header)
- **Subscription proxy**: fetch through `http` / `https` / `socks4` / `socks5` /
  `socks5h`, for sources that cannot be reached directly
- **Combined subscriptions**: merge any subset of existing subscriptions into a new
  one with its own name, token and link; it is recomputed when a source updates
- **Local subscriptions**: paste node text directly (one format at a time,
  auto-detected) instead of providing a URL, or enter nodes field by field

**Input parsing**
- Formats: URI list, Base64, JSON, Clash YAML, sing-box JSON, V2Ray / Xray JSON,
  Surge / Surfboard / Loon / Quantumult X configs, wg-quick / AmneziaWG `.conf`
- Protocols: `vmess` / `vless` / `trojan` / `shadowsocks` / `ssr` / `hysteria` /
  `hysteria2` / `tuic` / `wireguard` / `socks`
  (`http` can be imported and exported, but is not offered in the node form)
- **WireGuard / AmneziaWG**: all fields plus the `amnezia-wg-option` block; an
  AmneziaWG client `.conf` can be pasted as-is
- **Tolerant parsing**: nodes missing `server`, or with a port outside 1–65535, are
  dropped during parsing — otherwise they would be written into a config the client
  refuses to load, and one bad node would break the whole subscription

**Node handling**
- Filter by group / protocol, keyword search, sorting; a node's group is editable
  directly in the table (saved over XHR)
- Edit / delete a single node, or select several and delete them in bulk
- Per-subscription rules: keyword include / exclude, protocol filter, dedup, and
  rename (exact match / regex / placeholder template)

**Network probing** (nodes page)
- Ping (ICMP), TCPing (TCP connect) and URL test (HTTP), run in parallel with a
  success count and average latency

**Conversion & output**
- 15 output formats: Plain JSON, Stash, Clash.Meta / Mihomo, Clash (original),
  Surfboard, Surge, Surge Mac, Loon, Egern, Shadowrocket, Quantumult X, sing-box,
  V2Ray / Xray, V2Ray URI, WireGuard / AmneziaWG `.conf`
- SSR (`ssr://`) can only be emitted to clients that support it (Mihomo, Stash, Loon,
  Egern, Shadowrocket); other targets drop it
- **Only content the target client can actually load is emitted**: protocols are
  filtered by target capability, array-valued fields use the type the client expects,
  and proxy-group member lists drop node names that would break their syntax
- sing-box / V2Ray(Xray) output is a **complete working config** (including routing),
  usable as a single-file config

**Subscription links**
- A random per-subscription token backs the public download endpoint
  `/substore/download?token=<token>&target=<format>`, so Passwall / OpenClash can
  pull it directly

**LuCI interface & i18n**
- English by default, Simplified Chinese when the runtime language is `zh-cn`

## Installation

> The version in the package name must match `PKG_VERSION` / `PKG_RELEASE` in the
> [Makefile](Makefile) (currently `2.6.11-r1`).

opkg (OpenWrt / ImmortalWrt 24.10 and earlier):

```bash
opkg install luci-app-substore-2.6.11-r1.ipk
```

apk (OpenWrt / ImmortalWrt 25.12+):

```bash
apk add --allow-untrusted luci-app-substore-2.6.11-r1.apk
```

Then open LuCI: **Services → Subscriptions**.

## Usage

1. **Add a subscription** — paste the subscription URL; optionally set up a
   per-subscription cron schedule, rules, or a download proxy. No remote source?
   Use **Add local subscription**: paste node text or enter nodes via the form.
2. **Update** — fetch, parse and filter the nodes.
3. **Browse nodes** — filter (group / protocol / keyword), sort, probe latency; tick
   checkboxes and hit Delete for batch deletion, edit / delete / regroup in-row, and
   Refresh reloads the list.
4. **Export** — pick one of the 15 output formats, or copy the subscription link
   to feed a downstream client (Passwall / OpenClash / …).

> **Rename rules match with Lua patterns, not PCRE.** `|` means "or", but only at
> the **top level**: `(a|b)` is not expanded into "a or b" — it matches literally,
> requiring the name to actually contain `a|b`. Write `a|b` for alternatives, or
> use separate rules. A `|` inside a character class `[...]` is literal too.

## Project layout

```
.
├── Makefile                      # OpenWrt package definition
├── LICENSE                       # GPL-2.0-or-later
├── root/                         # install payload
│   ├── etc/
│   │   ├── config/substore       # UCI placeholder
│   │   └── uci-defaults/99-substore
│   ├── usr/
│   │   ├── bin/substore-cron.sh  # per-subscription cron runner
│   │   ├── lib/lua/luci/
│   │   │   ├── controller/admin/substore.lua   # routes / actions
│   │   │   └── view/substore/*.htm             # templates
│   │   └── share/
│   │       ├── luci/menu.d/luci-app-substore.json
│   │       └── substore/*.lua    # core logic (no luci.* dependency)
├── po/zh-cn/substore.po          # 简体中文 translations
├── docs/                         # design & guides
└── tests/                        # self-contained Lua 5.1 unit tests
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — architecture design
- [docs/PLAN.md](docs/PLAN.md) — staged development plan
- [docs/BUILD.md](docs/BUILD.md) — building from an OpenWrt SDK/source tree
- [docs/INSTALL.md](docs/INSTALL.md) — installation
- [docs/SECURITY.md](docs/SECURITY.md) — security model
- [docs/TESTING.md](docs/TESTING.md) — testing
- [docs/UCODE_MIGRATION.md](docs/UCODE_MIGRATION.md) — `.htm` → `.ut` (ucode) migration notes
- [CHANGELOG.md](CHANGELOG.md) — changelog
- [docs/LEGACY_ISSUES.md](docs/LEGACY_ISSUES.md) — known unfixed issues (pending decision)

## Building

Place the package under an OpenWrt / ImmortalWrt SDK or source tree matching the
target firmware, then:

```bash
cp -r luci-app-substore <openwrt-tree>/package/
make package/luci-app-substore/compile V=s
```

The `.ipk` (or `.apk` on apk builds) is produced under `bin/packages/.../`.

## Development & testing

The core is plain Lua 5.1 with no `luci.*` dependency, so it is unit-testable
without a device. Each file under `tests/` is self-contained:

```bash
lua5.1 tests/run_tests.lua          # or any single test file
for f in tests/*.lua; do lua5.1 "$f" || exit 1; done
```

Target-device verification is required for the LuCI UI and cron behaviour — see
[docs/TESTING.md](docs/TESTING.md).

## Security

SSRF protection (private / reserved / link-local ranges rejected; a hostname that
**fails to resolve is rejected** rather than allowed, so "unresolvable ⇒ pass" is not
a bypass), protocol whitelisting and port range validation (1–65535), response size &
timeout limits, download temp files removed on every exit path (`/tmp` is a tmpfs),
command-injection defence (whitelisted parsing + shell quoting, plus probe targets
starting with `-` rejected — busybox `getopt` would read them as options),
token-based access control on the public download endpoint, and no credentials in
logs.

Data on disk: `/etc/substore` is `0700`, and `subscriptions.json` / `nodes/*.json`
are `0600` — the former holds subscription URLs and public download tokens, the
latter uuid / passwords / private keys. `io.open` creates files per the umask
(typically 0644), readable by any local user, so the mode is tightened explicitly
after each write.

Batch node probing is capped at 16 concurrent processes (`probe.MAX_PARALLEL`):
the node count comes from subscription content, and unbounded concurrency exhausts
the router's fd / process budget, after which `io.popen` fails silently.

See [docs/SECURITY.md](docs/SECURITY.md).

## License

[GPL-2.0-or-later](LICENSE) — see the [LICENSE](LICENSE) file.