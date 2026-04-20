---@class LSPProvider
local M = {}

local refer = require "refer"
local util = require "refer.util"

---Generic handler for LSP location requests
---@param method string LSP method name (e.g. "textDocument/definition")
---@param label string Label for messages (e.g. "definitions")
---@param title string Picker title (e.g. "LSP Definitions")
---@param opts table User options
---@param param_modifier fun(params: table)|nil Optional function to modify request params
local function lsp_request(method, label, title, opts, param_modifier)
    local clients = vim.lsp.get_clients { bufnr = 0 }
    local client = nil
    for _, c in ipairs(clients) do
        if c:supports_method(method) then
            client = c
            break
        end
    end

    if not client then
        vim.notify("Refer: No LSP client attached", vim.log.levels.WARN)
        return
    end

    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    if param_modifier then
        param_modifier(params)
    end

    vim.lsp.buf_request(0, method, params, function(err, result, _, _)
        if err then
            vim.notify("LSP Error: " .. tostring(err), vim.log.levels.ERROR)
            return
        end
        if not result or vim.tbl_isempty(result) then
            vim.notify("Refer: No " .. label .. " found", vim.log.levels.INFO)
            return
        end

        if not vim.islist(result) then
            result = { result }
        end

        local items = {}
        local seen = {}

        for _, loc in ipairs(result) do
            local uri = loc.uri or loc.targetUri
            local range = loc.range or loc.targetSelectionRange or loc.targetRange

            if uri and range then
                local filename = vim.uri_to_fname(uri)
                filename = vim.uv.fs_realpath(filename) or filename
                local lnum = range.start.line + 1
                local col = range.start.character + 1

                local relative_path = util.get_relative_path(filename)
                local line_content = util.get_line_content(filename, lnum)

                local entry = string.format("%s:%d:%d:%s", relative_path, lnum, col, line_content)
                if not seen[entry] then
                    table.insert(items, entry)
                    seen[entry] = true
                end
            end
        end

        if #items == 0 then
            vim.notify("Refer: No " .. label .. " found (after filtering)", vim.log.levels.INFO)
            return
        end

        if #items == 1 then
            util.jump_to_location(items[1], "lsp")
            return
        end

        refer.pick(
            items,
            util.jump_to_location,
            vim.tbl_deep_extend("force", {
                prompt = title .. " > ",
                keymaps = {
                    ["<Tab>"] = "toggle_mark",
                    ["<CR>"] = "open_marked",
                },
                parser = util.parsers.lsp,
            }, opts or {})
        )
    end)
end

---Find references to symbol under cursor using LSP
---Shows filename, line, column, and content for each reference
function M.references(opts)
    lsp_request("textDocument/references", "references", "LSP References", opts, function(params)
        params.context = { includeDeclaration = true }
    end)
end

---Find definitions of symbol under cursor using LSP
---Shows filename, line, column, and content for each definition
function M.definitions(opts)
    lsp_request("textDocument/definition", "definitions", "LSP Definitions", opts)
end

---Find implementations of symbol under cursor using LSP
---Shows filename, line, column, and content for each implementation
function M.implementations(opts)
    lsp_request("textDocument/implementation", "implementations", "LSP Implementations", opts)
end

---Find declarations of symbol under cursor using LSP
---Shows filename, line, column, and content for each declaration
function M.declarations(opts)
    lsp_request("textDocument/declaration", "declarations", "LSP Declarations", opts)
end

---Document symbol kind to icon/highlight mapping
---@type table<number, {icon: string, hl: string}>
local kind_icons = {
    [1] = { icon = "󰈙", hl = "File" }, -- File
    [2] = { icon = "󰠱", hl = "Module" }, -- Module
    [3] = { icon = "", hl = "Structure" }, -- Namespace
    [4] = { icon = "", hl = "Normal" }, -- Package
    [5] = { icon = "", hl = "Class" }, -- Class
    [6] = { icon = "󰆧", hl = "Method" }, -- Method
    [7] = { icon = "", hl = "Property" }, -- Property
    [8] = { icon = "", hl = "Field" }, -- Field
    [9] = { icon = "", hl = "Function" }, -- Constructor
    [10] = { icon = "", hl = "Enum" }, -- Enum
    [11] = { icon = "", hl = "Type" }, -- Interface
    [12] = { icon = "󰊕", hl = "Function" }, -- Function
    [13] = { icon = "󰂡", hl = "Normal" }, -- Variable
    [14] = { icon = "󰏿", hl = "Constant" }, -- Constant
    [15] = { icon = "", hl = "String" }, -- String
    [16] = { icon = "", hl = "Number" }, -- Number
    [17] = { icon = "", hl = "Boolean" }, -- Boolean
    [18] = { icon = "", hl = "Array" }, -- Array
    [19] = { icon = "󰌋", hl = "Keyword" }, -- Key
    [20] = { icon = "", hl = "Class" }, -- Object
    [21] = { icon = "󰟢", hl = "Normal" }, -- Null
    [22] = { icon = "", hl = "Enum" }, -- EnumMember
    [23] = { icon = "", hl = "Struct" }, -- Struct
    [24] = { icon = "", hl = "Normal" }, -- Event
    [25] = { icon = "", hl = "Operator" }, -- Operator
    [26] = { icon = "󰅲", hl = "Type" }, -- TypeParameter
}

