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
    "index": 10,
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
    delete_all_servers = true,
    switch_node = true,
    import_links = true,
    save_subsection = true,
    delete_subsection = true,
    service_ctl = true,
    test_connectivity = true,
    get_preview = true,
    update_geodata = true
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
    return true, string.format("%.2f MB", sz / (1024 * 1024))
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

local function is_xray_running()
    local svc = ubus.call("service", "list", { name = "xray_core" })
    if svc and svc.xray_core and svc.xray_core.instances then
        for _, inst in pairs(svc.xray_core.instances) do
            if inst.running then return true end
        end
    end
    return fs.access("/var/run/xray.pid") or false
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

    local sub_types = { "lan_hosts", "extra_inbound", "fakedns", "manual_tproxy", "bridge", "fallback" }
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

    return {
        code = 0,
        data = {
            running = is_xray_running(),
            geoip_ok = geoip_ok,
            geoip_size = geoip_sz,
            geosite_ok = geosite_ok,
            geosite_size = geosite_sz,
            general_id = gen_id,
            general = clean_uci_section(gen),
            servers = servers,
            subsections = subsections,
            lan_clients = get_lan_clients()
        }
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
        os.execute("/etc/init.d/xray_core restart >/dev/null 2>&1 &")
    end
    return { code = 0, data = { ok = true } }
end

-- 3. Quick switch active TCP/UDP node & mode
function M.switch_node(args)
    if type(args) ~= "table" then
        return { code = -1, error = "参数错误" }
    end
    local c = uci.cursor()
    local gen_id, gen = get_general_section(c)

    if args.enabled ~= nil then
        c:set("xray_core", gen_id, "transparent_proxy_enable", args.enabled and "1" or "0")
    end
    if type(args.tcp_node) == "string" and args.tcp_node ~= "" then
        c:set("xray_core", gen_id, "tcp_balancer_v4", { args.tcp_node })
    elseif type(args.tcp_nodes) == "table" and #args.tcp_nodes > 0 then
        c:set("xray_core", gen_id, "tcp_balancer_v4", args.tcp_nodes)
    end
    if type(args.udp_node) == "string" and args.udp_node ~= "" then
        c:set("xray_core", gen_id, "udp_balancer_v4", { args.udp_node })
    elseif type(args.udp_nodes) == "table" and #args.udp_nodes > 0 then
        c:set("xray_core", gen_id, "udp_balancer_v4", args.udp_nodes)
    end

    -- Non-destructively toggle geosite:cn / geoip:cn for routing preset
    if args.preset == "bypass_cn" then
        local bp = type(gen.bypassed_domain_rules) == "table" and gen.bypassed_domain_rules or {}
        local found = false
        for _, v in ipairs(bp) do if v == "geosite:cn" then found = true end end
        if not found then bp[#bp + 1] = "geosite:cn" end
        c:set("xray_core", gen_id, "bypassed_domain_rules", bp)
        c:set("xray_core", gen_id, "geoip_direct_code_list", { "cn" })
        c:set("xray_core", gen_id, "geoip_direct_code_list_v6", { "cn" })
    elseif args.preset == "global" then
        local bp = {}
        if type(gen.bypassed_domain_rules) == "table" then
            for _, v in ipairs(gen.bypassed_domain_rules) do
                if v ~= "geosite:cn" then bp[#bp + 1] = v end
            end
        end
        if #bp > 0 then
            c:set("xray_core", gen_id, "bypassed_domain_rules", bp)
        else
            c:delete("xray_core", gen_id, "bypassed_domain_rules")
        end
        c:delete("xray_core", gen_id, "geoip_direct_code_list")
        c:delete("xray_core", gen_id, "geoip_direct_code_list_v6")
    end

    c:commit("xray_core")
    os.execute("/etc/init.d/xray_core restart >/dev/null 2>&1 &")
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
        os.execute("/etc/init.d/xray_core restart >/dev/null 2>&1 &")
    end
    return { code = 0, data = { id = sec } }
end

-- 5. Delete a server node
function M.delete_server(args)
    if type(args) ~= "table" or type(args.id) ~= "string" then
        return { code = -1, error = "未指定节点 ID" }
    end
    local c = uci.cursor()
    c:delete("xray_core", args.id)
    c:commit("xray_core")
    return { code = 0, data = { ok = true } }
end

-- 6. Parse URI share links (ss://, vmess://, vless://, trojan://) and subscription URLs
local function parse_query(qs)
    local q = {}
    if not qs then return q end
    for pair in qs:gmatch("[^&]+") do
        local k, v = pair:match("^([^=]+)=(.*)$")
        if k then q[url_decode(k)] = url_decode(v) end
    end
    return q
end

local function parse_single_uri(line)
    line = trim(line)
    if line == "" then return nil end

    -- 1. vmess:// (base64 JSON)
    if line:match("^vmess://") then
        local b64 = line:sub(9)
        local raw = base64_decode(b64)
        local ok, j = pcall(cjson.decode, raw)
        if ok and type(j) == "table" and j.add and j.port then
            local net = j.net or "tcp"
            if net == "xhttp" then net = "splithttp" end
            local tls_mode = (j.tls == "tls" or j.tls == "1") and "tls" or "none"
            local srv = {
                alias = tostring(j.ps or (j.add .. ":" .. tostring(j.port))),
                server = tostring(j.add),
                server_port = { tostring(j.port) },
                password = tostring(j.id or ""),
                protocol = "vmess",
                vmess_security = tostring(j.scy or "auto"),
                vmess_alter_id = tostring(j.aid or "0"),
                alter_id = tostring(j.aid or "0"),
                vmess_tls = tls_mode,
                transport = net,
                domain_strategy = "UseIP",
                dialer_proxy = "disabled"
            }
            if net == "tcp" then
                srv.tcp_guise = (j.type == "http") and "http" or "none"
                if j.host and j.host ~= "" then srv.http_host = { tostring(j.host) } end
                if j.path and j.path ~= "" then srv.http_path = { tostring(j.path) } end
            elseif net == "ws" then
                srv.ws_host = tostring(j.host or "")
                srv.ws_path = tostring(j.path or "/")
            elseif net == "grpc" then
                srv.grpc_service_name = tostring(j.path or "")
            elseif net == "splithttp" then
                srv.splithttp_host = tostring(j.host or "")
                srv.splithttp_path = tostring(j.path or "/")
            elseif net == "httpupgrade" then
                srv.httpupgrade_host = tostring(j.host or "")
                srv.httpupgrade_path = tostring(j.path or "/")
            end
            if tls_mode == "tls" then
                srv.vmess_tls_host = tostring(j.sni or j.host or "")
                srv.vmess_tls_insecure = (j.allowInsecure == true or j.allowInsecure == "1") and "1" or "0"
                srv.vmess_tls_fingerprint = tostring(j.fp or "chrome")
            end
            return srv
        end
        return nil
    end

    -- 2. ss:// (SIP002 & legacy base64)
    if line:match("^ss://") then
        local rest = line:sub(6)
        local alias = ""
        local hash_pos = rest:find("#", 1, true)
        if hash_pos then
            alias = url_decode(rest:sub(hash_pos + 1))
            rest = rest:sub(1, hash_pos - 1)
        end
        local q_pos = rest:find("?", 1, true)
        if q_pos then rest = rest:sub(1, q_pos - 1) end

        local userinfo, hostport = rest:match("^([^@]+)@(.+)$")
        local method, pass, host, port
        if userinfo and hostport then
            if not userinfo:find(":", 1, true) then
                userinfo = base64_decode(userinfo)
            else
                userinfo = url_decode(userinfo)
            end
            method, pass = userinfo:match("^([^:]+):(.+)$")
            host, port = hostport:match("^([^:]+):(%d+)$")
        else
            local decoded = base64_decode(rest)
            method, pass, host, port = decoded:match("^([^:]+):(.+)@([^:]+):(%d+)$")
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

    -- 3. vless:// and trojan://
    local proto = line:match("^(vless)://") or line:match("^(trojan)://")
    if proto then
        local rest = line:sub(#proto + 4)
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
        local uuid, host, port = rest:match("^([^@]+)@([^:]+):(%d+)$")
        if not uuid then return nil end
        uuid = url_decode(uuid)
        local q = parse_query(qs)
        local net = q.type or "tcp"
        if net == "xhttp" then net = "splithttp" end
        local sec = q.security or (proto == "trojan" and "tls" or "none")

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
                srv.vless_tls_insecure = (q.allowInsecure == "1") and "1" or "0"
            elseif sec == "reality" then
                srv.vless_flow_reality = q.flow or "xtls-rprx-vision"
                srv.vless_reality_server_name = q.sni or ""
                srv.vless_reality_public_key = q.pbk or ""
                srv.vless_reality_short_id = q.sid or ""
                srv.vless_spider_x = q.spx or ""
                srv.vless_reality_fingerprint = q.fp or "chrome"
            end
        elseif proto == "trojan" then
            srv.trojan_tls = (sec == "none") and "none" or "tls"
            if srv.trojan_tls == "tls" then
                srv.trojan_tls_host = q.sni or q.host or ""
                srv.trojan_tls_fingerprint = q.fp or "chrome"
                srv.trojan_tls_insecure = (q.allowInsecure == "1") and "1" or "0"
            end
        end

        if net == "tcp" then
            srv.tcp_guise = (q.headerType == "http") and "http" or "none"
        elseif net == "ws" then
            srv.ws_host = q.host or ""
            srv.ws_path = q.path or "/"
        elseif net == "grpc" then
            srv.grpc_service_name = q.serviceName or q.path or ""
        elseif net == "splithttp" then
            srv.splithttp_host = q.host or ""
            srv.splithttp_path = q.path or "/"
        elseif net == "httpupgrade" then
            srv.httpupgrade_host = q.host or ""
            srv.httpupgrade_path = q.path or "/"
        end

        return srv
    end

    return nil
end

function M.import_links(args)
    if type(args) ~= "table" or type(args.text) ~= "string" then
        return { code = -1, error = "请输入订阅链接或节点分享链接" }
    end
    local input = trim(args.text)
    if input == "" then
        return { code = -1, error = "内容不能为空" }
    end

    -- If input is a single HTTP/HTTPS subscription URL, fetch it via curl
    if input:match("^https?://[^%s]+$") then
        local tmp = os.tmpname()
        os.execute(string.format("curl -fsSL --connect-timeout 10 -m 20 -A 'v2rayN/6.45' '%s' -o '%s' 2>/dev/null", input:gsub("'", ""), tmp))
        local body = read_file(tmp, 2 * 1024 * 1024) or ""
        os.remove(tmp)
        if body == "" then
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

    local c = uci.cursor()
    if args.replace_all then
        local to_del = {}
        c:foreach("xray_core", "servers", function(s) to_del[#to_del + 1] = s[".name"] end)
        for _, id in ipairs(to_del) do c:delete("xray_core", id) end
    end

    local added = 0
    for line in input:gmatch("[^\r\n]+") do
        local srv = parse_single_uri(line)
        if srv then
            local sec = next_server_id(c)
            c:set("xray_core", sec, "servers")
            apply_uci_fields(c, "xray_core", sec, srv)
            added = added + 1
        end
    end

    if added == 0 then
        return { code = -1, error = "未解析到有效节点（支持 ss://、vmess://、vless://、trojan:// 及 Base64 订阅内容）" }
    end

    c:commit("xray_core")
    return { code = 0, data = { added = added } }
end

-- 7. Generic subsection CRUD (lan_hosts, extra_inbound, fakedns, manual_tproxy, bridge)
local allowed_sub_types = {
    lan_hosts = true,
    extra_inbound = true,
    fakedns = true,
    manual_tproxy = true,
    bridge = true,
    fallback = true
}

function M.save_subsection(args)
    if type(args) ~= "table" or not allowed_sub_types[args.type] or type(args.values) ~= "table" then
        return { code = -1, error = "子配置表类型错误" }
    end
    local c = uci.cursor()
    local sec = args.id
    if not sec or sec == "" then
        sec = c:add("xray_core", args.type)
    end
    apply_uci_fields(c, "xray_core", sec, args.values)
    c:commit("xray_core")
    if args.apply then
        os.execute("/etc/init.d/xray_core restart >/dev/null 2>&1 &")
    end
    return { code = 0, data = { id = sec } }
end

function M.delete_subsection(args)
    if type(args) ~= "table" or type(args.id) ~= "string" then
        return { code = -1, error = "未指定条目 ID" }
    end
    local c = uci.cursor()
    c:delete("xray_core", args.id)
    c:commit("xray_core")
    if args.apply then
        os.execute("/etc/init.d/xray_core restart >/dev/null 2>&1 &")
    end
    return { code = 0, data = { ok = true } }
end

-- 8. Service control (start / stop / restart)
function M.service_ctl(args)
    local action = (args and args.action) or "restart"
    if action ~= "start" and action ~= "stop" and action ~= "restart" then
        return { code = -1, error = "不支持的操作" }
    end
    os.execute("/etc/init.d/xray_core " .. action .. " >/dev/null 2>&1 &")
    return { code = 0, data = { ok = true } }
end

-- 9. Connectivity check (2s connect timeout, non-blocking feel)
function M.test_connectivity(args)
    local target = (args and args.target == "cn")
        and "http://connectivitycheck.platform.hicloud.com/generate_204"
        or "https://www.google.com/generate_204"

    local cmd = string.format(
        "curl -s -o /dev/null -w '%%{http_code}:%%{time_total}' --connect-timeout 2 -m 3 '%s' 2>/dev/null",
        target
    )
    local f = io.popen(cmd)
    local out = f and f:read("*a") or ""
    if f then f:close() end

    local code, time_s = out:match("^(%d+):([%d%.]+)$")
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
    local f = io.popen("logread -e xray 2>/dev/null | tail -n 80")
    local logs = f and f:read("*a") or ""
    if f then f:close() end
    return {
        code = 0,
        data = {
            config_json = cfg,
            logs = logs
        }
    }
end

-- 11. Online update GeoIP / GeoSite from Loyalsoldier/v2ray-rules-dat
function M.update_geodata()
    local cmd = "("
        .. "curl -fsSL --connect-timeout 10 -m 120 -o /tmp/geoip.dat.new https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && "
        .. "curl -fsSL --connect-timeout 10 -m 120 -o /tmp/geosite.dat.new https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat && "
        .. "mv /tmp/geoip.dat.new /usr/share/xray/geoip.dat && "
        .. "mv /tmp/geosite.dat.new /usr/share/xray/geosite.dat && "
        .. "/etc/init.d/xray_core restart"
        .. ") >/tmp/xray_geo_update.log 2>&1 &"
    os.execute(cmd)
    return { code = 0, data = { started = true } }
end

return M
EOF_RPC_LUA

say "4/4 正在构建并压缩前端 Vue 2 视图包 ($VIEW_GZ)..."
cat << 'EOF_VIEW_JS' > "$VIEW_JS"
(function () {
  if (typeof document !== "undefined" && !document.getElementById("gl-xray-full-style")) {
    var styleEl = document.createElement("style");
    styleEl.id = "gl-xray-full-style";
    styleEl.textContent = [
      ".xgl-wrap { padding: 8px 0 36px; font-size: 14px; line-height: 1.5; }",
      ".xgl-topbar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 18px; border-radius: 10px; background: rgba(128,128,128,0.08); margin-bottom: 16px; border: 1px solid rgba(140,140,140,0.18); }",
      ".xgl-status-group { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }",
      ".xgl-badge { display: inline-flex; align-items: center; padding: 4px 11px; border-radius: 999px; font-size: 12px; font-weight: 600; }",
      ".xgl-badge.ok { background: rgba(46, 204, 113, 0.16); color: #27ae60; }",
      ".xgl-badge.err { background: rgba(231, 76, 60, 0.16); color: #e74c3c; }",
      ".xgl-badge.info { background: rgba(52, 152, 219, 0.15); color: #2980b9; }",
      ".xgl-tabs { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 16px; border-bottom: 1px solid rgba(140,140,140,0.2); padding-bottom: 8px; }",
      ".xgl-tab { padding: 8px 15px; border-radius: 6px; cursor: pointer; font-weight: 500; font-size: 13px; transition: all 0.15s; user-select: none; opacity: 0.78; }",
      ".xgl-tab:hover { opacity: 1; background: rgba(128,128,128,0.1); }",
      ".xgl-tab.active { opacity: 1; background: #2b6cb0; color: #fff; font-weight: 600; }",
      ".xgl-section-title { font-size: 15px; font-weight: 600; margin: 18px 0 8px; padding-bottom: 6px; border-bottom: 1px solid rgba(140,140,140,0.18); display: flex; align-items: center; justify-content: space-between; }",
      ".xgl-section-title:first-child { margin-top: 2px; }",
      ".xgl-row { display: flex; align-items: flex-start; justify-content: space-between; padding: 12px 0; border-bottom: 1px dashed rgba(140,140,140,0.14); gap: 16px; flex-wrap: wrap; }",
      ".xgl-row:last-child { border-bottom: none; }",
      ".xgl-label-col { flex: 1; min-width: 220px; }",
      ".xgl-label { font-weight: 500; font-size: 14px; }",
      ".xgl-desc { font-size: 12px; opacity: 0.68; margin-top: 3px; }",
      ".xgl-ctrl-col { width: 360px; max-width: 100%; display: flex; flex-direction: column; align-items: flex-end; }",
      ".xgl-input, .xgl-select, .xgl-textarea { width: 100%; box-sizing: border-box; padding: 7px 11px; border-radius: 6px; border: 1px solid rgba(140,140,140,0.35); background: transparent; color: inherit; font-size: 13px; outline: none; }",
      ".xgl-input:focus, .xgl-select:focus, .xgl-textarea:focus { border-color: #2b6cb0; }",
      ".xgl-select option { background: #222; color: #fff; }",
      ".xgl-textarea { font-family: inherit; resize: vertical; min-height: 34px; line-height: 1.45; overflow-y: auto; }",
      ".xgl-btn-bar { display: flex; flex-wrap: wrap; gap: 10px; justify-content: flex-end; margin-top: 18px; padding-top: 12px; border-top: 1px solid rgba(140,140,140,0.18); }",
      ".xgl-btn { padding: 7px 15px; border-radius: 6px; border: 1px solid rgba(140,140,140,0.35); background: transparent; color: inherit; cursor: pointer; font-size: 13px; font-weight: 500; transition: all 0.15s; }",
      ".xgl-btn:hover { background: rgba(128,128,128,0.12); }",
      ".xgl-btn.primary { background: #2b6cb0; color: #fff; border-color: #2b6cb0; }",
      ".xgl-btn.primary:hover { background: #2c5282; }",
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

  function callRpc(method, args) {
    if (typeof window.$rpcRequest !== "function") {
      return Promise.reject(new Error("$rpcRequest 未就绪"));
    }
    return window.$rpcRequest("call", ["sid", "xray", method, withoutNulls(args || {})]).then(function (res) {
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

  var XrayApp = {
    name: "GlSdk4UiXray",
    data: function () {
      return {
        activeTab: "status",
        loading: true,
        saving: false,
        testing: false,
        toastMsg: "",
        running: false,
        geoip_ok: false,
        geoip_size: "0 MB",
        geosite_ok: false,
        geosite_size: "0 MB",
        cnPing: null,
        googlePing: null,

        // UCI data models
        gen: {},
        servers: [],
        subsections: {
          lan_hosts: [],
          extra_inbound: [],
          fakedns: [],
          manual_tproxy: [],
          bridge: []
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
        tproxyIfacesV4Text: "br-lan",
        tproxyIfacesV6Text: "br-lan",

        // Tab 2: Server search, import, and modal editing
        serverKeyword: "",
        showImportBox: false,
        importText: "",
        importReplaceAll: false,
        importing: false,
        editingServer: null,

        // Tab 5: New LAN host & Extra inbound forms
        newLanHost: { macaddr: "", alias: "", access_control_strategy_v4: "bypass", access_control_strategy_v6: "bypass" },
        newInbound: { inbound_addr: "0.0.0.0", inbound_port: "1080", inbound_type: "socks5", specify_outbound: "0", destination: "" },

        // Tab 7: Config JSON preview & logs
        previewJson: "",
        previewLogs: "",
        loadingPreview: false
      };
    },
    created: function () {
      this.loadAll();
    },
    methods: {
      showToast: function (msg) {
        var self = this;
        self.toastMsg = msg;
        setTimeout(function () {
          if (self.toastMsg === msg) self.toastMsg = "";
        }, 3200);
      },
      loadAll: function () {
        var self = this;
        self.loading = true;
        return callRpc("get_all", {}).then(function (d) {
          self.running = !!d.running;
          self.geoip_ok = !!d.geoip_ok;
          self.geoip_size = d.geoip_size || "0 MB";
          self.geosite_ok = !!d.geosite_ok;
          self.geosite_size = d.geosite_size || "0 MB";
          var g = d.general || {};
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
            pool_v4: g.pool_v4 || "198.18.0.0/15",
            pool_v4_size: g.pool_v4_size || "65535",
            pool_v6: g.pool_v6 || "2001:2::/48",
            pool_v6_size: g.pool_v6_size || "65535",
            transparent_default_port_policy: g.transparent_default_port_policy || "forwarded",
            tproxy_sniffing: g.tproxy_sniffing || "0",
            route_only: g.route_only || "0",
            direct_bittorrent: g.direct_bittorrent || "0",
            routing_domain_strategy: g.routing_domain_strategy || "AsIs",
            tproxy_port_tcp_v4: g.tproxy_port_tcp_v4 || "1082",
            tproxy_port_tcp_v6: g.tproxy_port_tcp_v6 || "1083",
            tproxy_port_udp_v4: g.tproxy_port_udp_v4 || "1084",
            tproxy_port_udp_v6: g.tproxy_port_udp_v6 || "1085",
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
            firewall_priority: g.firewall_priority || "10",
            handshake: g.handshake || "4",
            conn_idle: g.conn_idle || "300",
            uplink_only: g.uplink_only || "2",
            downlink_only: g.downlink_only || "5",
            buffer_size: g.buffer_size || "512",
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
          self.tproxyIfacesV4Text = arrToLines(g.tproxy_ifaces_v4 || ["br-lan"]);
          self.tproxyIfacesV6Text = arrToLines(g.tproxy_ifaces_v6 || ["br-lan"]);

          self.servers = Array.isArray(d.servers) ? d.servers : [];
          self.subsections = d.subsections || { lan_hosts: [], extra_inbound: [], fakedns: [], manual_tproxy: [], bridge: [] };
          self.lan_clients = Array.isArray(d.lan_clients) ? d.lan_clients : [];
        }).catch(function (e) {
          self.showToast("加载失败: " + e.message);
        }).finally(function () {
          self.loading = false;
        });
      },

      saveAllGeneral: function () {
        var self = this;
        self.saving = true;
        var payload = Object.assign({}, self.gen, {
          tcp_balancer_v4: self.tcpNodesV4,
          udp_balancer_v4: self.tcpNodesV4,
          tcp_balancer_v6: self.tcpNodesV6,
          udp_balancer_v6: self.tcpNodesV6,
          bypassed_domain_rules: linesToArr(self.bypassedRulesText),
          forwarded_domain_rules: linesToArr(self.forwardedRulesText),
          blocked_domain_rules: linesToArr(self.blockedRulesText),
          geoip_direct_code_list: linesToArr(self.geoipDirectV4Text),
          geoip_direct_code_list_v6: linesToArr(self.geoipDirectV6Text),
          wan_bp_ips: linesToArr(self.wanBpIpsText),
          wan_fw_ips: linesToArr(self.wanFwIpsText),
          wan_bp_tcp_ports: linesToArr(self.wanBpTcpPortsText),
          wan_bp_udp_ports: linesToArr(self.wanBpUdpPortsText),
          wan_fw_tcp_ports: linesToArr(self.wanFwTcpPortsText),
          wan_fw_udp_ports: linesToArr(self.wanFwUdpPortsText),
          tproxy_ifaces_v4: linesToArr(self.tproxyIfacesV4Text),
          tproxy_ifaces_v6: linesToArr(self.tproxyIfacesV6Text)
        });

        return callRpc("save_general", { values: payload, apply: true }).then(function () {
          self.showToast("配置已保存并正在重启 Xray 服务...");
          setTimeout(function () {
            self.loadAll();
            self.saving = false;
          }, 2200);
        }).catch(function (e) {
          self.showToast("保存失败: " + e.message);
          self.saving = false;
        });
      },

      applyRoutingPreset: function (preset) {
        if (preset === "bypass_cn") {
          this.bypassedRulesText = "geosite:cn";
          this.forwardedRulesText = "geosite:geolocation-!cn";
          this.blockedRulesText = "geosite:category-ads";
          this.geoipDirectV4Text = "cn";
          this.geoipDirectV6Text = "cn";
          this.showToast("已填入【绕过中国大陆】规则，点击下方保存生效");
        } else if (preset === "global") {
          this.bypassedRulesText = "";
          this.forwardedRulesText = "geosite:geolocation-!cn";
          this.geoipDirectV4Text = "";
          this.geoipDirectV6Text = "";
          this.showToast("已填入【全局代理】规则，点击下方保存生效");
        }
      },

      quickUseServer: function (srvId) {
        var self = this;
        self.tcpNodesV4 = [srvId];
        self.udpNodesV4 = [srvId];
        self.saving = true;
        callRpc("switch_node", {
          enabled: true,
          tcp_nodes: [srvId],
          udp_nodes: [srvId]
        }).then(function () {
          self.showToast("已切换为唯一主节点并重启 Xray！");
          setTimeout(function () {
            self.loadAll();
            self.saving = false;
          }, 2000);
        }).catch(function (e) {
          self.showToast("切换失败: " + e.message);
          self.saving = false;
        });
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
      },

      toggleCombinedPool: function (srvId) {
        this.togglePoolNode("tcpNodesV4", srvId);
      },

      openEditServer: function (srv) {
        if (!srv) {
          this.editingServer = {
            id: "",
            alias: "新节点",
            server: "",
            port: "443",
            password: "",
            username: "",
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
            tcp_guise: "none",
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
        var tlsMode = srv[tlsField] || "none";
        this.editingServer = {
          id: srv[".name"],
          alias: srv.alias || "",
          server: srv.server || "",
          port: firstItem(srv.server_port) || "443",
          password: srv.password || "",
          username: srv.username || "",
          domain_strategy: srv.domain_strategy || "UseIP",
          dialer_proxy: srv.dialer_proxy || "disabled",
          protocol: p,
          shadowsocks_security: srv.shadowsocks_security || "aes-256-gcm",
          shadowsocks_udp_over_tcp: srv.shadowsocks_udp_over_tcp || "0",
          vmess_security: srv.vmess_security || "auto",
          vmess_alter_id: srv.vmess_alter_id || "0",
          vless_encryption: srv.vless_encryption || "none",
          tls_mode: tlsMode,
          flow_mode: (tlsMode === "reality" ? srv.vless_flow_reality : srv.vless_flow_tls) || "none",
          tls_host: srv[p + "_tls_host"] || "",
          tls_insecure: srv[p + "_tls_insecure"] || "0",
          tls_fingerprint: srv[p + "_tls_fingerprint"] || "chrome",
          reality_server_name: srv.vless_reality_server_name || "",
          reality_public_key: srv.vless_reality_public_key || "",
          reality_short_id: srv.vless_reality_short_id || "",
          reality_spider_x: srv.vless_spider_x || "",
          reality_fingerprint: srv.vless_reality_fingerprint || "chrome",
          transport: srv.transport || "tcp",
          tcp_guise: srv.tcp_guise || "none",
          ws_host: srv.ws_host || "",
          ws_path: srv.ws_path || "/",
          grpc_service_name: srv.grpc_service_name || "",
          splithttp_host: srv.splithttp_host || "",
          splithttp_path: srv.splithttp_path || "/",
          httpupgrade_host: srv.httpupgrade_host || "",
          httpupgrade_path: srv.httpupgrade_path || "/",
          hysteria_up: srv.hysteria_up || "",
          hysteria_down: srv.hysteria_down || "",
          hysteria_udphop_port: srv.hysteria_udphop_port || ""
        };
      },

      saveEditingServer: function () {
        var self = this;
        var ed = self.editingServer;
        if (!ed || !ed.server || !ed.port) {
          self.showToast("请填写服务器地址与端口");
          return;
        }
        var p = ed.protocol;
        var vals = {
          alias: ed.alias || (ed.server + ":" + ed.port),
          server: ed.server,
          server_port: [String(ed.port)],
          password: ed.password,
          username: ed.username,
          domain_strategy: ed.domain_strategy,
          dialer_proxy: ed.dialer_proxy,
          protocol: p,
          transport: ed.transport
        };
        vals[p + "_tls"] = ed.tls_mode;
        if (p === "shadowsocks") {
          vals.shadowsocks_security = ed.shadowsocks_security;
          vals.shadowsocks_udp_over_tcp = ed.shadowsocks_udp_over_tcp;
        } else if (p === "vmess") {
          vals.vmess_security = ed.vmess_security;
          vals.vmess_alter_id = ed.vmess_alter_id;
          vals.alter_id = ed.vmess_alter_id;
        } else if (p === "vless") {
          vals.vless_encryption = ed.vless_encryption || "none";
          if (ed.tls_mode === "tls") vals.vless_flow_tls = ed.flow_mode;
          if (ed.tls_mode === "reality") {
            vals.vless_flow_reality = ed.flow_mode;
            vals.vless_reality_server_name = ed.reality_server_name;
            vals.vless_reality_public_key = ed.reality_public_key;
            vals.vless_reality_short_id = ed.reality_short_id;
            vals.vless_spider_x = ed.reality_spider_x;
            vals.vless_reality_fingerprint = ed.reality_fingerprint;
          }
        }
        if (ed.tls_mode === "tls") {
          vals[p + "_tls_host"] = ed.tls_host;
          vals[p + "_tls_insecure"] = ed.tls_insecure;
          vals[p + "_tls_fingerprint"] = ed.tls_fingerprint;
        }
        if (ed.transport === "tcp") vals.tcp_guise = ed.tcp_guise;
        if (ed.transport === "ws") { vals.ws_host = ed.ws_host; vals.ws_path = ed.ws_path; }
        if (ed.transport === "grpc") vals.grpc_service_name = ed.grpc_service_name;
        if (ed.transport === "splithttp") { vals.splithttp_host = ed.splithttp_host; vals.splithttp_path = ed.splithttp_path; }
        if (ed.transport === "httpupgrade") { vals.httpupgrade_host = ed.httpupgrade_host; vals.httpupgrade_path = ed.httpupgrade_path; }
        if (ed.transport === "hysteria") {
          vals.hysteria_up = ed.hysteria_up;
          vals.hysteria_down = ed.hysteria_down;
          vals.hysteria_udphop_port = ed.hysteria_udphop_port;
        }

        callRpc("save_server", { id: ed.id, values: vals, apply: false }).then(function () {
          self.editingServer = null;
          self.showToast("节点已保存");
          self.loadAll();
        }).catch(function (e) {
          self.showToast("保存节点失败: " + e.message);
        });
      },

      removeServer: function (id) {
        var self = this;
        if (!confirm("确定要删除节点 " + id + " 吗？")) return;
        callRpc("delete_server", { id: id }).then(function () {
          self.showToast("已删除节点");
          self.loadAll();
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
        }).then(function (res) {
          self.showToast("成功导入 " + res.added + " 个节点！");
          self.importText = "";
          self.showImportBox = false;
          self.loadAll();
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
        callRpc("save_subsection", {
          type: "lan_hosts",
          values: self.newLanHost,
          apply: true
        }).then(function () {
          self.newLanHost = { macaddr: "", alias: "", access_control_strategy_v4: "bypass", access_control_strategy_v6: "bypass" };
          self.showToast("已添加设备分流规则并生效");
          self.loadAll();
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
        callRpc("save_subsection", {
          type: "extra_inbound",
          values: vals,
          apply: true
        }).then(function () {
          self.showToast("已添加额外入站端口并生效");
          self.loadAll();
        });
      },

      deleteSubItem: function (id) {
        var self = this;
        callRpc("delete_subsection", { id: id, apply: true }).then(function () {
          self.showToast("已删除规则");
          self.loadAll();
        });
      },

      controlService: function (action) {
        var self = this;
        callRpc("service_ctl", { action: action }).then(function () {
          self.showToast("已发送服务指令: " + action);
          setTimeout(function () { self.loadAll(); }, 1800);
        });
      },

      runPingTest: function () {
        var self = this;
        self.testing = true;
        self.cnPing = null;
        self.googlePing = null;
        Promise.all([
          callRpc("test_connectivity", { target: "cn" }),
          callRpc("test_connectivity", { target: "google" })
        ]).then(function (r) {
          self.cnPing = r[0];
          self.googlePing = r[1];
        }).finally(function () {
          self.testing = false;
        });
      },

      triggerGeoUpdate: function () {
        var self = this;
        callRpc("update_geodata", {}).then(function () {
          self.showToast("已在后台开始下载最新 GeoIP / GeoSite 规则库，完成后将自动重启 Xray");
        });
      },

      loadPreviewData: function () {
        var self = this;
        self.loadingPreview = true;
        callRpc("get_preview", {}).then(function (d) {
          self.previewJson = d.config_json || "";
          self.previewLogs = d.logs || "暂无相关日志";
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

      function selectInput(obj, key, options) {
        return h("select", {
          class: "xgl-select",
          domProps: { value: obj[key] || "" },
          on: { change: function (e) { self.$set(obj, key, e.target.value); } }
        }, options.map(function (opt) {
          return h("option", { domProps: { value: opt[0] } }, opt[1]);
        }));
      }

      function serverAliasById(id) {
        var found = self.servers.find(function (s) { return s[".name"] === id; });
        return found ? (found.alias || found.server || id) : id;
      }

      function multiNodeSelector(poolKey) {
        var selected = self[poolKey] || [];
        return h("div", { style: { width: "100%", display: "flex", flexDirection: "column", gap: "8px" } }, [
          h("div", { style: { display: "flex", flexWrap: "wrap", gap: "6px", alignItems: "center" } },
            selected.length > 0 ? selected.map(function (id) {
              return h("span", {
                key: id,
                class: "xgl-badge ok",
                style: { cursor: "pointer", userSelect: "none" },
                attrs: { title: "点击从池中移除该节点" },
                on: { click: function () { self.togglePoolNode(poolKey, id); } }
              }, serverAliasById(id) + " ✕");
            }).concat([
              h("button", {
                class: "xgl-btn sm",
                style: { padding: "2px 8px", fontSize: "11px" },
                on: { click: function () { self[poolKey] = []; } }
              }, "清空")
            ]) : [
              h("span", { class: "xgl-desc" }, "未选择节点（当前方向不启用代理）")
            ]
          ),
          h("select", {
            class: "xgl-select",
            domProps: { value: "" },
            on: {
              change: function (e) {
                var val = e.target.value;
                if (val && self[poolKey].indexOf(val) < 0) {
                  self[poolKey] = self[poolKey].concat([val]);
                }
                e.target.value = "";
              }
            }
          }, [
            h("option", { domProps: { value: "" } }, "+ 点击添加节点到此池 (可选多个组成负载均衡)...")
          ].concat(self.servers.map(function (s) {
            var id = s[".name"];
            var inPool = self[poolKey].indexOf(id) >= 0;
            return h("option", { domProps: { value: id, disabled: inPool } }, (inPool ? "✓ " : "") + (s.alias || s.server) + " [" + (s.protocol || "").toUpperCase() + "]");
          })))
        ]);
      }

      // Top status bar
      var topBar = h("div", { class: "xgl-topbar" }, [
        h("div", { class: "xgl-status-group" }, [
          h("span", { class: "xgl-badge " + (self.running ? "ok" : "err") }, self.running ? "● Xray 运行中" : "○ Xray 已停止"),
          h("span", { class: "xgl-badge " + (self.geoip_ok ? "info" : "err") }, "GeoIP: " + self.geoip_size),
          h("span", { class: "xgl-badge " + (self.geosite_ok ? "info" : "err") }, "GeoSite: " + self.geosite_size),
          self.cnPing ? h("span", { class: "xgl-badge " + (self.cnPing.ok ? "ok" : "err") }, "国内: " + (self.cnPing.ok ? self.cnPing.latency_ms + "ms" : "不通")) : null,
          self.googlePing ? h("span", { class: "xgl-badge " + (self.googlePing.ok ? "ok" : "err") }, "Google: " + (self.googlePing.ok ? self.googlePing.latency_ms + "ms" : "不通")) : null
        ]),
        h("div", { class: "xgl-status-group" }, [
          h("button", { class: "xgl-btn sm", on: { click: self.runPingTest } }, self.testing ? "测速中..." : "⚡ 连通性测速"),
          h("button", { class: "xgl-btn sm", on: { click: function () { self.controlService("restart"); } } }, "🔄 重启服务"),
          h("button", {
            class: "xgl-btn sm " + (self.running ? "danger" : "success"),
            on: { click: function () { self.controlService(self.running ? "stop" : "start"); } }
          }, self.running ? "⏹ 停止" : "▶ 启动")
        ])
      ]);

      // Navigation tabs
      var tabs = [
        ["status", "1. 基本设置与节点订阅 (" + self.servers.length + ")"],
        ["dns", "2. DNS 与分流规则"],
        ["advanced", "3. 高级参数与监控"],
        ["preview", "4. 配置预览与日志"]
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
      var filteredServers = self.servers.filter(function (s) {
        if (!kw) return true;
        return ((s.alias || "") + " " + (s.server || "") + " " + (s.protocol || "")).toLowerCase().indexOf(kw) >= 0;
      });

      // Tab 1: General Settings + Routing Mode + Servers & Subscriptions (Merged)
      var tabStatus = h("div", [
        h("div", { class: "xgl-section-title" }, [
          h("span", "核心透明代理开关、多节点负载均衡池与分流模式"),
          h("div", { class: "xgl-status-group" }, [
            h("button", { class: "xgl-btn sm", on: { click: function () { self.applyRoutingPreset("bypass_cn"); } } }, "一键预设：绕过中国大陆"),
            h("button", { class: "xgl-btn sm", on: { click: function () { self.applyRoutingPreset("global"); } } }, "一键预设：全局代理")
          ])
        ]),
        row("启用透明代理 (Enable Transparent Proxy)", "总开关：启用后自动配置 dnsmasq 与 nftables 将局域网设备流量按规则转入 Xray", flagSwitch(self.gen, "transparent_proxy_enable")),
        row("IPv4 TCP/UDP 节点池 (已选 " + self.tcpNodesV4.length + " 个)", "同时作用于 IPv4 的 TCP 与 UDP 流量（可选 1 个主节点，或添加多个节点开启负载均衡 / 自动故障切换）", multiNodeSelector("tcpNodesV4")),
        row("IPv6 TCP/UDP 节点池 (已选 " + self.tcpNodesV6.length + " 个)", "同时作用于 IPv6 的 TCP 与 UDP 流量（默认留空可防 IPv6 分流异常）", multiNodeSelector("tcpNodesV6")),
        row("多节点负载均衡策略 (Balancer Strategy)", "当上方节点池添加 ≥2 个节点时生效：leastPing 会自动探测并优先走延迟最低的存活节点（需开启 Observatory）", selectInput(self.gen, "general_balancer_strategy", [
          ["random", "random (随机均摊流量)"],
          ["leastPing", "leastPing (最低延迟优先 + 自动故障切换)"],
          ["roundRobin", "roundRobin (按序轮询分配)"]
        ])),

        // Node management & Subscription section placed right below routing/general settings
        h("div", { class: "xgl-section-title", style: { marginTop: "28px" } }, [
          h("span", "服务器节点管理与订阅 (" + filteredServers.length + " / " + self.servers.length + ")"),
          h("div", { class: "xgl-status-group" }, [
            h("input", {
              class: "xgl-input",
              style: { width: "180px", padding: "4px 10px" },
              attrs: { placeholder: "🔍 搜索节点名称/协议..." },
              domProps: { value: self.serverKeyword },
              on: { input: function (e) { self.serverKeyword = e.target.value; } }
            }),
            h("button", { class: "xgl-btn sm primary", on: { click: function () { self.showImportBox = !self.showImportBox; } } }, "📥 订阅 / 链接批量导入"),
            h("button", { class: "xgl-btn sm success", on: { click: function () { self.openEditServer(null); } } }, "➕ 手动新增节点")
          ])
        ]),

        self.showImportBox ? h("div", { style: { padding: "14px", borderRadius: "8px", background: "rgba(52,152,219,0.08)", marginBottom: "14px", border: "1px solid rgba(52,152,219,0.25)" } }, [
          h("div", { style: { fontWeight: "600", marginBottom: "6px" } }, "批量导入机场订阅 URL 或节点分享链接"),
          h("div", { class: "xgl-desc", style: { marginBottom: "8px" } }, "支持直接输入 http(s):// 机场订阅地址自动拉取，或直接从 v2rayN 全选复制 ss://、vmess://、vless://、trojan:// 链接粘贴在下方（每行一条或 Base64 文本）："),
          h("textarea", {
            class: "xgl-textarea",
            attrs: { placeholder: "https://example.com/api/v1/client/subscribe?token=xxx\n或粘贴 vless://... vmess://... ss://..." },
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
              h("button", { class: "xgl-btn sm", on: { click: function () { self.showImportBox = false; } } }, "取消"),
              h("button", { class: "xgl-btn sm primary", on: { click: self.submitImportLinks } }, self.importing ? "正在解析导入..." : "立即导入节点")
            ])
          ])
        ]) : null,

        h("div", { class: "xgl-table-wrap" }, [
          h("table", { class: "xgl-table", style: { tableLayout: "fixed" } }, [
            h("thead", [
              h("tr", [
                h("th", { style: { width: "26%" } }, "节点别名 (Alias)"),
                h("th", { style: { width: "68px", whiteSpace: "nowrap" } }, "协议"),
                h("th", { style: { width: "92px", whiteSpace: "nowrap" } }, "传输/安全"),
                h("th", { style: { width: "28%" } }, "服务器地址 : 端口"),
                h("th", { style: { width: "270px", textAlign: "right", whiteSpace: "nowrap" } }, "快捷单选 / 负载池多选 / 操作")
              ])
            ]),
            h("tbody", filteredServers.map(function (srv) {
              var id = srv[".name"];
              var isCurrent = self.tcpNodesV4.indexOf(id) >= 0;
              var p = srv.protocol || "";
              var tls = srv[p + "_tls"] || "none";
              return h("tr", { key: id, class: isCurrent ? "active-row" : "" }, [
                h("td", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, [
                  h("strong", srv.alias || "-"),
                  isCurrent ? h("span", { class: "xgl-badge ok", style: { marginLeft: "6px", padding: "2px 7px" } }, "已启用") : null
                ]),
                h("td", { style: { whiteSpace: "nowrap", fontSize: "12px" } }, p === "shadowsocks" ? "SS" : p.toUpperCase()),
                h("td", { style: { whiteSpace: "nowrap", fontSize: "12px" } }, (srv.transport || "tcp").toUpperCase() + (tls !== "none" ? "+" + tls.toUpperCase() : "")),
                h("td", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: "12px" }, attrs: { title: (srv.server || "") + ":" + firstItem(srv.server_port) } }, (srv.server || "") + ":" + firstItem(srv.server_port)),
                h("td", { style: { textAlign: "right", whiteSpace: "nowrap" } }, [
                  h("button", {
                    class: "xgl-btn sm success",
                    style: { marginRight: "6px" },
                    attrs: { title: "将该节点设为唯一的 TCP+UDP 主节点并立即重启生效" },
                    on: { click: function () { self.quickUseServer(id); } }
                  }, "单选启用"),
                  h("button", {
                    class: "xgl-btn sm " + (isCurrent ? "primary" : ""),
                    style: { marginRight: "6px" },
                    attrs: { title: "加入或移出上方 TCP+UDP 负载均衡节点池" },
                    on: { click: function () { self.toggleCombinedPool(id); } }
                  }, isCurrent ? "✓ 节点池" : "+节点池"),
                  h("button", {
                    class: "xgl-btn sm",
                    style: { marginRight: "6px" },
                    on: { click: function () { self.openEditServer(srv); } }
                  }, "编辑"),
                  h("button", {
                    class: "xgl-btn sm danger",
                    on: { click: function () { self.removeServer(id); } }
                  }, "删除")
                ])
              ]);
            }))
          ])
        ])
      ]);

      // Tab 2: DNS, Outbound Routing, Sniffing, LAN Hosts & Extra Inbounds
      var lanList = self.subsections.lan_hosts || [];
      var extraInbounds = self.subsections.extra_inbound || [];

      var tabDns = h("div", [
        h("div", { class: "xgl-section-title" }, [
          h("span", "分流 DNS 与去广告域名规则"),
          h("button", { class: "xgl-btn sm", on: { click: self.triggerGeoUpdate } }, "🌐 在线更新 GeoIP / GeoSite 规则库")
        ]),
        row("国内快速 DNS (Fast DNS)", "用于解析代理服务器入口域名及下方直连白名单域名（推荐 223.5.5.5:53 或 119.29.29.29:53）", textInput(self.gen, "fast_dns", "223.5.5.5:53")),
        row("直连域名规则 (Bypassed Domain Rules)", "每行一条，匹配域名使用快速 DNS 解析且直接绕过代理直连（如 geosite:cn 或 domain:bilibili.com）", autoTextarea(self, "bypassedRulesText", "例如 geosite:cn（回车可输入多行）")),
        row("海外安全 DNS (Secure DNS)", "通过代理解析被污染的海外域名（推荐 1.1.1.1:53 或 8.8.8.8:53）", textInput(self.gen, "secure_dns", "1.1.1.1:53")),
        row("强制代理域名规则 (Forwarded Domain Rules)", "每行一条，匹配域名走安全 DNS 并强制走代理出站（如 geosite:geolocation-!cn 或 domain:openai.com）", autoTextarea(self, "forwardedRulesText", "例如 geosite:geolocation-!cn（回车可输入多行）")),
        row("默认兜底 DNS (Default DNS)", "未命中上述规则的其他域名使用的 DNS", textInput(self.gen, "default_dns", "1.1.1.1:53")),
        row("广告与拦截域名规则 (Blocked Domain Rules)", "每行一条，匹配域名直接拦截（如 geosite:category-ads）", autoTextarea(self, "blockedRulesText", "例如 geosite:category-ads（回车可输入多行）")),
        row("拦截域名返回 127.127.127.127 (Blocked to Loopback)", "关闭则返回 NXDOMAIN", flagSwitch(self.gen, "blocked_to_loopback")),
        row("Xray 内部 DNS 监听端口 (DNS Server Port)", "供 dnsmasq 转发上游使用，勿填 53 或 5353", textInput(self.gen, "dns_port", "5300")),
        row("额外并发 DNS 端口数 (Extra DNS Ports)", "默认 3 表示同时监听 5300~5303 共 4 个端口提升并发能力", textInput(self.gen, "dns_count", "3")),
        row("快速 DNS 严格对齐 GeoIP 直连", "开启后 Fast DNS 仅返回属于直连国家 IP 段的解析结果", flagSwitch(self.gen, "align_fast_dns_to_geoip_direct")),
        row("Dnsmasq 集成模式", "OpenWrt 24.10+ 支持按实例集成；默认 global 即可", selectInput(self.gen, "dnsmasq_integration_mode", [
          ["global", "global (全局集成)"],
          ["per_instance", "per_instance (按实例集成)"]
        ])),

        // Merged Outbound Routing, Sniffing, LAN Hosts & Extra Inbounds
        h("div", { class: "xgl-section-title", style: { marginTop: "24px" } }, "GeoIP 国家代码与 IP/端口出站分流规则"),
        row("GeoIP 直连代码列表 (IPv4)", "每行一个代码，如 cn（中国大陆 IP 直连）或 telegram；留空则全部非私网 IP 走代理", autoTextarea(self, "geoipDirectV4Text", "如 cn")),
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

        h("div", { class: "xgl-section-title" }, "流量域名嗅探 (Traffic Sniffing)"),
        row("启用流量嗅探 (Enable Sniffing)", "从 TLS SNI / HTTP Host 中还原真实访问域名用于精准路由分流（强烈建议开启）", flagSwitch(self.gen, "tproxy_sniffing")),
        row("仅用于路由分流 (Route Only)", "开启后嗅探出的域名仅用于匹配分流规则，连接时仍使用已解析的 IP，避免二次 DNS 解析开销", flagSwitch(self.gen, "route_only")),
        row("BT 下载流量强制直连 (Bittorrent Direct)", "开启后识别到 BitTorrent 协议流量直接走本地宽带直连，防止触发机场审计封号", flagSwitch(self.gen, "direct_bittorrent")),
        row("路由域名解析策略 (Routing Domain Strategy)", "匹配路由规则时的 IP 解析策略", selectInput(self.gen, "routing_domain_strategy", [
          ["AsIs", "AsIs (仅按域名匹配，最快)"],
          ["IPIfNonMatch", "IPIfNonMatch (域名未命中时解析 IP 匹配)"],
          ["IPOnDemand", "IPOnDemand (遇到 IP 规则时按需解析)"]
        ])),

        h("div", { class: "xgl-section-title", style: { marginTop: "24px" } }, "局域网设备独立分流控制 (LAN Hosts Access Control)"),
        h("div", { class: "xgl-desc", style: { marginBottom: "10px" } }, "可针对家里特定设备（如智能电视、游戏机、NAS 或工作电脑）单独指定“完全直连不走代理 (bypass)”或“启用透明代理 (tproxy)”："),
        h("div", { style: { display: "flex", flexWrap: "wrap", gap: "8px", alignItems: "center", marginBottom: "12px" } }, [
          h("select", {
            class: "xgl-select",
            style: { width: "220px" },
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
            h("option", { domProps: { value: "" } }, "-- 从当前在线设备中选择 --")
          ].concat(self.lan_clients.map(function (c) {
            return h("option", { domProps: { value: c.mac } }, c.name + " (" + c.ip + " / " + c.mac + ")");
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
            h("option", { domProps: { value: "bypass" } }, "强制直连 (不走代理)"),
            h("option", { domProps: { value: "tproxy" } }, "启用透明代理")
          ]),
          h("button", { class: "xgl-btn sm primary", on: { click: self.addLanHostRule } }, "➕ 添加设备规则")
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
                h("button", { class: "xgl-btn sm danger", on: { click: function () { self.deleteSubItem(item[".name"]); } } }, "删除")
              ])
            ]);
          }))
        ]) : h("div", { class: "xgl-desc" }, "当前暂无单独指定的局域网设备规则（所有连接 br-lan 的设备默认共享全局透明代理设置）。"),

        h("div", { class: "xgl-section-title", style: { marginTop: "24px" } }, "额外 SOCKS5 / HTTP 入站端口 (Extra Inbounds)"),
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
            style: { width: "140px" },
            domProps: { value: self.newInbound.inbound_type },
            on: { change: function (e) { self.newInbound.inbound_type = e.target.value; } }
          }, [
            h("option", { domProps: { value: "socks5" } }, "SOCKS5 代理"),
            h("option", { domProps: { value: "http" } }, "HTTP 代理")
          ]),
          h("button", { class: "xgl-btn sm primary", on: { click: self.addExtraInbound } }, "➕ 添加入站端口")
        ]),
        extraInbounds.length > 0 ? h("table", { class: "xgl-table" }, [
          h("thead", [h("tr", [h("th", "监听地址:端口"), h("th", "协议类型"), h("th", "出站设置"), h("th", "操作")])]),
          h("tbody", extraInbounds.map(function (ib) {
            return h("tr", { key: ib[".name"] }, [
              h("td", (ib.inbound_addr || "0.0.0.0") + ":" + (ib.inbound_port || "")),
              h("td", (ib.inbound_type || "").toUpperCase()),
              h("td", ib.specify_outbound === "1" ? firstItem(ib.destination) : "跟随全局分流"),
              h("td", [
                h("button", { class: "xgl-btn sm danger", on: { click: function () { self.deleteSubItem(ib[".name"]); } } }, "删除")
              ])
            ]);
          }))
        ]) : null
      ]);

      // Tab 6: Extra Options & Firewall
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
        row("启用 Metrics 监控接口 (Metrics Server)", "开启本地 HTTP debug/vars 统计接口", flagSwitch(self.gen, "metrics_server_enable")),
        row("Metrics 监控监听端口", "默认 18888", textInput(self.gen, "metrics_server_port", "18888")),
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
        row("每连接内部缓存大小 (Buffer Size KB)", "默认 512", textInput(self.gen, "buffer_size", "512")),
        row("启用 IPv4 TCP 动态直连优化 (Dynamic Direct)", "大连接数下载场景可提升直连性能", flagSwitch(self.gen, "dynamic_direct_tcp4")),
        row("自定义 ucode 配置钩子 (Custom Configuration Hook)", "高级用户在生成 config.json 前动态修改配置对象的 ucode 函数", autoTextarea(self.gen, "custom_configuration_hook", "return function(config) { return config; };"))
      ]);

      // Tab 4: Config Preview & Logs
      var luciHref = "http://" + window.location.hostname + ":8080/cgi-bin/luci/admin/services/xray_core";
      var tabPreview = h("div", [
        h("div", { class: "xgl-section-title" }, [
          h("span", "Xray 实时系统日志 (logread -e xray)"),
          h("div", { class: "xgl-status-group" }, [
            h("button", { class: "xgl-btn sm", on: { click: self.loadPreviewData } }, self.loadingPreview ? "刷新中..." : "🔄 刷新配置与日志"),
            h("a", { class: "xgl-btn sm", attrs: { href: luciHref, target: "_blank" }, style: { textDecoration: "none" } }, "🔗 新窗口打开 8080 原版 LuCI")
          ])
        ]),
        h("pre", { class: "xgl-code", style: { height: "220px", marginBottom: "18px" } }, self.previewLogs || "点击右上方刷新按钮加载日志..."),
        h("div", { class: "xgl-section-title" }, "当前生效的 /var/etc/xray/config.json 全文预览"),
        h("pre", { class: "xgl-code" }, self.previewJson || "点击右上方刷新按钮加载 config.json...")
      ]);

      // Server Edit Modal
      var ed = self.editingServer;
      var editModal = ed ? h("div", { class: "xgl-modal-mask" }, [
        h("div", { class: "xgl-modal" }, [
          h("div", { class: "xgl-modal-header" }, [
            h("span", ed.id ? "编辑节点 (" + ed.id + ")" : "新增 Xray 节点"),
            h("button", { class: "xgl-btn sm", on: { click: function () { self.editingServer = null; } } }, "✕")
          ]),
          h("div", { class: "xgl-modal-body" }, [
            row("节点别名 (Alias)", "显示在下拉框与列表中的中文名称", textInput(ed, "alias", "例如：日本Z03 | IEPL")),
            row("服务器地址 (Server Hostname / IP)", "填写域名或 IP 地址", textInput(ed, "server", "example.com")),
            row("服务器端口 (Port)", "填写数字端口号", textInput(ed, "port", "443")),
            row("代理协议 (Protocol)", "支持 Xray 全部主流出站协议", selectInput(ed, "protocol", [
              ["shadowsocks", "Shadowsocks (SS / SS-2022)"],
              ["vmess", "VMess"],
              ["vless", "VLESS (含 XTLS / Reality)"],
              ["trojan", "Trojan"],
              ["hysteria", "Hysteria2"],
              ["socks", "SOCKS5"],
              ["http", "HTTP"]
            ])),
            row("密码 / UUID (Password / UserId)", "VMess/VLESS 填 UUID；SS/Trojan 填密码", textInput(ed, "password", "UUID 或密码")),

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
              ["hysteria", "Hysteria"]
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

            row("传输层加密 (Stream Security)", "VLESS 支持 REALITY 与 TLS；专线节点一般为 none", selectInput(ed, "tls_mode", [
              ["none", "none (不启用 TLS)"],
              ["tls", "tls (标准 TLS)"],
              ["reality", "reality (VLESS REALITY)"]
            ])),

            (ed.protocol === "vless" && (ed.tls_mode === "tls" || ed.tls_mode === "reality")) ? row("VLESS XTLS 流控 (Flow)", "REALITY / TLS 直连推荐 xtls-rprx-vision", selectInput(ed, "flow_mode", [
              ["none", "none"],
              ["xtls-rprx-vision", "xtls-rprx-vision"],
              ["xtls-rprx-vision-udp443", "xtls-rprx-vision-udp443"]
            ])) : null,

            ed.tls_mode === "tls" ? row("TLS SNI 域名与 uTLS 指纹", "Server Name 与浏览器握手特征模拟", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
              textInput(ed, "tls_host", "SNI 域名"),
              selectInput(ed, "tls_fingerprint", [["chrome", "chrome"], ["firefox", "firefox"], ["safari", "safari"], ["ios", "ios"], ["random", "random"]])
            ])) : null,

            ed.tls_mode === "reality" ? h("div", [
              row("REALITY 目标偷取域名 (Server Name)", "如 www.microsoft.com 或 apple.com", textInput(ed, "reality_server_name", "www.microsoft.com")),
              row("REALITY 公钥 (Public Key / pbk)", "服务端生成的公钥", textInput(ed, "reality_public_key", "Public Key")),
              row("REALITY Short ID 与 Fingerprint", "ShortId 与浏览器指纹", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
                textInput(ed, "reality_short_id", "ShortId"),
                selectInput(ed, "reality_fingerprint", [["chrome", "chrome"], ["firefox", "firefox"], ["safari", "safari"], ["ios", "ios"]])
              ]))
            ]) : null,

            row("服务器域名解析策略与前置代理", "默认 UseIP；前置代理默认 disabled", h("div", { style: { display: "flex", gap: "8px", width: "100%" } }, [
              selectInput(ed, "domain_strategy", [["UseIP", "UseIP"], ["UseIPv4", "UseIPv4"], ["UseIPv6", "UseIPv6"]]),
              textInput(ed, "dialer_proxy", "disabled")
            ]))
          ]),
          h("div", { class: "xgl-modal-footer" }, [
            h("button", { class: "xgl-btn", on: { click: function () { self.editingServer = null; } } }, "取消"),
            h("button", { class: "xgl-btn primary", on: { click: self.saveEditingServer } }, "保存节点")
          ])
        ])
      ]) : null;

      var activeView = tabStatus;
      if (self.activeTab === "dns") activeView = tabDns;
      else if (self.activeTab === "advanced") activeView = tabAdvanced;
      else if (self.activeTab === "preview") activeView = tabPreview;

      return h("div", { class: "xgl-wrap" }, [
        h("gl-title", { props: { title: "Xray 透明代理控制台" } }),
        h("gl-card", [
          topBar,
          tabBar,
          activeView,
          self.activeTab !== "preview" ? h("div", { class: "xgl-btn-bar" }, [
            h("button", { class: "xgl-btn", on: { click: self.loadAll } }, "重新加载配置"),
            h("button", {
              class: "xgl-btn primary",
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
