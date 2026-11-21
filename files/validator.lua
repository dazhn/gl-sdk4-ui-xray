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
