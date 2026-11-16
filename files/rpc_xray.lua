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

local function fetch_metrics_summary(port)
    port = tonumber(port) or 18888
    local f = io.popen(string.format("curl -s --connect-timeout 1 -m 2 http://127.0.0.1:%d/debug/vars 2>/dev/null", port))
    local raw = f and f:read("*a") or ""
    if f then f:close() end
    if raw == "" then return nil end

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
                    local srv_id = tag:match(":(srv_%d+)$")
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
                    local srv_id = tag:match(":(srv_%d+)$")
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
    local running = is_xray_running()
    local metrics = running and fetch_metrics_summary(gen.metrics_server_port) or nil

    return {
        code = 0,
        data = {
            running = running,
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
    local running = is_xray_running()
    return {
        code = 0,
        data = {
            running = running,
            metrics = running and fetch_metrics_summary(gen and gen.metrics_server_port) or nil
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

-- 5. Delete a server node (and clean up any dangling reference in balancer pools)
function M.delete_server(args)
    if type(args) ~= "table" or type(args.id) ~= "string" then
        return { code = -1, error = "未指定节点 ID" }
    end
    local c = uci.cursor()
    c:delete("xray_core", args.id)

    local gen_id, gen = get_general_section(c)
    if gen_id and gen then
        for _, pool_key in ipairs({ "tcp_balancer_v4", "udp_balancer_v4", "tcp_balancer_v6", "udp_balancer_v6" }) do
            local pool = gen[pool_key]
            if type(pool) == "table" then
                local filtered = {}
                for _, item in ipairs(pool) do
                    if item ~= args.id then filtered[#filtered + 1] = item end
                end
                if #filtered > 0 then
                    c:set("xray_core", gen_id, pool_key, filtered)
                else
                    c:delete("xray_core", gen_id, pool_key)
                end
            end
        end
    end

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

    local parsed_list = {}
    for line in input:gmatch("[^\r\n]+") do
        local srv = parse_single_uri(line)
        if srv then
            parsed_list[#parsed_list + 1] = srv
        end
    end

    if #parsed_list == 0 then
        return { code = -1, error = "未解析到有效节点（支持 ss://、vmess://、vless://、trojan:// 及 Base64 订阅内容）" }
    end

    local c = uci.cursor()
    if args.replace_all then
        local to_del = {}
        c:foreach("xray_core", "servers", function(s) to_del[#to_del + 1] = s[".name"] end)
        for _, id in ipairs(to_del) do c:delete("xray_core", id) end
    end

    local first_new_id = nil
    for _, srv in ipairs(parsed_list) do
        local sec = next_server_id(c)
        if not first_new_id then first_new_id = sec end
        c:set("xray_core", sec, "servers")
        apply_uci_fields(c, "xray_core", sec, srv)
    end

    -- Ensure general balancer pools do not point to deleted server IDs after replace_all
    if args.replace_all and first_new_id then
        local gen_id, gen = get_general_section(c)
        local valid_ids = {}
        c:foreach("xray_core", "servers", function(s) valid_ids[s[".name"]] = true end)
        local keep_v4 = {}
        if type(gen.tcp_balancer_v4) == "table" then
            for _, id in ipairs(gen.tcp_balancer_v4) do
                if valid_ids[id] then keep_v4[#keep_v4 + 1] = id end
            end
        end
        if #keep_v4 == 0 then keep_v4 = { first_new_id } end
        c:set("xray_core", gen_id, "tcp_balancer_v4", keep_v4)
        c:set("xray_core", gen_id, "udp_balancer_v4", keep_v4)
    end

    c:commit("xray_core")
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
    os.execute("(" .. script .. ") >/tmp/xray_geo_update.log 2>&1 &")
    return { code = 0, data = { started = true } }
end

return M
