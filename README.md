# gl-sdk4-ui-xray (GL.iNet 4.x 原生全中文 Xray 透明代理面板)

专为 **GL-MT3000 (Beryl AX)** 等运行 **GL.iNet SDK 4.x（含最新 OpenWrt 25.12 `apk` 固件）** 的路由器打造的全中文、原生集成式 Xray 透明代理控制面板。

完全采用 GL.iNet 官方 `oui-httpd` + Vue 2 组件方案重写了 [`yichya/luci-app-xray`](https://github.com/yichya/luci-app-xray) 的全部前端配置页面，直接挂载在 **80 端口 GL.iNet 官方管理后台 $\to$ 应用 (Applications) $\to$ Xray 透明代理** 下，无需再进入 8080 端口操作全英文的 LuCI 界面。

---

## ✨ 功能特性

1. **100% 零侵入非破坏性安装**：不修改任何系统原有文件，仅在 GL.iNet 标准插件目录新增 4 个独立文件，支持随时一键无痕卸载。
2. **与 `luci-app-xray` 100% 双向无损兼容**：直接读写 `/etc/config/xray_core`，复用 `/usr/share/xray/gen_config.uc` 与 `nftables` 透明代理引擎。
3. **全中文 7 大功能标签页（完整覆盖原版 LuCI Xray 全部选项并增强）**：
   * **1. 基本设置与分流模式**：Xray 运行状态监控、国内/Google 实时延迟测速、TCP/UDP 主节点切换、一键切换“绕过中国大陆 / 全局代理”模式。
   * **2. 节点管理与订阅导入**：支持直接输入 **机场订阅 URL** 在线拉取，或批量粘贴 `ss://`、`vmess://`、`vless://`、`trojan://` 分享链接一键导入；内置全功能节点编辑器（支持 SS-2022、VMess、VLESS + XTLS-Vision + REALITY、Trojan、Hysteria2、SplitHTTP/XHTTP、WebSocket、gRPC 等）。
   * **3. DNS 与 FakeDNS**：Fast DNS、Secure DNS、直连/代理/去广告域名规则、FakeDNS 地址池、**一键在线更新 GeoIP / GeoSite 规则库**。
   * **4. 出站规则与流量嗅探**：GeoIP 国家代码直连列表、绕过/强制 IP 段、端口策略、流量域名嗅探 (`Sniffing` / `Route Only` / `BT 直连`)。
   * **5. 局域网设备与入站控制**：自动读取当前连接路由器的手机/电脑列表（MAC + 设备名），一键指定特定设备“强制直连不走代理”或“启用透明代理”；支持开启额外局域网 SOCKS5 / HTTP 代理端口。
   * **6. 高级参数与监控**：日志级别、Observatory 连通性观测器、Metrics 统计端口、防环回 Socket Mark (`255`)、连接超时策略与自定义 `ucode` 钩子。
   * **7. 配置预览与日志**：在页面内直接查看生成的 `/var/etc/xray/config.json` 与 `logread -e xray` 实时日志。

---

## 🚀 一键安装与更新（单 `.sh` 脚本搞定）

通过 SSH 登录路由器（`root@192.168.8.1`），执行以下单行命令即可完成安装（如系统尚未安装 `xray-core` 与 `luci-app-xray`，脚本会自动检测并在 OpenWrt 25.12 下完成安装）：

```sh
curl -fsSL https://raw.githubusercontent.com/dazhn/gl-sdk4-ui-xray/main/install.sh -o /root/install-xray-gl.sh && sh /root/install-xray-gl.sh
```

安装完成后，直接打开浏览器访问 `http://192.168.8.1`，点击左侧菜单栏 **【应用】 $\to$ 【Xray 透明代理】** 即可使用。

---

## 🗑️ 一键无痕卸载

如需卸载该原生面板（不会删除你已配置的节点和底层的 Xray 服务）：

```sh
sh /root/install-xray-gl.sh --uninstall
```

---

## 📂 目录结构说明

| 仓库文件 | 路由器安装路径 | 说明 |
| :--- | :--- | :--- |
| `install.sh` | `/root/install-xray-gl.sh` | **单文件自包含安装/卸载脚本**（内嵌以下全部文件，下载单个 `.sh` 即可独立运行） |
| `files/menu.json` | `/usr/share/oui/menu.d/xray.json` | GL.iNet 左侧导航栏菜单注册配置 |
| `files/validator.lua` | `/usr/share/gl-validator.d/xray.lua` | `oui-rpc` 参数校验白名单（放行中文别名与订阅 URL 特殊字符） |
| `files/rpc_xray.lua` | `/usr/lib/oui-httpd/rpc/xray` | Lua 5.1 后端 RPC 引擎（UCI 读写、订阅解析、连通性测试、服务控制） |
| `files/gl-sdk4-ui-xray.common.js` | `/www/views/gl-sdk4-ui-xray.common.js.gz` | 前端 Vue 2 视图包（自动 Gzip 压缩，体积仅 15.9 KB） |
