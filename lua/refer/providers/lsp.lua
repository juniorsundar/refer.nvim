---@class LSPProvider
local M = {}

local refer = require "refer"
local util = require "refer.util"

---Find references to symbol under cursor using LSP
---Shows filename, line, column, and content for each reference
function M.references()
    local clients = vim.lsp.get_clients { bufnr = 0 }
    local client = clients[1]

    if not client then
        print "No LSP client attached"
        return
    end

    ---@class lsp.TextDocumentPositionParams
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    params.context = { includeDeclaration = true }

    vim.lsp.buf_request(0, "textDocument/references", params, function(err, result, _, _)
        if err then
            print("LSP Error: " .. tostring(err))
            return
        end
        if not result or vim.tbl_isempty(result) then
            print "No references found"
            return
        end

        local items = {}

        for _, loc in ipairs(result) do
            local filename = vim.uri_to_fname(loc.uri)
            local lnum = loc.range.start.line + 1
            local col = loc.range.start.character + 1

            local relative_path = util.get_relative_path(filename)
            local line_content = util.get_line_content(filename, lnum)

            local entry = string.format("%s:%d:%d:%s", relative_path, lnum, col, line_content)
            table.insert(items, entry)
        end

        refer.pick(items, util.jump_to_location, {
            prompt = "LSP References > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
            },
            parser = util.parsers.lsp,
        })
    end)
end

---Find definitions of symbol under cursor using LSP
---Shows filename, line, column, and content for each definition
function M.definitions()
    local clients = vim.lsp.get_clients { bufnr = 0 }
    local client = clients[1]

    if not client then
        print "No LSP client attached"
        return
    end

    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

    vim.lsp.buf_request(0, "textDocument/definition", params, function(err, result, _, _)
        if err then
            print("LSP Error: " .. tostring(err))
            return
        end
        if not result or vim.tbl_isempty(result) then
            print "No definitions found"
            return
        end

        if not vim.islist(result) then
            result = { result }
        end

        local items = {}

        for _, loc in ipairs(result) do
            local uri = loc.uri or loc.targetUri
            local range = loc.range or loc.targetSelectionRange or loc.targetRange

            if uri and range then
                local filename = vim.uri_to_fname(uri)
                local lnum = range.start.line + 1
                local col = range.start.character + 1

                local relative_path = util.get_relative_path(filename)
                local line_content = util.get_line_content(filename, lnum)

                local entry = string.format("%s:%d:%d:%s", relative_path, lnum, col, line_content)
                table.insert(items, entry)
            end
        end

        refer.pick(items, util.jump_to_location, {
            prompt = "LSP Definitions > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
            },
            parser = util.parsers.lsp,
        })
    end)
end

return M
