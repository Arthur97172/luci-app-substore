#
# Copyright (C) 2026 luci-app-substore
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-substore
PKG_VERSION:=0.1.0
PKG_RELEASE:=10

LUCI_DEPENDS:=+luci-lua-runtime +luci-compat

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-substore
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=Airport subscription manager (Sub-Store like)
	PKGARCH:=all
	DEPENDS:=$(LUCI_DEPENDS)
endef

define Package/luci-app-substore/description
	Native OpenWrt / ImmortalWrt LuCI application for managing
	airport subscriptions, parsing proxy nodes, filtering, deduplicating,
	merging and generating client subscription configs.
	Sub-Store like experience, without Docker or external services.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-substore/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/substore $(1)/etc/config/substore

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-substore $(1)/etc/uci-defaults/99-substore

	$(INSTALL_DIR) $(1)/etc/cron.d
	$(INSTALL_CONF) ./root/etc/cron.d/substore $(1)/etc/cron.d/substore

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/substore-cron.sh $(1)/usr/bin/substore-cron.sh

	$(INSTALL_DIR) $(1)/usr/lib/lua/substore
	$(INSTALL_DATA) ./root/usr/share/substore/core.lua $(1)/usr/lib/lua/substore/core.lua
	$(INSTALL_DATA) ./root/usr/share/substore/util.lua $(1)/usr/lib/lua/substore/util.lua
	$(INSTALL_DATA) ./root/usr/share/substore/node.lua $(1)/usr/lib/lua/substore/node.lua
	$(INSTALL_DATA) ./root/usr/share/substore/parser.lua $(1)/usr/lib/lua/substore/parser.lua
	$(INSTALL_DATA) ./root/usr/share/substore/http.lua $(1)/usr/lib/lua/substore/http.lua
	$(INSTALL_DATA) ./root/usr/share/substore/output.lua $(1)/usr/lib/lua/substore/output.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/admin
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/admin/substore.lua $(1)/usr/lib/lua/luci/controller/admin/substore.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/substore
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/subscriptions.htm $(1)/usr/lib/lua/luci/view/substore/subscriptions.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/form.htm $(1)/usr/lib/lua/luci/view/substore/form.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/nodes.htm $(1)/usr/lib/lua/luci/view/substore/nodes.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/output.htm $(1)/usr/lib/lua/luci/view/substore/output.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/settings.htm $(1)/usr/lib/lua/luci/view/substore/settings.htm

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-substore.json $(1)/usr/share/luci/menu.d/luci-app-substore.json
endef

define Package/luci-app-substore/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	# 刷新 LuCI 缓存（现代 OpenWrt 已移除 lua 时代的 /lib/functions/luci.sh）
	rm -f /tmp/luci-indexcache
	[ -f /etc/init.d/luci ] && /etc/init.d/luci reload
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-substore))