---Show document symbols for the current buffer using LSP
---Displays a hierarchical list of symbols with icons and navigates to selection
function M.document_symbols(opts)
    local clients = vim.lsp.get_clients { bufnr = 0 }
    local client = nil
    for _, c in ipairs(clients) do
        if c:supports_method "textDocument/documentSymbol" then
            client = c
            break
        end
    end

    if not client then
        vim.notify("Refer: No LSP client attached", vim.log.levels.WARN)
        return
    end

    local supports_symbol = vim.fn.has "nvim-0.12" == 1 and client:supports_method "textDocument/documentSymbol"
        or client.supports_method "textDocument/documentSymbol"

    if not supports_symbol then
        vim.notify("Refer: LSP client does not support textDocument/documentSymbol", vim.log.levels.WARN)
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local uri = vim.lsp.util.make_text_document_params(bufnr)["uri"]
    if not uri then
        vim.notify("Refer: Could not get URI for buffer", vim.log.levels.ERROR)
        return
    end

    local params = { textDocument = { uri = uri } }

    vim.lsp.buf_request(0, "textDocument/documentSymbol", params, function(err, result, _, _)
        if err then
            vim.notify("LSP Error: " .. tostring(err), vim.log.levels.ERROR)
            return
        end
        if not result or vim.tbl_isempty(result) then
            vim.notify("Refer: No document symbols found", vim.log.levels.INFO)
            return
        end

        local filename = vim.api.nvim_buf_get_name(bufnr)
        filename = vim.uv.fs_realpath(filename) or filename
        local relative_path = util.get_relative_path(filename)

        local items = {}
        local item_hls = {}

        ---Recursively traverse the symbol tree
        ---@param symbols table List of DocumentSymbol items
        ---@param depth number Current depth (0-indexed)
        local function traverse(symbols, depth)
            for _, symbol in ipairs(symbols) do
                local kind_info = kind_icons[symbol.kind] or { icon = "", hl = "Normal" }
                local indent = string.rep("  ", depth)
                local sel_range = symbol.selectionRange or symbol.range
                local lnum = sel_range.start.line + 1
                local col = sel_range.start.character + 1
                local entry =
                    string.format("%s:%d:%d:%s[ %s ] %s", relative_path, lnum, col, indent, kind_info.icon, symbol.name)
                table.insert(items, entry)
                item_hls[entry] = { hl = kind_info.hl, depth = depth }

                if symbol.children and #symbol.children > 0 then
                    traverse(symbol.children, depth + 1)
                end
            end
        end

        traverse(result, 0)

        if #items == 0 then
            vim.notify("Refer: No document symbols found", vim.log.levels.INFO)
            return
        end

        ---Custom highlight function for symbol icons
        ---@param buf number Buffer handle
        ---@param ns number Namespace ID
        ---@param line_idx number Line index (0-indexed)
        ---@param line string Line content
        local function custom_highlight(buf, ns, line_idx, line)
            local hl_info = item_hls[line]
            if not hl_info then
                return
            end

            local prefix_end = line:find "^.-:%d+:%d+:"
            if not prefix_end then
                return
            end

            local icon_bracket_start = line:find("%[", prefix_end)
            if not icon_bracket_start then
                return
            end

            local icon_col = icon_bracket_start
            local icon_start_0 = icon_col
            local icon_bracket_end = line:find("%]", icon_bracket_start)
            if not icon_bracket_end then
                return
            end

            pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_idx, icon_start_0 - 1, {
                end_col = icon_bracket_end,
                hl_group = hl_info.hl,
                priority = 120,
            })

            -- Add Treesitter Highlighting for the symbol name
            local content_start = icon_bracket_end + 2
            if content_start <= #line then
                local content = line:sub(content_start)
                local filename_end = line:find ":"
                if filename_end then
                    local filename_token = line:sub(1, filename_end - 1)
                    require("refer.highlight").highlight_code(
                        buf,
                        ns,
                        line_idx,
                        content_start - 1,
                        content,
                        filename_token
                    )
                end
            end
        end

        refer.pick(
            items,
            util.jump_to_location,
            vim.tbl_deep_extend("force", {
                prompt = "LSP Document Symbols > ",
                keymaps = {
                    ["<Tab>"] = "toggle_mark",
                    ["<CR>"] = "open_marked",
                },
                parser = util.parsers.lsp,
                highlight_code = false,
                highlight_fn = custom_highlight,
            }, opts or {})
        )
    end)
