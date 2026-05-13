local builtin = require "refer.providers.builtin"
local refer = require "refer"
local stub = require "luassert.stub"

describe("builtin.commands execution", function()
    after_each(function()
        vim.g.refer_builtin_range_no_range = nil
        pcall(vim.cmd, "bwipe!")
    end)

    it("handles range correctly", function()
        local picker = builtin.commands { range = 2, line1 = 10, line2 = 20 }

        assert.equals("'<,'>", picker.opts.default_text)

        vim.cmd "enew!"
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "c", "b", "a" })
        vim.fn.setpos("'<", { 0, 1, 1, 0 })
        vim.fn.setpos("'>", { 0, 3, 1, 0 })

        picker.on_select "'<,'>sort"

        assert.are.same({ "a", "b", "c" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("handles no range correctly", function()
        local picker = builtin.commands()

        assert.equals(nil, picker.opts.default_text)

        picker.on_select "let g:refer_builtin_range_no_range = 'hi'"

        assert.are.same("hi", vim.g.refer_builtin_range_no_range)
    end)

    it("jumps to a bare line number command", function()
        local s_pick = stub(refer, "pick")
        s_pick.invokes(function(_, on_select, opts)
            return { on_select = on_select, opts = opts }
        end)

        vim.cmd "enew!"
        local lines = {}
        for i = 1, 40 do
            lines[i] = "line " .. i
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local picker = builtin.commands()
        picker.on_select "32"

        assert.are.same(32, vim.api.nvim_win_get_cursor(0)[1])

        s_pick:revert()
    end)
end)
