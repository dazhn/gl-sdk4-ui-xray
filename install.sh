#!/bin/sh
# ==============================================================================
# Project: gl-sdk4-ui-xray (Native GL.iNet 4.x Full-Chinese UI for luci-app-xray)
# Target : GL-MT3000 / GL.iNet SDK 4.x (OpenWrt 21.02 ~ 25.12+, opkg & apk)
# Usage  :
#   Install   : sh install.sh
#   Uninstall : sh install.sh --uninstall
# ==============================================================================

set -e

MENU_FILE="/usr/share/oui/menu.d/xray.json"
VALIDATOR_FILE="/usr/share/gl-validator.d/xray.lua"
RPC_FILE="/usr/lib/oui-httpd/rpc/xray"
VIEW_JS="/www/views/gl-sdk4-ui-xray.common.js"
VIEW_GZ="/www/views/gl-sdk4-ui-xray.common.js.gz"

LUCI_XRAY_URL="https://github.com/dazhn/luci-app-xray/releases/download/v3.7.2/luci-app-xray_3.7.2-r1_all.apk"
LUCI_XRAY_STATUS_URL="https://github.com/dazhn/luci-app-xray/releases/download/v3.7.2/luci-app-xray-status_3.7.2-r1_all.apk"

say() { printf "\033[1;32m[gl-sdk4-ui-xray]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; exit 1; }

download_with_fallback() {
    local url="$1"
    local dest="$2"
    if curl -fsSL --connect-timeout 8 -m 60 -o "$dest" "$url" 2>/dev/null; then
        return 0
    fi
    warn "GitHub 直连较慢，尝试通过镜像加速下载..."
    for proxy in "https://ghfast.top/" "https://gh-proxy.com/"; do
        if curl -fsSL --connect-timeout 8 -m 60 -o "$dest" "${proxy}${url}" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

[ "$(id -u)" = "0" ] || die "请使用 root 权限运行此脚本 (Please run as root)"

if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "uninstall" ] || [ "${1:-}" = "remove" ]; then
    say "正在从 GL.iNet 管理面板移除 Xray 原生页面..."
    rm -f "$MENU_FILE" "$VALIDATOR_FILE" "$RPC_FILE" "$VIEW_JS" "$VIEW_GZ"
    if [ -f /etc/sysupgrade.conf ]; then
        sed -i '\|/usr/share/oui/menu.d/xray.json|d' /etc/sysupgrade.conf
        sed -i '\|/usr/share/gl-validator.d/xray.lua|d' /etc/sysupgrade.conf
        sed -i '\|/usr/lib/oui-httpd/rpc/xray|d' /etc/sysupgrade.conf
        sed -i '\|/www/views/gl-sdk4-ui-xray.common.js|d' /etc/sysupgrade.conf
    fi
    nginx -s reload >/dev/null 2>&1 || true
    say "已彻底卸载并恢复原状（底层 xray_core 配置未受影响）。"
    exit 0
fi

[ -d /usr/share/oui/menu.d ] && [ -d /usr/lib/oui-httpd/rpc ] && [ -d /www/views ] || \
    die "未检测到 GL.iNet SDK4 (oui-httpd) 目录结构，请确认当前设备为 GL.iNet 官方固件。"

# 1. Auto-install xray-core and luci-app-xray if missing
if ! command -v xray >/dev/null 2>&1 || [ ! -f /etc/init.d/xray_core ]; then
    say "检测到系统尚未完整安装 xray-core 或 luci-app-xray，开始自动部署依赖..."
    if command -v apk >/dev/null 2>&1; then
        apk update || true
        if ! command -v xray >/dev/null 2>&1; then
            say "正在从官方软件源安装 xray-core..."
            apk add xray-core
        fi
        if [ ! -f /etc/init.d/xray_core ]; then
            say "正在下载并安装 luci-app-xray (OpenWrt 25.12 APK)..."
            TMP_APK1="/tmp/luci-app-xray.apk"
            TMP_APK2="/tmp/luci-app-xray-status.apk"
            if download_with_fallback "$LUCI_XRAY_URL" "$TMP_APK1"; then
                if download_with_fallback "$LUCI_XRAY_STATUS_URL" "$TMP_APK2"; then
                    apk add --allow-untrusted "$TMP_APK1" "$TMP_APK2"
                else
                    apk add --allow-untrusted "$TMP_APK1"
                fi
                rm -f "$TMP_APK1" "$TMP_APK2"
            else
                die "下载 luci-app-xray.apk 失败，请检查网络连接！"
            fi
        fi
    elif command -v opkg >/dev/null 2>&1; then
        opkg update || true
        command -v xray >/dev/null 2>&1 || opkg install xray-core
    fi
else
    say "检测到 xray-core 与 luci-app-xray 已安装，直接部署原生面板。"
fi

# 2. Ensure geoip.dat and geosite.dat exist under /usr/share/xray
mkdir -p /usr/share/xray
if [ ! -s /usr/share/xray/geoip.dat ] || [ ! -s /usr/share/xray/geosite.dat ]; then
    say "检测到 /usr/share/xray 缺少 geoip.dat 或 geosite.dat，正在自动安装规则库..."
    if command -v apk >/dev/null 2>&1; then
        apk add v2ray-geoip v2ray-geosite >/dev/null 2>&1 || true
    fi
    if [ ! -s /usr/share/xray/geoip.dat ]; then
        download_with_fallback "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" "/usr/share/xray/geoip.dat" || true
    fi
    if [ ! -s /usr/share/xray/geosite.dat ]; then
        download_with_fallback "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" "/usr/share/xray/geosite.dat" || true
    fi
fi

mkdir -p /usr/share/oui/menu.d /usr/share/gl-validator.d /usr/lib/oui-httpd/rpc /www/views

say "1/4 正在写入 GL.iNet 左侧导航菜单配置 ($MENU_FILE)..."
cat << 'EOF_MENU_JSON' > "$MENU_FILE"
{
    "index": 15,
    "view": "xray",
    "title": "Xray 透明代理",
    "level": 2,
    "parent": "applications",
    "parent_icon": "application",
    "parent_index": 55,
    "show_mode": [
        "router"
    ]
}
EOF_MENU_JSON

say "2/4 正在写入 RPC 参数校验白名单 ($VALIDATOR_FILE)..."
cat << 'EOF_VALIDATOR_LUA' > "$VALIDATOR_FILE"
-- /usr/share/gl-validator.d/xray.lua
-- Allow complex JSON objects, Chinese aliases, and URL characters in xray RPC methods
return {
    get_all = true,
    save_general = true,
    save_server = true,
    delete_server = true,
    import_links = true,
    save_subsection = true,
    delete_subsection = true,
    service_ctl = true,
    test_connectivity = true,
    get_preview = true,
    update_geodata = true,
    get_metrics = true
}
EOF_VALIDATOR_LUA

say "3/4 正在写入 Lua 5.1 后端 RPC 引擎 ($RPC_FILE)..."
cat << 'EOF_RPC_LUA' > "$RPC_FILE"
-- /usr/lib/oui-httpd/rpc/xray
-- Full-featured GL.iNet SDK4 RPC backend for luci-app-xray (OpenWrt 25.12 / Lua 5.1)

local uci = require "uci"
local ubus = require "oui.ubus"
local fs = require "oui.fs"
local cjson = require "cjson"

local M = {}

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_file(path, max_bytes)
    local f = io.open(path, "r")
    if not f then return nil end
    local s
    if max_bytes then
        s = f:read(max_bytes)
    else
        s = f:read("*a")
    end
    f:close()
    return s
end

local function file_size_mb(path)
    local f = io.open(path, "rb")
    if not f then return false, "0 MB" end
    local sz = f:seek("end") or 0
    f:close()
    return sz > 0, string.format("%.2f MB", sz / (1024 * 1024))
end

-- Non-blocking subprocess stdout reader via OpenResty ngx.pipe.spawn
local function spawn_read(cmd, timeout_ms)
    if ngx and ngx.pipe and ngx.pipe.spawn then
        local ok, proc = pcall(ngx.pipe.spawn, cmd, {
            stdout_read_timeout = timeout_ms or 10000
        })
        if ok and proc then
            local out = proc:stdout_read_all() or ""
            pcall(function() proc:wait() end)
            return out
        end
    end
    local cmd_str
    if type(cmd) == "table" then
        local parts = {}
        for _, arg in ipairs(cmd) do
            parts[#parts + 1] = "'" .. tostring(arg):gsub("'", "'\\''") .. "'"
        end
        cmd_str = table.concat(parts, " ")
    else
        cmd_str = tostring(cmd)
    end
    local f = io.popen(cmd_str)
    local out = f and f:read("*a") or ""
    if f then f:close() end
    return out
end

local function safe_str(v, fallback)
    if v == nil or v == cjson.null or type(v) == "table" then
        return fallback or ""
    end
    return tostring(v)
end

-- Synchronous (non-blocking coroutine wait) service control via ngx.pipe.spawn
local function service_exec(action)
    if ngx and ngx.pipe and ngx.pipe.spawn then
        local ok, proc = pcall(ngx.pipe.spawn, { "/etc/init.d/xray_core", action }, {
            stdout_read_timeout = 30000
        })
        if ok and proc then
            pcall(function() proc:wait() end)
            return true
        end
    end
    os.execute("/etc/init.d/xray_core " .. action .. " >/dev/null 2>&1")
    return true
end

local function url_decode(s)
    if not s then return "" end
    s = s:gsub("+", " ")
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64_decode(data)
    if type(data) ~= "string" or data == "" then return "" end
    data = data:gsub("-", "+"):gsub("_", "/")
    data = data:gsub("[^" .. b64chars .. "=]", "")
    local rem = #data % 4
    if rem == 2 then data = data .. "=="
    elseif rem == 3 then data = data .. "=" end
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (b64chars:find(x) - 1)
        for i = 6, 1, -1 do
            r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0")
        end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do
            c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0)
        end
        return string.char(c)
    end))
end

local function get_general_section(c)
    local sec_name, sec_data
    c:foreach("xray_core", "general", function(s)
        if not sec_name then
            sec_name = s[".name"]
            sec_data = s
        end
    end)
    if not sec_name then
        sec_name = c:add("xray_core", "general")
        sec_data = {}
    end
    return sec_name, sec_data
end

local function clean_uci_section(s)
    local out = {}
    for k, v in pairs(s) do
        if k:sub(1, 1) ~= "." then
            out[k] = v
        end
    end
    out[".name"] = s[".name"]
    out[".index"] = s[".index"] or 0
    return out
end

local function get_lan_clients()
    local clients = {}
    local seen = {}
    local leases = read_file("/tmp/dhcp.leases") or ""
    for line in leases:gmatch("[^\r\n]+") do
        local _, mac, ip, name = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if mac and not seen[mac:upper()] then
            seen[mac:upper()] = true
            clients[#clients + 1] = {
                mac = mac:upper(),
                ip = ip or "",
                name = (name and name ~= "*") and name or ip or mac
            }
        end
    end
    return clients
end

-- Check both xray process status and /var/etc/xray/01_firewall_include.nft TProxy rule file
local function get_xray_status(gen)
    local proc_alive = false
    local ok_u, svc = pcall(ubus.call, "service", "list", { name = "xray_core" })
    if ok_u and svc and svc.xray_core and svc.xray_core.instances then
        for _, inst in pairs(svc.xray_core.instances) do
            if inst.running then
                proc_alive = true
                break
            end
        end
    end
    if not proc_alive then
        local pid = trim(spawn_read({ "pidof", "xray" }, 2000))
        proc_alive = (pid ~= "")
    end

    local tproxy_active = fs.access("/var/etc/xray/01_firewall_include.nft") and true or false
    local want_tproxy = (not gen) or (gen.transparent_proxy_enable == "1")
    local running = proc_alive and (not want_tproxy or tproxy_active)
    return running, proc_alive, tproxy_active
end

