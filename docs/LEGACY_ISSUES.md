# 遗留缺陷与已知限制汇总（待决定修复方案）

**决策时点**：P0 + P1 + P2 全部修复工作完成后统一决定。本文件只记录**不在 P2
范围内**、需要另行决策的项。

**当前进度**：

| 批次 | 范围 | 状态 |
|---|---|---|
| P0 | 14 项高危（输出整份不可用 / 数据永久丢失 / 安全） | ✅ 已完成（4 次推送，见 CHANGELOG `[2.6.0-r2]`～`[2.6.0-r5]`） |
| P1 | 13 项中危 + 审计中实测确认的 4 项新缺陷 | ✅ 已完成（`[2.6.1-r1]`） |
| P2 | 其余 M / L 项 | 🔄 进行中（批次一 `[2.6.3-r1]`、批次二 `[2.6.4-r1]`、批次三 `[2.6.5-r1]`、批次四 `[2.6.6-r1]`、批次五 `[2.6.7-r1]`、批次六 `[2.6.8-r1]`、批次七 `[2.6.9-r1]`） |
| P3 | 输出层代码级复审（10 项）+ shadowsocks SIP003 插件全链路（1 项） | ✅ 已完成（`[2.6.10-r1]`，见下文「四」） |
| P4 | 遗留项决策后实施（1.1 / 1.3 / 1.4 / 1.5 / 2.5 五项，3.3 补文档） | ✅ 已完成（`[2.6.11-r1]`，见下文「五」） |

**编写纪律**：只记录经**代码级审计或实测探针**确认的结论，不含推测。原始 70 项
审计表（高危 14 / 中危 30 / 低危 26）未落盘，本文件自本次起作为「未修复项」的
权威清单。已修复项见 [CHANGELOG.md](../CHANGELOG.md)。

---

# 一、本轮（P1 之后）确认的遗留项

## 1.1 H10 的「无锁」部分 —— `load()` → `save()` 丢更新（**已修复 `[2.6.11-r1]`**）

**已修的部分**：H10 的另一半（临时文件名固定为 `path..".tmp"` 被并发写者共用）
已在 P0 批次三修复，改为 `path..".tmp.<8 字节随机 hex>"`。

**未修的部分**：读-改-写全程仍无互斥。

**代码级依据**：

- `core.lua` 的 `local function load()` 读出整表，`local function save(seq, items)`
  整表写回，中间无锁；`M.add` / `M.add_local` / `M.add_combo` / `M.save_meta` /
  `M.save_combo` 均走这条路径。
- `util.lua` 中**不存在任何锁原语**（无 `flock`、无 `mkdir` 锁、无 `link()`）。
- `nixio` 只用于 `http.lua:208-210` 的 `getaddrinfo`（`util.try_require` 可选加载），
  `Makefile` 的 `LUCI_DEPENDS` 未声明 `+nixio`。

**并发来源**：LuCI 页面保存订阅、cron 定时更新、组合订阅自动重算，三者可能同时发生。

**影响**：后写者整表覆盖先写者 → 订阅丢失或新增丢失。与已修复的 H8 同属「数据被
抹除」，但触发条件是并发而非文件损坏，H8 的修复**不覆盖**本项。

**候选方案**：

| 方案 | 做法 | 代价 / 风险 |
|---|---|---|
| A. 记为已知限制 | 文档说明「同一时间只应有一个写操作」 | 零成本；用户无从感知，仍会丢数据 |
| B. 引入 `nixio` flock | `Makefile` 加 `+nixio`，写路径加文件锁 | 最可靠；新增运行时依赖，本机**无法验证** |
| C. `mkdir` 锁 + 陈旧锁回收 | 目录创建做互斥，带超时与持有者 PID 回收 | 纯 Lua 无依赖；需正确处理崩溃残留锁，否则死锁 |
| D. 写路径单点串行化 | 所有写入收敛到同一入口 | 跨进程串行仍需 OS 原语，实际仍要 B 或 C |

## 1.2 M28 / M29 —— CSRF `post_ok()` 与 ACL

**状态**：**已决定跳过验证**（用户 2026-09-30 指示）。

