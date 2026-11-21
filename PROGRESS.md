# gl-sdk4-ui-xray 项目进度文档

> **最后更新**：2026-11-21  
> **目标设备与固件**：GL-MT3000 (`192.168.8.1`) / GL.iNet SDK `4.11.0-op25`（底层 `OpenWrt 25.12.6`，`apk` 包管理）  
> **关联底座**：`xray-core` (`26.3.27`) + `luci-app-xray` (`v3.7.2`) + GL.iNet `oui-httpd` (Lua 5.1 / Vue 2)

---

## 一、 当前总体进度看板

| 模块 / 维度 | 状态 | 说明 |
| :--- | :---: | :--- |
| **菜单与参数校验** (`menu.json`, `validator.lua`) | ✅ 已完成 | 注册至 `applications` 菜单（`index: 15`，兼容简体/繁体中文），13 个 RPC 方法白名单对齐 |
| **Lua 5.1 后端引擎** (`rpc_xray.lua`) | ✅ 已完成 | UCI 读写、订阅/链接解析、服务同步启停 (`ngx.pipe.spawn`)、TProxy 状态判别、Metrics 解析 |
| **Vue 2 原生前端** (`gl-sdk4-ui-xray.common.js`) | ✅ 已完成 | 重构为职责分离的 5 个标签页，含未保存提醒、智能轮询、协议筛选、黑名单模式预设 |
| **一键安装脚本** (`install.sh`) | ✅ 已同步 | 单文件自包含安装包，与 `files/*` 完全同步，支持 `--uninstall` 无痕卸载与升级保留 |
| **路由器实机部署 (`192.168.8.1`)** | ✅ 已部署验证 | 2026-11-21 已上传全部组件与 `/root/install-xray-gl.sh` 并重载 Nginx，清理遗留 `buffer_size` |
| **Git 仓库提交** | ✅ 已同步 | 阶段 3 黑名单模式、5 标签页重构与文档已提交并推送至 `origin/main` |
| **项目说明同步 (`README.md`)** | ✅ 已更新 | 已同步为最新 5 标签页架构、v2rayN 黑名单模式与 18888 实时监控说明 |

---

## 二、 迭代里程碑与完成记录

