# Installation — luci-app-substore

> NOTE: stage-0 skeleton has not yet been installed/verified on a target device.
> This document will be updated once installation is validated.

## Install (opkg)

```bash
opkg update
opkg install luci-app-substore_0.1.0_all.ipk
```

Refresh LuCI:

```bash
rm -f /tmp/luci-indexcache
/etc/init.d/luci reload
```

Then open LuCI menu: **Services → Subscriptions** (or **System → Subscriptions** depending on firmware).