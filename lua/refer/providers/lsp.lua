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
    local client = clients[1]

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

        refer.pick(items, util.jump_to_location, vim.tbl_deep_extend("force", {
            prompt = title .. " > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
            },
            parser = util.parsers.lsp,
        }, opts or {}))
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

return M