**原因**：二者依赖 LuCI 框架运行时行为（`test_post_security`、ACL 解析），本机没有
LuCI 运行环境，无法做代码级确认。按「不靠猜」的纪律，未做改动。

**审计结论（未做运行时验证，置信度有限）**：

- M28：`substore.lua:40-44` 的 `post_ok()` 只判 `formvalue("token") ~= nil`（空串也过），
  且 `entry` 均未声明 `post` → 框架的 `test_post_security` 从未执行。缓解因素是
  Cookie `SameSite=strict`。
- M29：`menu.d/luci-app-substore.json` 无 `depends.acl`、`entry` 无 `acl_depends`、
  仓库内无 rpcd ACL 文件 → 任意已登录 LuCI 用户可读写全部订阅（含凭据 URL）。

**建议**：在目标设备上以真实 LuCI 环境复核后再决定。

## 1.3 sing-box 读取侧：transport 整层丢失（**已修复 `[2.6.11-r1]`**）

**现象**：sing-box 配置中 ws / grpc / h2 的传输参数在导入后**完全丢失**，节点退化
为 tcp 直连。

**实测探针**（`parser.parse`，vmess + `transport: {type: ws, path: /ws, headers.Host}`）：

```
JSON -> proto=vmess net=tcp sni=a.com fp=nil    path=nil host=nil
YAML -> proto=vmess net=tcp sni=a.com fp=chrome path=nil host=nil
```

**代码级依据**：

- `parser_json_config.lua`（`parse_singbox_json`，314 行）全文**不含**
  `transport` / `path` / `host` / `utls` 任何一处。它读的是 `outbound.network`，
  而 sing-box 表达传输方式用的是 `transport.type` —— 该字段在 sing-box 出站里
  并不存在，因此 `net` 恒为默认值 `tcp`。
- 简易 YAML 解析器（`parser.lua`）只展开 `tls:` 子块，同样不处理 `transport`。

**影响**：ws / grpc / h2 节点在机场导出的 sing-box 配置里占相当比例，导入后全部按
tcp 直连，握手必然失败，且**不报错**。比原记录（「不读 path/host」）更严重：连传输
类型本身都没读进来。

**附带不一致**：`tls.utls.fingerprint` 在 YAML 侧**已读**（`fp=chrome`，P1 修复），
JSON 侧**不读**（`fp=nil`）。

**候选方案**：在 `parse_singbox_json` 中补 `transport.type` → `net`、
`transport.path` → `path`、`transport.headers.Host` → `host`、
`tls.utls.fingerprint` → `fp`；并让简易 YAML 侧同样处理 `transport`。

**权威字段名已核实（`[2.6.10-r1]`，取自上游
`sing-box.sagernet.org/configuration/shared/v2ray-transport/`，可直接照此实现，
无需再猜）**：

| `transport.type` | 本项目的 `net` | 字段映射 |
|---|---|---|
| `ws` | `ws` | `path` → `path`；`headers.Host` → `host` |
| `grpc` | `grpc` | `service_name` → `path` |
| `http` | `http` | `path` → `path`；`host` 是**数组**，取首个 → `host` |
| `httpupgrade` | `http` | `path` → `path`；`host` 是**单个字符串** → `host` |
| `quic` | 无对应 | 本项目模型没有 quic，按未知传输处理（回落 tcp 或丢弃） |

另：`tls.utls.fingerprint` → `fp`（YAML 侧已读，JSON 侧未读，需对齐）；
`tls.enabled` 为 `false` 时不得置 `security`。

**修复建议：本轮修复**（`[2.6.10-r1]` 未实施，留待下一轮）。它与 F5 / F6 / F11
同属「静默丢传输层 → 节点连不上且不报错」，而 ws / grpc 节点在机场的 sing-box
配置里占比很高，影响面比 F5/F6 更大。实施时两侧（JSON 与简易 YAML）必须一起改，
否则同一条订阅走两条导入路径会得到不同的节点。

## 1.4 `converter.lua` / `node_converter.lua` 为死代码（**已删除 `[2.6.11-r1]`**）

（即审计表 L2）

**代码级依据**：

