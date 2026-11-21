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
    local running, proc_alive, tproxy_active = get_xray_status(gen)
    local metrics = proc_alive and fetch_metrics_summary(gen.metrics_server_port) or nil

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
    return {
        code = 0,
        data = {
            running = running,
            proc_running = proc_alive,
            tproxy_enabled = tproxy_active,
            metrics = proc_alive and fetch_metrics_summary(gen and gen.metrics_server_port) or nil
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
        service_exec("restart")
    end
    return { code = 0, data = { ok = true } }
end

local BLACKLIST_HOOK = [[// __GL_XRAY_PRESET_BLACKLIST__
return function(config) {
    let new_rules = [];
    let fallback_rules = [];

    // 1. Block UDP 443 (QUIC) matching v2rayN Blacklist preset
    push(new_rules, {
        type: "field",
        port: "443",
        network: "udp",
        outboundTag: "blackhole_outbound"
    });

    // 2. Rewrite unconditional catch-all proxy rules to direct
    for (let r in config.routing.rules) {
        if (r.domain == null && r.ip == null && (
            r.balancerTag == "tcp_outbound_v4" ||
            r.balancerTag == "udp_outbound_v4" ||
            r.balancerTag == "tcp_outbound_v6" ||
            r.balancerTag == "udp_outbound_v6"
        )) {
            if (r.balancerTag == "tcp_outbound_v4" || r.balancerTag == "udp_outbound_v4") {
                push(new_rules, {
                    type: "field",
                    inboundTag: r.inboundTag,
                    ip: [
                        "geoip:facebook", "geoip:fastly", "geoip:google",
                        "geoip:netflix", "geoip:telegram", "geoip:twitter",
                        "1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3",
                        "8.8.8.8", "8.8.4.4", "94.140.14.14", "94.140.15.15",
                        "208.67.222.222", "208.67.220.220", "9.9.9.9", "149.112.112.112",
                        "77.88.8.8", "77.88.8.1"
                    ],
                    balancerTag: r.balancerTag
                });
            }
            push(fallback_rules, {
                type: "field",
                inboundTag: r.inboundTag,
                outboundTag: "direct"
            });
        } else {
            push(new_rules, r);
        }
    }

    for (let fb in fallback_rules) {
        push(new_rules, fb);
    }
    config.routing.rules = new_rules;
    return config;
};]]

local function filter_valid_servers(c, list)
    local out = {}
    if type(list) == "string" then list = { list } end
    if type(list) ~= "table" then return out end
    for _, id in ipairs(list) do
        if type(id) == "string" and id ~= "" and c:get("xray_core", id) == "servers" then
            out[#out + 1] = id
        end
    end
    return out
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
    local tcp_list = filter_valid_servers(c, args.tcp_nodes or args.tcp_node)
    if (args.tcp_nodes or args.tcp_node) and #tcp_list == 0 then
        return { code = -1, error = "指定的 TCP 节点不存在" }
    elseif #tcp_list > 0 then
        c:set("xray_core", gen_id, "tcp_balancer_v4", tcp_list)
    end

    local udp_list = filter_valid_servers(c, args.udp_nodes or args.udp_node)
    if (args.udp_nodes or args.udp_node) and #udp_list == 0 then
        return { code = -1, error = "指定的 UDP 节点不存在" }
    elseif #udp_list > 0 then
        c:set("xray_core", gen_id, "udp_balancer_v4", udp_list)
    end

    local cur_hook = type(gen.custom_configuration_hook) == "string" and gen.custom_configuration_hook or ""
    if args.preset == "bypass_cn" then
        local bp = type(gen.bypassed_domain_rules) == "table" and gen.bypassed_domain_rules or {}
        local found = false
        for _, v in ipairs(bp) do if v == "geosite:cn" then found = true end end
        if not found then bp[#bp + 1] = "geosite:cn" end
        c:set("xray_core", gen_id, "bypassed_domain_rules", bp)
        c:set("xray_core", gen_id, "geoip_direct_code_list", { "cn" })
        c:set("xray_core", gen_id, "geoip_direct_code_list_v6", { "cn" })
        c:set("xray_core", gen_id, "default_dns", "1.1.1.1:53")
        if cur_hook:find("__GL_XRAY_PRESET_BLACKLIST__", 1, true) then
            c:delete("xray_core", gen_id, "custom_configuration_hook")
        end
    elseif args.preset == "blacklist" then
        c:set("xray_core", gen_id, "bypassed_domain_rules", { "geosite:private", "geosite:cn" })
        c:set("xray_core", gen_id, "forwarded_domain_rules", {
            "geosite:gfw", "geosite:greatfire", "geosite:google", "domain:api.ip.sb",
            "domain:cloudflare-dns.com", "domain:one.one.one.one", "domain:dns.google",
            "domain:adguard-dns.com", "domain:opendns.com", "domain:umbrella.com",
            "domain:quad9.net", "domain:yandex.net"
        })
        c:delete("xray_core", gen_id, "geoip_direct_code_list")
        c:delete("xray_core", gen_id, "geoip_direct_code_list_v6")
        c:set("xray_core", gen_id, "fast_dns", "223.5.5.5:53")
        c:set("xray_core", gen_id, "secure_dns", "1.1.1.1:53")
        c:set("xray_core", gen_id, "default_dns", "223.5.5.5:53")
        c:set("xray_core", gen_id, "tproxy_sniffing", "1")
        c:set("xray_core", gen_id, "route_only", "1")
        c:set("xray_core", gen_id, "direct_bittorrent", "1")
        c:set("xray_core", gen_id, "custom_configuration_hook", BLACKLIST_HOOK)
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
        c:set("xray_core", gen_id, "default_dns", "1.1.1.1:53")
        if cur_hook:find("__GL_XRAY_PRESET_BLACKLIST__", 1, true) then
            c:delete("xray_core", gen_id, "custom_configuration_hook")
        end
    end

    c:commit("xray_core")
    service_exec("restart")
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
                vmess_alter_id = j_aid,
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

function M.import_links(args)
    if type(args) ~= "table" or type(args.text) ~= "string" then
        return { code = -1, error = "请输入订阅链接或节点分享链接" }
    end
    local input = trim(args.text)
    if input == "" then
        return { code = -1, error = "内容不能为空" }
    end

    -- If input is a single HTTP/HTTPS subscription URL, fetch it non-blockingly via ngx.pipe.spawn
    if input:match("^https?://[^%s]+$") then
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
    local deleted_map = {}
    if args.replace_all then
        local to_del = {}
        c:foreach("xray_core", "servers", function(s)
            local sid = s[".name"]
            to_del[#to_del + 1] = sid
            deleted_map[sid] = true
        end)
        for _, id in ipairs(to_del) do c:delete("xray_core", id) end
    end

    local first_new_id = nil
    for _, srv in ipairs(parsed_list) do
        local sec = next_server_id(c)
        if not first_new_id then first_new_id = sec end
        c:set("xray_core", sec, "servers")
        apply_uci_fields(c, "xray_core", sec, srv)
    end

    if args.replace_all and first_new_id then
        cleanup_deleted_server_refs(c, deleted_map)
        local gen_id, gen = get_general_section(c)
        if not gen.tcp_balancer_v4 or #gen.tcp_balancer_v4 == 0 then
            c:set("xray_core", gen_id, "tcp_balancer_v4", { first_new_id })
        end
        if not gen.udp_balancer_v4 or #gen.udp_balancer_v4 == 0 then
            c:set("xray_core", gen_id, "udp_balancer_v4", { first_new_id })
        end
    end

    c:commit("xray_core")
    if args.replace_all then
        local _, gen = get_general_section(c)
        local _, proc_alive = get_xray_status(gen)
        if proc_alive then
            service_exec("restart")
        end
    end
    return { code = 0, data = { added = #parsed_list } }
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
    /etc/init.d/xray_core restart
else
    rm -f /tmp/geoip.dat.new /tmp/geosite.dat.new
fi
]]
    spawn_read({ "/bin/sh", "-c", "(" .. script .. ") >/tmp/xray_geo_update.log 2>&1 &" }, 2000)
    return { code = 0, data = { started = true } }
end

return M