local function apply_uci_fields(c, pkg, sec, values)
    for k, v in pairs(values) do
        if type(k) == "string" and not k:match("^%.") and k:match("^[%w_]+$") then
            if v == nil or v == "" or v == false then
                c:delete(pkg, sec, k)
            elseif v == true then
                c:set(pkg, sec, k, "1")
            elseif type(v) == "table" then
                local list = {}
                for _, item in ipairs(v) do
                    local s = trim(tostring(item))
                    if s ~= "" then list[#list + 1] = s end
                end
                if #list > 0 then
                    c:set(pkg, sec, k, list)
                else
                    c:delete(pkg, sec, k)
                end
            else
                c:set(pkg, sec, k, tostring(v))
            end
        end
    end
end

-- Clean up references to deleted server IDs across general balancers, servers.dialer_proxy, and extra_inbound.destination
local function cleanup_deleted_server_refs(c, deleted_map)
    local changed = false
    local gen_id, gen = get_general_section(c)
    if gen_id and gen then
        for _, pool_key in ipairs({ "tcp_balancer_v4", "udp_balancer_v4", "tcp_balancer_v6", "udp_balancer_v6" }) do
            local pool = gen[pool_key]
            if type(pool) == "string" then pool = { pool } end
            if type(pool) == "table" then
                local filtered = {}
                for _, item in ipairs(pool) do
                    if deleted_map[item] then
                        changed = true
                    else
                        filtered[#filtered + 1] = item
                    end
                end
                if #filtered ~= #pool then
                    if #filtered > 0 then
                        c:set("xray_core", gen_id, pool_key, filtered)
                    else
                        c:delete("xray_core", gen_id, pool_key)
                    end
                end
            end
        end
    end

    c:foreach("xray_core", "servers", function(s)
        local s_id = s[".name"]
        if not deleted_map[s_id] and s.dialer_proxy and deleted_map[s.dialer_proxy] then
            c:set("xray_core", s_id, "dialer_proxy", "disabled")
            changed = true
        end
    end)

    c:foreach("xray_core", "extra_inbound", function(ib)
        local ib_id = ib[".name"]
        local dest = ib.destination
        if type(dest) == "string" then dest = { dest } end
        if type(dest) == "table" then
            local filtered = {}
            for _, item in ipairs(dest) do
                if deleted_map[item] then
                    changed = true
                else
                    filtered[#filtered + 1] = item
                end
            end
            if #filtered ~= #dest then
                if #filtered > 0 then
                    c:set("xray_core", ib_id, "destination", filtered)
                else
                    c:delete("xray_core", ib_id, "destination")
                    c:set("xray_core", ib_id, "specify_outbound", "0")
                end
            end
        end
    end)

    return changed
end

local function fetch_metrics_summary(port)
    port = tonumber(port) or 18888
    local url = string.format("http://127.0.0.1:%d/debug/vars", port)
    local raw = spawn_read({ "curl", "-s", "--connect-timeout", "1", "-m", "2", url }, 3000)
    if not raw or raw == "" then return nil end

    local ok, j = pcall(cjson.decode, raw)
    if not ok or type(j) ~= "table" then return nil end

    local mem_mb = "0 MB"
    if type(j.memstats) == "table" and tonumber(j.memstats.Alloc) then
        mem_mb = string.format("%.1f MB", tonumber(j.memstats.Alloc) / (1024 * 1024))
    end

    local direct_delay = nil
    local nodes = {}

    if type(j.observatory) == "table" then
        for tag, info in pairs(j.observatory) do
            if type(info) == "table" then
                if tag == "direct" then
                    direct_delay = info.alive and tonumber(info.delay) or -1
                else
                    local srv_id = tag:match(":([^:]+)$")
                    if srv_id then
                        nodes[srv_id] = nodes[srv_id] or { alive = false, delay = 0, up = 0, down = 0 }
                        if info.alive then
                            nodes[srv_id].alive = true
                            local d = tonumber(info.delay) or 0
                            if nodes[srv_id].delay == 0 or (d > 0 and d < nodes[srv_id].delay) then
                                nodes[srv_id].delay = d
                            end
                        end
                    end
                end
            end
        end
    end

    local proxy_up, proxy_down = 0, 0
    local direct_up, direct_down = 0, 0

    if type(j.stats) == "table" and type(j.stats.outbound) == "table" then
        for tag, st in pairs(j.stats.outbound) do
            if type(st) == "table" then
                local up = tonumber(st.uplink) or 0
                local down = tonumber(st.downlink) or 0
                if tag == "direct" or tag == "dynamic_direct" then
                    direct_up = direct_up + up
                    direct_down = direct_down + down
                else
                    local srv_id = tag:match(":([^:]+)$")
                    if srv_id then
                        proxy_up = proxy_up + up
                        proxy_down = proxy_down + down
                        nodes[srv_id] = nodes[srv_id] or { alive = true, delay = 0, up = 0, down = 0 }
                        nodes[srv_id].up = nodes[srv_id].up + up
                        nodes[srv_id].down = nodes[srv_id].down + down
                    end
                end
            end
        end
    end

    return {
        mem_mb = mem_mb,
        direct_delay = direct_delay,
        proxy_up = proxy_up,
        proxy_down = proxy_down,
        direct_up = direct_up,
        direct_down = direct_down,
        nodes = nodes
    }
end

-- 1. Get complete UCI state + runtime status + LAN clients
function M.get_all()
    local c = uci.cursor()
    local gen_id, gen = get_general_section(c)

    local servers = {}
    c:foreach("xray_core", "servers", function(s)
        servers[#servers + 1] = clean_uci_section(s)
    end)
    table.sort(servers, function(a, b)
        return (a[".index"] or 0) < (b[".index"] or 0)
    end)

    local sub_types = { "lan_hosts", "extra_inbound" }
    local subsections = {}
    for _, st in ipairs(sub_types) do
        local list = {}
        c:foreach("xray_core", st, function(s)
            list[#list + 1] = clean_uci_section(s)
        end)
        table.sort(list, function(a, b)
            return (a[".index"] or 0) < (b[".index"] or 0)
        end)
        subsections[st] = list
    end

    local geoip_ok, geoip_sz = file_size_mb("/usr/share/xray/geoip.dat")
    local geosite_ok, geosite_sz = file_size_mb("/usr/share/xray/geosite.dat")
    local geo_status = fs.access("/tmp/xray_geo_update.status") and trim(read_file("/tmp/xray_geo_update.status") or "") or ""
    local running, proc_alive, tproxy_active = get_xray_status(gen)
    local metrics = (proc_alive and gen.metrics_server_enable == "1") and fetch_metrics_summary(gen.metrics_server_port) or nil

    return {
        code = 0,
        data = {
            running = running,
            proc_running = proc_alive,
            tproxy_enabled = tproxy_active,
            geoip_ok = geoip_ok,
            geoip_size = geoip_sz,
            geosite_ok = geosite_ok,
            geosite_size = geosite_sz,
            geo_status = geo_status,
            metrics = metrics,
            general_id = gen_id,
            general = clean_uci_section(gen),
            servers = servers,
            subsections = subsections,
            lan_clients = get_lan_clients()
        }
    }
end

function M.get_metrics()
    local c = uci.cursor()
    local _, gen = get_general_section(c)
    local running, proc_alive, tproxy_active = get_xray_status(gen)
    local out = {
        running = running,
        proc_running = proc_alive,
        tproxy_enabled = tproxy_active,
        metrics = (proc_alive and gen and gen.metrics_server_enable == "1") and fetch_metrics_summary(gen.metrics_server_port) or nil
    }
    if fs.access("/tmp/xray_geo_update.status") then
        local geo_status = trim(read_file("/tmp/xray_geo_update.status") or "")
        out.geo_status = geo_status
        if geo_status == "ok" or geo_status == "err" then
            os.remove("/tmp/xray_geo_update.status")
            local geoip_ok, geoip_sz = file_size_mb("/usr/share/xray/geoip.dat")
            local geosite_ok, geosite_sz = file_size_mb("/usr/share/xray/geosite.dat")
            out.geoip_ok = geoip_ok
            out.geoip_size = geoip_sz
            out.geosite_ok = geosite_ok
            out.geosite_size = geosite_sz
        end
    end
    return {
        code = 0,
        data = out
    }
end

-- 2. Save general settings (incremental non-destructive update)
function M.save_general(args)
    if type(args) ~= "table" or type(args.values) ~= "table" then
        return { code = -1, error = "参数格式错误" }
    end
    local c = uci.cursor()
    local gen_id = get_general_section(c)
    apply_uci_fields(c, "xray_core", gen_id, args.values)
    c:commit("xray_core")

    if args.apply ~= false then
        service_exec("restart")
    end
    return { code = 0, data = { ok = true } }
end

-- Helper: generate next srv_XXXXX section name
local function next_server_id(c)
    local max_n = 0
    c:foreach("xray_core", "servers", function(s)
        local n = tonumber((s[".name"] or ""):match("^srv_(%d+)$"))
        if n and n > max_n then max_n = n end
    end)
    return string.format("srv_%05d", max_n + 1)
end

-- 4. Save or create a server node
function M.save_server(args)
    if type(args) ~= "table" or type(args.values) ~= "table" then
        return { code = -1, error = "节点参数错误" }
    end
    local c = uci.cursor()
    local sec = args.id
    if not sec or sec == "" then
        sec = next_server_id(c)
        c:set("xray_core", sec, "servers")
    else
        if c:get("xray_core", sec) ~= "servers" then
            c:set("xray_core", sec, "servers")
        end
    end

    apply_uci_fields(c, "xray_core", sec, args.values)
    c:commit("xray_core")
    if args.apply then
        service_exec("restart")
    end
    return { code = 0, data = { id = sec } }
end

-- 5. Delete a server node (clean up balancers, dialer_proxy, extra_inbound.destination & restart if active)
function M.delete_server(args)
    if type(args) ~= "table" or type(args.id) ~= "string" or args.id == "" then
        return { code = -1, error = "未指定节点 ID" }
    end
    local c = uci.cursor()
    if c:get("xray_core", args.id) ~= "servers" then
        return { code = -1, error = "目标不是有效的服务器节点" }
    end

    local _, gen = get_general_section(c)
    local _, proc_alive = get_xray_status(gen)

    c:delete("xray_core", args.id)
    local ref_changed = cleanup_deleted_server_refs(c, { [args.id] = true })
    c:commit("xray_core")

    if (ref_changed or args.apply) and proc_alive then
        service_exec("restart")
    end
    return { code = 0, data = { ok = true, restarted = (ref_changed and proc_alive) or false } }
end

-- 6. Parse URI share links (ss://, vmess://, vless://, trojan://, hysteria2://, hy2://) and subscription URLs
local function parse_query(qs)
    local q = {}
    if not qs then return q end
    for pair in qs:gmatch("[^&]+") do
        local k, v = pair:match("^([^=]+)=(.*)$")
        if k then q[url_decode(k)] = url_decode(v) end
    end
    return q
end

-- Parse host:port with support for IPv6 literal ([...]:port), trailing slash (:443/...), and Hysteria2 port hopping (:443,20000-50000)
local function parse_host_port(hp)
    if not hp or hp == "" then return nil, nil, nil end
    local url_path = hp:match("^[^/]+(/.*)$")
    hp = hp:gsub("/.*$", "")

    local host, port_spec
    if hp:sub(1, 1) == "[" then
        host, port_spec = hp:match("^%[([^%]]+)%]:(.+)$")
        if not host then
            host = hp:match("^%[([^%]]+)%]$")
        end
    else
        host, port_spec = hp:match("^([^:]+):(.+)$")
        if not host then
            host = hp
        end
    end
    if not host or host == "" then return nil, nil, nil end

    local port, hop_port
    if port_spec and port_spec ~= "" then
        local p1, rest = port_spec:match("^(%d+),(.+)$")
        if p1 then
            port = p1
            hop_port = rest
        else
            local single_p = port_spec:match("^(%d+)$")
            if single_p then
                port = single_p
            else
                local range_start = port_spec:match("^(%d+)%-%d+$")
                if range_start then
                    port = range_start
                    hop_port = port_spec
                end
            end
        end
    end

    return host, port, hop_port, url_path
end

local function split_uri_parts(rest)
    local alias = ""
    local hash_pos = rest:find("#", 1, true)
    if hash_pos then
        alias = url_decode(rest:sub(hash_pos + 1))
        rest = rest:sub(1, hash_pos - 1)
    end
    local qs = ""
    local q_pos = rest:find("?", 1, true)
    if q_pos then
        qs = rest:sub(q_pos + 1)
        rest = rest:sub(1, q_pos - 1)
    end
    return rest, alias, qs
end

local function parse_single_uri(line)
    line = trim(line)
    if line == "" then return nil end

    -- 1. vmess:// (base64 JSON, with optional #remark suffix)
    if line:match("^vmess://") then
        local rest, hash_alias = split_uri_parts(line:sub(9))
        local raw = base64_decode(rest)
        local ok, j = pcall(cjson.decode, raw)
        local j_add = ok and type(j) == "table" and safe_str(j.add) or ""
        local j_port = ok and type(j) == "table" and safe_str(j.port) or ""
        if j_add ~= "" and j_port ~= "" then
            local net = safe_str(j.net, "tcp")
            if net == "" then net = "tcp" end
            if net == "xhttp" then net = "splithttp" end
            local j_tls = safe_str(j.tls)
            local tls_mode = (j_tls == "tls" or j_tls == "1") and "tls" or "none"
            local j_ps = safe_str(j.ps)
            local j_host = safe_str(j.host)
            local j_path = safe_str(j.path)
            local j_sni = safe_str(j.sni)
            local j_aid = safe_str(j.aid, "0")
            if j_aid == "" then j_aid = "0" end
            local alias_val = (j_ps ~= "" and j_ps)
                or (hash_alias ~= "" and hash_alias)
                or (j_add .. ":" .. j_port)
            local srv = {
                alias = alias_val,
                server = j_add,
                server_port = { j_port },
                password = safe_str(j.id),
                protocol = "vmess",
                vmess_security = safe_str(j.scy, "auto"),
                alter_id = j_aid,
                vmess_tls = tls_mode,
                transport = net,
                domain_strategy = "UseIP",
                dialer_proxy = "disabled"
            }
            if srv.vmess_security == "" then srv.vmess_security = "auto" end
            if net == "tcp" then
                srv.tcp_guise = (safe_str(j.type) == "http") and "http" or "none"
                if j_host ~= "" then srv.http_host = { j_host } end
                if j_path ~= "" then srv.http_path = { j_path } end
            elseif net == "ws" then
                srv.ws_host = j_host
                srv.ws_path = j_path ~= "" and j_path or "/"
            elseif net == "grpc" then
                srv.grpc_service_name = j_path
            elseif net == "splithttp" then
                srv.splithttp_host = j_host
                srv.splithttp_path = j_path ~= "" and j_path or "/"
            elseif net == "httpupgrade" then
                srv.httpupgrade_host = j_host
                srv.httpupgrade_path = j_path ~= "" and j_path or "/"
            end
            if tls_mode == "tls" then
                srv.vmess_tls_host = j_sni ~= "" and j_sni or j_host
                srv.vmess_tls_insecure = (j.allowInsecure == true or safe_str(j.allowInsecure) == "1" or safe_str(j.insecure) == "1") and "1" or "0"
                srv.vmess_tls_fingerprint = safe_str(j.fp, "chrome")
                if srv.vmess_tls_fingerprint == "" then srv.vmess_tls_fingerprint = "chrome" end
            end
            return srv
        end
        return nil
    end

    -- 2. ss:// (SIP002 & legacy base64, IPv4 & IPv6 literal)
    if line:match("^ss://") then
        local rest, alias = split_uri_parts(line:sub(6))

        local userinfo, hostport = rest:match("^([^@]+)@(.+)$")
        local method, pass, host, port
        if userinfo and hostport then
            if not userinfo:find(":", 1, true) then
                userinfo = base64_decode(userinfo)
            else
                userinfo = url_decode(userinfo)
            end
            method, pass = userinfo:match("^([^:]+):(.+)$")
            host, port = parse_host_port(hostport)
        else
            local decoded = base64_decode(rest)
            local d_user, d_hp = decoded:match("^(.+)@([^@]+)$")
            if d_user and d_hp then
                method, pass = d_user:match("^([^:]+):(.+)$")
                host, port = parse_host_port(d_hp)
            end
        end

        if method and pass and host and port then
            return {
                alias = (alias ~= "" and alias) or (host .. ":" .. port),
                server = host,
                server_port = { port },
                password = pass,
                protocol = "shadowsocks",
                shadowsocks_security = method:lower(),
                shadowsocks_udp_over_tcp = "0",
                shadowsocks_tls = "none",
                transport = "tcp",
                tcp_guise = "none",
                domain_strategy = "UseIP",
                dialer_proxy = "disabled"
            }
        end
        return nil
    end

    -- 3. hysteria2:// and hy2://
    local hy_prefix = line:match("^(hysteria2)://") or line:match("^(hy2)://")
    if hy_prefix then
        local rest, alias, qs = split_uri_parts(line:sub(#hy_prefix + 4))
        local auth, hostport = rest:match("^([^@]+)@(.+)$")
        if not auth then
            auth = ""
            hostport = rest
        else
            auth = url_decode(auth)
        end
        local host, port, hop_port = parse_host_port(hostport)
        if not host then return nil end
        port = port or "443"

        local q = parse_query(qs)
        local up_val = (q.upmbps or q.up or ""):match("^(%d+)") or ""
        local down_val = (q.downmbps or q.down or ""):match("^(%d+)") or ""
        local mport = q.mport or hop_port or ""
        local insecure = (q.insecure == "1" or q.insecure == "true" or q.allowInsecure == "1") and "1" or "0"

        return {
            alias = (alias ~= "" and alias) or (host .. ":" .. port),
            server = host,
            server_port = { port },
            password = auth,
            protocol = "hysteria",
            transport = "hysteria",
            hysteria_tls = "tls",
            hysteria_tls_host = q.sni or q.peer or "",
            hysteria_tls_insecure = insecure,
            hysteria_tls_fingerprint = q.fp or "chrome",
            hysteria_up_mbps = up_val,
            hysteria_down_mbps = down_val,
            hysteria_udphop_port = mport,
            domain_strategy = "UseIP",
            dialer_proxy = "disabled"
        }
    end

    -- 4. vless:// and trojan://
    local proto = line:match("^(vless)://") or line:match("^(trojan)://")
    if proto then
        local rest, alias, qs = split_uri_parts(line:sub(#proto + 4))
        local uuid, hostport = rest:match("^([^@]+)@(.+)$")
        if not uuid or not hostport then return nil end
        local host, port, _, url_path = parse_host_port(hostport)
        if not host or not port then return nil end
        uuid = url_decode(uuid)
        local q = parse_query(qs)
        local net = q.type or "tcp"
        if net == "xhttp" then net = "splithttp" end
        local sec = q.security or (proto == "trojan" and "tls" or "none")
        local path_val = q.path or (url_path and url_path ~= "/" and url_decode(url_path)) or "/"

        local srv = {
            alias = (alias ~= "" and alias) or (host .. ":" .. port),
            server = host,
            server_port = { port },
            password = uuid,
            protocol = proto,
            transport = net,
            domain_strategy = "UseIP",
            dialer_proxy = "disabled"
        }

        if proto == "vless" then
            srv.vless_encryption = q.encryption or "none"
            srv.vless_tls = sec
            if sec == "tls" then
                srv.vless_flow_tls = q.flow or "none"
                srv.vless_tls_host = q.sni or q.host or ""
                srv.vless_tls_fingerprint = q.fp or "chrome"
                srv.vless_tls_insecure = (q.allowInsecure == "1" or q.insecure == "1") and "1" or "0"
            elseif sec == "reality" then
                srv.vless_flow_reality = q.flow or "xtls-rprx-vision"
                srv.vless_reality_server_name = q.sni or ""
                srv.vless_reality_public_key = q.pbk or ""
                srv.vless_reality_short_id = q.sid or ""
                srv.vless_reality_spider_x = q.spx or ""
                srv.vless_reality_fingerprint = q.fp or "chrome"
            end
        elseif proto == "trojan" then
            srv.trojan_tls = (sec == "none") and "none" or "tls"
            if srv.trojan_tls == "tls" then
                srv.trojan_tls_host = q.sni or q.host or ""
                srv.trojan_tls_fingerprint = q.fp or "chrome"
                srv.trojan_tls_insecure = (q.allowInsecure == "1" or q.insecure == "1") and "1" or "0"
            end
        end

        if net == "tcp" then
            srv.tcp_guise = (q.headerType == "http") and "http" or "none"
        elseif net == "ws" then
            srv.ws_host = q.host or ""
            srv.ws_path = path_val
        elseif net == "grpc" then
            srv.grpc_service_name = q.serviceName or q.path or ""
        elseif net == "splithttp" then
            srv.splithttp_host = q.host or ""
            srv.splithttp_path = path_val
        elseif net == "httpupgrade" then
            srv.httpupgrade_host = q.host or ""
            srv.httpupgrade_path = path_val
        end

        return srv
    end

    return nil
end

local function is_fake_info_server(srv)
    local host = (srv.server or ""):lower()
    if host == "www.g00gle.com" or host == "127.0.0.1" or host == "0.0.0.0" or host == "localhost" then
        return true
    end
    local a = srv.alias or ""
    if a:find("剩余流量", 1, true) or a:find("过期时间", 1, true) or a:find("到期时间", 1, true) or a:find("套餐到期", 1, true) then
        return true
    end
    return false
end

function M.import_links(args)
    if type(args) ~= "table" or type(args.text) ~= "string" then
        return { code = -1, error = "请输入订阅链接或节点分享链接" }
    end
    local input = trim(args.text)
    if input == "" then
        return { code = -1, error = "内容不能为空" }
    end

    local sub_url = nil
    -- If input is a single HTTP/HTTPS subscription URL, fetch it non-blockingly via ngx.pipe.spawn
    if input:match("^https?://[^%s]+$") then
        sub_url = input
        local body = spawn_read({
            "curl", "-fsSL", "--connect-timeout", "10", "-m", "20", "-A", "v2rayN/6.45", input
        }, 22000)
        if not body or trim(body) == "" then
            return { code = -1, error = "拉取订阅链接失败，请检查网络连接或直接从 v2rayN 复制节点分享链接粘贴导入" }
        end
        input = body
    end

    -- If input doesn't contain protocol://, try base64 decoding
    if not input:find("://", 1, true) then
        local decoded = base64_decode(input)
        if decoded:find("://", 1, true) then
            input = decoded
        end
    end

    local parsed_list = {}
    for line in input:gmatch("[^\r\n]+") do
        local srv = parse_single_uri(line)
        if srv then
            parsed_list[#parsed_list + 1] = srv
        end
    end

    if #parsed_list == 0 then
        return { code = -1, error = "未解析到有效节点（支持 ss://、vmess://、vless://、trojan://、hysteria2:// 及 Base64 订阅内容）" }
    end

    local c = uci.cursor()
    local gen_id, gen = get_general_section(c)
    if sub_url then
        c:set("xray_core", gen_id, "subscription_url", sub_url)
    end

    local prev_pool_aliases = {}
    if args.replace_all then
        local id_to_alias = {}
        local to_del = {}
        local deleted_map = {}
        c:foreach("xray_core", "servers", function(s)
            local sid = s[".name"]
            to_del[#to_del + 1] = sid
            deleted_map[sid] = true
            if s.alias and s.alias ~= "" then
                id_to_alias[sid] = s.alias
            end
        end)
        for _, pk in ipairs({ "tcp_balancer_v4", "udp_balancer_v4", "tcp_balancer_v6", "udp_balancer_v6" }) do
            local pool = gen[pk]
            if type(pool) == "string" then pool = { pool } end
            if type(pool) == "table" then
                local aliases = {}
                for _, id in ipairs(pool) do
                    if id_to_alias[id] then aliases[#aliases + 1] = id_to_alias[id] end
                end
                prev_pool_aliases[pk] = aliases
            end
        end
        for _, id in ipairs(to_del) do c:delete("xray_core", id) end
        cleanup_deleted_server_refs(c, deleted_map)
    end

    local first_any_id = nil
    local first_valid_id = nil
    local alias_to_new_id = {}
    for _, srv in ipairs(parsed_list) do
        local sec = next_server_id(c)
        if not first_any_id then first_any_id = sec end
        if not first_valid_id and not is_fake_info_server(srv) then
            first_valid_id = sec
        end
        if srv.alias and srv.alias ~= "" and not alias_to_new_id[srv.alias] then
            alias_to_new_id[srv.alias] = sec
        end
        c:set("xray_core", sec, "servers")
        apply_uci_fields(c, "xray_core", sec, srv)
    end

    local fallback_id = first_valid_id or first_any_id
    if args.replace_all and fallback_id then
        for _, pk in ipairs({ "tcp_balancer_v4", "udp_balancer_v4", "tcp_balancer_v6", "udp_balancer_v6" }) do
            local restored = {}
            for _, al in ipairs(prev_pool_aliases[pk] or {}) do
                if alias_to_new_id[al] then
                    restored[#restored + 1] = alias_to_new_id[al]
                end
            end
            if #restored > 0 then
                c:set("xray_core", gen_id, pk, restored)
            elseif pk == "tcp_balancer_v4" or pk == "udp_balancer_v4" then
                c:set("xray_core", gen_id, pk, { fallback_id })
            end
        end
    end

    c:commit("xray_core")
    if args.replace_all then
        local _, cur_gen = get_general_section(c)
        local _, proc_alive = get_xray_status(cur_gen)
        if proc_alive then
            service_exec("restart")
        end
    end
    return { code = 0, data = { added = #parsed_list } }
end

-- 7. Generic subsection CRUD (lan_hosts, extra_inbound)
local allowed_sub_types = {
    lan_hosts = true,
    extra_inbound = true
}

function M.save_subsection(args)
    if type(args) ~= "table" or not allowed_sub_types[args.type] or type(args.values) ~= "table" then
        return { code = -1, error = "子配置表类型错误" }
    end
    local c = uci.cursor()
    local sec = args.id
    if not sec or sec == "" then
        sec = c:add("xray_core", args.type)
    else
        if c:get("xray_core", sec) ~= args.type then
            return { code = -1, error = "目标配置段类型不匹配" }
        end
    end
    apply_uci_fields(c, "xray_core", sec, args.values)
    c:commit("xray_core")
    if args.apply then
        service_exec("restart")
    end
    return { code = 0, data = { id = sec } }
end

function M.delete_subsection(args)
    if type(args) ~= "table" or type(args.id) ~= "string" or args.id == "" then
        return { code = -1, error = "未指定条目 ID" }
    end
    local c = uci.cursor()
    local sec_type = c:get("xray_core", args.id)
    if not sec_type or not allowed_sub_types[sec_type] then
        return { code = -1, error = "不允许删除该类型配置段" }
    end
    c:delete("xray_core", args.id)
    c:commit("xray_core")
    if args.apply then
        service_exec("restart")
    end
    return { code = 0, data = { ok = true } }
end

-- 8. Service control (start / stop / restart) - waits synchronously via ngx.pipe.spawn
function M.service_ctl(args)
    local action = (args and args.action) or "restart"
    if action ~= "start" and action ~= "stop" and action ~= "restart" then
        return { code = -1, error = "不支持的操作" }
    end
    service_exec(action)
    return { code = 0, data = { ok = true } }
end

-- 9. Connectivity check (non-blocking via ngx.pipe.spawn)
function M.test_connectivity(args)
    local target = (args and args.target == "cn")
        and "http://connectivitycheck.platform.hicloud.com/generate_204"
        or "https://www.google.com/generate_204"

    local out = spawn_read({
        "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}:%{time_total}",
        "--connect-timeout", "2", "-m", "3", target
    }, 4000)

    local code, time_s = trim(out):match("(%d+):([%d%.,]+)")
    if time_s then time_s = time_s:gsub(",", ".") end
    local http_code = tonumber(code) or 0
    local ms = tonumber(time_s) and math.floor(tonumber(time_s) * 1000) or 0

    return {
        code = 0,
        data = {
            ok = (http_code == 204 or http_code == 200),
            http_code = http_code,
            latency_ms = ms
        }
    }
end

-- 10. Read generated /var/etc/xray/config.json and recent xray system logs
function M.get_preview()
    local cfg = read_file("/var/etc/xray/config.json", 256 * 1024) or "// /var/etc/xray/config.json 尚未生成（服务未启动）"
    local logs = spawn_read({ "/bin/sh", "-c", "logread -e xray 2>/dev/null | tail -n 80" }, 5000)
    return {
        code = 0,
        data = {
            config_json = cfg,
            logs = logs
        }
    }
end

-- 11. Online update GeoIP / GeoSite from Loyalsoldier/v2ray-rules-dat (with domestic mirror & CDN fallback)
function M.update_geodata()
    local sf = io.open("/tmp/xray_geo_update.status", "w")
    if sf then
        sf:write("updating\n")
        sf:close()
    end
    local script = [[
mkdir -p /usr/share/xray
dl() {
    local name="$1"
    local out="$2"
    for url in \
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/${name}" \
        "https://ghfast.top/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/${name}" \
        "https://gh-proxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/${name}" \
        "https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/${name}"; do
        if curl -fsSL --connect-timeout 8 -m 120 -o "$out" "$url" 2>/dev/null; then
            local sz=$(wc -c < "$out" 2>/dev/null || echo 0)
            if [ "$sz" -gt 1000000 ]; then
                return 0
            fi
        fi
    done
    return 1
}
if dl "geoip.dat" "/tmp/geoip.dat.new" && dl "geosite.dat" "/tmp/geosite.dat.new"; then
    mv /tmp/geoip.dat.new /usr/share/xray/geoip.dat
    mv /tmp/geosite.dat.new /usr/share/xray/geosite.dat
    echo "ok" > /tmp/xray_geo_update.status
    /etc/init.d/xray_core restart
else
    rm -f /tmp/geoip.dat.new /tmp/geosite.dat.new
    echo "err" > /tmp/xray_geo_update.status
fi
]]
    spawn_read({ "/bin/sh", "-c", "(" .. script .. ") >/tmp/xray_geo_update.log 2>&1 &" }, 2000)
    return { code = 0, data = { started = true } }
end

return M
EOF_RPC_LUA

say "4/4 正在编译并压缩全中文前端视图组件 ($VIEW_JS)..."
cat << 'EOF_VIEW_JS' > "$VIEW_JS"
(function () {
  if (typeof document !== "undefined" && !document.getElementById("gl-xray-full-style")) {
    var styleEl = document.createElement("style");
    styleEl.id = "gl-xray-full-style";
    styleEl.textContent = [
      ".xgl-wrap { padding: 8px 0 36px; font-size: 14px; line-height: 1.5; }",
      ".xgl-topbar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 18px; border-radius: 10px; background: rgba(128,128,128,0.08); margin-bottom: 14px; border: 1px solid rgba(140,140,140,0.18); }",
      ".xgl-dirty-bar { position: sticky; top: 8px; z-index: 100; display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 16px; border-radius: 8px; background: rgba(243, 156, 18, 0.22); backdrop-filter: blur(8px); border: 1px solid rgba(243, 156, 18, 0.55); box-shadow: 0 4px 14px rgba(0,0,0,0.14); margin-bottom: 14px; font-size: 13px; }",
      ".xgl-status-group { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }",
      ".xgl-badge { display: inline-flex; align-items: center; padding: 4px 11px; border-radius: 999px; font-size: 12px; font-weight: 600; }",
      ".xgl-badge.ok { background: rgba(46, 204, 113, 0.16); color: #27ae60; }",
      ".xgl-badge.warn { background: rgba(243, 156, 18, 0.16); color: #d68910; }",
      ".xgl-badge.err { background: rgba(231, 76, 60, 0.16); color: #e74c3c; }",
      ".xgl-badge.info { background: rgba(52, 152, 219, 0.15); color: #2980b9; }",
      ".xgl-tabs { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 16px; border-bottom: 1px solid rgba(140,140,140,0.2); padding-bottom: 8px; }",
      ".xgl-tab { padding: 8px 14px; border-radius: 6px; cursor: pointer; font-weight: 500; font-size: 13px; transition: all 0.15s; user-select: none; opacity: 0.78; }",
      ".xgl-tab:hover { opacity: 1; background: rgba(128,128,128,0.1); }",
      ".xgl-tab.active { opacity: 1; background: #2b6cb0; color: #fff; font-weight: 600; }",
      ".xgl-section-title { font-size: 15px; font-weight: 600; margin: 18px 0 8px; padding-bottom: 6px; border-bottom: 1px solid rgba(140,140,140,0.18); display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; }",
      ".xgl-section-title:first-child { margin-top: 2px; }",
      ".xgl-row { display: flex; align-items: flex-start; justify-content: space-between; padding: 12px 0; border-bottom: 1px dashed rgba(140,140,140,0.14); gap: 16px; flex-wrap: wrap; }",
      ".xgl-row:last-child { border-bottom: none; }",
      ".xgl-label-col { flex: 1; min-width: 220px; }",
      ".xgl-label { font-weight: 500; font-size: 14px; }",
      ".xgl-desc { font-size: 12px; opacity: 0.68; margin-top: 3px; }",
      ".xgl-ctrl-col { width: 380px; max-width: 100%; display: flex; flex-direction: column; align-items: flex-end; }",
      ".xgl-input, .xgl-select, .xgl-textarea { width: 100%; box-sizing: border-box; padding: 7px 11px; border-radius: 6px; border: 1px solid rgba(140,140,140,0.35); background: transparent; color: inherit; font-size: 13px; outline: none; }",
      ".xgl-input:focus, .xgl-select:focus, .xgl-textarea:focus { border-color: #2b6cb0; }",
      ".xgl-select option { background: var(--card-bg, #ffffff); color: var(--text-color, #222222); }",
      ".xgl-textarea { font-family: inherit; resize: vertical; min-height: 34px; line-height: 1.45; overflow-y: auto; }",
      ".xgl-btn-bar { display: flex; flex-wrap: wrap; gap: 10px; justify-content: flex-end; margin-top: 18px; padding-top: 12px; border-top: 1px solid rgba(140,140,140,0.18); }",
      ".xgl-btn { padding: 7px 14px; border-radius: 6px; border: 1px solid rgba(140,140,140,0.35); background: transparent; color: inherit; cursor: pointer; font-size: 13px; font-weight: 500; transition: all 0.15s; }",
      ".xgl-btn:hover:not(:disabled) { background: rgba(128,128,128,0.12); }",
      ".xgl-btn:disabled { opacity: 0.52; cursor: not-allowed; }",
      ".xgl-btn.primary { background: #2b6cb0; color: #fff; border-color: #2b6cb0; }",
      ".xgl-btn.primary:hover:not(:disabled) { background: #2c5282; }",
      ".xgl-btn.success { background: #27ae60; color: #fff; border-color: #27ae60; }",
      ".xgl-btn.danger { color: #e74c3c; border-color: rgba(231,76,60,0.45); }",
      ".xgl-btn.sm { padding: 4px 10px; font-size: 12px; }",
      ".xgl-table-wrap { width: 100%; overflow-x: auto; margin-top: 10px; }",
      ".xgl-table { width: 100%; border-collapse: collapse; font-size: 13px; }",
      ".xgl-table th, .xgl-table td { padding: 9px 10px; text-align: left; border-bottom: 1px solid rgba(140,140,140,0.16); }",
      ".xgl-table th { font-weight: 600; opacity: 0.8; background: rgba(128,128,128,0.06); }",
      ".xgl-table tr.active-row { background: rgba(46, 204, 113, 0.08); }",
      ".xgl-modal-mask { position: fixed; inset: 0; background: rgba(0,0,0,0.55); z-index: 9999; display: flex; align-items: center; justify-content: center; padding: 16px; }",
      ".xgl-modal { background: var(--card-bg, #fff); color: var(--text-color, #222); width: 720px; max-width: 100%; max-height: 88vh; border-radius: 10px; display: flex; flex-direction: column; box-shadow: 0 12px 32px rgba(0,0,0,0.3); overflow: hidden; border: 1px solid rgba(140,140,140,0.25); }",
      ".xgl-modal-header { padding: 14px 20px; font-size: 16px; font-weight: 600; border-bottom: 1px solid rgba(140,140,140,0.2); display: flex; justify-content: space-between; align-items: center; }",
      ".xgl-modal-body { padding: 16px 20px; overflow-y: auto; flex: 1; }",
      ".xgl-modal-footer { padding: 12px 20px; border-top: 1px solid rgba(140,140,140,0.2); display: flex; justify-content: flex-end; gap: 10px; }",
      ".xgl-code { width: 100%; height: 420px; font-family: Consolas, Monaco, monospace; font-size: 12px; padding: 12px; border-radius: 8px; background: rgba(0,0,0,0.82); color: #e2e8f0; overflow: auto; white-space: pre; box-sizing: border-box; }",
      ".xgl-toast { position: fixed; bottom: 24px; right: 24px; z-index: 10000; padding: 10px 18px; border-radius: 8px; background: #2b6cb0; color: #fff; font-weight: 500; box-shadow: 0 6px 18px rgba(0,0,0,0.25); }"
    ].join("\n");
    document.head.appendChild(styleEl);
  }

  function withoutNulls(v) {
    if (Array.isArray(v)) return v.filter(function (x) { return x != null; }).map(withoutNulls);
    if (v && typeof v === "object") {
      var out = {};
      Object.keys(v).forEach(function (k) {
        if (v[k] != null) out[k] = withoutNulls(v[k]);
      });
      return out;
    }
    return v;
  }

  var BLACKLIST_HOOK_TAG = "// __GL_XRAY_PRESET_BLACKLIST__";
  var BLACKLIST_HOOK_SCRIPT = [
    BLACKLIST_HOOK_TAG,
    "return function(config) {",
    "    let new_rules = [];",
    "    let fallback_rules = [];",
    "",
    "    // 1. 阻断 UDP 443 (QUIC)，对应 v2rayN 阻断udp443",
    "    push(new_rules, {",
    "        type: \"field\",",
    "        port: \"443\",",
    "        network: \"udp\",",
    "        outboundTag: \"blackhole_outbound\"",
    "    });",
    "",
    "    // 2. 在兜底规则前追加 v2rayN 黑名单 IP 集 (IPv4 & IPv6)，并将最终兜底改为 direct",
    "    let blacklist_ips_v4 = [",
    "        \"geoip:facebook\", \"geoip:fastly\", \"geoip:google\",",
    "        \"geoip:netflix\", \"geoip:telegram\", \"geoip:twitter\",",
    "        \"1.1.1.1\", \"1.0.0.1\", \"1.1.1.2\", \"1.0.0.2\", \"1.1.1.3\", \"1.0.0.3\",",
    "        \"8.8.8.8\", \"8.8.4.4\", \"94.140.14.14\", \"94.140.15.15\",",
    "        \"208.67.222.222\", \"208.67.220.220\", \"9.9.9.9\", \"149.112.112.112\",",
    "        \"77.88.8.8\", \"77.88.8.1\"",
    "    ];",
    "    let blacklist_ips_v6 = [",
    "        \"geoip:facebook\", \"geoip:fastly\", \"geoip:google\",",
    "        \"geoip:netflix\", \"geoip:telegram\", \"geoip:twitter\",",
    "        \"2606:4700:4700::1111\", \"2606:4700:4700::1001\",",
    "        \"2001:4860:4860::8888\", \"2001:4860:4860::8844\",",
    "        \"2a10:50c0::ad1:ff\", \"2a10:50c0::ad2:ff\",",
    "        \"2620:119:35::35\", \"2620:119:53::53\",",
    "        \"2620:fe::9\", \"2620:fe::fe\",",
    "        \"2a02:6b8::feed:0ff\", \"2a02:6b8:0:1::feed:0ff\"",
    "    ];",
    "    for (let r in config.routing.rules) {",
    "        if (r.domain == null && r.ip == null && (",
    "            r.balancerTag == \"tcp_outbound_v4\" ||",
    "            r.balancerTag == \"udp_outbound_v4\" ||",
    "            r.balancerTag == \"tcp_outbound_v6\" ||",
    "            r.balancerTag == \"udp_outbound_v6\"",
    "        )) {",
    "            let is_v4 = (r.balancerTag == \"tcp_outbound_v4\" || r.balancerTag == \"udp_outbound_v4\");",
    "            push(new_rules, {",
    "                type: \"field\",",
    "                inboundTag: r.inboundTag,",
    "                ip: is_v4 ? blacklist_ips_v4 : blacklist_ips_v6,",
    "                balancerTag: r.balancerTag",
    "            });",
    "            push(fallback_rules, {",
    "                type: \"field\",",
    "                inboundTag: r.inboundTag,",
    "                outboundTag: \"direct\"",
    "            });",
    "        } else {",
    "            push(new_rules, r);",
    "        }",
    "    }",
    "",
    "    for (let fb in fallback_rules) {",
    "        push(new_rules, fb);",
    "    }",
    "    config.routing.rules = new_rules;",
    "    return config;",
    "};"
  ].join("\n");

  function callRpc(method, args, timeoutMs) {
    if (typeof window.$rpcRequest !== "function") {
      return Promise.reject(new Error("$rpcRequest 未就绪"));
    }
    var opts = timeoutMs ? { timeout: timeoutMs } : {};
    return window.$rpcRequest("call", ["sid", "xray", method, withoutNulls(args || {})], opts).then(function (res) {
      if (!res || res.code !== 0) {
        throw new Error((res && res.error) || "RPC 请求失败");
      }
      return res.data;
    });
  }

  function arrToLines(v) {
    if (Array.isArray(v)) return v.join("\n");
    if (typeof v === "string" && v !== "") return v;
    return "";
  }

  function linesToArr(s) {
    if (Array.isArray(s)) return s;
    if (typeof s !== "string") return [];
    return s.split(/[\r\n,]+/).map(function (x) { return x.trim(); }).filter(Boolean);
  }

  function firstItem(v) {
    if (Array.isArray(v)) return v[0] || "";
    return v || "";
  }

  function asArray(v) {
    if (Array.isArray(v)) return v.slice();
    if (typeof v === "string" && v !== "") return [v];
    return [];
  }

  function fmtBytes(b) {
    var n = Number(b) || 0;
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB";
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(2) + " MB";
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
  }

  function getLuciUrl() {
    var proto = window.location.protocol;
    var port = proto === "https:" ? "8443" : "8080";
    return proto + "//" + window.location.hostname + ":" + port + "/cgi-bin/luci/admin/services/xray_core";
  }

  var XrayApp = {
    name: "GlSdk4UiXray",
    data: function () {
      return {
        activeTab: "status",
        loading: true,
        saving: false,
        savingServer: false,
        testing: false,
        toastMsg: "",
        savedSnapshot: "",
        running: false,
        proc_running: false,
        tproxy_enabled: false,
        geoip_ok: false,
        geoip_size: "0 MB",
        geosite_ok: false,
        geosite_size: "0 MB",
        updatingGeo: false,
        metrics: null,
        metricsTimer: null,
        cnPing: null,
        googlePing: null,

        // UCI data models
        gen: {},
        servers: [],
        subsections: {
          lan_hosts: [],
          extra_inbound: []
        },
        lan_clients: [],

        // Multi-node balancer arrays for general
        tcpNodesV4: [],
        udpNodesV4: [],
        tcpNodesV6: [],
        udpNodesV6: [],
        bypassedRulesText: "",
        forwardedRulesText: "",
        blockedRulesText: "",
        geoipDirectV4Text: "",
        geoipDirectV6Text: "",
        wanBpIpsText: "",
        wanFwIpsText: "",
        wanBpTcpPortsText: "",
        wanBpUdpPortsText: "",
        wanFwTcpPortsText: "",
        wanFwUdpPortsText: "",

        // Server search, protocol filter, import, and modal editing
        serverKeyword: "",
        serverProtoFilter: "",
        showImportBox: false,
        importText: "",
        importReplaceAll: false,
        importing: false,
        editingServer: null,

        // Instant-apply subsection forms (Tab 3)
        newLanHost: { macaddr: "", alias: "", access_control_strategy_v4: "bypass", access_control_strategy_v6: "bypass" },
        newInbound: { inbound_addr: "0.0.0.0", inbound_port: "1080", inbound_type: "socks5", specify_outbound: "0", destination: "" },

        // Config JSON preview & logs (Tab 5)
        previewJson: "",
        previewLogs: "",
        loadingPreview: false
      };
    },
    computed: {
      isDirty: function () {
        if (!this.savedSnapshot) return false;
        return this.buildGeneralSnapshot() !== this.savedSnapshot;
      }
    },
    created: function () {
      var self = this;
      self.loadAll();
      self.metricsTimer = setInterval(function () {
        if (typeof document !== "undefined" && document.hidden) return;
        if (!self.updatingGeo && !self.proc_running && !self.tproxy_enabled) return;
        self.refreshMetrics();
      }, 5000);
      self._onKeyDown = function (e) {
        if (e.key === "Escape" && self.editingServer) {
          self.editingServer = null;
        }
      };
      self._onVisChange = function () {
        if (typeof document !== "undefined" && !document.hidden && (self.proc_running || self.tproxy_enabled || self.updatingGeo)) {
          self.refreshMetrics();
        }
      };
      if (typeof document !== "undefined") {
        document.addEventListener("keydown", self._onKeyDown);
        document.addEventListener("visibilitychange", self._onVisChange);
      }
    },
    beforeDestroy: function () {
      if (this.metricsTimer) {
        clearInterval(this.metricsTimer);
        this.metricsTimer = null;
      }
      if (typeof document !== "undefined") {
        if (this._onKeyDown) document.removeEventListener("keydown", this._onKeyDown);
        if (this._onVisChange) document.removeEventListener("visibilitychange", this._onVisChange);
      }
    },
    methods: {
      buildGeneralPayload: function () {
        return Object.assign({}, this.gen, {
          tcp_balancer_v4: this.tcpNodesV4,
          udp_balancer_v4: this.udpNodesV4,
          tcp_balancer_v6: this.tcpNodesV6,
          udp_balancer_v6: this.udpNodesV6,
          bypassed_domain_rules: linesToArr(this.bypassedRulesText),
          forwarded_domain_rules: linesToArr(this.forwardedRulesText),
          blocked_domain_rules: linesToArr(this.blockedRulesText),
          geoip_direct_code_list: linesToArr(this.geoipDirectV4Text),
          geoip_direct_code_list_v6: linesToArr(this.geoipDirectV6Text),
          wan_bp_ips: linesToArr(this.wanBpIpsText),
          wan_fw_ips: linesToArr(this.wanFwIpsText),
          wan_bp_tcp_ports: linesToArr(this.wanBpTcpPortsText),
          wan_bp_udp_ports: linesToArr(this.wanBpUdpPortsText),
          wan_fw_tcp_ports: linesToArr(this.wanFwTcpPortsText),
          wan_fw_udp_ports: linesToArr(this.wanFwUdpPortsText)
        });
      },
      buildGeneralSnapshot: function () {
        return JSON.stringify(this.buildGeneralPayload());
      },
      refreshMetrics: function () {
        var self = this;
        callRpc("get_metrics", {}).then(function (d) {
          self.running = !!d.running;
          self.proc_running = d.proc_running != null ? !!d.proc_running : !!d.running;
          self.tproxy_enabled = !!d.tproxy_enabled;
          if (d.geoip_size) {
            self.geoip_ok = !!d.geoip_ok;
            self.geoip_size = d.geoip_size;
            self.geosite_ok = !!d.geosite_ok;
            self.geosite_size = d.geosite_size;
          }
          if (self.updatingGeo && d.geo_status && d.geo_status !== "updating") {
            self.updatingGeo = false;
            if (d.geo_status === "ok") {
              self.showToast("GeoIP / GeoSite 规则库更新成功并已重启 Xray！");
            } else {
              self.showToast("规则库下载失败，请检查网络连接");
            }
          }
          self.metrics = d.metrics || null;
        }).catch(function () {});
      },
      showToast: function (msg) {
        var self = this;
        self.toastMsg = msg;
        setTimeout(function () {
          if (self.toastMsg === msg) self.toastMsg = "";
        }, 3200);
      },
      loadAll: function (preserveUnsaved) {
        var self = this;
        var keepForm = !!(preserveUnsaved && self.isDirty);
        if (!keepForm) self.loading = true;
        return callRpc("get_all", {}).then(function (d) {
          self.running = !!d.running;
          self.proc_running = d.proc_running != null ? !!d.proc_running : !!d.running;
          self.tproxy_enabled = !!d.tproxy_enabled;
          self.geoip_ok = !!d.geoip_ok;
          self.geoip_size = d.geoip_size || "0 MB";
          self.geosite_ok = !!d.geosite_ok;
          self.geosite_size = d.geosite_size || "0 MB";
          self.updatingGeo = d.geo_status === "updating";
          self.metrics = d.metrics || null;
          self.servers = Array.isArray(d.servers) ? d.servers : [];
          self.subsections = d.subsections || { lan_hosts: [], extra_inbound: [] };
          self.lan_clients = Array.isArray(d.lan_clients) ? d.lan_clients : [];
          if (!self.newInbound.destination && self.servers.length > 0) {
            self.newInbound.destination = self.servers[0][".name"];
          }
          var g = d.general || {};
          if (g.subscription_url && !self.importText) {
            self.importText = g.subscription_url;
            self.importReplaceAll = true;
          }
          if (keepForm) {
            var validMap = {};
            self.servers.forEach(function (s) { validMap[s[".name"]] = true; });
            self.tcpNodesV4 = self.tcpNodesV4.filter(function (id) { return validMap[id]; });
            self.udpNodesV4 = self.udpNodesV4.filter(function (id) { return validMap[id]; });
            self.tcpNodesV6 = self.tcpNodesV6.filter(function (id) { return validMap[id]; });
            self.udpNodesV6 = self.udpNodesV6.filter(function (id) { return validMap[id]; });
            return;
          }
          self.gen = {
            transparent_proxy_enable: g.transparent_proxy_enable || "0",
            general_balancer_strategy: g.general_balancer_strategy || "random",
            fast_dns: g.fast_dns || "223.5.5.5:53",
            secure_dns: g.secure_dns || "1.1.1.1:53",
            default_dns: g.default_dns || "1.1.1.1:53",
            dns_port: g.dns_port || "5300",
            dns_count: g.dns_count || "3",
            blocked_to_loopback: g.blocked_to_loopback || "0",
            align_fast_dns_to_geoip_direct: g.align_fast_dns_to_geoip_direct || "0",
            dnsmasq_integration_mode: g.dnsmasq_integration_mode || "global",
            transparent_default_port_policy: g.transparent_default_port_policy || "forwarded",
            tproxy_sniffing: g.tproxy_sniffing || "0",
            route_only: g.route_only || "0",
            direct_bittorrent: g.direct_bittorrent || "0",
            routing_domain_strategy: g.routing_domain_strategy || "AsIs",
            xray_bin: g.xray_bin || "/usr/bin/xray",
            loglevel: g.loglevel || "warning",
            access_log: g.access_log || "0",
            dns_log: g.dns_log || "0",
            stats: g.stats || "0",
            observatory: g.observatory || "0",
            fw4_counter: g.fw4_counter || "0",
            metrics_server_enable: g.metrics_server_enable || "0",
            metrics_server_port: g.metrics_server_port || "18888",
            mark: g.mark || "255",
            firewall_priority: g.firewall_priority || "",
            handshake: g.handshake || "",
            conn_idle: g.conn_idle || "",
            uplink_only: g.uplink_only || "",
            downlink_only: g.downlink_only || "",
            buffer_size: g.buffer_size || "",
            dynamic_direct_tcp4: g.dynamic_direct_tcp4 || "0",
            dynamic_direct_udp4: g.dynamic_direct_udp4 || "0",
            custom_configuration_hook: g.custom_configuration_hook || ""
          };

          self.tcpNodesV4 = asArray(g.tcp_balancer_v4);
          self.udpNodesV4 = asArray(g.udp_balancer_v4);
          self.tcpNodesV6 = asArray(g.tcp_balancer_v6);
          self.udpNodesV6 = asArray(g.udp_balancer_v6);

          self.bypassedRulesText = arrToLines(g.bypassed_domain_rules);
          self.forwardedRulesText = arrToLines(g.forwarded_domain_rules);
          self.blockedRulesText = arrToLines(g.blocked_domain_rules);
          self.geoipDirectV4Text = arrToLines(g.geoip_direct_code_list);
          self.geoipDirectV6Text = arrToLines(g.geoip_direct_code_list_v6);
          self.wanBpIpsText = arrToLines(g.wan_bp_ips);
          self.wanFwIpsText = arrToLines(g.wan_fw_ips);
          self.wanBpTcpPortsText = arrToLines(g.wan_bp_tcp_ports);
          self.wanBpUdpPortsText = arrToLines(g.wan_bp_udp_ports);
          self.wanFwTcpPortsText = arrToLines(g.wan_fw_tcp_ports);
          self.wanFwUdpPortsText = arrToLines(g.wan_fw_udp_ports);

          self.savedSnapshot = self.buildGeneralSnapshot();
        }).catch(function (e) {
          self.showToast("加载失败: " + e.message);
        }).finally(function () {
          self.loading = false;
        });
      },

      saveAllGeneral: function () {
        var self = this;
        if (self.gen.transparent_proxy_enable === "1" && (self.tcpNodesV4.length === 0 || self.udpNodesV4.length === 0)) {
          self.showToast("启用透明代理时，IPv4 TCP 与 UDP 节点池至少需选择 1 个节点");
          return Promise.resolve();
        }
        self.saving = true;
        var payload = self.buildGeneralPayload();
        return callRpc("save_general", { values: payload, apply: true }, 35000).then(function () {
          self.showToast("配置已保存并应用生效！");
          return self.loadAll();
        }).catch(function (e) {
          self.showToast("保存失败: " + e.message);
        }).finally(function () {
          self.saving = false;
        });
      },

      detectRoutingPreset: function () {
        var hook = (this.gen && this.gen.custom_configuration_hook) || "";
        if (hook.indexOf(BLACKLIST_HOOK_TAG) >= 0) return "blacklist";
        var bp = linesToArr(this.bypassedRulesText);
        var geo4 = linesToArr(this.geoipDirectV4Text);
        if (bp.indexOf("geosite:cn") >= 0 || geo4.indexOf("cn") >= 0) return "bypass_cn";
        var onlyPrivateOrEmpty = bp.length === 0 || (bp.length === 1 && bp[0] === "geosite:private");
        if (onlyPrivateOrEmpty && geo4.length === 0 && !hook.trim()) return "global";
        return "custom";
      },

      applyRoutingPreset: function (preset) {
        var curHook = (this.gen && this.gen.custom_configuration_hook) || "";
        if (preset === "bypass_cn") {
          this.bypassedRulesText = "geosite:private\ngeosite:cn";
          this.forwardedRulesText = "geosite:geolocation-!cn";
          this.blockedRulesText = "geosite:category-ads";
          this.geoipDirectV4Text = "cn";
          this.geoipDirectV6Text = "cn";
          this.$set(this.gen, "fast_dns", "223.5.5.5:53");
          this.$set(this.gen, "secure_dns", "1.1.1.1:53");
          this.$set(this.gen, "default_dns", "1.1.1.1:53");
          this.$set(this.gen, "tproxy_sniffing", "1");
          this.$set(this.gen, "route_only", "1");
          this.$set(this.gen, "routing_domain_strategy", "IPIfNonMatch");
          if (curHook.indexOf(BLACKLIST_HOOK_TAG) >= 0) {
            this.$set(this.gen, "custom_configuration_hook", "");
          }
          this.showToast("已填入【绕过中国大陆】规则，点击“保存并应用”生效");
        } else if (preset === "blacklist") {
          this.bypassedRulesText = "geosite:private\ngeosite:cn";
          this.forwardedRulesText = [
            "geosite:gfw",
            "geosite:greatfire",
            "geosite:google",
            "domain:api.ip.sb",
            "domain:cloudflare-dns.com",
            "domain:one.one.one.one",
            "domain:dns.google",
            "domain:adguard-dns.com",
            "domain:opendns.com",
            "domain:umbrella.com",
            "domain:quad9.net",
            "domain:yandex.net"
          ].join("\n");
          this.blockedRulesText = "geosite:category-ads";
          this.geoipDirectV4Text = "";
          this.geoipDirectV6Text = "";
          this.$set(this.gen, "fast_dns", "223.5.5.5:53");
          this.$set(this.gen, "secure_dns", "1.1.1.1:53");
          this.$set(this.gen, "default_dns", "223.5.5.5:53");
          this.$set(this.gen, "tproxy_sniffing", "1");
          this.$set(this.gen, "route_only", "1");
          this.$set(this.gen, "direct_bittorrent", "1");
          this.$set(this.gen, "routing_domain_strategy", "IPIfNonMatch");
          this.$set(this.gen, "custom_configuration_hook", BLACKLIST_HOOK_SCRIPT);
          this.showToast("已填入【黑名单模式 (参考 v2rayN)】，点击“保存并应用”生效");
        } else if (preset === "global") {
          this.bypassedRulesText = "geosite:private";
          this.forwardedRulesText = "geosite:geolocation-!cn";
          this.geoipDirectV4Text = "";
          this.geoipDirectV6Text = "";
          this.$set(this.gen, "fast_dns", "223.5.5.5:53");
          this.$set(this.gen, "secure_dns", "1.1.1.1:53");
          this.$set(this.gen, "default_dns", "1.1.1.1:53");
          this.$set(this.gen, "tproxy_sniffing", "1");
          this.$set(this.gen, "route_only", "1");
          this.$set(this.gen, "routing_domain_strategy", "AsIs");
          if (curHook.indexOf(BLACKLIST_HOOK_TAG) >= 0) {
            this.$set(this.gen, "custom_configuration_hook", "");
          }
          this.showToast("已填入【全局代理】规则，点击“保存并应用”生效");
        }
      },

      quickUseServer: function (srvId) {
        this.tcpNodesV4 = [srvId];
        this.udpNodesV4 = [srvId];
        this.$set(this.gen, "transparent_proxy_enable", "1");
        return this.saveAllGeneral();
      },

      addFilteredToV4Pool: function (list) {
        var tcpArr = this.tcpNodesV4.slice();
        var udpArr = this.udpNodesV4.slice();
        var added = 0;
        (list || []).forEach(function (srv) {
          var host = (srv.server || "").toLowerCase();
          var alias = srv.alias || "";
          if (host === "www.g00gle.com" || alias.indexOf("剩余流量") >= 0 || alias.indexOf("过期时间") >= 0) return;
          var id = srv[".name"];
          if (tcpArr.indexOf(id) < 0) { tcpArr.push(id); added++; }
          if (udpArr.indexOf(id) < 0) udpArr.push(id);
        });
        this.tcpNodesV4 = tcpArr;
        this.udpNodesV4 = udpArr;
        this.showToast(added > 0 ? ("已将 " + added + " 个筛选节点加入 IPv4 池，请点击保存生效") : "当前筛选节点已全部在 IPv4 池中");
      },

      togglePoolNode: function (poolKey, srvId) {
        var arr = this[poolKey].slice();
        var idx = arr.indexOf(srvId);
        if (idx >= 0) {
          arr.splice(idx, 1);
        } else {
          arr.push(srvId);
        }
        this[poolKey] = arr;
        this.showToast("已更新节点池，请点击“立即保存并应用”生效");
      },

      toggleFamilyPool: function (tcpKey, udpKey, srvId) {
        var tcpArr = this[tcpKey].slice();
        var udpArr = this[udpKey].slice();
        var inBoth = tcpArr.indexOf(srvId) >= 0 && udpArr.indexOf(srvId) >= 0;
        if (inBoth) {
          this[tcpKey] = tcpArr.filter(function (x) { return x !== srvId; });
          this[udpKey] = udpArr.filter(function (x) { return x !== srvId; });
        } else {
          if (tcpArr.indexOf(srvId) < 0) tcpArr.push(srvId);
          if (udpArr.indexOf(srvId) < 0) udpArr.push(srvId);
          this[tcpKey] = tcpArr;
          this[udpKey] = udpArr;
        }
        this.showToast("已更新节点池，请点击“立即保存并应用”生效");
      },

      openEditServer: function (srv) {
        if (!srv) {
          this.editingServer = {
            id: "",
            alias: "新节点",
            server: "",
            port: "443",
            password: "",
            domain_strategy: "UseIP",
            dialer_proxy: "disabled",
            protocol: "vless",
            shadowsocks_security: "aes-256-gcm",
            shadowsocks_udp_over_tcp: "0",
            vmess_security: "auto",
            vmess_alter_id: "0",
            vless_encryption: "none",
            tls_mode: "reality",
            flow_mode: "xtls-rprx-vision",
            tls_host: "",
            tls_insecure: "0",
            tls_fingerprint: "chrome",
            reality_server_name: "",
            reality_public_key: "",
            reality_short_id: "",
            reality_spider_x: "",
            reality_fingerprint: "chrome",
            transport: "tcp",
            ws_host: "",
            ws_path: "/",
            grpc_service_name: "",
            splithttp_host: "",
            splithttp_path: "/",
            httpupgrade_host: "",
            httpupgrade_path: "/",
            hysteria_up: "",
            hysteria_down: "",
            hysteria_udphop_port: ""
          };
          return;
        }
        var p = srv.protocol || "shadowsocks";
        var tlsField = p + "_tls";
        var tlsMode = srv[tlsField] || (p === "hysteria" ? "tls" : "none");
        this.editingServer = {
          id: srv[".name"],
          alias: srv.alias || "",
          server: srv.server || "",
          port: firstItem(srv.server_port) || "443",
          password: srv.password || "",
          domain_strategy: srv.domain_strategy || "UseIP",
          dialer_proxy: srv.dialer_proxy || "disabled",
          protocol: p,
          shadowsocks_security: srv.shadowsocks_security || "aes-256-gcm",
          shadowsocks_udp_over_tcp: srv.shadowsocks_udp_over_tcp || "0",
          vmess_security: srv.vmess_security || "auto",
          vmess_alter_id: srv.alter_id || srv.vmess_alter_id || "0",
          vless_encryption: srv.vless_encryption || "none",
          tls_mode: tlsMode,
          flow_mode: (tlsMode === "reality" ? srv.vless_flow_reality : srv.vless_flow_tls) || "none",
          tls_host: srv[p + "_tls_host"] || "",
          tls_insecure: srv[p + "_tls_insecure"] || "0",
          tls_fingerprint: srv[p + "_tls_fingerprint"] || "chrome",
          reality_server_name: srv.vless_reality_server_name || "",
          reality_public_key: srv.vless_reality_public_key || "",
          reality_short_id: srv.vless_reality_short_id || "",
          reality_spider_x: srv.vless_reality_spider_x || srv.vless_spider_x || "",
          reality_fingerprint: srv.vless_reality_fingerprint || "chrome",
          transport: srv.transport || (p === "hysteria" ? "hysteria" : "tcp"),
          ws_host: srv.ws_host || "",
          ws_path: srv.ws_path || "/",
          grpc_service_name: srv.grpc_service_name || "",
          splithttp_host: srv.splithttp_host || "",
          splithttp_path: srv.splithttp_path || "/",
          httpupgrade_host: srv.httpupgrade_host || "",
          httpupgrade_path: srv.httpupgrade_path || "/",
          hysteria_up: srv.hysteria_up_mbps || srv.hysteria_up || "",
          hysteria_down: srv.hysteria_down_mbps || srv.hysteria_down || "",
          hysteria_udphop_port: srv.hysteria_udphop_port || ""
        };
      },

      saveEditingServer: function (applyNow) {
        var self = this;
        var ed = self.editingServer;
        if (!ed || !ed.server || !ed.port) {
          self.showToast("请填写服务器地址与端口");
          return;
        }
        var p = ed.protocol;
        if (p === "hysteria") {
          ed.transport = "hysteria";
          if (ed.tls_mode !== "tls") ed.tls_mode = "tls";
        } else if (p !== "vless" && ed.tls_mode === "reality") {
          ed.tls_mode = p === "trojan" ? "tls" : "none";
        }
        var vals = {
          alias: ed.alias || (ed.server + ":" + ed.port),
          server: ed.server,
          server_port: [String(ed.port)],
          password: ed.password,
          domain_strategy: ed.domain_strategy,
          dialer_proxy: ed.dialer_proxy,
          protocol: p,
          transport: ed.transport,
          shadowsocks_security: p === "shadowsocks" ? ed.shadowsocks_security : "",
          shadowsocks_udp_over_tcp: p === "shadowsocks" ? ed.shadowsocks_udp_over_tcp : "",
          vmess_security: p === "vmess" ? ed.vmess_security : "",
          alter_id: p === "vmess" ? ed.vmess_alter_id : "",
          vless_encryption: p === "vless" ? (ed.vless_encryption || "none") : "",
          vless_flow_tls: (p === "vless" && ed.tls_mode === "tls") ? ed.flow_mode : "",
          vless_flow_reality: (p === "vless" && ed.tls_mode === "reality") ? ed.flow_mode : "",
          vless_reality_server_name: (p === "vless" && ed.tls_mode === "reality") ? ed.reality_server_name : "",
          vless_reality_public_key: (p === "vless" && ed.tls_mode === "reality") ? ed.reality_public_key : "",
          vless_reality_short_id: (p === "vless" && ed.tls_mode === "reality") ? ed.reality_short_id : "",
          vless_reality_spider_x: (p === "vless" && ed.tls_mode === "reality") ? ed.reality_spider_x : "",
          vless_reality_fingerprint: (p === "vless" && ed.tls_mode === "reality") ? ed.reality_fingerprint : "",
          ws_host: ed.transport === "ws" ? ed.ws_host : "",
          ws_path: ed.transport === "ws" ? ed.ws_path : "",
          grpc_service_name: ed.transport === "grpc" ? ed.grpc_service_name : "",
          splithttp_host: ed.transport === "splithttp" ? ed.splithttp_host : "",
          splithttp_path: ed.transport === "splithttp" ? ed.splithttp_path : "",
          httpupgrade_host: ed.transport === "httpupgrade" ? ed.httpupgrade_host : "",
          httpupgrade_path: ed.transport === "httpupgrade" ? ed.httpupgrade_path : "",
          hysteria_up_mbps: (ed.transport === "hysteria" || p === "hysteria") ? ed.hysteria_up : "",
          hysteria_down_mbps: (ed.transport === "hysteria" || p === "hysteria") ? ed.hysteria_down : "",
          hysteria_udphop_port: (ed.transport === "hysteria" || p === "hysteria") ? ed.hysteria_udphop_port : ""
        };
        if (!ed.id && ed.transport === "tcp") vals.tcp_guise = "none";
        ["shadowsocks", "vmess", "vless", "trojan", "hysteria", "socks", "http"].forEach(function (proto) {
          if (proto !== p) {
            vals[proto + "_tls"] = "";
            vals[proto + "_tls_host"] = "";
            vals[proto + "_tls_insecure"] = "";
            vals[proto + "_tls_fingerprint"] = "";
          }
        });
        vals[p + "_tls"] = ed.tls_mode;
        if (ed.tls_mode === "tls") {
          vals[p + "_tls_host"] = ed.tls_host;
          vals[p + "_tls_insecure"] = ed.tls_insecure || "0";
          vals[p + "_tls_fingerprint"] = ed.tls_fingerprint || "chrome";
        } else {
          vals[p + "_tls_host"] = "";
          vals[p + "_tls_insecure"] = "";
          vals[p + "_tls_fingerprint"] = "";
        }

        self.savingServer = true;
        callRpc("save_server", { id: ed.id, values: vals, apply: !!applyNow }, applyNow ? 35000 : 12000).then(function () {
          self.editingServer = null;
          self.showToast(applyNow ? "节点已保存并应用生效" : "节点已保存");
          return self.loadAll(true);
        }).catch(function (e) {
          self.showToast("保存节点失败: " + e.message);
        }).finally(function () {
          self.savingServer = false;
        });
      },

      removeServer: function (id, alias) {
        var self = this;
        if (!confirm("确定要删除节点 " + (alias || id) + " (" + id + ") 吗？")) return;
        callRpc("delete_server", { id: id }, 35000).then(function (res) {
          self.showToast(res && res.restarted ? "已删除节点并自动同步重启服务" : "已删除节点");
          self.loadAll(true);
        }).catch(function (e) {
          self.showToast("删除失败: " + e.message);
        });
      },

      submitImportLinks: function () {
        var self = this;
        if (!self.importText.trim()) {
          self.showToast("请粘贴订阅 URL 或节点分享链接");
          return;
        }
        self.importing = true;
        callRpc("import_links", {
          text: self.importText,
          replace_all: self.importReplaceAll
        }, 35000).then(function (res) {
          self.showToast("成功导入 " + res.added + " 个节点！");
          self.showImportBox = false;
          self.loadAll(!self.importReplaceAll);
        }).catch(function (e) {
          self.showToast("导入失败: " + e.message);
        }).finally(function () {
          self.importing = false;
        });
      },

      addLanHostRule: function () {
        var self = this;
        if (!self.newLanHost.macaddr) {
          self.showToast("请填写或选择设备 MAC 地址");
          return;
        }
        self.saving = true;
        callRpc("save_subsection", {
          type: "lan_hosts",
          values: self.newLanHost,
          apply: true
        }, 35000).then(function () {
          self.newLanHost = { macaddr: "", alias: "", access_control_strategy_v4: "bypass", access_control_strategy_v6: "bypass" };
          self.showToast("已添加设备分流规则并生效");
          return self.loadAll();
        }).catch(function (e) {
          self.showToast("添加失败: " + e.message);
        }).finally(function () {
          self.saving = false;
        });
      },

      addExtraInbound: function () {
        var self = this;
        if (!self.newInbound.inbound_port) {
          self.showToast("请填写监听端口");
          return;
        }
        var vals = {
          inbound_addr: self.newInbound.inbound_addr || "0.0.0.0",
          inbound_port: self.newInbound.inbound_port,
          inbound_type: self.newInbound.inbound_type,
          specify_outbound: self.newInbound.specify_outbound
        };
        if (self.newInbound.specify_outbound === "1" && self.newInbound.destination) {
          vals.destination = [self.newInbound.destination];
        }
        self.saving = true;
        callRpc("save_subsection", {
          type: "extra_inbound",
          values: vals,
          apply: true
        }, 35000).then(function () {
          self.showToast("已添加额外入站端口并生效");
          return self.loadAll();
        }).catch(function (e) {
          self.showToast("添加失败: " + e.message);
        }).finally(function () {
          self.saving = false;
        });
      },

      deleteSubItem: function (id, label) {
        var self = this;
        if (!confirm("确定要删除规则“" + (label || id) + "”并重启生效吗？")) return;
        self.saving = true;
        callRpc("delete_subsection", { id: id, apply: true }, 35000).then(function () {
          self.showToast("已删除规则并生效");
          return self.loadAll();
        }).catch(function (e) {
          self.showToast("删除失败: " + e.message);
        }).finally(function () {
          self.saving = false;
        });
      },

      controlService: function (action) {
        var self = this;
        self.saving = true;
        callRpc("service_ctl", { action: action }, 35000).then(function () {
          self.showToast(action === "stop" ? "已停止 Xray 并卸载 nftables / dnsmasq 转发规则" : ("服务操作已完成: " + action));
          return self.loadAll(true);
        }).catch(function (e) {
          self.showToast("操作失败: " + e.message);
        }).finally(function () {
          self.saving = false;
        });
      },

      runPingTest: function () {
        var self = this;
        self.testing = true;
        self.cnPing = null;
        self.googlePing = null;
        Promise.all([
          callRpc("test_connectivity", { target: "cn" }, 10000),
          callRpc("test_connectivity", { target: "google" }, 10000)
        ]).then(function (r) {
          self.cnPing = r[0];
          self.googlePing = r[1];
        }).catch(function (e) {
          self.showToast("测速失败: " + e.message);
        }).finally(function () {
          self.testing = false;
        });
      },

      triggerGeoUpdate: function () {
        var self = this;
        if (self.updatingGeo) return;
        self.updatingGeo = true;
        callRpc("update_geodata", {}).then(function () {
          self.showToast("正在后台下载最新 GeoIP / GeoSite 规则库，完成后将自动提示并重启 Xray");
        }).catch(function (e) {
          self.updatingGeo = false;
          self.showToast("触发规则更新失败: " + e.message);
        });
      },

      loadPreviewData: function () {
        var self = this;
        self.loadingPreview = true;
        callRpc("get_preview", {}).then(function (d) {
          self.previewJson = d.config_json || "";
          self.previewLogs = d.logs || "暂无相关日志";
        }).catch(function (e) {
          self.showToast("加载预览失败: " + e.message);
        }).finally(function () {
          self.loadingPreview = false;
        });
      }
    },

    render: function (h) {
      var self = this;

      function row(label, desc, ctrlNode) {
        return h("div", { class: "xgl-row" }, [
          h("div", { class: "xgl-label-col" }, [
            h("div", { class: "xgl-label" }, label),
            desc ? h("div", { class: "xgl-desc" }, desc) : null
          ]),
          h("div", { class: "xgl-ctrl-col" }, Array.isArray(ctrlNode) ? ctrlNode : [ctrlNode])
        ]);
      }

      function textInput(obj, key, placeholder) {
        return h("input", {
          class: "xgl-input",
          attrs: { type: "text", placeholder: placeholder || "" },
          domProps: { value: obj[key] || "" },
          on: { input: function (e) { self.$set(obj, key, e.target.value); } }
        });
      }

      function autoTextarea(obj, key, placeholder) {
        var val = obj[key] || "";
        var lineCount = val ? String(val).split(/\r?\n/).length : 1;
        var rows = lineCount <= 1 ? 1 : (lineCount > 6 ? 6 : lineCount);
        return h("textarea", {
          class: "xgl-textarea",
          attrs: { rows: rows, placeholder: placeholder || "" },
          domProps: { value: val },
          on: { input: function (e) { self.$set(obj, key, e.target.value); } }
        });
      }

      function flagSwitch(obj, key) {
        return h("gl-switch", {
          props: { value: obj[key] === "1" },
          on: { input: function (v) { self.$set(obj, key, v ? "1" : "0"); } }
        });
      }

      function selectInput(obj, key, options, onChangeExtra) {
        var cur = obj[key] || "";
        return h("select", {
          class: "xgl-select",
          domProps: { value: cur },
          on: {
            change: function (e) {
              self.$set(obj, key, e.target.value);
              if (onChangeExtra) onChangeExtra(e.target.value);
            }
          }
        }, options.map(function (opt) {
          return h("option", { domProps: { value: opt[0], selected: opt[0] === cur } }, opt[1]);
        }));
      }

      function serverAliasById(id) {
        var found = self.servers.find(function (s) { return s[".name"] === id; });
        return found ? (found.alias || found.server || id) : id;
      }

      function multiNodeSelector(poolKey) {
        var selected = self[poolKey] || [];
        var nodeMap = (self.metrics && self.metrics.nodes) || {};
        return h("div", { style: { width: "100%", display: "flex", flexWrap: "wrap", gap: "6px", alignItems: "center", justifyContent: "flex-end" } },
          selected.length > 0 ? selected.map(function (id) {
            var nm = nodeMap[id];
            var statText = "";
            if (nm) {
              if (nm.delay > 0) statText += " · " + nm.delay + "ms";
              if (nm.down > 0 || nm.up > 0) statText += " · ↓" + fmtBytes(nm.down) + " ↑" + fmtBytes(nm.up);
            }
            return h("span", {
              key: id,
              class: "xgl-badge " + (nm && nm.alive === false ? "err" : "ok"),
              style: { cursor: "pointer", userSelect: "none" },
              attrs: { title: "点击从池中移除该节点" },
              on: { click: function () { self.togglePoolNode(poolKey, id); } }
            }, serverAliasById(id) + statText + " ✕");
          }).concat([
            h("button", {
              class: "xgl-btn sm",
              style: { padding: "2px 8px", fontSize: "11px" },
              on: {
                click: function () {
                  self[poolKey] = [];
                  self.showToast("已清空该节点池，请点击“立即保存并应用”生效");
                }
              }
            }, "清空")
          ]) : [
            h("span", { class: "xgl-desc" }, "未添加节点（请在下方节点列表中点击 ⚡ 设为主用 或 +IPv4池）")
          ]
        );
      }

      // Top status bar
      var m = self.metrics;
      var statusBadgeClass = "err";
      var statusLabel = self.tproxy_enabled ? "○ Xray 已停止 (点击卸载转发规则)" : "○ Xray 已停止";
      if (self.proc_running) {
        statusBadgeClass = self.tproxy_enabled ? "ok" : "warn";
        statusLabel = (self.tproxy_enabled ? "● Xray 透明代理运行中" : "◐ 仅核心运行 (TProxy 未挂载)") + (m && m.mem_mb ? " (" + m.mem_mb + ")" : "");
      }
      var topBar = h("div", { class: "xgl-topbar" }, [
        h("div", { class: "xgl-status-group" }, [
          h("span", {
            class: "xgl-badge " + statusBadgeClass,
            style: !self.proc_running ? { cursor: "pointer", userSelect: "none" } : null,
            attrs: {
              title: !self.proc_running
                ? "点击直接卸载残留的 nftables / dnsmasq 转发规则"
                : ""
            },
            on: {
              click: function () {
                if (!self.proc_running && !self.saving) {
                  self.controlService("stop");
                }
              }
            }
          }, statusLabel),
          m ? h("span", { class: "xgl-badge ok" }, "代理流量: ↓" + fmtBytes(m.proxy_down) + " / ↑" + fmtBytes(m.proxy_up)) : null,
          m ? h("span", { class: "xgl-badge info" }, "直连流量: ↓" + fmtBytes(m.direct_down) + " / ↑" + fmtBytes(m.direct_up)) : null,
          (m && m.direct_delay != null) ? h("span", { class: "xgl-badge " + (m.direct_delay > 0 ? "ok" : "err") },
            "直连观测: " + (m.direct_delay > 0 ? m.direct_delay + "ms" : "超时")
          ) : null,
          h("span", { class: "xgl-badge " + (self.geoip_ok ? "info" : "err") }, "GeoIP: " + self.geoip_size),
          h("span", { class: "xgl-badge " + (self.geosite_ok ? "info" : "err") }, "GeoSite: " + self.geosite_size),
          self.cnPing ? h("span", { class: "xgl-badge " + (self.cnPing.ok ? "ok" : "err") }, "国内测速: " + (self.cnPing.ok ? self.cnPing.latency_ms + "ms" : "不通")) : null,
          self.googlePing ? h("span", { class: "xgl-badge " + (self.googlePing.ok ? "ok" : "err") }, "Google测速: " + (self.googlePing.ok ? self.googlePing.latency_ms + "ms" : "不通")) : null
        ]),
        h("div", { class: "xgl-status-group" }, [
          h("button", { class: "xgl-btn sm", attrs: { disabled: self.testing }, on: { click: self.runPingTest } }, self.testing ? "测速中..." : "⚡ 连通性测速"),
          h("button", { class: "xgl-btn sm", attrs: { disabled: self.saving }, on: { click: function () { self.controlService("restart"); } } }, "🔄 重启服务"),
          h("button", {
            class: "xgl-btn sm " + (self.proc_running ? "danger" : "success"),
            attrs: { disabled: self.saving },
            on: { click: function () { self.controlService(self.proc_running ? "stop" : "start"); } }
          }, self.proc_running ? "⏹ 停止服务" : "▶ 启动服务")
        ])
      ]);

      // Unsaved changes reminder banner
      var dirtyBanner = self.isDirty ? h("div", { class: "xgl-dirty-bar" }, [
        h("span", "⚠ 检测到未保存的配置或预设修改，需点击保存后才会写入路由器并重启生效。"),
        h("div", { class: "xgl-status-group" }, [
          h("button", { class: "xgl-btn sm", attrs: { disabled: self.saving }, on: { click: self.loadAll } }, "放弃修改"),
          h("button", { class: "xgl-btn sm primary", attrs: { disabled: self.saving }, on: { click: self.saveAllGeneral } }, self.saving ? "保存中..." : "💾 立即保存并应用")
        ])
      ]) : null;

      // Navigation tabs (5 single-responsibility tabs)
      var lanList = self.subsections.lan_hosts || [];
      var extraInbounds = self.subsections.extra_inbound || [];
      var tabs = [
        ["status", "1. 控制台与节点 (" + self.servers.length + ")"],
        ["dns", "2. DNS 与分流规则"],
        ["access", "3. 设备控制与入站 (" + (lanList.length + extraInbounds.length) + ")"],
        ["advanced", "4. 高级参数与监控"],
        ["preview", "5. 配置预览与日志"]
      ];
      var tabBar = h("div", { class: "xgl-tabs" }, tabs.map(function (t) {
        return h("div", {
          class: "xgl-tab " + (self.activeTab === t[0] ? "active" : ""),
          on: {
            click: function () {
              self.activeTab = t[0];
              if (t[0] === "preview") self.loadPreviewData();
            }
          }
        }, t[1]);
      }));

      // Filter servers for node list
      var kw = self.serverKeyword.trim().toLowerCase();
      var protoF = self.serverProtoFilter;
      var filteredServers = self.servers.filter(function (s) {
        if (protoF && (s.protocol || "") !== protoF) return false;
        if (!kw) return true;
        return ((s.alias || "") + " " + (s.server || "") + " " + (s.protocol || "")).toLowerCase().indexOf(kw) >= 0;
      });

      var currentPreset = self.detectRoutingPreset();
      var presetLabelMap = {
        bypass_cn: "当前模式：绕过中国大陆",
        blacklist: "当前模式：黑名单模式 (v2rayN)",
        global: "当前模式：全局代理",
        custom: "当前模式：自定义规则"
      };

      // Tab 1: General Settings + Routing Mode + Servers & Subscriptions
      var tabStatus = h("div", [
        h("div", { class: "xgl-section-title" }, [
          h("div", { class: "xgl-status-group" }, [
            h("span", "核心透明代理开关、多节点负载均衡池与分流模式"),
            h("span", { class: "xgl-badge info" }, presetLabelMap[currentPreset] || "自定义")
          ]),
          h("div", { class: "xgl-status-group" }, [
            h("button", {
              class: "xgl-btn sm " + (currentPreset === "bypass_cn" ? "success" : ""),
              on: { click: function () { self.applyRoutingPreset("bypass_cn"); } }
            }, "绕过中国大陆"),
            h("button", {
              class: "xgl-btn sm " + (currentPreset === "blacklist" ? "success" : ""),
              attrs: { title: "参考本地 v2rayN V4-黑名单(Blacklist)：仅 GFW/海外常用服务走代理，其余默认直连并阻断 UDP 443" },
              on: { click: function () { self.applyRoutingPreset("blacklist"); } }
            }, "黑名单模式 (v2rayN)"),
            h("button", {
              class: "xgl-btn sm " + (currentPreset === "global" ? "success" : ""),
              on: { click: function () { self.applyRoutingPreset("global"); } }
            }, "全局代理")
          ])
        ]),
        row("启用透明代理 (Enable Transparent Proxy)", "总开关：启用后自动配置 dnsmasq 与 nftables 将局域网设备流量按规则转入 Xray", flagSwitch(self.gen, "transparent_proxy_enable")),
        row("IPv4 TCP 节点池 (已选 " + self.tcpNodesV4.length + " 个)", "可选 1 个主节点，或添加多个节点开启负载均衡 / 自动故障切换", multiNodeSelector("tcpNodesV4")),
        row("IPv4 UDP 节点池 (已选 " + self.udpNodesV4.length + " 个)", "用于 QUIC / 游戏 / 语音及 DNS 查询的 IPv4 UDP 出站节点池", multiNodeSelector("udpNodesV4")),
        row("IPv6 TCP 节点池 (已选 " + self.tcpNodesV6.length + " 个)", "用于 IPv6 TCP 流量（默认留空可防无 IPv6 代理时分流异常）", multiNodeSelector("tcpNodesV6")),
        row("IPv6 UDP 节点池 (已选 " + self.udpNodesV6.length + " 个)", "用于 IPv6 UDP 流量（默认留空）", multiNodeSelector("udpNodesV6")),
        row("多节点负载均衡策略 (Balancer Strategy)", "当上方节点池添加 ≥2 个节点时生效：leastPing 会自动探测并优先走延迟最低的存活节点（需开启 Observatory）", selectInput(self.gen, "general_balancer_strategy", [
          ["random", "random (随机均摊流量)"],
          ["leastPing", "leastPing (最低延迟优先 + 自动故障切换)"],
          ["roundRobin", "roundRobin (按序轮询分配)"]
        ])),

        h("div", { class: "xgl-section-title", style: { marginTop: "24px" } }, [
          h("span", "服务器节点管理与订阅 (" + filteredServers.length + " / " + self.servers.length + ")"),
          h("div", { class: "xgl-status-group" }, [
            h("select", {
              class: "xgl-select",
              style: { width: "115px", padding: "4px 8px" },
              domProps: { value: self.serverProtoFilter },
              on: { change: function (e) { self.serverProtoFilter = e.target.value; } }
            }, [
              ["", "全部协议"],
              ["vless", "VLESS"],
              ["vmess", "VMess"],
              ["shadowsocks", "SS"],
              ["trojan", "Trojan"],
              ["hysteria", "Hysteria2"]
            ].map(function (opt) {
              return h("option", { domProps: { value: opt[0], selected: opt[0] === self.serverProtoFilter } }, opt[1]);
            })),
            h("input", {
              class: "xgl-input",
              style: { width: "170px", padding: "4px 10px" },
              attrs: { placeholder: "🔍 搜索节点名称/地址..." },
              domProps: { value: self.serverKeyword },
              on: { input: function (e) { self.serverKeyword = e.target.value; } }
            }),
            ((kw || protoF) && filteredServers.length > 0) ? h("button", {
              class: "xgl-btn sm",
              attrs: { title: "将当前筛选出的有效节点全部加入 IPv4 负载均衡池" },
              on: { click: function () { self.addFilteredToV4Pool(filteredServers); } }
            }, "➕ 筛选入v4池 (" + filteredServers.length + ")") : null,
            h("button", { class: "xgl-btn sm primary", on: { click: function () { self.showImportBox = !self.showImportBox; } } }, "📥 订阅 / 链接导入"),
            h("button", { class: "xgl-btn sm success", on: { click: function () { self.openEditServer(null); } } }, "➕ 新增节点")
          ])
        ]),

        self.showImportBox ? h("div", { style: { padding: "14px", borderRadius: "8px", background: "rgba(52,152,219,0.08)", marginBottom: "14px", border: "1px solid rgba(52,152,219,0.25)" } }, [
          h("div", { style: { fontWeight: "600", marginBottom: "6px" } }, "批量导入机场订阅 URL 或节点分享链接"),
          h("div", { class: "xgl-desc", style: { marginBottom: "8px" } }, "支持直接输入 http(s):// 机场订阅地址自动拉取，或直接粘贴 ss://、vmess://、vless://、trojan://、hysteria2:// 链接（每行一条或 Base64 文本）："),
          h("textarea", {
            class: "xgl-textarea",
            attrs: { placeholder: "https://example.com/api/v1/client/subscribe?token=xxx\n或粘贴 vless://... vmess://... ss://... hysteria2://..." },
            domProps: { value: self.importText },
            on: { input: function (e) { self.importText = e.target.value; } }
          }),
          h("div", { style: { display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: "10px", flexWrap: "wrap", gap: "10px" } }, [
            h("label", { style: { display: "flex", alignItems: "center", gap: "6px", cursor: "pointer", fontSize: "13px" } }, [
              h("input", {
                attrs: { type: "checkbox" },
                domProps: { checked: self.importReplaceAll },
                on: { change: function (e) { self.importReplaceAll = e.target.checked; } }
              }),
              "导入前清空现有全部节点（覆盖更新订阅时勾选）"
            ]),
            h("div", { class: "xgl-status-group" }, [
              h("button", { class: "xgl-btn sm", attrs: { disabled: self.importing }, on: { click: function () { self.showImportBox = false; } } }, "取消"),
              h("button", { class: "xgl-btn sm primary", attrs: { disabled: self.importing }, on: { click: self.submitImportLinks } }, self.importing ? "正在解析导入..." : "立即导入节点")
            ])
          ])
        ]) : null,

        h("div", { class: "xgl-table-wrap" }, [
          h("table", { class: "xgl-table", style: { tableLayout: "fixed" } }, [
            h("thead", [
              h("tr", [
                h("th", { style: { width: "26%" } }, "节点别名 (Alias)"),
                h("th", { style: { width: "60px", whiteSpace: "nowrap" } }, "协议"),
                h("th", { style: { width: "92px", whiteSpace: "nowrap" } }, "传输/安全"),
                h("th", { style: { width: "24%" } }, "服务器地址 : 端口"),
                h("th", { style: { width: "330px", textAlign: "right", whiteSpace: "nowrap" } }, "快捷切换 / 负载池 / 操作")
              ])
            ]),
            h("tbody", filteredServers.map(function (srv) {
              var id = srv[".name"];
              var inV4 = self.tcpNodesV4.indexOf(id) >= 0 || self.udpNodesV4.indexOf(id) >= 0;
              var inV6 = self.tcpNodesV6.indexOf(id) >= 0 || self.udpNodesV6.indexOf(id) >= 0;
              var isSoleV4 = self.tcpNodesV4.length === 1 && self.tcpNodesV4[0] === id && self.udpNodesV4.length === 1 && self.udpNodesV4[0] === id;
              var isCurrent = inV4 || inV6;
              var nm = (self.metrics && self.metrics.nodes && self.metrics.nodes[id]) || null;
              var p = srv.protocol || "";
              var tls = srv[p + "_tls"] || "none";
              return h("tr", { key: id, class: isCurrent ? "active-row" : "" }, [
                h("td", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, [
                  h("strong", srv.alias || "-"),
                  inV4 ? h("span", { class: "xgl-badge ok", style: { marginLeft: "6px", padding: "2px 7px" } }, "IPv4") : null,
                  inV6 ? h("span", { class: "xgl-badge info", style: { marginLeft: "4px", padding: "2px 7px" } }, "IPv6") : null,
                  (nm && nm.delay > 0) ? h("span", { class: "xgl-badge ok", style: { marginLeft: "4px", padding: "2px 7px" } }, nm.delay + "ms") : null
                ]),
                h("td", { style: { whiteSpace: "nowrap", fontSize: "12px" } }, p === "shadowsocks" ? "SS" : p.toUpperCase()),
                h("td", { style: { whiteSpace: "nowrap", fontSize: "12px" } }, (srv.transport || "tcp").toUpperCase() + (tls !== "none" ? "+" + tls.toUpperCase() : "")),
                h("td", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: "12px" }, attrs: { title: (srv.server || "") + ":" + firstItem(srv.server_port) } }, (srv.server || "") + ":" + firstItem(srv.server_port)),
                h("td", { style: { textAlign: "right", whiteSpace: "nowrap" } }, [
                  h("button", {
                    class: "xgl-btn sm " + (isSoleV4 ? "primary" : ""),
                    style: { marginRight: "5px" },
                    attrs: { disabled: self.saving || isSoleV4, title: "设为唯一 IPv4 主节点并立即重启生效" },
                    on: { click: function () { self.quickUseServer(id); } }
                  }, isSoleV4 ? "当前主用" : "⚡ 设为主用"),
                  h("button", {
                    class: "xgl-btn sm " + (inV4 ? "success" : ""),
                    style: { marginRight: "5px" },
                    attrs: { title: "加入或移出上方 IPv4 TCP/UDP 负载均衡池" },
                    on: { click: function () { self.toggleFamilyPool("tcpNodesV4", "udpNodesV4", id); } }
                  }, inV4 ? "✓ v4池" : "+v4池"),
                  h("button", {
                    class: "xgl-btn sm " + (inV6 ? "primary" : ""),
                    style: { marginRight: "5px" },
                    attrs: { title: "加入或移出上方 IPv6 TCP/UDP 负载均衡池" },
                    on: { click: function () { self.toggleFamilyPool("tcpNodesV6", "udpNodesV6", id); } }
                  }, inV6 ? "✓ v6池" : "+v6池"),
                  h("button", {
                    class: "xgl-btn sm",
                    style: { marginRight: "5px" },
                    on: { click: function () { self.openEditServer(srv); } }
                  }, "编辑"),
                  h("button", {
                    class: "xgl-btn sm danger",
                    attrs: { disabled: self.saving },
                    on: { click: function () { self.removeServer(id, srv.alias); } }
                  }, "删除")
                ])
              ]);
            }))
          ])
        ])
      ]);

      // Tab 2: DNS, Domain Rules, Outbound IP/Port Routing, Sniffing
      var tabDns = h("div", [
        h("div", { class: "xgl-section-title" }, [
          h("span", "分流 DNS 与去广告域名规则"),
          h("button", {
            class: "xgl-btn sm",
            attrs: { disabled: self.updatingGeo },
            on: { click: self.triggerGeoUpdate }
          }, self.updatingGeo ? "⏳ 正在下载更新规则库..." : "🌐 在线更新 GeoIP / GeoSite 规则库")
        ]),
        row("国内快速 DNS (Fast DNS)", "用于解析代理服务器入口域名及下方直连白名单域名（填 IP:端口，推荐 223.5.5.5:53）", textInput(self.gen, "fast_dns", "223.5.5.5:53")),
        row("直连域名规则 (Bypassed Domain Rules)", "每行一条，匹配域名使用快速 DNS 解析且直接绕过代理直连（如 geosite:cn）", autoTextarea(self, "bypassedRulesText", "例如 geosite:cn（回车可输入多行）")),
        row("海外安全 DNS (Secure DNS)", "通过代理解析被污染的海外域名（填 IP:端口，推荐 1.1.1.1:53）", textInput(self.gen, "secure_dns", "1.1.1.1:53")),
        row("强制代理域名规则 (Forwarded Domain Rules)", "每行一条，匹配域名走安全 DNS 并强制走代理出站（如 geosite:gfw 或 geosite:geolocation-!cn）", autoTextarea(self, "forwardedRulesText", "例如 geosite:geolocation-!cn（回车可输入多行）")),
        row("默认兜底 DNS (Default DNS)", "未命中上述规则的其他域名使用的 DNS（绕过大陆模式建议 1.1.1.1:53，黑名单模式建议 223.5.5.5:53）", textInput(self.gen, "default_dns", "1.1.1.1:53")),
        row("广告与拦截域名规则 (Blocked Domain Rules)", "每行一条，匹配域名直接拦截（如 geosite:category-ads）", autoTextarea(self, "blockedRulesText", "例如 geosite:category-ads（回车可输入多行）")),
        row("拦截域名返回 127.127.127.127 (Blocked to Loopback)", "关闭则返回 NXDOMAIN", flagSwitch(self.gen, "blocked_to_loopback")),
        row("Xray 内部 DNS 监听端口 (DNS Server Port)", "供 dnsmasq 转发上游使用，勿填 53 或 5353", textInput(self.gen, "dns_port", "5300")),
        row("额外并发 DNS 端口数 (Extra DNS Ports)", "默认 3 表示同时监听 5300~5303 共 4 个端口提升并发能力", textInput(self.gen, "dns_count", "3")),
        row("快速 DNS 严格对齐 GeoIP 直连", "开启后 Fast DNS 仅返回属于直连国家 IP 段的解析结果", flagSwitch(self.gen, "align_fast_dns_to_geoip_direct")),
        row("Dnsmasq 集成模式", "OpenWrt 24.10+ 支持按实例集成；默认 global 即可", selectInput(self.gen, "dnsmasq_integration_mode", [
          ["global", "global (全局集成)"],
          ["per_instance", "per_instance (按实例集成)"]
        ])),

        h("div", { class: "xgl-section-title", style: { marginTop: "24px" } }, "GeoIP 国家代码与 IP/端口出站分流规则"),
        row("GeoIP 直连代码列表 (IPv4)", "每行一个代码，如 cn（中国大陆 IP 直连）；黑名单或全局模式请留空", autoTextarea(self, "geoipDirectV4Text", "如 cn")),
        row("GeoIP 直连代码列表 (IPv6)", "每行一个代码，如 cn", autoTextarea(self, "geoipDirectV6Text", "如 cn")),
        row("绕过代理的目标 IP / CIDR (Bypassed IP)", "每行一个 IP 或网段，访问这些目标 IP 时强制直连不经过 Xray", autoTextarea(self, "wanBpIpsText", "每行一个 IP 或 CIDR")),
        row("强制代理的目标 IP / CIDR (Forwarded IP)", "每行一个 IP 或网段，访问这些目标 IP 时始终交由 Xray 处理", autoTextarea(self, "wanFwIpsText", "每行一个 IP 或 CIDR")),
        row("默认端口转发策略 (Default Ports Policy)", "Forwarded 转发所有端口；Bypassed 仅代理指定的常用端口（如 80, 443）", selectInput(self.gen, "transparent_default_port_policy", [
          ["forwarded", "forwarded (默认转发所有端口)"],
          ["bypassed", "bypassed (默认绕过，仅转发指定端口)"]
        ])),
        self.gen.transparent_default_port_policy === "forwarded"
          ? row("绕过代理的 TCP 端口 (Bypassed TCP Ports)", "每行一个端口或范围", textInput(self, "wanBpTcpPortsText", "如 22, 3389"))
          : row("需要代理的 TCP 端口 (Forwarded TCP Ports)", "推荐 80, 443, 853", textInput(self, "wanFwTcpPortsText", "80, 443, 853")),
        self.gen.transparent_default_port_policy === "forwarded"
          ? row("绕过代理的 UDP 端口 (Bypassed UDP Ports)", "每行一个端口或范围", textInput(self, "wanBpUdpPortsText", "如 123"))
          : row("需要代理的 UDP 端口 (Forwarded UDP Ports)", "推荐 53, 443", textInput(self, "wanFwUdpPortsText", "53, 443")),

        h("div", { class: "xgl-section-title", style: { marginTop: "24px" } }, "流量域名嗅探 (Traffic Sniffing)"),
        row("启用流量嗅探 (Enable Sniffing)", "从 TLS SNI / HTTP Host 中还原真实访问域名用于精准路由分流（强烈建议开启）", flagSwitch(self.gen, "tproxy_sniffing")),
        self.gen.tproxy_sniffing === "1"
          ? row("仅用于路由分流 (Route Only)", "开启后嗅探出的域名仅用于匹配分流规则，连接时仍使用已解析的 IP，避免二次 DNS 解析开销", flagSwitch(self.gen, "route_only"))
          : null,
        row("BT 下载流量强制直连 (Bittorrent Direct)", "开启后识别到 BitTorrent 协议流量直接走本地宽带直连，防止触发机场审计封号", flagSwitch(self.gen, "direct_bittorrent")),
        row("路由域名解析策略 (Routing Domain Strategy)", "匹配路由规则时的 IP 解析策略", selectInput(self.gen, "routing_domain_strategy", [
          ["AsIs", "AsIs (仅按域名匹配，最快)"],
          ["IPIfNonMatch", "IPIfNonMatch (域名未命中时解析 IP 匹配)"],
          ["IPOnDemand", "IPOnDemand (遇到 IP 规则时按需解析)"]
        ]))
      ]);

      // Tab 3: Instant-apply LAN Hosts & Extra Inbounds
      var tabAccess = h("div", [
        h("div", { class: "xgl-section-title" }, [
          h("span", "局域网设备独立分流控制 (LAN Hosts Access Control)"),
          h("span", { class: "xgl-badge info" }, "添加/删除即时生效")
        ]),
        h("div", { class: "xgl-desc", style: { marginBottom: "10px" } }, "可针对家里特定设备（如智能电视、游戏机、NAS 或工作电脑）单独指定“完全直连不走代理 (bypass)”或“启用透明代理 (tproxy)”："),
        h("div", { style: { display: "flex", flexWrap: "wrap", gap: "8px", alignItems: "center", marginBottom: "12px" } }, [
          h("select", {
            class: "xgl-select",
            style: { width: "220px" },
            domProps: { value: self.newLanHost.macaddr },
            on: {
              change: function (e) {
                var mac = e.target.value;
                if (!mac) return;
                self.newLanHost.macaddr = mac;
                var found = self.lan_clients.find(function (c) { return c.mac === mac; });
                if (found) self.newLanHost.alias = found.name;
              }
            }
          }, [
            h("option", { domProps: { value: "", selected: !self.newLanHost.macaddr } }, "-- 从当前在线设备中选择 --")
          ].concat(self.lan_clients.map(function (c) {
            return h("option", { domProps: { value: c.mac, selected: c.mac === self.newLanHost.macaddr } }, c.name + " (" + c.ip + " / " + c.mac + ")");
          }))),
          h("input", {
            class: "xgl-input",
            style: { width: "160px" },
            attrs: { placeholder: "设备 MAC 地址" },
            domProps: { value: self.newLanHost.macaddr },
            on: { input: function (e) { self.newLanHost.macaddr = e.target.value; } }
          }),
          h("input", {
            class: "xgl-input",
            style: { width: "140px" },
            attrs: { placeholder: "设备备注名" },
            domProps: { value: self.newLanHost.alias },
            on: { input: function (e) { self.newLanHost.alias = e.target.value; } }
          }),
          h("select", {
            class: "xgl-select",
            style: { width: "170px" },
            domProps: { value: self.newLanHost.access_control_strategy_v4 },
            on: {
              change: function (e) {
                self.newLanHost.access_control_strategy_v4 = e.target.value;
                self.newLanHost.access_control_strategy_v6 = e.target.value;
              }
            }
          }, [
            h("option", { domProps: { value: "bypass", selected: self.newLanHost.access_control_strategy_v4 === "bypass" } }, "强制直连 (不走代理)"),
            h("option", { domProps: { value: "tproxy", selected: self.newLanHost.access_control_strategy_v4 === "tproxy" } }, "启用透明代理")
          ]),
          h("button", { class: "xgl-btn sm primary", attrs: { disabled: self.saving }, on: { click: self.addLanHostRule } }, "➕ 添加设备规则")
        ]),
        lanList.length > 0 ? h("table", { class: "xgl-table" }, [
          h("thead", [h("tr", [h("th", "设备备注"), h("th", "MAC 地址"), h("th", "IPv4 策略"), h("th", "IPv6 策略"), h("th", "操作")])]),
          h("tbody", lanList.map(function (item) {
            return h("tr", { key: item[".name"] }, [
              h("td", item.alias || "-"),
              h("td", item.macaddr || ""),
              h("td", item.access_control_strategy_v4 === "bypass" ? "直连 (Bypass)" : "透明代理 (TProxy)"),
              h("td", item.access_control_strategy_v6 === "bypass" ? "直连 (Bypass)" : "透明代理 (TProxy)"),
              h("td", [
                h("button", {
                  class: "xgl-btn sm danger",
                  attrs: { disabled: self.saving },
                  on: { click: function () { self.deleteSubItem(item[".name"], item.alias || item.macaddr); } }
                }, "删除")
              ])
            ]);
          }))
        ]) : h("div", { class: "xgl-desc" }, "当前暂无单独指定的局域网设备规则（所有连接 br-lan 的设备默认共享全局透明代理设置）。"),

        h("div", { class: "xgl-section-title", style: { marginTop: "28px" } }, [
          h("span", "额外 SOCKS5 / HTTP 入站端口 (Extra Inbounds)"),
          h("span", { class: "xgl-badge info" }, "添加/删除即时生效")
        ]),
        h("div", { style: { display: "flex", flexWrap: "wrap", gap: "8px", alignItems: "center", marginBottom: "12px" } }, [
          h("input", {
            class: "xgl-input",
            style: { width: "130px" },
            attrs: { placeholder: "监听地址 0.0.0.0" },
            domProps: { value: self.newInbound.inbound_addr },
            on: { input: function (e) { self.newInbound.inbound_addr = e.target.value; } }
          }),
          h("input", {
            class: "xgl-input",
            style: { width: "90px" },
            attrs: { placeholder: "端口 1080" },
            domProps: { value: self.newInbound.inbound_port },
            on: { input: function (e) { self.newInbound.inbound_port = e.target.value; } }
          }),
          h("select", {
            class: "xgl-select",
            style: { width: "135px" },
            domProps: { value: self.newInbound.inbound_type },
            on: { change: function (e) { self.newInbound.inbound_type = e.target.value; } }
          }, [
            h("option", { domProps: { value: "socks5", selected: self.newInbound.inbound_type === "socks5" } }, "SOCKS5 代理"),
            h("option", { domProps: { value: "http", selected: self.newInbound.inbound_type === "http" } }, "HTTP 代理")
          ]),
          h("select", {
            class: "xgl-select",
            style: { width: "160px" },
            domProps: { value: self.newInbound.specify_outbound },
            on: { change: function (e) { self.newInbound.specify_outbound = e.target.value; } }
          }, [
            h("option", { domProps: { value: "0", selected: self.newInbound.specify_outbound === "0" } }, "出站：跟随全局分流"),
            h("option", { domProps: { value: "1", selected: self.newInbound.specify_outbound === "1" } }, "出站：绑定指定节点")
          ]),
          self.newInbound.specify_outbound === "1" ? h("select", {
            class: "xgl-select",
            style: { width: "210px" },
            domProps: { value: self.newInbound.destination },
            on: { change: function (e) { self.newInbound.destination = e.target.value; } }
          }, self.servers.map(function (s) {
            return h("option", { domProps: { value: s[".name"], selected: s[".name"] === self.newInbound.destination } }, (s.alias || s.server) + " (" + s[".name"] + ")");
          })) : null,
          h("button", { class: "xgl-btn sm primary", attrs: { disabled: self.saving }, on: { click: self.addExtraInbound } }, "➕ 添加入站端口")
        ]),
        extraInbounds.length > 0 ? h("table", { class: "xgl-table" }, [
          h("thead", [h("tr", [h("th", "监听地址:端口"), h("th", "协议类型"), h("th", "出站设置"), h("th", "操作")])]),
          h("tbody", extraInbounds.map(function (ib) {
            var destId = firstItem(ib.destination);
            var label = (ib.inbound_addr || "0.0.0.0") + ":" + (ib.inbound_port || "");
            return h("tr", { key: ib[".name"] }, [
              h("td", label),
              h("td", (ib.inbound_type || "").toUpperCase()),
              h("td", ib.specify_outbound === "1" ? ("绑定节点: " + serverAliasById(destId)) : "跟随全局分流"),
              h("td", [
                h("button", {
                  class: "xgl-btn sm danger",
                  attrs: { disabled: self.saving },
                  on: { click: function () { self.deleteSubItem(ib[".name"], label); } }
                }, "删除")
              ])
            ]);
          }))
        ]) : h("div", { class: "xgl-desc" }, "当前暂无额外入站端口。")
      ]);

      // Tab 4: Extra Options & Firewall
      var tabAdvanced = h("div", [
        h("div", { class: "xgl-section-title" }, "Xray 运行程序与监控统计 (Extra Options)"),
        row("Xray 可执行文件路径 (Xray Bin)", "默认 /usr/bin/xray", textInput(self.gen, "xray_bin", "/usr/bin/xray")),
        row("日志级别 (Log Level)", "日常推荐 warning 以减少日志写入", selectInput(self.gen, "loglevel", [
          ["debug", "debug (调试)"],
          ["info", "info (信息)"],
          ["warning", "warning (警告 - 推荐)"],
          ["error", "error (仅错误)"],
          ["none", "none (禁用日志)"]
        ])),
        row("启用访问日志 (Access Log)", "将每次连接记录写入系统日志", flagSwitch(self.gen, "access_log")),
        row("启用 DNS 日志 (DNS Log)", "将每次 DNS 查询记录写入系统日志", flagSwitch(self.gen, "dns_log")),
        row("启用流量统计 (Enable Statistics)", "统计各入站与出站节点的实时流量", flagSwitch(self.gen, "stats")),
        row("启用节点连通性观测器 (Enable Observatory)", "后台定期探测出站节点延迟，支撑 leastPing 策略与状态页展示", flagSwitch(self.gen, "observatory")),
        row("启用Metrics 监控接口 (Metrics Server)", "开启本地 HTTP debug/vars 统计接口", flagSwitch(self.gen, "metrics_server_enable")),
        self.gen.metrics_server_enable === "1"
          ? row("Metrics 监控监听端口", "默认 18888", textInput(self.gen, "metrics_server_port", "18888"))
          : null,
        row("启用 Firewall4 规则计数器", "在 nftables 中统计透明代理匹配包数", flagSwitch(self.gen, "fw4_counter")),

        h("div", { class: "xgl-section-title" }, "防火墙标记与连接超时策略 (Firewall & Policy)"),
        row("防环回 Socket Mark 标记值", "Xray 出站流量打上该标记以绕过 nftables 劫持防死循环（默认 255）", textInput(self.gen, "mark", "255")),
        row("防火墙规则优先级 (Firewall Priority)", "默认 10", textInput(self.gen, "firewall_priority", "10")),
        row("握手超时 / 空闲超时 (秒)", "handshake 默认 4 秒；conn_idle 默认 300 秒", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
          textInput(self.gen, "handshake", "4"),
          textInput(self.gen, "conn_idle", "300")
        ])),
        row("连接单端关闭等待时间 (Uplink / Downlink Only)", "默认 2 秒 / 5 秒", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
          textInput(self.gen, "uplink_only", "2"),
          textInput(self.gen, "downlink_only", "5")
        ])),
        row("每连接内部缓存大小 (Buffer Size KB)", "留空默认 4 KB（填 0 禁用内部缓存；GL-MT3000 勿设过大防 OOM）", textInput(self.gen, "buffer_size", "4")),
        row("启用 IPv4 TCP 动态直连优化 (Dynamic Direct TCP)", "大连接数下载场景可提升直连性能", flagSwitch(self.gen, "dynamic_direct_tcp4")),
        row("启用 IPv4 UDP 动态直连优化 (Dynamic Direct UDP)", "UDP 并发场景可提升直连性能", flagSwitch(self.gen, "dynamic_direct_udp4")),
        row("自定义 ucode 配置钩子 (Custom Configuration Hook)", "高级用户在生成 config.json 前动态修改配置对象的 ucode 函数（黑名单模式预设会自动注入此处）", autoTextarea(self.gen, "custom_configuration_hook", "return function(config) { return config; };"))
      ]);

      // Tab 5: Config Preview & Logs
      var luciHref = getLuciUrl();
      var tabPreview = h("div", [
        h("div", { class: "xgl-section-title" }, [
          h("span", "Xray 实时系统日志 (logread -e xray)"),
          h("div", { class: "xgl-status-group" }, [
            h("button", { class: "xgl-btn sm", attrs: { disabled: self.loadingPreview }, on: { click: self.loadPreviewData } }, self.loadingPreview ? "刷新中..." : "🔄 刷新配置与日志"),
            h("a", { class: "xgl-btn sm", attrs: { href: luciHref, target: "_blank", rel: "noopener" }, style: { textDecoration: "none" } }, "🔗 新窗口打开原版 LuCI")
          ])
        ]),
        h("pre", { class: "xgl-code", style: { height: "220px", marginBottom: "18px" } }, self.previewLogs || "点击右上方刷新按钮加载日志..."),
        h("div", { class: "xgl-section-title" }, "当前生效的 /var/etc/xray/config.json 全文预览"),
        h("pre", { class: "xgl-code" }, self.previewJson || "点击右上方刷新按钮加载 config.json...")
      ]);

      // Server Edit Modal
      var ed = self.editingServer;
      var dialerOptions = [["disabled", "disabled (不启用前置代理)"]].concat(
        self.servers.filter(function (s) { return !ed || s[".name"] !== ed.id; }).map(function (s) {
          return [s[".name"], (s.alias || s.server) + " (" + s[".name"] + ")"];
        })
      );
      var editModal = ed ? h("div", {
        class: "xgl-modal-mask",
        on: {
          click: function (e) {
            if (e.target === e.currentTarget && !self.savingServer) self.editingServer = null;
          }
        }
      }, [
        h("div", { class: "xgl-modal" }, [
          h("div", { class: "xgl-modal-header" }, [
            h("span", ed.id ? "编辑节点 (" + ed.id + ")" : "新增 Xray 节点"),
            h("button", { class: "xgl-btn sm", attrs: { disabled: self.savingServer }, on: { click: function () { self.editingServer = null; } } }, "✕")
          ]),
          h("div", { class: "xgl-modal-body" }, [
            row("节点别名 (Alias)", "显示在列表与状态栏中的中文名称", textInput(ed, "alias", "例如：日本Z03 | IEPL")),
            row("服务器地址 (Server Hostname / IP)", "填写域名或 IPv4 / IPv6 地址", textInput(ed, "server", "example.com")),
            row("服务器端口 (Port)", "填写数字端口号", textInput(ed, "port", "443")),
            row("代理协议 (Protocol)", "支持 Xray 全部主流出站协议", selectInput(ed, "protocol", [
              ["shadowsocks", "Shadowsocks (SS / SS-2022)"],
              ["vmess", "VMess"],
              ["vless", "VLESS (含 XTLS / Reality)"],
              ["trojan", "Trojan"],
              ["hysteria", "Hysteria2"],
              ["socks", "SOCKS5"],
              ["http", "HTTP"]
            ], function (val) {
              if (val === "hysteria") {
                self.$set(ed, "transport", "hysteria");
                self.$set(ed, "tls_mode", "tls");
              } else {
                if (ed.transport === "hysteria") {
                  self.$set(ed, "transport", "tcp");
                }
                if (val !== "vless" && ed.tls_mode === "reality") {
                  self.$set(ed, "tls_mode", val === "trojan" ? "tls" : "none");
                }
              }
            })),
            row("密码 / UUID (Password / UserId)", "VMess/VLESS 填 UUID；SS/Trojan/Hysteria2 填密码", textInput(ed, "password", "UUID 或密码")),

            ed.protocol === "shadowsocks" ? row("Shadowsocks 加密算法", "支持传统 AEAD 与最新 2022-blake3 系列", selectInput(ed, "shadowsocks_security", [
              ["aes-256-gcm", "aes-256-gcm"],
              ["aes-128-gcm", "aes-128-gcm"],
              ["chacha20-poly1305", "chacha20-poly1305"],
              ["2022-blake3-aes-128-gcm", "2022-blake3-aes-128-gcm"],
              ["2022-blake3-aes-256-gcm", "2022-blake3-aes-256-gcm"],
              ["2022-blake3-chacha20-poly1305", "2022-blake3-chacha20-poly1305"],
              ["none", "none"]
            ])) : null,

            ed.protocol === "vmess" ? row("VMess 加密算法与 AlterId", "现代节点 AlterId 建议为 0 (AEAD)", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
              selectInput(ed, "vmess_security", [["auto", "auto"], ["aes-128-gcm", "aes-128-gcm"], ["chacha20-poly1305", "chacha20-poly1305"], ["none", "none"]]),
              textInput(ed, "vmess_alter_id", "0")
            ])) : null,

            row("传输层协议 (Transport)", "底层数据传输载体", selectInput(ed, "transport", [
              ["tcp", "TCP (RAW)"],
              ["ws", "WebSocket (WS)"],
              ["grpc", "gRPC"],
              ["splithttp", "SplitHTTP (XHTTP)"],
              ["httpupgrade", "HTTPUpgrade"],
              ["h2", "HTTP/2"],
              ["mkcp", "mKCP"],
              ["quic", "QUIC"],
              ["hysteria", "Hysteria2"]
            ])),

            ed.transport === "ws" ? row("WebSocket Host 与 Path", "伪装域名与路径", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
              textInput(ed, "ws_host", "伪装 Host 域名"),
              textInput(ed, "ws_path", "/path")
            ])) : null,

            ed.transport === "grpc" ? row("gRPC Service Name", "gRPC 服务名称", textInput(ed, "grpc_service_name", "serviceName")) : null,

            ed.transport === "splithttp" ? row("SplitHTTP (XHTTP) Host 与 Path", "XHTTP 伪装域名与路径", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
              textInput(ed, "splithttp_host", "Host"),
              textInput(ed, "splithttp_path", "/path")
            ])) : null,

            ed.transport === "httpupgrade" ? row("HTTPUpgrade Host 与 Path", "伪装域名与路径", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
              textInput(ed, "httpupgrade_host", "Host"),
              textInput(ed, "httpupgrade_path", "/path")
            ])) : null,

            (ed.transport === "hysteria" || ed.protocol === "hysteria") ? h("div", [
              row("Hysteria2 上行 / 下行带宽 (Mbps)", "填写整数 Mbps（留空则使用 BBR），对应 hysteria_up_mbps / down_mbps", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
                textInput(ed, "hysteria_up", "上行 Mbps (如 50)"),
                textInput(ed, "hysteria_down", "下行 Mbps (如 200)")
              ])),
              row("Hysteria2 端口跳跃范围 (UDP Hop Port)", "例如 20000-50000（留空则不启用端口跳跃）", textInput(ed, "hysteria_udphop_port", "20000-50000"))
            ]) : null,

            row("传输层加密 (Stream Security)", "VLESS 支持 REALITY 与 TLS；Hysteria2 强制 TLS", selectInput(ed, "tls_mode",
              ed.protocol === "hysteria"
                ? [["tls", "tls (标准 TLS)"]]
                : (ed.protocol === "vless"
                  ? [["none", "none (不启用 TLS)"], ["tls", "tls (标准 TLS)"], ["reality", "reality (VLESS REALITY)"]]
                  : [["none", "none (不启用 TLS)"], ["tls", "tls (标准 TLS)"]])
            )),

            (ed.protocol === "vless" && (ed.tls_mode === "tls" || ed.tls_mode === "reality")) ? row("VLESS XTLS 流控 (Flow)", "REALITY / TLS 直连推荐 xtls-rprx-vision", selectInput(ed, "flow_mode", [
              ["none", "none"],
              ["xtls-rprx-vision", "xtls-rprx-vision"],
              ["xtls-rprx-vision-udp443", "xtls-rprx-vision-udp443"]
            ])) : null,

            ed.tls_mode === "tls" ? h("div", [
              row("TLS SNI 域名与 uTLS 指纹", "Server Name 与浏览器握手特征模拟", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
                textInput(ed, "tls_host", "SNI 域名"),
                selectInput(ed, "tls_fingerprint", [["chrome", "chrome"], ["firefox", "firefox"], ["safari", "safari"], ["ios", "ios"], ["random", "random"]])
              ])),
              row("证书校验策略 (Allow Insecure)", "默认 0 严格验证服务端证书；自签证书可设为 1", selectInput(ed, "tls_insecure", [
                ["0", "0 (严格验证证书 - 安全推荐)"],
                ["1", "1 (跳过证书验证 allowInsecure)"]
              ]))
            ]) : null,

            ed.tls_mode === "reality" ? h("div", [
              row("REALITY 目标偷取域名 (Server Name)", "如 www.microsoft.com 或 apple.com", textInput(ed, "reality_server_name", "www.microsoft.com")),
              row("REALITY 公钥 (Public Key / pbk)", "服务端生成的公钥", textInput(ed, "reality_public_key", "Public Key")),
              row("REALITY Short ID 与 Fingerprint", "ShortId 与浏览器指纹", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
                textInput(ed, "reality_short_id", "ShortId"),
                selectInput(ed, "reality_fingerprint", [["chrome", "chrome"], ["firefox", "firefox"], ["safari", "safari"], ["ios", "ios"]])
              ])),
              row("REALITY 爬虫路径 (SpiderX / spx)", "选填，如 /（对应 vless_reality_spider_x）", textInput(ed, "reality_spider_x", "/"))
            ]) : null,

            row("服务器域名解析策略与前置代理", "默认 UseIP；前置代理可选择链式代理跳板节点", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
              selectInput(ed, "domain_strategy", [["UseIP", "UseIP"], ["UseIPv4", "UseIPv4"], ["UseIPv6", "UseIPv6"]]),
              selectInput(ed, "dialer_proxy", dialerOptions)
            ]))
          ]),
          h("div", { class: "xgl-modal-footer" }, [
            h("button", { class: "xgl-btn", attrs: { disabled: self.savingServer }, on: { click: function () { self.editingServer = null; } } }, "取消"),
            h("button", { class: "xgl-btn", attrs: { disabled: self.savingServer }, on: { click: function () { self.saveEditingServer(false); } } }, "仅保存节点"),
            h("button", { class: "xgl-btn primary", attrs: { disabled: self.savingServer }, on: { click: function () { self.saveEditingServer(true); } } }, self.savingServer ? "应用中..." : "保存并立即应用")
          ])
        ])
      ]) : null;

      var activeView = tabStatus;
      if (self.activeTab === "dns") activeView = tabDns;
      else if (self.activeTab === "access") activeView = tabAccess;
      else if (self.activeTab === "advanced") activeView = tabAdvanced;
      else if (self.activeTab === "preview") activeView = tabPreview;

      var showGeneralFooter = self.activeTab === "status" || self.activeTab === "dns" || self.activeTab === "advanced";

      return h("div", { class: "xgl-wrap" }, [
        h("gl-title", { props: { title: "Xray 透明代理控制台" } }),
        h("gl-card", [
          topBar,
          dirtyBanner,
          tabBar,
          activeView,
          showGeneralFooter ? h("div", { class: "xgl-btn-bar" }, [
            h("button", { class: "xgl-btn", attrs: { disabled: self.saving }, on: { click: self.loadAll } }, "重新加载配置"),
            h("button", {
              class: "xgl-btn primary",
              attrs: { disabled: self.saving },
              on: { click: self.saveAllGeneral }
            }, self.saving ? "正在保存并重启 Xray..." : "💾 保存配置并应用生效")
          ]) : null
        ]),
        editModal,
        self.toastMsg ? h("div", { class: "xgl-toast" }, self.toastMsg) : null
      ]);
    }
  };

  if (typeof module !== "undefined") {
    module.exports = XrayApp;
  }
  return XrayApp;
})();
EOF_VIEW_JS

gzip -9 -f -c "$VIEW_JS" > "$VIEW_GZ"

# Persist across firmware upgrades
if [ -f /etc/sysupgrade.conf ]; then
    for f in "$MENU_FILE" "$VALIDATOR_FILE" "$RPC_FILE" "$VIEW_JS" "$VIEW_GZ"; do
        grep -qxF "$f" /etc/sysupgrade.conf 2>/dev/null || echo "$f" >> /etc/sysupgrade.conf
    done
fi

say "正在平滑重载 Nginx 工作进程以激活 RPC 模块..."
nginx -s reload >/dev/null 2>&1 || true

say "=================================================================="
say "安装成功！请打开浏览器访问 http://192.168.8.1 (GL.iNet 官方后台)"
say "在左侧菜单栏点击：【应用 (Applications)】 -> 【Xray 透明代理】"
say "如需卸载，随时运行：sh install.sh --uninstall"
say "=================================================================="