- `root/` 下**没有任何文件** `require` 这两个模块 —— 唯一的引用是
  `converter.lua:7` 引用 `node_converter.lua`，以及 `tests/` 下的单元测试。
- LuCI controller 与前端 JS 中**不存在**「转换」相关的路由或 UI。
- 模块实现本身也有问题：禁止 shadowsocks 转换；`hysteria2/tuic/wireguard →
  "sing-box"/"clash"` 产出**非法 proto**；`node_converter.convert` 因 `network` /
  `fingerprint` 字段名不匹配丢 `net`/`path`/`host`/`fp`；`core.generate_link` 不传
  opts → `options.proto` 永不被设置。

**README 声明**：`README.md:59`「协议转换：任意协议 → 任意协议」、
`README.en.md:68`「Protocol conversion: any node type → any other type」；
紧接其后的 `README.md:60-62` 又说明「SSR 不能与 vmess/vless 等其它协议互转」，
与上一行自相矛盾。

**候选方案**：A. 接入 UI（需先定义「哪些协议可互转」的权威矩阵并审计现有映射表）；
B. 删除两个模块与测试，修正 README 两处声明。

---

## 1.5 Quantumult X：节点名含逗号时 `tag=` 字段本身被写坏（**已按方案 B 修复 `[2.6.11-r1]`**）

**发现于**：P2 批次三修复 L21 时顺带发现。L21 只处理了**成员列表**（Surge 家族
`[Proxy Group]` 与 QX `[policy]`），已修复；本条是同一根因在 QX **定义行**上的
另一处表现。

**实测（已验证的部分）**：`output_formats.lua` 的 `to_qx` 用
`string.format("trojan=%s, password=%s, over-tls=true, tag=%s", …)` 拼行，
`tag` 直接取自 `n.name`。节点名 `A,B` 经 `util.one_line` 后仍含逗号，
输出为：

```
trojan=1.2.3.4:443, password=p, over-tls=true, tag=A,B
```

`[server_local]` 行内是逗号分隔的 `key=value` 字段序列，名字里的逗号落在
`tag=` 的值里，按该语法会被读成字段分隔符。

**补充（`[2.6.10-r1]`）**：同一条行语法在**参数值**上的同类问题已修复 —— `to_qx`
现在先把具名字段攒成列表、逐字段判定值里是否含逗号，含逗号的整条丢弃（连同
`[policy]` 成员），不再出现 `password=pa,ss` 被静默截断成 `password=pa`。
本条讨论的 `tag=` **名字**部分已于 `[2.6.11-r1]` 按下面的方案 B 一并处理：
`to_qx` 现在对「one_line 之后仍含逗号」的节点整条丢弃（定义行与 `[policy]` 成员
一起），判定条件与 `names_of` 完全一致，两边不会再对不上。

**未验证的部分（不猜）**：QX 对这种「最后一个字段值里多出逗号」的行究竟是
报错、忽略多余片段，还是原样接受，**本机没有 Quantumult X 可供实测**。
因此本条按「待核实」记录，未作修改。

**候选方案**（三选一，需先核实 QX 实际行为再定）：

- **A. 改名**：输出时把名字里的 `,` 替换为安全字符。节点不丢失，但导出名与
  LuCI 中显示的名字不一致；且 `A,B` 与 `A_B` 两个节点会撞名（Surge / QX 对
  重名代理的处理需另行核实）。
- **B. 丢弃**：把含逗号名字的节点从 QX 输出中整体剔除（连定义行一起）。
  与「Surge 家族丢弃 wireguard / ssr、Clash 原版丢弃不支持的协议」的既有约定
  一致，产出必定合法；代价是节点静默消失。
- **C. 维持现状**：仅在文档中说明「QX 输出请勿使用含逗号的节点名」。

**注**：Surge 家族的 `[Proxy]` 定义行是 `NAME = type, host, port, …`，
名字在 `=` **左侧**，逗号大概率不影响解析（未实测），故本条**只针对 QX**。

**推荐方案：B（丢弃）**。理由：

- A（改名）会引入新的重名风险，而「重名代理」在 Surge / QX 上的行为同样未核实 ——
  等于用一个未核实的问题换掉另一个，不划算。
