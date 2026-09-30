# 遗留缺陷汇总（待决定修复方案）

本文件汇总截至 **2.6.1-r1** 的审计中**已确认但尚未修复**的问题，供决定后续修复
方案使用。每项给出：现象、代码级依据、影响面、候选方案与取舍。

编写纪律：只记录经**代码级审计或实测探针**确认的结论，不含推测。
原始审计表（70 项，14 HIGH / 30 MEDIUM / 26 LOW）未落盘保存，因此本文件自本次起
作为「未修复项」的权威清单。

已修复项见 [CHANGELOG.md](../CHANGELOG.md)。

---

## 1. H10 — `load()` → `save()` 之间的丢更新（lost update）

**现象**：订阅列表的读取与写回之间没有任何互斥，并发写会互相覆盖。

**代码级依据**：

- `core.lua` 的 `local function load()`（第 36 行起）读出整表，`local function save(seq, items)`
  （第 65 行起）把整表写回；两者之间是典型的 read-modify-write，中间无锁。
- `M.add` / `M.add_local` / `M.add_combo` / `M.save_meta` / `M.save_combo` 均走这条路径。
- `util.lua` 中**不存在任何锁原语**（无 `flock`、无 `mkdir` 锁、无 `link()`）；
  `atomic_write` 只保证「单次写入是原子的」，不保证「读-改-写是原子的」。
- `nixio` 在本项目中**只**用于 `http.lua:208-210` 的 `getaddrinfo`（经
  `util.try_require` 可选加载），`Makefile` 的 `LUCI_DEPENDS` 未声明 `+nixio`。

**并发来源**：LuCI 页面保存订阅、cron 定时更新（`substore-cron.sh`）、
组合订阅在源订阅更新后的自动重算——三者可能同时发生。

**影响**：后写者整表覆盖先写者，导致订阅丢失或新增丢失。后果与已修复的
H8（把「解析失败」当空列表）同属「数据被抹除」，但触发条件是并发而非文件损坏，
因此 H8 的修复**不覆盖**本项。

**候选方案**：

| 方案 | 做法 | 代价 / 风险 |
|---|---|---|
| A. 记为已知限制 | 文档说明「同一时间只应有一个写操作」 | 零成本，但用户无从感知，仍会丢数据 |
| B. 引入 `nixio` flock | `Makefile` 加 `+nixio`，写路径加文件锁 | 新增运行时依赖；本机无 OpenWrt/nixio 环境，**无法验证** |
| C. `mkdir` 锁 + 陈旧锁回收 | 用目录创建做互斥，带超时与持有者 PID 回收 | 纯 Lua 无依赖；需正确处理崩溃残留锁，否则死锁 |
| D. 写路径单点串行化 | 所有写入收敛到同一入口，UI 与 cron 经同一队列 | 改动面大，跨进程串行仍需 OS 级原语，实际仍需 B 或 C |

**建议**：待定。若倾向「不引入新依赖」，C 是唯一自包含的选项，但需要额外的
陈旧锁回收逻辑与相应测试；若可接受依赖，B 最可靠。

---

## 2. M28 / M29 — CSRF `post_ok()` 与 ACL

**状态**：**已决定跳过验证**（用户 2026-09-30 指示）。

**原因**：二者依赖 LuCI 框架的运行时行为（`test_post_security`、ACL 解析），
本机没有 LuCI 运行环境，无法做代码级确认。按「不靠猜」的纪律，未做改动。

**影响**：未确认，不等于无风险。建议在目标设备上以真实 LuCI 环境复核。

---

## 3. sing-box 读取侧：transport 整层丢失（实测确认，比原记录更严重）

**现象**：sing-box 配置中 ws / grpc / h2 的传输参数在导入后**完全丢失**，
节点退化为 tcp 直连。

**实测探针**（`parser.parse`，vmess + `transport: {type: ws, path: /ws, headers.Host}`）：

```
JSON -> proto=vmess net=tcp sni=a.com fp=nil   path=nil host=nil
YAML -> proto=vmess net=tcp sni=a.com fp=chrome path=nil host=nil
```

**代码级依据**：

- `parser_json_config.lua`（`parse_singbox_json`，314 行）全文**不含**
  `transport` / `path` / `host` / `utls` 任何一处。它读的是 `outbound.network`
  （第 129-131 行），而 sing-box 表达传输方式用的是 `transport.type`——
  该字段在 sing-box 出站里并不存在，因此 `net` 恒为默认值 `tcp`。
- 简易 YAML 解析器（`parser.lua`）只展开 `tls:` 子块，同样不处理 `transport`。

**影响**：机场/客户端导出 sing-box 配置时，ws / grpc / h2 节点占相当比例；
导入后全部按 tcp 直连，握手必然失败，且**不报错**——用户只看到「节点连不上」。
比原记录的「不读 path/host」更严重：连传输类型本身都没读进来。

**附带的不一致**（同一探针可见）：`tls.utls.fingerprint` 在 YAML 侧**已读**
（`fp=chrome`，P1 批次修复），JSON 侧**不读**（`fp=nil`）。两侧行为不一致。

**候选方案**：在 `parse_singbox_json` 中补 `transport.type` → `net`、
`transport.path` → `path`、`transport.headers.Host` → `host`、
`tls.utls.fingerprint` → `fp`；并让简易 YAML 侧同样处理 `transport`。
需先核实 sing-box 各 transport 的字段名（ws / grpc / http），**不凭记忆**。

---

## 4. `converter.lua` / `node_converter.lua` 为死代码，README 声明与实现不符

**现象**：README 声称支持「协议转换：任意协议 → 任意协议」，但应用中**没有任何
转换入口**。

**代码级依据**：

- `root/` 下**没有任何文件** `require` 这两个模块——唯一的引用是
  `converter.lua:7` 引用 `node_converter.lua`，以及 `tests/` 下的单元测试。
- LuCI controller（`controller/admin/substore.lua`）与前端 JS
  （`www/luci-static/resources/substore/*.js`）中**不存在**「转换」相关的路由或 UI。
- 因此两个模块连同其测试虽然在跑，但**不在任何用户可达路径上**。

**README 声明**：

- `README.md:59`：「- 协议转换：任意协议 → 任意协议」
- `README.en.md:68`：「- Protocol conversion: any node type → any other type」
- 紧接其后的 `README.md:60-62` 又说明「SSR 不能与 vmess/vless 等其它协议互转」，
  与上一行自相矛盾。

**候选方案**：

| 方案 | 做法 |
|---|---|
| A. 接入 UI | 在节点页/导出页暴露转换功能，按协议矩阵决定可用目标 |
| B. 删除 | 删除两个模块与其测试，修正 README 两处声明，消除矛盾 |

**建议**：待定。若短期不做转换功能，B 更诚实；若计划做，A 需先定义
「哪些协议可互转」的权威矩阵（现有 `node_converter` 的映射表可作为起点，
但需先审计其正确性）。

---

## 附：已确认修复、此处不再跟踪

- H1–H9、H11、H2、H3（P0 批次一～四）
- P1 批次 13 项 + 审计中实测确认的 4 项新缺陷
- 详见 [CHANGELOG.md](../CHANGELOG.md) 的 `[2.6.0-r2]` ～ `[2.6.1-r1]`
