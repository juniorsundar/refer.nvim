local refer = require "refer"

describe("refer regression builtin surface", function()
    local original_loaded_refer
    local original_registry
    local original_builtin_provider
    local original_files_provider
    local original_lsp_provider

    local function load_plugin_commands()
        pcall(vim.api.nvim_del_user_command, "Refer")
        refer._registry = {}
        vim.g.loaded_refer = nil
        dofile(vim.fn.getcwd() .. "/plugin/refer.lua")
        return refer.get_commands()
    end

    before_each(function()
        original_loaded_refer = vim.g.loaded_refer
        original_registry = vim.deepcopy(refer.get_commands())
        original_builtin_provider = package.loaded["refer.providers.builtin"]
        original_files_provider = package.loaded["refer.providers.files"]
        original_lsp_provider = package.loaded["refer.providers.lsp"]
    end)

    after_each(function()
        pcall(vim.api.nvim_del_user_command, "Refer")
        vim.g.loaded_refer = original_loaded_refer
        refer._registry = original_registry or {}
        package.loaded["refer.providers.builtin"] = original_builtin_provider
        package.loaded["refer.providers.files"] = original_files_provider
        package.loaded["refer.providers.lsp"] = original_lsp_provider
    end)

    it("registers the full builtin command surface and routes every command", function()
        local calls = {}
        local function record(target)
            return function(opts)
                table.insert(calls, { target = target, opts = opts })
            end
        end

        package.loaded["refer.providers.builtin"] = {
            buffers = record "builtin.buffers",
            old_files = record "builtin.old_files",
            commands = record "builtin.commands",
            macros = record "builtin.macros",
        }
        package.loaded["refer.providers.files"] = {
            files = record "files.files",
            live_grep = record "files.live_grep",
            grep_word = record "files.grep_word",
            lines = record "files.lines",
        }
        package.loaded["refer.providers.lsp"] = {
            references = record "lsp.references",
            definitions = record "lsp.definitions",
            implementations = record "lsp.implementations",
            declarations = record "lsp.declarations",
            lsp_servers = record "lsp.lsp_servers",
            document_symbols = record "lsp.document_symbols",
        }

        local commands = load_plugin_commands()
        local expected = {
            Buffers = "builtin.buffers",
            Commands = "builtin.commands",
            Declarations = "lsp.declarations",
            Definitions = "lsp.definitions",
            Files = "files.files",
            Grep = "files.live_grep",
            Implementations = "lsp.implementations",
            Lines = "files.lines",
            LspServers = "lsp.lsp_servers",
            Macros = "builtin.macros",
            OldFiles = "builtin.old_files",
            References = "lsp.references",
            Selection = "files.grep_word",
            Symbols = "lsp.document_symbols",
        }
        local expected_names = {
            "Buffers",
            "Commands",
            "Declarations",
            "Definitions",
            "Files",
            "Grep",
            "Implementations",
            "Lines",
            "LspServers",
            "Macros",
            "OldFiles",
            "References",
            "Selection",
            "Symbols",
        }

        local actual_names = vim.tbl_keys(commands)
        table.sort(actual_names)

        assert.are.same(expected_names, actual_names)

        for name, target in pairs(expected) do
            local opts = { subcommand = name }
            commands[name](opts)

            local call = calls[#calls]
            assert.are.same(target, call.target)
            assert.is_true(call.opts == opts)
        end
    end)

    describe("local builtin picker behavior", function()
        local builtin = require "refer.providers.builtin"
        local files = require "refer.providers.files"
        local tmpdir

        local function close_active_picker()
            local active = refer._active_picker
            if active then
                active:close()
            end
        end

        local function set_input(picker, text)
            vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { text })
            vim.api.nvim_win_set_cursor(picker.ui.input_win, { 1, #text })
            picker:refresh()
        end

        local function wait_for_matches(picker, count)
            vim.wait(1000, function()
                return picker.current_matches and #picker.current_matches >= count
            end)
        end

        local function write_file(path, lines)
            local fd = assert(io.open(path, "w"))
            fd:write(table.concat(lines, "\n"))
            fd:write "\n"
            fd:close()
        end

        before_each(function()
            tmpdir = vim.fn.tempname()
            vim.fn.mkdir(tmpdir, "p")
        end)

        after_each(function()
            close_active_picker()
            if tmpdir then
                vim.fn.delete(tmpdir, "rf")
            end
            pcall(vim.api.nvim_del_user_command, "ReferRegressionBuiltinOne")
            pcall(vim.api.nvim_del_user_command, "ReferRegressionBuiltinTwo")
            vim.g.refer_regression_commands = nil
            vim.v.oldfiles = {}
            vim.fn.setreg("a", "")
            vim.fn.setreg("b", "")
        end)

        it("keeps Commands behavior for prompt, results, navigation, and confirm", function()
            local picker = builtin.commands()
            assert.are.same("M-x > ", picker.opts.prompt)

            set_input(picker, "set")
            wait_for_matches(picker, 2)

            assert.are.same(1, picker.selected_index)
            picker.actions.next_item()
            assert.are.same(2, picker.selected_index)

            set_input(picker, "let g:refer_regression_command = 'two'")
            picker.actions.select_input()

            assert.are.same("two", vim.g.refer_regression_command)
        end)

        it("keeps Buffers behavior for prompt, navigation, and confirm", function()
            local first = tmpdir .. "/buffer-one.lua"
            local second = tmpdir .. "/buffer-two.lua"
            write_file(first, { "first" })
            write_file(second, { "second" })

            vim.cmd("edit " .. vim.fn.fnameescape(first))
            vim.cmd("edit " .. vim.fn.fnameescape(second))

            local picker = builtin.buffers()
            wait_for_matches(picker, 2)

            assert.are.same("Buffers > ", picker.opts.prompt)
            assert.are.same(1, picker.selected_index)

            picker.actions.next_item()
            assert.are.same(2, picker.selected_index)

            local target = picker.current_matches[picker.selected_index]
            assert.is_truthy(target:find("buffer%-one%.lua") or target:find("buffer%-two%.lua"))

            picker.actions.select_entry()
            assert.is_true(vim.api.nvim_buf_get_name(0):find("buffer%-%a+%.lua") ~= nil)
        end)

        it("keeps OldFiles behavior for results, confirm, and empty state", function()
            local recent = tmpdir .. "/recent.lua"
            write_file(recent, { "recent" })

            vim.v.oldfiles = { recent }
            local picker = builtin.old_files()
            wait_for_matches(picker, 1)

            assert.are.same("Recent Files > ", picker.opts.prompt)
            assert.are.same(recent, picker.current_matches[1])

            picker.actions.select_entry()
            assert.are.same(recent, vim.api.nvim_buf_get_name(0))

            vim.v.oldfiles = { tmpdir .. "/missing.lua" }
            local empty_picker = builtin.old_files()
            vim.wait(1000, function()
                return empty_picker.current_matches ~= nil
            end)

            assert.are.same(0, #empty_picker.current_matches)
            local results = vim.api.nvim_buf_get_lines(empty_picker.ui.results_buf, 0, -1, false)
            assert.are.same(1, #results)
            assert.is_truthy(results[1]:match "^%s*$")
        end)

        it("keeps Macros behavior for results, navigation, and confirm", function()
            vim.fn.setreg("a", "ix\27")
            vim.fn.setreg("b", "A!\27")

            local picker = builtin.macros()
            wait_for_matches(picker, 2)

            assert.are.same("Macros > ", picker.opts.prompt)
            assert.are.same(1, picker.selected_index)

            picker.actions.next_item()
            assert.are.same(2, picker.selected_index)

            local original_schedule = vim.schedule
            vim.schedule = function(fn)
                fn()
            end

            picker.actions.select_entry()

            vim.schedule = original_schedule

            local edit_picker = refer._active_picker
            assert.are.same("Edit Macro [b] > ", edit_picker.opts.prompt)

            edit_picker.opts.on_confirm "Iupdated\27"
            assert.are.same("Iupdated\27", vim.fn.getreg "b")
        end)

        it("keeps Lines behavior for prompt, results, navigation, and confirm", function()
            local file = tmpdir .. "/lines.lua"
            write_file(file, { "alpha", "beta", "gamma" })

            vim.cmd("edit " .. vim.fn.fnameescape(file))

            local picker = files.lines()
            wait_for_matches(picker, 3)

            assert.are.same("Lines > ", picker.opts.prompt)
            assert.are.same(1, picker.selected_index)
            assert.is_truthy(picker.current_matches[1]:find("alpha", 1, true))

            picker.actions.next_item()
            assert.are.same(2, picker.selected_index)

            picker.actions.select_entry()
            assert.are.same(2, vim.api.nvim_win_get_cursor(0)[1])
        end)
    end)
end)
