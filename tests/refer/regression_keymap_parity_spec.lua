local refer = require "refer"

describe("refer regression keymap parity", function()
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

    local function trigger_default_keymap(key)
        local handler = picker.opts.keymaps[key]
        assert.is_not_nil(handler)

        if type(handler) == "table" then
            picker.actions[handler.action]()
            return
        end

        if type(handler) == "string" then
            picker.actions[handler]()
            return
        end

        handler(nil, {
            picker = picker,
            actions = picker.actions,
            parameters = {
                original_win = picker.original_win,
                original_buf = picker.original_buf,
                original_cursor = picker.original_cursor,
            },
            marked = picker.marked,
        })
    end

    before_each(function()
        tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        close_picker()
        if tmpdir then
            vim.fn.delete(tmpdir, "rf")
        end
    end)

    it("keeps <C-s> cycling the active sorter", function()
        picker = refer.pick({ "alpha", "beta" }, function() end, {
            available_sorters = { "lua", "native" },
            default_sorter = "lua",
        })

        vim.wait(1000, function()
            return picker.current_matches and #picker.current_matches == 2
        end)

        assert.are.same(1, picker.sorter_idx)

        trigger_default_keymap "<C-s>"

        assert.are.same(2, picker.sorter_idx)
        assert.are.same("alpha", picker.current_matches[1].text)
        assert.are.same("beta", picker.current_matches[2].text)
    end)

    it("keeps <C-v> toggling preview on and off", function()
        local file = tmpdir .. "/preview.lua"
        write_file(file, { "alpha", "beta", "gamma" })

        local original_buf = vim.api.nvim_get_current_buf()

        picker = refer.pick({ {
            text = file .. ":2:1:beta",
            data = { filename = file, lnum = 2, col = 1 },
        } }, function() end, {
            preview = { enabled = false },
        })

        vim.wait(1000, function()
            return picker.current_matches and #picker.current_matches == 1
        end)

        assert.is_false(picker.preview_enabled)
        assert.are.same(original_buf, vim.api.nvim_win_get_buf(picker.original_win))

        trigger_default_keymap "<C-v>"

        vim.wait(1000, function()
            return picker.preview_enabled and vim.api.nvim_win_get_buf(picker.original_win) ~= original_buf
        end)

        assert.is_true(picker.preview_enabled)
        assert.are.same(2, vim.api.nvim_win_get_cursor(picker.original_win)[1])

        trigger_default_keymap "<C-v>"

        vim.wait(1000, function()
            return not picker.preview_enabled and vim.api.nvim_win_get_buf(picker.original_win) == original_buf
        end)

        assert.is_false(picker.preview_enabled)
        assert.are.same(original_buf, vim.api.nvim_win_get_buf(picker.original_win))
    end)
end)
