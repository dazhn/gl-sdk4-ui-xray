# gl-sdk4-ui-xray (GL.iNet 4.x 原生全中文 Xray 透明代理面板)

专为 **GL-MT3000 (Beryl AX)** 等运行 **GL.iNet SDK 4.x（含最新 OpenWrt 25.12 `apk` 固件）** 的路由器打造的全中文、原生集成式 Xray 透明代理控制面板。

完全采用 GL.iNet 官方 `oui-httpd` + Vue 2 组件方案重写了 [`yichya/luci-app-xray`](https://github.com/yichya/luci-app-xray) 的全部前端配置页面，直接挂载在 **80 端口 GL.iNet 官方管理后台 $\to$ 应用 (Applications) $\to$ Xray 透明代理** 下，无需再进入 8080 端口操作全英文的 LuCI 界面。

---

## ✨ 功能特性

1. **100% 零侵入非破坏性安装**：不修改任何系统原有文件，仅在 GL.iNet 标准插件目录新增 4 个独立模块文件（菜单、校验白名单、Lua RPC、Vue 视图），支持随时一键无痕卸载。
2. **与 `luci-app-xray` 100% 双向无损兼容**：直接增量读写 `/etc/config/xray_core`，复用 `/usr/share/xray/gen_config.uc` 与 `fw4 (nftables)` 透明代理引擎，并结合 `/var/etc/xray/01_firewall_include.nft` 精准识别 TProxy 透明代理挂载状态。
3. **非阻塞协程架构与实时遥测大盘**：后端全面采用 OpenResty `ngx.pipe.spawn` 异步非阻塞管道执行启停与探测；对接 `127.0.0.1:18888/debug/vars` 实时展示 Xray 内存占用、代理/直连上下行累计流量及 Observatory 各节点实时存活延迟。
4. **三大分流模式一键预设**：
   * **绕过中国大陆（白名单模式）**：大陆域名 (`geosite:cn`) 与大陆 IP (`geoip:cn`) 走本地直连，其余流量走代理。
   * **黑名单模式（v2rayN 同款规则）**：仅被封锁域名 (`geosite:gfw` / `geosite:greatfire`) 与海外核心服务 IP 段走代理，自动注入 `ucode` 钩子阻断 `udp:443` QUIC 并将其余流量兜底直连。
   * **全局代理模式**：除局域网私有地址外全部流量走代理。
5. **全中文 5 大功能标签页（职责分离、未保存变更提醒）**：
   * **1. 控制台与节点**：透明代理总开关、三大分流模式一键预设、IPv4/IPv6 TCP & UDP 四个独立多节点负载均衡池（支持 `random` / `leastPing` / `roundRobin`）、节点搜索与协议筛选、**机场订阅 URL / 分享链接（`ss://`、`vmess://`、`vless://`、`trojan://`、`hysteria2://`、`hy2://`，含 IPv6 字面量）批量导入**、节点行一键 `⚡ 设为主用` 及全参数可视化编辑弹窗（含 `VLESS-REALITY SpiderX`、`Hysteria2` 上下行带宽与端口跳跃、`Allow Insecure`、链式前置代理）。
   * **2. DNS 与分流规则**：Fast DNS、Secure DNS、Default DNS、直连/代理/去广告域名规则（单行自适应多行展开输入框）、GeoIP 直连代码、绕过/强制 IP 段、端口转发策略、流量域名嗅探 (`Sniffing` / `Route Only` / `BT 直连`) 及 **一键在线更新 GeoIP / GeoSite 规则库**（内置 GitHub 镜像与 jsDelivr CDN 自动回退及 `>1MB` 完整性校验）。
   * **3. 设备控制与入站**：自动读取当前局域网在线设备列表（MAC + IP + 主机名），一键指定特定设备“强制直连 (Bypass)”或“启用透明代理 (TProxy)”；支持添加额外 SOCKS5 / HTTP 入站端口并支持绑定指定出站节点（添加/删除即时生效）。
   * **4. 高级参数与监控**：日志级别、流量统计 (`stats`)、Observatory 连通性观测器、Metrics 监控接口 (`18888`)、Firewall4 计数器、防环回 Socket Mark (`255`)、连接超时与缓存大小 (`Buffer Size` 默认 `4 KB`)、IPv4 TCP/UDP 动态直连优化及自定义 `ucode` 配置钩子。
   * **5. 配置预览与日志**：在页面内直接查看当前生效的 `/var/etc/xray/config.json` 全文与 `logread -e xray` 实时日志，并提供 8080/8443 原版 LuCI 快捷入口。

---

## 🚀 一键安装与更新（单 `.sh` 脚本搞定）

通过 SSH 登录路由器（`root@192.168.8.1`），执行以下单行命令即可完成安装（如系统尚未安装 `xray-core`、`luci-app-xray` 或 `geoip.dat`/`geosite.dat`，脚本会自动检测并在 OpenWrt 25.12 下完成部署）：

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
| `files/menu.json` | `/usr/share/oui/menu.d/xray.json` | GL.iNet 左侧导航栏菜单注册配置（`index: 15`，兼容简体/繁体中文） |
| `files/validator.lua` | `/usr/share/gl-validator.d/xray.lua` | `oui-rpc` 参数校验白名单（13 个 RPC 方法） |
| `files/rpc_xray.lua` | `/usr/lib/oui-httpd/rpc/xray` | Lua 5.1 后端 RPC 引擎（UCI 读写、订阅解析、Metrics 采集、非阻塞服务控制） |
| `files/gl-sdk4-ui-xray.common.js` | `/www/views/gl-sdk4-ui-xray.common.js(.gz)` | 前端 Vue 2 视图包（自动 Gzip 预压缩，适配 Nginx `gzip_static`） |
| `PROGRESS.md` | - | 项目阶段里程碑、架构重构与验证记录文档 |