end

---@class LspServerItem
---@field name string
---@field file string|nil
---@field active boolean
---@field config table|nil
---@field registered_config table|nil

---Get all LSP server configurations from active clients, registry, and runtime files
---@return LspServerItem[]
local function get_lsp_configs()
    local config_map = {}

    for _, client in ipairs(vim.lsp.get_clients()) do
        config_map[client.name] = {
            name = client.name,
            active = true,
            config = client.config,
        }
    end

    if vim.lsp.config and vim.lsp._enabled_configs then
        for name, config in pairs(vim.lsp._enabled_configs) do
            if not config_map[name] and name ~= "*" then
                config_map[name] = {
                    name = name,
                    active = false,
                    config = config,
                }
            else
                config_map[name].registered_config = config
            end
        end
    end

    local files = vim.api.nvim_get_runtime_file("after/lsp/*.lua", true)
    vim.list_extend(files, vim.api.nvim_get_runtime_file("lsp/*.lua", true))

    for _, file in ipairs(files) do
        local name = vim.fn.fnamemodify(file, ":t:r")
        if not config_map[name] then
            config_map[name] = {
                name = name,
                active = false,
                file = file,
            }
        else
            config_map[name].file = file
        end
    end

    local configs = {}
    for _, conf in pairs(config_map) do
        table.insert(configs, conf)
    end
    table.sort(configs, function(a, b)
        return a.name < b.name
    end)

    return configs
end

---Show picker for LSP servers with ability to start/stop
---Lists all configured LSP servers and shows which are active
function M.lsp_servers(opts)
    local configs = get_lsp_configs()
    local items = {}
    local lookup = {}

    for _, config in ipairs(configs) do
        local is_active = config.active

        local display_text = (is_active and "● " or "○ ") .. config.name
        table.insert(items, display_text)
        lookup[display_text] = config
    end

    if #items == 0 then
        vim.notify("Refer: No LSP configurations found", vim.log.levels.WARN)
        return
    end

    refer.pick(
        items,
        function(selection, _)
            local item = lookup[selection]
            if not item then
                return
            end

            if item.active then
                local clients = vim.lsp.get_clients { name = item.name }
                for _, client in ipairs(clients) do
                    vim.lsp.stop_client(client.id)
                end
                vim.notify("Stopped LSP: " .. item.name, vim.log.levels.INFO)
            else
                local config = {}

                if item.file then
                    local ok, loaded_config = pcall(dofile, item.file)
                    if ok and type(loaded_config) == "table" then
                        config = loaded_config
                    end
                elseif item.registered_config then
                    config = item.registered_config
                elseif item.config then
                    config = item.config
                end

                config.name = config.name or item.name

                if not config.root_dir then
                    if config.root_markers then
                        config.root_dir = vim.fs.root(0, config.root_markers)
                    end
                    if not config.root_dir then
                        config.root_dir = vim.fn.getcwd()
                    end
                end

                local client_id = vim.lsp.start(config)
                if client_id then
                    vim.notify("Started LSP: " .. item.name, vim.log.levels.INFO)
                else
                    vim.notify("Failed to start LSP: " .. item.name, vim.log.levels.ERROR)
                end
            end
        end,
        vim.tbl_deep_extend("force", {
            prompt = "LSP Servers > ",
            keymaps = {
                ["<S-Tab>"] = "prev_item",
                ["<Tab>"] = "next_item",
                ["<CR>"] = "select_entry",
            },
        }, opts or {})
    )
end

return M
