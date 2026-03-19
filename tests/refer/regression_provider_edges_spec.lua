local files = require "refer.providers.files"
local lsp = require "refer.providers.lsp"
local util = require "refer.util"
local stub = require "luassert.stub"

describe("refer regression provider edges", function()
    local notify_stub

    local function close_active_picker()
        local refer = require "refer"
        local active = refer._active_picker
        if active then
            active:close()
        end
    end

    before_each(function()
        notify_stub = stub(vim, "notify")
    end)

    after_each(function()
        close_active_picker()
        if notify_stub then
            notify_stub:revert()
        end
    end)

    describe("tool-backed file providers", function()
        local pick_async_stub
        local pick_stub
        local system_stub
        local executable_stub

        after_each(function()
            if pick_async_stub then
                pick_async_stub:revert()
            end
            if pick_stub then
                pick_stub:revert()
            end
            if system_stub then
                system_stub:revert()
            end
            if executable_stub then
                executable_stub:revert()
            end
        end)

        it("keeps Files async command generation and prompt contract", function()
            local captured = {}
            pick_async_stub = stub(require("refer"), "pick_async", function(generator, on_select, opts)
                captured.generator = generator
                captured.on_select = on_select
                captured.opts = opts
                return { kind = "files-picker" }
            end)

            local picker = files.files()

            assert.are.same("files-picker", picker.kind)
            assert.are.same("Files > ", captured.opts.prompt)
            assert.are.same("select_entry", captured.opts.keymaps["<CR>"])

            local plain = captured.generator "alpha"
            assert.are.same({ "fd", "-H", "--type", "f", "--color", "never", "--exclude", ".git", "--exclude", ".jj", "--exclude", "node_modules", "--exclude", ".cache", "--", "al" }, plain)

            local path_query = captured.generator "lua/ref"
            assert.are.same("--full-path", path_query[#path_query - 2])
            assert.are.same("--", path_query[#path_query - 1])
            assert.are.same("lua[^/]*/.*ref", path_query[#path_query])
            assert.is_true(captured.opts.on_select ~= nil)
        end)

        it("keeps Grep async prompt and command contract", function()
            local captured = {}
            pick_async_stub = stub(require("refer"), "pick_async", function(generator, on_select, opts)
                captured.generator = generator
                captured.on_select = on_select
                captured.opts = opts
                return { kind = "grep-picker" }
            end)

            local picker = files.live_grep()

            assert.are.same("grep-picker", picker.kind)
            assert.are.same("Grep > ", captured.opts.prompt)
            assert.are.same(util.jump_to_location, captured.on_select)
            assert.are.same({ "rg", "--vimgrep", "--smart-case", "--", "needle" }, captured.generator "needle")
        end)

        it("keeps Selection happy-path behavior with rg and loading placeholder", function()
            executable_stub = stub(vim.fn, "executable", function(cmd)
                return cmd == "rg" and 1 or 0
            end)

            stub(vim.fn, "mode", function()
                return "n"
            end)
            stub(vim.fn, "expand", function(expr)
                if expr == "<cword>" then
                    return "needle"
                end
            end)

            local captured = {}
            pick_stub = stub(require("refer"), "pick", function(items, on_select, opts)
                captured.items = items
                captured.on_select = on_select
                captured.opts = opts
                return {
                    set_items = function(_, items)
                        captured.updated_items = items
                    end,
                }
            end)

            system_stub = stub(vim, "system", function(cmd, opts, callback)
                captured.cmd = cmd
                callback({ code = 0, stdout = "a.lua:1:1:alpha\nb.lua:2:3:beta\n" })
            end)

            files.grep_word()

            vim.wait(1000, function()
                return captured.updated_items ~= nil
            end)

            assert.are.same({ "Searching..." }, captured.items)
            assert.are.same("Grep (needle) > ", captured.opts.prompt)
            assert.are.same({ "rg", "--vimgrep", "--smart-case", "--fixed-strings", "--", "needle" }, captured.cmd)
            assert.are.same({ "a.lua:1:1:alpha", "b.lua:2:3:beta" }, captured.updated_items)

            vim.fn.mode:revert()
            vim.fn.expand:revert()
        end)

        it("keeps Selection no-results and grep fallback behavior", function()
            executable_stub = stub(vim.fn, "executable", function(cmd)
                return cmd == "rg" and 0 or 1
            end)

            stub(vim.fn, "mode", function()
                return "n"
            end)
            stub(vim.fn, "expand", function(expr)
                if expr == "<cword>" then
                    return "fallback-query"
                end
            end)

            local captured = {}
            pick_stub = stub(require("refer"), "pick", function(items, on_select, opts)
                captured.items = items
                captured.opts = opts
                return {
                    set_items = function(_, items)
                        captured.updated_items = items
                    end,
                }
            end)

            system_stub = stub(vim, "system", function(cmd, opts, callback)
                captured.cmd = cmd
                callback({ code = 1, stdout = "", stderr = "" })
            end)

            files.grep_word()

            vim.wait(1000, function()
                return captured.updated_items ~= nil
            end)

            assert.are.same({ "grep", "-rnH", "-F", "--", "fallback-query", "." }, captured.cmd)
            assert.are.same({ "No matches found for: fallback-query" }, captured.updated_items)

            vim.fn.mode:revert()
            vim.fn.expand:revert()
        end)

        it("warns when Selection has no text to search", function()
            stub(vim.fn, "mode", function()
                return "n"
            end)
            stub(vim.fn, "expand", function()
                return ""
            end)

            local picker = files.grep_word()

            assert.is_nil(picker)
            assert.stub(vim.notify).was_called_with("Refer: No text to search", vim.log.levels.WARN)

            vim.fn.mode:revert()
            vim.fn.expand:revert()
        end)

        it("surfaces Selection backend errors as error items", function()
            executable_stub = stub(vim.fn, "executable", function()
                return 1
            end)

            stub(vim.fn, "mode", function()
                return "n"
            end)
            stub(vim.fn, "expand", function()
                return "boom"
            end)

            local captured = {}
            pick_stub = stub(require("refer"), "pick", function(items, on_select, opts)
                captured.items = items
                captured.opts = opts
                return {
                    set_items = function(_, items)
                        captured.updated_items = items
                    end,
                }
            end)

            system_stub = stub(vim, "system", function(cmd, opts, callback)
                callback({ code = 2, stdout = "", stderr = "permission denied" })
            end)

            files.grep_word()

            vim.wait(1000, function()
                return captured.updated_items ~= nil
            end)

            assert.are.same({ "Error: permission denied" }, captured.updated_items)

            vim.fn.mode:revert()
            vim.fn.expand:revert()
        end)
    end)

    describe("LSP fallbacks and branching", function()
        local get_clients_stub
        local make_position_params_stub
        local buf_request_stub
        local jump_stub
        local pick_stub
        local runtime_file_stub
        local lsp_start_stub
        local lsp_stop_stub

        after_each(function()
            for _, s in ipairs({
                get_clients_stub,
                make_position_params_stub,
                buf_request_stub,
                jump_stub,
                pick_stub,
                runtime_file_stub,
                lsp_start_stub,
                lsp_stop_stub,
            }) do
                if s then
                    s:revert()
                end
            end
        end)

        local function stub_single_client()
            get_clients_stub = stub(vim.lsp, "get_clients", function(filter)
                if filter and filter.name == "lua_ls" then
                    return { { id = 9, name = "lua_ls" } }
                end
                return { {
                    id = 9,
                    name = "lua_ls",
                    offset_encoding = "utf-16",
                    supports_method = function(_, method)
                        return method == "textDocument/documentSymbol"
                    end,
                } }
            end)
            make_position_params_stub = stub(vim.lsp.util, "make_position_params", function()
                return { textDocument = { uri = "file:///tmp/example.lua" }, position = { line = 0, character = 0 } }
            end)
        end

        it("warns when no LSP client is attached", function()
            get_clients_stub = stub(vim.lsp, "get_clients", function()
                return {}
            end)

            assert.is_nil(lsp.references())
            assert.stub(vim.notify).was_called_with("Refer: No LSP client attached", vim.log.levels.WARN)
        end)

        it("notifies when location requests return no results", function()
            stub_single_client()
            buf_request_stub = stub(vim.lsp, "buf_request", function(_, _, _, callback)
                callback(nil, {}, nil, nil)
            end)

            lsp.definitions()

            assert.stub(vim.notify).was_called_with("Refer: No definitions found", vim.log.levels.INFO)
        end)

        it("fast-jumps when an LSP request returns a single result", function()
            stub_single_client()
            jump_stub = stub(util, "jump_to_location")
            buf_request_stub = stub(vim.lsp, "buf_request", function(_, _, _, callback)
                callback(nil, {
                    uri = vim.uri_from_fname(vim.fn.getcwd() .. "/lua/refer/init.lua"),
                    range = { start = { line = 4, character = 2 }, ["end"] = { line = 4, character = 5 } },
                }, nil, nil)
            end)

            lsp.definitions()

            assert.stub(util.jump_to_location).was_called(1)
        end)

        it("opens a picker when an LSP request returns multiple results", function()
            stub_single_client()
            pick_stub = stub(require("refer"), "pick", function(items, on_select, opts)
                assert.are.same("LSP References > ", opts.prompt)
                assert.are.same("select_entry", opts.keymaps["<CR>"])
                assert.are.same(2, #items)
                return { items = items }
            end)
            buf_request_stub = stub(vim.lsp, "buf_request", function(_, _, _, callback)
                callback(nil, {
                    {
                        uri = vim.uri_from_fname(vim.fn.getcwd() .. "/lua/refer/init.lua"),
                        range = { start = { line = 4, character = 2 }, ["end"] = { line = 4, character = 5 } },
                    },
                    {
                        uri = vim.uri_from_fname(vim.fn.getcwd() .. "/lua/refer/util.lua"),
                        range = { start = { line = 6, character = 1 }, ["end"] = { line = 6, character = 4 } },
                    },
                }, nil, nil)
            end)

            lsp.references()

            assert.stub(require("refer").pick).was_called(1)
        end)

        it("warns when document symbols are requested without a client", function()
            get_clients_stub = stub(vim.lsp, "get_clients", function()
                return {}
            end)

            lsp.document_symbols()

            assert.stub(vim.notify).was_called_with("Refer: No LSP client attached", vim.log.levels.WARN)
        end)

        it("warns when no LSP configurations are available", function()
            get_clients_stub = stub(vim.lsp, "get_clients", function()
                return {}
            end)
            runtime_file_stub = stub(vim.api, "nvim_get_runtime_file", function()
                return {}
            end)
            vim.lsp._enabled_configs = {}

            lsp.lsp_servers()

            assert.stub(vim.notify).was_called_with("Refer: No LSP configurations found", vim.log.levels.WARN)
        end)

        it("keeps LspServers picker and stop-client behavior", function()
            get_clients_stub = stub(vim.lsp, "get_clients", function(filter)
                if filter and filter.name == "lua_ls" then
                    return { { id = 10, name = "lua_ls" } }
                end
                return { { id = 10, name = "lua_ls", config = { name = "lua_ls" } } }
            end)
            runtime_file_stub = stub(vim.api, "nvim_get_runtime_file", function()
                return {}
            end)
            lsp_stop_stub = stub(vim.lsp, "stop_client")
            vim.lsp._enabled_configs = {}

            local picker
            pick_stub = stub(require("refer"), "pick", function(items, on_select, opts)
                picker = { items = items, on_select = on_select, opts = opts }
                return picker
            end)

            lsp.lsp_servers()

            assert.are.same("LSP Servers > ", picker.opts.prompt)
            assert.are.same({ "● lua_ls" }, picker.items)
            picker.on_select("● lua_ls", nil)

            assert.stub(vim.lsp.stop_client).was_called_with(10)
            assert.stub(vim.notify).was_called_with("Stopped LSP: lua_ls", vim.log.levels.INFO)
        end)

        it("keeps LspServers start-client behavior for inactive configs", function()
            get_clients_stub = stub(vim.lsp, "get_clients", function()
                return {}
            end)
            runtime_file_stub = stub(vim.api, "nvim_get_runtime_file", function()
                return {}
            end)
            lsp_start_stub = stub(vim.lsp, "start", function(config)
                return config.name == "lua_ls" and 42 or nil
            end)
            vim.lsp._enabled_configs = {
                lua_ls = { cmd = { "lua-language-server" }, root_dir = vim.fn.getcwd() },
            }

            local picker
            pick_stub = stub(require("refer"), "pick", function(items, on_select, opts)
                picker = { items = items, on_select = on_select, opts = opts }
                return picker
            end)

            lsp.lsp_servers()
            picker.on_select("○ lua_ls", nil)

            assert.stub(vim.lsp.start).was_called(1)
            assert.stub(vim.notify).was_called_with("Started LSP: lua_ls", vim.log.levels.INFO)
        end)
    end)

end)
