# luci-app-substore

**简体中文** | [English](README.en.md)

原生 **OpenWrt / ImmortalWrt** LuCI 应用，用于管理机场 / 代理订阅：解析订阅节点、
筛选、去重、重命名与分组，再转换为客户端可用的配置格式输出。

参考 [Sub-Store](https://github.com/sub-store-org/Sub-Store) 的功能与用户体验，
独立设计与实现：不使用 Docker，不依赖外部云端服务，资源占用友好，适配低配置路由器。

![Screenshot](screenshot.png)

## 功能特性

**订阅管理**
- 多订阅源的新增 / 编辑 / 删除 / 更新，支持手动更新与按订阅的定时（cron）更新；
  状态总览显示节点数、最近更新时间与错误信息
- 每个订阅的剩余流量 / 剩余时长（解析 `subscription-userinfo` 响应头）
- **订阅代理**：经 `http` / `https` / `socks4` / `socks5` / `socks5h` 代理下载订阅，
  用于订阅源直连失败时
- **组合订阅**：把任意子集的现有订阅合并成一个新订阅，拥有独立名称、token 与订阅链接；
  源订阅更新后组合自动重算
- **本地订阅**：不填 URL，直接粘贴节点文本导入（一次一种格式，自动判定），
  或用表单按协议动态字段逐条录入节点

**输入解析**
- 订阅格式：URI 列表、Base64、JSON、Clash YAML、sing-box JSON、V2Ray / Xray JSON、
  Surge / Surfboard / Loon / Quantumult X 配置、wg-quick / AmneziaWG `.conf`
- 节点协议：`vmess` / `vless` / `trojan` / `shadowsocks` / `ssr` / `hysteria` /
  `hysteria2` / `tuic` / `wireguard` / `socks`
  （`http` 可导入并导出，但不在表单可选协议内）
- **WireGuard / AmneziaWG**：完整字段与 `amnezia-wg-option` 子块，
  可直接粘贴 AmneziaWG 客户端导出的 `.conf` 内容
- **解析容错**：缺 `server` 或端口不在 1–65535 的残缺节点在解析阶段即丢弃 ——
  否则会被写成客户端无法加载的配置，一个坏节点废掉整个订阅

**节点处理**
- 按分组 / 协议筛选、关键词搜索、排序；分组可在表格内直接修改（无刷新保存）
- 单节点编辑 / 删除，勾选后批量删除
- 按订阅规则：关键词包含 / 排除、协议筛选、去重、重命名（精确匹配 / 正则 / 占位符模板）

**网络探测**（节点页）
- Ping（ICMP）、TCPing（TCP 连接）、URL 测试（HTTP），并行探测并显示成功数与平均延迟

**转换与输出**
- 15 种输出格式：Plain JSON、Stash、Clash.Meta / Mihomo、Clash 原版、Surfboard、Surge、
  Surge Mac、Loon、Egern、Shadowrocket、Quantumult X、sing-box、V2Ray / Xray、
  V2Ray URI、WireGuard / AmneziaWG `.conf`
- SSR（`ssr://`）只能原样输出到支持它的客户端（Mihomo、Stash、Loon、Egern、Shadowrocket），
  其余目标会将其丢弃
- **只输出目标客户端真正能加载的内容**：按目标能力过滤协议；数组字段按客户端要求的类型
  输出；策略组成员列表剔除会破坏语法的节点名
- sing-box / V2Ray(Xray) 输出**完整可用配置**（含分流规则），可直接作为单文件配置启动

**订阅链接**
- 每个订阅独立随机 token → 公开下载端点
  `/substore/download?token=<token>&target=<format>`，Passwall / OpenClash 等可直接拉取

**LuCI 界面与国际化**
- 默认英文，运行时语言为 `zh-cn` 时自动显示简体中文

## 安装

> 包名中的版本号必须与 [Makefile](Makefile) 的 `PKG_VERSION` / `PKG_RELEASE` 保持一致
> （当前 `2.6.11-r1`）。

opkg（OpenWrt / ImmortalWrt 24.10 及更早）：

```bash
opkg install luci-app-substore-2.6.11-r1.ipk
```

apk（OpenWrt / ImmortalWrt 25.12+）：

```bash
apk add --allow-untrusted luci-app-substore-2.6.11-r1.apk
```

然后在 LuCI 菜单打开：**服务 → 订阅**。

## 使用方法

1. **添加订阅** —— 粘贴订阅 URL；可选的按订阅 cron 定时、规则或下载代理。
   无订阅源时可「添加本地订阅」：粘贴节点文本或表单逐条录入。
2. **更新** —— 下载、解析并过滤节点。
3. **浏览节点** —— 筛选（分组 / 协议 / 关键词）、排序、探测延迟；勾选复选框后「删除」
   可批量删除，行内可编辑 / 删除 / 改分组，「刷新」重载列表。
4. **导出** —— 任选 15 种格式之一，或复制订阅链接供下游客户端（Passwall / OpenClash / …）使用。

> **重命名规则的匹配语法是 Lua 模式，不是 PCRE**。`|` 表示「或」，但只在**顶层**
> 生效：写成 `(a|b)` 不会展开成「a 或 b」，而是按字面匹配（要求名字里真的出现
> `a|b`）。多分支直接写 `a|b`，或拆成多条规则。字符类 `[...]` 内的 `|` 同样是字面。

## 目录结构

```
.
├── Makefile                      # OpenWrt 包定义
├── LICENSE                       # GPL-2.0-or-later
├── root/                         # 安装内容
│   ├── etc/
│   │   ├── config/substore       # UCI 占位
│   │   └── uci-defaults/99-substore
│   ├── usr/
│   │   ├── bin/substore-cron.sh  # 按订阅 cron 执行脚本
│   │   ├── lib/lua/luci/
│   │   │   ├── controller/admin/substore.lua   # 路由 / 动作
│   │   │   └── view/substore/*.htm             # 模板
│   │   └── share/
│   │       ├── luci/menu.d/luci-app-substore.json
│   │       └── substore/*.lua    # 核心逻辑（不依赖 luci.*）
├── po/zh-cn/substore.po          # 简体中文翻译
├── docs/                         # 设计与指南
└── tests/                        # 自包含 Lua 5.1 单元测试
```

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构设计
- [docs/PLAN.md](docs/PLAN.md) — 分阶段开发计划
- [docs/BUILD.md](docs/BUILD.md) — 从 OpenWrt SDK / 源码树构建
- [docs/INSTALL.md](docs/INSTALL.md) — 安装
- [docs/SECURITY.md](docs/SECURITY.md) — 安全模型
- [docs/TESTING.md](docs/TESTING.md) — 测试
- [docs/UCODE_MIGRATION.md](docs/UCODE_MIGRATION.md) — `.htm` → `.ut`（ucode）迁移说明
- [CHANGELOG.md](CHANGELOG.md) — 更新日志
- [docs/LEGACY_ISSUES.md](docs/LEGACY_ISSUES.md) — 遗留缺陷汇总（待决定修复方案）

## 构建

将本包放入与目标固件版本匹配的 OpenWrt / ImmortalWrt SDK 或源码树：

```bash
cp -r luci-app-substore <openwrt-tree>/package/
make package/luci-app-substore/compile V=s
```

`.ipk`（或 apk 构建下的 `.apk`）生成于 `bin/packages/.../` 下。

## 开发与测试

核心逻辑为纯 Lua 5.1，不依赖 `luci.*`，无需设备即可单元测试。`tests/` 下每个测试文件自包含：

```bash
lua5.1 tests/run_tests.lua          # 或任意单个测试文件
for f in tests/*.lua; do lua5.1 "$f" || exit 1; done
```

LuCI 界面与 cron 行为仍需在目标设备上验证 —— 见 [docs/TESTING.md](docs/TESTING.md)。

## 安全

SSRF 防护（拒绝内网 / 保留 / 链路本地地址；**DNS 解析失败即拒绝**，不给
「解析不出来就放行」留绕过口）、协议白名单与端口范围校验（1–65535）、
响应体大小与超时限制、下载临时文件在每条退出路径上清理（`/tmp` 是 tmpfs）、
命令注入防护（白名单解析 + shell 引用 + 探测目标拒绝以 `-` 开头的主机名）、
公开下载端点基于 token 的访问控制、日志不含凭据。

数据落盘权限：`/etc/substore` 目录 `0700`，`subscriptions.json` 与 `nodes/*.json`
`0600`（前者含订阅 URL 与公开下载 token，后者含 uuid / 密码 / 私钥）——
`io.open` 按 umask 创建（通常 0644），同机任何用户都能读到，因此写入后显式收紧。

批量节点探测的并发上限为 16 个进程（`probe.MAX_PARALLEL`）：节点数由订阅内容决定，
不限并发会把路由器的 fd / 进程额度打满，之后 `io.popen` 静默失败。

详见 [docs/SECURITY.md](docs/SECURITY.md)。

## 许可证

[GPL-2.0-or-later](LICENSE) —— 见 [LICENSE](LICENSE) 文件。