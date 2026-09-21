# Testing — luci-app-substore

## 单元测试
`tests/run_tests.lua` 覆盖：
- util: base64、json、url、hostport
- node: normalize、filter、dedup、sort、apply_rules
- parser: vmess/vless/trojan/ss 解析、格式检测

运行：`lua5.1 tests/run_tests.lua`

## 集成测试
1. 编译安装到目标设备
2. 添加订阅 URL，手动更新，验证节点数
3. 节点浏览：筛选、排序
4. 输出生成：Clash YAML / JSON / Base64
5. 定时更新：修改 Settings cron，验证 `/etc/cron.d/substore` 生成
6. 规则应用：设置协议过滤、关键词，验证节点列表/输出受影响

## 安全测试
- SSRF：尝试内网 URL，被拒绝
- 大响应：>10MB 被截断
- 恶意 Base64/JSON：解析失败不崩溃

## 回归测试
每次阶段发布前执行 `tests/run_tests.lua` 并在目标设备手动验证菜单/功能。
