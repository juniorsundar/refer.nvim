local refer = require "refer"

describe("refer regression selection actions", function()
    local picker
    local tmpdir

    local function close_picker()
        if picker then
            picker:close()
            picker = nil
        end
    end

    local function write_file(path, lines)
        local fd = assert(io.open(path, "w"))
        fd:write(table.concat(lines, "\n"))
        fd:write "\n"
        fd:close()
    end

    local function make_location(path, lnum, col, text)
        return string.format("%s:%d:%d:%s", path, lnum, col, text or "")
    end

    local function open_picker(items, opts)
        picker = refer.pick(items, function(selection, data)
            require("refer.util").jump_to_location(selection, data)
        end, vim.tbl_deep_extend("force", {
            prompt = "Regression > ",
            parser = require("refer.util").parsers.grep,
        }, opts or {}))
        vim.wait(1000, function()
            return picker.current_matches and #picker.current_matches == #items
        end)
    end

    before_each(function()
        tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        close_picker()
        pcall(vim.cmd, "tabonly")
        pcall(vim.cmd, "only")
        if tmpdir then
            vim.fn.delete(tmpdir, "rf")
        end
    end)

    it("keeps normal next and prev navigation semantics", function()
        open_picker({ "one", "two", "three" })

        assert.are.same(1, picker.selected_index)
        picker.actions.next_item()
        assert.are.same(2, picker.selected_index)
        picker.actions.prev_item()
        assert.are.same(1, picker.selected_index)
    end)

    it("keeps reverse-result navigation semantics", function()
        open_picker({ "one", "two", "three" }, { ui = { reverse_result = true } })

        assert.are.same(1, picker.selected_index)
        picker.actions.prev_item()
        assert.are.same(2, picker.selected_index)
        picker.actions.next_item()
        assert.are.same(1, picker.selected_index)
    end)

    it("keeps edit confirmation behavior", function()
        local file = tmpdir .. "/edit.lua"
        write_file(file, { "alpha", "beta", "gamma" })
        vim.cmd("edit " .. vim.fn.fnameescape(file))

        open_picker({ make_location(file, 2, 1, "beta") })
        picker.actions.edit_entry()

        assert.are.same(file, vim.api.nvim_buf_get_name(0))
        assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("keeps split confirmation behavior", function()
        local file = tmpdir .. "/split.lua"
        write_file(file, { "alpha", "beta" })
        vim.cmd("edit " .. vim.fn.fnameescape(file))
        local initial_windows = #vim.api.nvim_list_wins()

        open_picker({ make_location(file, 2, 1, "beta") })
        picker.actions.split_entry()

        assert.are.same(initial_windows + 1, #vim.api.nvim_list_wins())
        assert.are.same(file, vim.api.nvim_buf_get_name(0))
        assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("keeps vsplit confirmation behavior", function()
        local file = tmpdir .. "/vsplit.lua"
        write_file(file, { "alpha", "beta" })
        vim.cmd("edit " .. vim.fn.fnameescape(file))
        local initial_windows = #vim.api.nvim_list_wins()

        open_picker({ make_location(file, 1, 1, "alpha") })
        picker.actions.vsplit_entry()

        assert.are.same(initial_windows + 1, #vim.api.nvim_list_wins())
        assert.are.same(file, vim.api.nvim_buf_get_name(0))
        assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("keeps tab confirmation behavior", function()
        local file = tmpdir .. "/tab.lua"
        write_file(file, { "alpha", "beta" })
        vim.cmd("edit " .. vim.fn.fnameescape(file))
        local initial_tabs = #vim.api.nvim_list_tabpages()

        open_picker({ make_location(file, 2, 1, "beta") })
        picker.actions.tab_entry()

        assert.are.same(initial_tabs + 1, #vim.api.nvim_list_tabpages())
        assert.are.same(file, vim.api.nvim_buf_get_name(0))
        assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("keeps no-selection behavior as a safe no-op for all open actions", function()
        local file = tmpdir .. "/noop.lua"
        write_file(file, { "alpha" })
        vim.cmd("edit " .. vim.fn.fnameescape(file))
        local original_win = vim.api.nvim_get_current_win()
        local original_buf = vim.api.nvim_get_current_buf()
        local original_tab_count = #vim.api.nvim_list_tabpages()

        open_picker({})
        local picker_win_count = #vim.api.nvim_list_wins()
        picker.current_matches = {}
        picker.selected_index = 1

        picker.actions.edit_entry()
        picker.actions.split_entry()
        picker.actions.vsplit_entry()
        picker.actions.tab_entry()

        assert.are.same(original_buf, vim.api.nvim_win_get_buf(original_win))
        assert.are.same(picker_win_count, #vim.api.nvim_list_wins())
        assert.are.same(original_tab_count, #vim.api.nvim_list_tabpages())
        assert.is_not_nil(picker)
    end)
end)
