# Changelog — luci-app-substore

All notable changes to this project will be documented in this file.

## [Unreleased]

- 规则编辑页简化与对齐（form.htm）
  - 「定时更新时间」与「关键词包含/排除」改为与其它行一致的 cbi-section-descr + min-width:10em 标签，左对齐；cron_time_row 由 display:flex 改为 block + inline-flex
  - 移除「协议过滤」「重命名规则」字段；底部新增多关键词备注
  - node.lua: 关键词包含/排除支持逗号（含中文逗号）/空白分隔的多关键词，命中任一即保留/去除
  - tests/core_rules_test.lua 增补多关键词用例（14 断言）
- 规则下沉到订阅（per-subscription），更新订阅时直接生效；移除全局「设置」页
  - core.lua: 订阅元数据新增 rules_enable / proto_filter / keyword_include / keyword_exclude / dedup / rename_map；新增纯函数 apply_rules()；sync() 解析后按订阅规则过滤/去重/重命名再落盘；移除 load_rules()（不再依赖 luci.model.uci）
  - controller: read_rules_fields()；create/save 读取并持久化规则；移除 settings/settings_save 路由与 action_settings_save
  - view/form.htm: 新增「启用规则」复选框 + 规则字段（协议过滤/关键词包含/排除/去重/重命名），随复选框显隐
  - 删除 view/settings.htm、menu.d 的 Settings 条目、UCI config rules 'default'；uci-defaults 清理旧 substore.default
  - tests/core_rules_test.lua 新增（11 断言）
- Stage 4: 定时更新、规则、错误处理、安全加固、多版本兼容
  - substore-cron.sh: 重写为独立 cron 可运行（显式 package.path、自动探测 lua5.1/lua、pcall 保护、输出走 logger）
  - node.lua: 重命名规则统一三种形式——精确 `旧=新`、正则 `pattern -> replacement`、模板 `{server}_{port}_{proto}`（parse_rename_rules / rename_with_rules / apply_rules）
  - view/settings.htm: 重命名规则 hint、协议过滤/关键词/去重规则配置
  - controller: action_update 用 pcall 兜底，解析/写入异常不 500，错误落库并在列表页状态列展示
  - controller: action_download 文件名白名单化，防 HTTP 头注入
  - Makefile: LUCI_DEPENDS 显式 +luci-lua-runtime +luci-compat（23.05/24.10 兼容）
  - docs/UCODE_MIGRATION.md: `.htm` → `.ut`（ucode）迁移评估与对照（未执行，需 25.12 构建环境验证）
  - tests: node_rename_test.lua 增补精确匹配重命名用例（27 断言）
- Stage 3: 订阅转换 + 订阅链接（核心功能）
  - output.lua: 统一分发全部 13 种目标格式（FORMAT_ALIASES 别名映射）
  - output_uri.lua: vmess/vless/trojan/ss/hysteria2/tuic/socks 分享链接、Shadowrocket(base64)/V2Ray URI
  - output_singbox.lua: sing-box JSON outbounds
  - output_v2ray.lua: V2Ray/Xray JSON outbounds
  - output_formats.lua: Surge/Surfboard/SurgeMac/Loon/Egern/QX/Stash/Plain JSON
  - core.lua: 每订阅随机 token、generate_link(token, target)
  - controller: 公开下载端点 /substore/download?token=&target= （token 访问控制）
  - view: output.htm 13 格式下拉、subscriptions.htm 展示可复制的订阅链接
  - Makefile: 通配安装新增 .lua 模块
  - tests: output_formats_test.lua、core_link_test.lua
- Stage 1: subscription CRUD + download/parse core
  - util.lua: JSON/Base64/URL/file helpers, atomic_write
  - node.lua: protocol normalize
  - parser.lua: vmess/vless/trojan/ss URI parse
  - http.lua: curl/wget download with SSRF check
  - core.lua: subscription meta/nodes persistence, sync()
  - LuCI: subscriptions list & form, controller actions
  - tests/run_tests.lua added
- Stage 0 skeleton: package scaffolding, LuCI menu placeholder, docs.

## [0.1.0] - not yet released

- Initial package skeleton (in development).