- C（维持现状）会让用户拿到一份静默损坏的配置，与本项目「宁可丢节点也不输出
  损坏行」的既有约定（Surge 家族丢 wireguard / ssr、Clash 原版丢不支持的协议）相悖。
- B 与 F7 已落地的处置完全一致，实现上只是把 `names_of` 的排除条件也用到定义行上，
  改动小、行为可预期。

实施前仍建议先核实 QX 对多余逗号片段是报错还是忽略 —— 若确认是「忽略多余片段、
`tag` 取第一段」，则 C 也可接受，届时再定。

---

# 二、P0 时代的遗留项（2.6.0 审计时记录）

来源：CHANGELOG `[2.6.0-r1]` 的「已知限制（本轮不修，均有明确原因）」。以下逐条
复核过当前代码，均**仍然成立**。

## 2.1 M11 混合格式文本导入不支持

**依据**：`parse_local → parse → detect` 只识别**一种**格式，其余部分被静默丢弃
（实测：「URI + WG conf」只剩 WG 节点；「URI + JSON」只剩 URI 节点）。

**性质**：**功能缺失**而非小缺陷，需要重新设计 parser 的分段架构（规格 §22 明确
警告不要直接采用未经验证的逐行算法）。

**候选方案**：A. 设计分段架构后实现（工作量大，属 minor 版本特性）；
B. 在 README / UI 明确「一次只支持一种格式」（README 已如实说明，但 UI 未提示）。

## 2.2 sing-box 的 hysteria(v1) 出站还要求 `up` / `down`（带宽）

**依据**：`output_singbox.lua:127` 有明确注释说明；本项目的节点模型不承载该字段，
凭空填默认值属于猜测，故不输出。

**影响**：导出到 sing-box 的 hysteria v1 节点需用户自行补 `up`/`down`。

**候选方案**：A. 保持现状（文档说明）；B. 在节点模型中增加 `up`/`down` 字段并贯通
解析 / 表单 / 输出（属新功能）。

## 2.3 hysteria(v1) 的上游 URI 规范未能核实

**依据**：上游文档站点持续 404，无法取得权威定义。`parse_hysteria` 只保证解析本
项目 `output_uri` 自身生成的链接形态（回环已验证），认不出的查询参数一律忽略而不
报错，不臆造参数语义。

**候选方案**：待上游文档可访问后核实并补全；或维持「回环保证」的现状。

## 2.4 `http` 不加入任何 UI 协议列表

**依据**：规格 §25 的权威协议表恰好是 10 个协议、不含 `http`。`node.lua` 的
`M.PROTOS` 实测为 10 项（vmess / vless / trojan / shadowsocks / ssr / hysteria2 /
tuic / hysteria / wireguard / socks），确实不含 `http`。它可由 Clash YAML / JSON
配置导入并正常导出（凭据已修），但不作为表单可选项。

**候选方案**：A. 维持现状（`http` 属「可导入可导出但不可手录」）；B. 加入 UI 列表
（需先确认规格 §25 是否有意排除）。

## 2.5 `parser_yaml.lua` 为死代码（**已删除 `[2.6.11-r1]`**）

**依据**：`parser.lua:6` `require` 了它，但全文对 `parser_yaml.` 的调用次数实测为
**0**。其中留有同样未归一的 `socks5` 映射。

**影响**：不影响运行，属清理项。

**候选方案**：A. 删除文件与 `require`；B. 保留（无害）。

## 2.6 AmneziaWG 3.0 / 3.1 新增的 9 个字段不被 `.conf` 解析器接受

**字段**：`HeaderProtectionKey`、`ContentPaddingAddition`、`RekeyAfterTime`、
`RekeyTimeout`、`RejectAfterTime`、`KeepaliveTimeout`、`MaxHandshakeAttempts`、
`RandomTrailers`、`DisableCookies`。

**依据**：实测这 9 个名字在 `parser.lua` 中**一处都不出现** —— 即 `.conf` 解析器
按已知键白名单映射，这 9 个键落在白名单外，**导入即丢弃**；但它们会从 Clash / JSON /
`wireguard://` 导入路径原样透传。

