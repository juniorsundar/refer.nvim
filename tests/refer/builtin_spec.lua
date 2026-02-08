local builtin = require "refer.providers.builtin"

describe("builtin.commands history cycling", function()
    local picker

    local function trigger_key(key)
        local handler = picker.opts.keymaps[key]
        local context = {
            picker = picker,
            actions = picker.actions,
            parameters = {
                original_win = picker.original_win,
                original_buf = picker.original_buf,
            },
        }
        handler(nil, context)
    end

    local function set_input(text)
        vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { text })
        vim.api.nvim_win_set_cursor(picker.ui.input_win, { 1, #text })
    end

    local function get_input()
        local lines = vim.api.nvim_buf_get_lines(picker.input_buf, 0, -1, false)
        return lines[1] or ""
    end

    before_each(function()
        vim.fn.histdel "cmd"
        vim.fn.histadd("cmd", "short")
        vim.fn.histadd("cmd", "longer command")
        vim.fn.histadd("cmd", "lua print('very long command that caused issues')")
        vim.fn.histadd("cmd", "duplicate")
        vim.fn.histadd("cmd", "duplicate")
    end)

    after_each(function()
        if picker then
            picker:close()
        end
    end)

    it("cycles backwards through history with <C-p>", function()
        picker = builtin.commands()

        -- Initial state
        assert.are.same("", get_input())

        trigger_key "<C-p>"
        assert.are.same("duplicate", get_input())

        trigger_key "<C-p>"
        assert.are.same("lua print('very long command that caused issues')", get_input())

        trigger_key "<C-p>"
        assert.are.same("longer command", get_input())

        trigger_key "<C-p>"
        assert.are.same("short", get_input())
    end)

    it("cycles forwards through history with <C-n>", function()
        picker = builtin.commands()

        trigger_key "<C-p>"
        trigger_key "<C-p>"
        trigger_key "<C-p>"
        assert.are.same("longer command", get_input())

        trigger_key "<C-n>"
        assert.are.same("lua print('very long command that caused issues')", get_input())
    end)

    it("resets cycling when input matches but user types", function()
        picker = builtin.commands()

        set_input "lo"
        trigger_key "<C-p>"
        assert.are.same("longer command", get_input())

        set_input "sh"

        trigger_key "<C-p>"
        assert.are.same("short", get_input())
    end)

    it("handles the specific long entry bug scenario", function()
        picker = builtin.commands()

        -- Cycle to "lua print..."
        trigger_key "<C-p>"
        trigger_key "<C-p>"
        assert.are.same("lua print('very long command that caused issues')", get_input())

        trigger_key "<C-p>"
        assert.are.same("longer command", get_input())
    end)
end)
