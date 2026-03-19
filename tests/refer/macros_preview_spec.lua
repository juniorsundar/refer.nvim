local builtin = require "refer.providers.builtin"

describe("builtin.macros", function()
    local picker
    local buf

    before_each(function()
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(0, buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello", "world" })
        -- Set a macro in register 'a': insert "X" at start of line
        vim.fn.setreg("a", "IX\27")
    end)

    after_each(function()
        if picker then
            picker:close()
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        vim.fn.setreg("a", "")
    end)

    it("lists populated registers", function()
        picker = builtin.macros()
        local found = false
        for _, item in ipairs(picker.items) do
            local text = type(item) == "table" and item.text or item
            if text:sub(1, 1) == "a" then
                found = true
                break
            end
        end
        assert.is_true(found)
    end)

    it("applies macro preview on change", function()
        picker = builtin.macros()

        local reg = "a"
        local content = vim.fn.keytrans(vim.fn.getreg(reg))

        local selection = string.format("%s: %s", reg, content)
        local edit_picker

        local original_schedule = vim.schedule
        vim.schedule = function(fn)
            fn()
        end

        picker.opts.on_select(selection, {})

        vim.schedule = original_schedule

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        -- After IX<Esc> on "hello", first line becomes "Xhello"
        assert.are.same("Xhello", lines[1])
    end)

    it("undoes macro preview when edit picker closes", function()
        picker = builtin.macros()

        local reg = "a"
        local content = vim.fn.keytrans(vim.fn.getreg(reg))
        local selection = string.format("%s: %s", reg, content)

        local original_schedule = vim.schedule
        vim.schedule = function(fn)
            fn()
        end

        picker.opts.on_select(selection, {})

        vim.schedule = original_schedule

        local lines_after_preview = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.same("Xhello", lines_after_preview[1])

        local refer = require "refer"
        if refer._active_picker then
            refer._active_picker:close()
        end

        local lines_after_close = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.same({ "hello", "world" }, lines_after_close)
    end)

    it("saves updated macro to register on confirm", function()
        picker = builtin.macros()

        local reg = "a"
        local content = vim.fn.keytrans(vim.fn.getreg(reg))
        local selection = string.format("%s: %s", reg, content)

        local original_schedule = vim.schedule
        vim.schedule = function(fn)
            fn()
        end

        picker.opts.on_select(selection, {})

        vim.schedule = original_schedule

        -- Retrieve the edit_macro picker and confirm with new content
        local refer = require "refer"
        if refer._active_picker then
            refer._active_picker.opts.on_confirm "Inew\27"
        end

        local saved = vim.fn.getreg(reg)
        assert.are.same("Inew\27", saved)
    end)
end)
