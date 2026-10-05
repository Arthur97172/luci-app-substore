# Building — luci-app-substore

## Prerequisites

An OpenWrt / ImmortalWrt SDK or full source tree matching the target firmware version.

## Build

Place this package under the OpenWrt tree:

```bash
cd <openwrt-sdk-or-source>
# copy or symlink the package
cp -r <path>/luci-app-substore package/
make package/luci-app-substore/compile V=s
```

The `.ipk` (or `.apk` on apk-based builds) is produced under
`bin/packages/.../luci-app-substore_*.ipk`.

简体中文翻译是**独立包**，由 `feeds/luci/luci.mk` 按 `po/<lang>/` 目录自动生成，
主包的 install 步骤**不再**打包 `.lmo`（见 Makefile 末尾的说明）：

```bash
make package/luci-i18n-substore-zh-cn/compile V=s
```

产物为 `bin/packages/.../luci-i18n-substore-zh-cn_*.ipk`，内含
`/usr/lib/lua/luci/i18n/substore.zh-cn.lmo`。目录名必须是 `po/zh_Hans/`
（`LUCI_LANG` 的键）—— 写成 `po/zh-cn/` 时 luci.mk 会静默跳过，不生成任何包。

> NOTE: stage-0 skeleton has not yet been built/verified on a target device.
> This document will be updated once the build chain is validated (see docs/PLAN.md stage 0).