**影响**：同一节点经 `.conf` 导入与经 JSON 导入，得到的字段集**不一致**。

**状态：已修复（`[2.6.10-r1]` 复核）**。`parser.lua` 的 `.conf` 键映射表已收录全部
9 个 v3.0 / 3.1 键（`headerprotectionkey` → `header-protection-key` …
`disablecookies` → `disable-cookies`），并补入了 v1.5 的 `s3/s4/i1..i5/j1..j3/itime`。
其中 `random-trailers` / `disable-cookies` 是布尔字段，按 amneziawg-tools 的
`parse_bool`（只认 `on`/`off` 或十进制数）解析，非法值丢弃而不是原样透传 ——
留着会让 mihomo 解析该字段时报错。**本条无需再决策。**

---

# 三、更早的遗留项（2.5.x 记录，一并归档）

来源：CHANGELOG `[2.5.1-r1]` / `[2.5.0-r1]` 的「已知限制」。均为**已确认、未修复**。

## 3.1 LuCI 里 `amnezia-wg-option` 仍是单个 JSON 文本框

**依据**：`node.lua` 的 `PROTO_FIELDS.wireguard` 中 `amnezia-wg-option` 是**单个**
字段（实测该数组共 13 项，`amnezia-wg-option` 占其一），因此前端渲染成一个文本框，
需用户手写 JSON。数据本身能正确往返，但录入体验不佳。

**候选方案**：逐字段化（属新功能，按版本约定应进入 minor 版本）。

## 3.2 wget 后端的下载体积上限是**下载后**判断

**依据**：busybox wget 没有「下载前限流」的选项。响应体虽被丢弃，但请求已经发出。

**候选方案**：改用 curl（若有）或维持现状并在文档说明。

## 3.3 改名规则不支持括号内的「或」`(a|b)`

**依据**：Lua 模式无 alternation 语义，按字面处理。

**候选方案**：A. 维持现状并文档说明；B. 实现一个简单的 alternation 展开。

## 3.4 `check_public` 在无 DNS 解析能力时放行（fail-open）

**依据**：`http.lua` 实测代码为：

```lua
local ips = resolve(host)
if not ips then
    -- 无 DNS 解析能力：放行，交由下载工具处理（尽力而为）
    return true
end
```

即无 `nixio` 时任意主机名放行。另存在解析与下载之间的 TOCTOU 窗口。

**状态：已修复（`[2.6.8-r1]`）**。`http.lua` 现在解析不到主机名时返回
`false, "无法解析目标主机名"`（fail-closed），并额外拦截 `@`、空白、`%` 等
非法字符与 IPv6 字面量形式的私网地址。TOCTOU 窗口仍在（解析与下载之间），
但已不再是「任意主机名放行」。**本条无需再决策。**

## 3.5 wget 路径的重定向校验是**事后**的

**依据**：busybox wget 无 `--max-redirect`；响应体虽被丢弃但请求已经发出，且无法
限制下载体积。

**候选方案**：与 3.2 一并处理（改用 curl 或自实现 HTTP 客户端）。

---

# 四、P3：输出层代码级复审（`[2.6.10-r1]` 已修复）

对 8 个输出模块与 `output.lua` 做了逐行复审，按「生成的配置能否被目标客户端加载」
这一条标准筛出 11 项缺陷。**全部已修复、已补回归测试、并已对 `HEAD` 反向验证**
（`tests/output_layer_fixes_test.lua` 30 条断言、`tests/ss_plugin_test.lua` 25 条
断言在修复前失败，修复后全绿）。逐项记录如下。