### 阶段 1：底座探测与方案定型（2026-11-16）
* 完成 GL-MT3000 (`4.11.0-op25`) `oui/rpc.lua`、`oui-init.lua`、`app.ed74dff3.js.gz`、`gen_config.uc` 与 `uhttpd` 实机逆向与兼容性排查，确立免 Node.js 编译的纯文本 Lua 5.1 RPC + Vue 2 `render(h)` 集成方案。
* 输出并修订技术施工文档：[GL-MT3000_GL.iNet原生面板集成施工文档.md](file:///d:/Documents/Codex%20Projects/Chat/GL-MT3000_GL.iNet原生面板集成施工文档.md)。

### 阶段 2：基础功能开发与多轮审查修复（2026-11-16，`b380c0e` ~ `0d67616`）
* **`b380c0e` ~ `0d01905`**：搭建项目骨架，完成 `menu.json`、`validator.lua`、`rpc_xray.lua`、`gl-sdk4-ui-xray.common.js` 与自包含 `install.sh`（支持 OpenWrt 25.12 `apk` 自动安装 `xray-core`、`luci-app-xray` 与 Geo 规则库）。
* **`27f4b3f` ~ `ed04c90`**：实现多节点均衡池、节点搜索、单行自适应规则文本框，修正 LuCI 跳转路径为 `/cgi-bin/luci/admin/services/xray_core`。
* **`c421c3a` ~ `3982b96`**：接入 `127.0.0.1:18888/debug/vars` 实时流量/内存/Observatory 延迟监控，增强 GeoIP/GeoSite 在线更新（支持镜像与 jsDelivr CDN 回退及 `>1MB` 校验）。
* **`d86916e` ~ `0d67616`**：完成首轮与次轮深度审计修复：
  * 解决删节点残留引用、`replace_all` 覆写顺序、`tls_insecure` 默认值与 `vless_reality_spider_x` / `hysteria_up_mbps` 字段名错配；
  * 后端服务控制与命令执行改用 OpenResty 非阻塞 `ngx.pipe.spawn`；
  * 通过 `/var/etc/xray/01_firewall_include.nft` 区分“核心存活”与“TProxy 规则生效”；
  * URI 解析器补齐 IPv6 字面量、`vmess://` `#备注` 与 `hysteria2://` / `hy2://` 协议支持。

### 阶段 3：v2rayN 黑名单模式移植与架构重构（2026-11-21，工作区最新）
* **对照本地 `v2rayN` 实现黑名单模式**：
  * 对照 `D:\Program Files\v2rayN-windows-64\guiConfigs\guiNDB.db` 中的 `V4-绕过大陆(Whitelist)`、`V4-黑名单(Blacklist)` 与 `V4-全局(Global)` 规则，在前端 `applyRoutingPreset` 与后端 `M.switch_node` 中新增 **`黑名单模式 (v2rayN)`** 一键预设；
  * 自动配置 `geosite:gfw` / `geosite:greatfire` / `geosite:google` / 海外公共 DNS 域名、`default_dns = 223.5.5.5:53`、开启嗅探与 BT 直连，并通过带 `// __GL_XRAY_PRESET_BLACKLIST__` 标记的 `custom_configuration_hook` 实现阻断 `udp:443` (`blackhole_outbound`)、黑名单 IP 集走代理与最终兜底 `direct` 直连；切回其他预设时自动清理该标记钩子。
* **页面架构重构与冗余清理**：
  * 将原有 4 个臃肿标签页拆分为职责清晰的 **5 个标签页**：
    1. `1. 控制台与节点`（总开关、模式预设徽标、节点池、协议筛选、订阅导入、节点行一键 `⚡ 设为主用`）
    2. `2. DNS 与分流规则`（DNS、域名/GeoIP/IP/端口规则与嗅探）
    3. `3. 设备控制与入站`（即时生效的 `LAN Hosts` 与 `Extra Inbounds` 独立分页，移除误导性的底部全局保存栏）
    4. `4. 高级参数与监控`（补齐 `dynamic_direct_udp4` 开关、`buffer_size` 默认提示修正为 `4 KB`）
    5. `5. 配置预览与日志`（日志与 `config.json` 预览，LuCI 跳转按 `https:` 自动适配 `:8443`）
  * 新增未保存变更（`isDirty`）顶部提醒条；为全部异步操作补齐 `disabled` 防连点、`35000ms` 超时保护、`.catch()` 异常提示与 `deleteSubItem` 删除确认；`metricsTimer` 改为仅在 `metrics_server_enable == "1"` 且页面可见时轮询。
  * 清理死函数 `is_xray_running`、死状态 `fakedns/manual_tproxy/bridge`、冗余 UCI 写入字段 `vless_spider_x`/`hysteria_up`/`hysteria_down`；抽离 `split_uri_parts` 与 `safe_str`（防止 `cjson.null` 转成 `"userdata: ..."`）；在 `switch_node` 中加入节点存在性校验。

---

## 三、 当前代码结构与部署映射

| 仓库文件 | 路由器部署路径 | 当前状态 |
| :--- | :--- | :--- |
| [files/menu.json](file:///d:/Documents/Codex%20Projects/Chat/gl-sdk4-ui-xray/files/menu.json) | `/usr/share/oui/menu.d/xray.json` | 221 B，已部署 |
| [files/validator.lua](file:///d:/Documents/Codex%20Projects/Chat/gl-sdk4-ui-xray/files/validator.lua) | `/usr/share/gl-validator.d/xray.lua` | 466 B，已部署（13 个方法） |
| [files/rpc_xray.lua](file:///d:/Documents/Codex%20Projects/Chat/gl-sdk4-ui-xray/files/rpc_xray.lua) | `/usr/lib/oui-httpd/rpc/xray` | 40,950 B，已部署 |
| [files/gl-sdk4-ui-xray.common.js](file:///d:/Documents/Codex%20Projects/Chat/gl-sdk4-ui-xray/files/gl-sdk4-ui-xray.common.js) | `/www/views/gl-sdk4-ui-xray.common.js(.gz)` | 85,581 B / `.gz` 20,965 B，已部署 |
| [install.sh](file:///d:/Documents/Codex%20Projects/Chat/gl-sdk4-ui-xray/install.sh) | *(独立分发脚本)* | 133,392 B，与 `files/*` 同步 |

---

## 四、 最近一次验证记录（2026-11-21）

* **前端脚本校验**：Node.js `eval` 解析返回 `GlSdk4UiXray`（22 个 methods，未引用方法为 `[]`），预设切换与黑名单钩子清理测试通过。
* **Xray 规则校验**：通过本地 `xray.exe run -test` 结合 `geoip.dat` / `geosite.dat` 验证 `geosite:gfw`、`geosite:greatfire`、`geoip:facebook/fastly/google/netflix/telegram/twitter`、`blackhole_outbound` 与 `direct` 规则，返回 `Configuration OK.`。
* **路由器端校验**：
  * Lua 5.1 `loadfile` 语法检查通过（`xray.lua` 与 `rpc/xray`）；
  * `nginx -s reload` 成功；
  * `ui.get_menu_list` 成功检索到 `view: "xray"`；
  * `xray.get_all` 返回 `code=0, running=true, proc_running=true, tproxy_enabled=true, servers=48`；
  * `xray.test_connectivity` (`cn`) 返回 `{"ok":true,"http_code":204,"latency_ms":125}`。

---

## 五、 遗留事项与下一步计划

1. **清理路由器历史遗留 UCI 值（高优先级）**：
   * 路由器 `/etc/config/xray_core` 当前仍保留早期版本写入的 `buffer_size='512'`（`luci-app-xray` 默认仅 `4` KB）。需在面板 **Tab 4** 将 `每连接内部缓存大小` 清空（或填 `4`）后点击保存应用。
2. **提交当前工作区改动与同步文档**：
   * 将 `files/gl-sdk4-ui-xray.common.js`、`files/rpc_xray.lua`、`install.sh` 及本进度文档提交到 Git 仓库；
   * 同步更新 [README.md](file:///d:/Documents/Codex%20Projects/Chat/gl-sdk4-ui-xray/README.md) 中的标签页结构描述与“黑名单模式”特性说明。
3. **可选后续增强**：
   * 为 `update_geodata` 增加前端日志轮询（读取 `/tmp/xray_geo_update.log`）展示下载进度与结果；
   * 支持持久化保存机场订阅 URL，实现一键同步更新订阅；
   * 当节点数量继续增长时，为节点表格增加分页或批量 TCP 测速排序。
