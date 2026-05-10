local builtin = require "refer.providers.builtin"
local refer = require "refer"
local stub = require "luassert.stub"

describe("builtin.commands execution", function()
    after_each(function()
        pcall(vim.cmd, "bwipe!")
    end)

    it("handles range correctly", function()
        local s = stub(vim, "cmd")
        local picker = builtin.commands { range = 2, line1 = 10, line2 = 20 }

        assert.equals("'<,'>", picker.opts.default_text)

        picker.on_select "'<,'>sort"

        assert.stub(s).was.called_with "'<,'>sort"
        s:revert()
    end)

    it("handles no range correctly", function()
        local s = stub(vim, "cmd")
        local picker = builtin.commands()

        assert.equals(nil, picker.opts.default_text)

        picker.on_select "echo 'hi'"

        assert.stub(s).was.called_with "echo 'hi'"
        s:revert()
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