| 编号 | 位置 | 缺陷 | 后果 |
|---|---|---|---|
| F1 | `output_clash_meta` | `ws-opts:` 写在 `if node.path` 内，只有 host 的 ws 节点输出悬空的 `headers:` | YAML 非法 / Host 被忽略，ws 握手被拒 |
| F2 | `output_v2ray` | 空传输层编码成 `[]` 而非 `{}` | Xray `UnmarshalTypeError`，拒绝启动 |
| F3 | `output_clash_meta` | 节点名与其它节点 / 策略组名 / 保留名冲突时不消解 | mihomo `proxies` 重名，拒绝加载整份配置 |
| F4 | `output_clash_meta` | `esc_yaml` 未引用以 `%` `!` `-` 开头的标量 | 非法 YAML，mihomo 解析失败 |
| F5 | `output_formats` | QX 的 vless 分支不输出 obfs / tls 参数 | 客户端按明文 tcp 连 ws 端口，必然失败且不报错 |
| F6 | `output_formats` | Surge 家族的 vless 分支不输出 ws 传输层 | 同上 |
| F7 | `output_formats` | 参数值里的逗号把凭据静默截断（`password=pa,ss` → `password=pa`） | 静默发错凭据 |
| F8 | `output_uri` | IPv6 字面量地址未加方括号 | authority 无法解析 |
| F9 | `output_clash_meta` | `amnezia-wg-option` 子键未转义 | 键名里的 `:` / 引号写坏 YAML 映射 |
| F10 | `output.lua` | `content_type_for` / `extension_for` 对空 target 落空（`""` 在 Lua 里是真值） | 正文与响应头 / 文件名后缀不一致 |
| F11 | 全链路 | shadowsocks 的 SIP003 `plugin` 被三个输出模块静默丢弃；表单保存时被清空 | 带 obfs / v2ray-plugin 的节点导出后连不上；界面上编辑一次即永久丢失插件配置 |

**F11 的处置依据**（均核对上游源码 / 文档，非推测）：

- **SIP002**：`SS-URI = "ss://" userinfo "@" host ":" port [ "/" ] [ "?" plugin ] [ "#" tag ]`，
  插件参数整体做百分号编码。
- **sing-box**：`shadowsocks` 出站只有 `plugin`（字符串，官方文档明确
  *"Only two are supported: obfs-local and v2ray-plugin"*）与 `plugin_opts`
  （SIP003 原始参数串，原样透传）。其余插件名会被拒绝，故按白名单过滤。
- **mihomo**：`plugin-opts` 是**映射**而非字符串，且名称与参数名都要翻译
  （`obfs-local`/`simple-obfs` → `obfs`，参数 `obfs` → `mode`、`obfs-host` → `host`）。
  `adapter/outbound/shadowsocks.go` 对这两类插件是**强校验**的：obfs 的 mode 不在
  `{tls,http}` 里报 `"ss %s obfs mode error"`，v2ray-plugin 的 mode 不是 `websocket`
  同样报错 —— 都会让整个 outbound 构造失败，进而**拒绝加载整份配置**。因此参数
  不全时宁可整个不输出插件，也不能输出一个必然被拒绝的组合。

**顺带修正的既有测试**：`tests/output_formats_test.lua` 原断言
`tuic alpn array joined` 期望 `alpn=h3,h2`。多值 alpn 在 Surge 家族的行语法里
表达不了（逗号分隔的 `key=value`，无转义），F7 的通用逗号检查会因此丢掉整个节点。
处置：alpn 是**协商提示**而非凭据，缺省时客户端用服务端给出的列表 —— 所以只省略
该参数、保留节点。断言已按此契约更新。

---

# 五、其余遗留项的修复建议（按推荐优先级排序）

**实施记录（`[2.6.11-r1]`）**：下表中 1.1 / 1.3 / 1.4 / 1.5 / 2.5 五项已按推荐方案
实施完毕，3.3 按方案 A 补了用户文档说明。每项都补了自包含回归测试，并对 `HEAD`
做了反向验证（新断言在修复前失败、修复后全绿）：

| 项 | 回归测试 | HEAD 上失败断言数 |
|---|---|---|
| 1.1 `mkdir` 锁 | `tests/list_lock_test.lua`（39 条） | 18 |
| 1.3 sing-box `transport` | `tests/singbox_transport_test.lua`（28 条） | 18 |
| 1.5 QX `tag=` 逗号 | `tests/qx_tag_comma_test.lua`（24 条） | 9 |

1.4 / 2.5 是删除死代码，无新增断言；1.4 顺带修复了 `tests/p2_batch7_test.lua`
中对已删模块的依赖（改为直接验证 `util.uuid`）。

实施中修正了两处**推荐方案本身**的疏漏，记录如下：

- **1.1**：`with_list_lock` 最初把锁目录写成常量 `M.LOCK_DIR`。测试普遍在
  `require` 之后改写 `core.DATA_DIR`，常量不会跟着变 —— 于是测试会去锁真实的
  `/etc/substore`。改为由 `M.DATA_DIR` 现算。另一处：全新安装时 `DATA_DIR` 尚不存在，
  `mkdir <DATA_DIR>/.lock` 失败，而失败在 `lock_acquire` 眼里等同于「他人持锁」，
  症状是第一次保存订阅就报「正被另一个进程修改」；已在取锁前先 `ensure_dirs()`。
- **1.1**：`M.merge` 是**只读**的（只读各订阅节点、过滤排序后返回数组），
  包进锁后一旦取锁失败会返回 `nil` 顶掉原本的数组，把「拿不到锁」变成调用方眼里的
  「没有数据」—— 比不加锁更糟。已移出包装列表。

| 项 | 推荐方案 | 理由 | 前置条件 |
|---|---|---|---|
| 1.1 H10 无锁 | ✅ **C**：`mkdir` 原子锁 + 陈旧锁回收 | 纯 Lua、无新依赖，本机**可测**（桩掉 `os.execute` / `os.time`）；崩溃残留锁由锁目录 mtime 自愈 | 已定阈值 `util.LOCK_STALE = 60` 秒 |
| 1.3 sing-box 读取侧 transport 丢失 | ✅ **已修复**（补 `transport` 解析） | 与 F5/F6/F11 同类：静默丢传输层 → 节点连不上；影响面更大 | 字段映射**已核实**（见 1.3 正文） |
| 1.4 死代码 + README 声明不符 | ✅ **已删除**死代码（并已随 `[2.6.10-r1]` 精简 README 声明） | 删去了「协议转换：任意协议 → 任意协议」的过度声明 | 已确认无任何 `require` |
| 1.5 QX `tag=` 逗号 | ✅ **B**：整体丢弃 | 见上文 | 已实施；QX 实际行为仍未实测（无 QX 环境），按「宁可丢节点也不输出损坏行」处理 |
| 2.1 混合格式文本导入 | **暂缓** | 需要「按行嗅探格式」的启发式，误判代价高于收益 | 无 |
| 2.2 hysteria v1 `up`/`down` | **暂缓** | 节点模型里没有带宽字段，补它属于新功能（应进 minor 版本） | 需先定字段名与单位 |
| 2.3 hysteria v1 URI 规范 | **维持现状** | 上游规范无法核实，按「不猜」原则不动 | 找到权威规范后再定 |
| 2.4 `http` 不进 UI | **暂缓** | 后端已完整支持，只是 UI 不暴露；补它属于新功能 | 无 |
| 2.5 `parser_yaml.lua` 死代码 | ✅ **已删除** | 死代码会被后续审计反复重新评估，成本高于收益 | 已确认只被 `parser.lua` 一行 `require` 引用、且从未使用 |
| 3.1 AWG 逐字段化 UI | **暂缓**（新功能，进 minor） | 数据往返已正确，仅录入体验 | 无 |
| 3.2 / 3.5 wget 体积与重定向 | **暂缓** | busybox wget 无对应选项；改 curl 或自实现 HTTP 客户端是大改动 | 无 |
| 3.3 改名规则 `(a\|b)` | ✅ **A**：维持现状 + 文档说明 | Lua 模式无 alternation；自实现展开要处理嵌套与字符类，收益低 | 已在 README.md / README.en.md 的「使用方法」补说明（顶层 `\|` 才是「或」，`(...)` 内按字面） |

---

# 附：P2 修复范围（不含本文件所列项）

P2 为审计表中**其余中危 / 低危**项中性质明确、无需另行决策的缺陷，例如
M6 / M9 / M13 / M14 / M16 / M17 / M18 / M19 / M23 / M24 / M25 / M26 / M27 / M30
与 L1 / L3～L6 / L8～L26 等。逐项修复并补回归测试，完成后在 CHANGELOG 中记录。
本文件所列各项**不在** P2 范围内。
