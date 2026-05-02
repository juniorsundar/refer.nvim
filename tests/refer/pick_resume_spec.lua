local refer = require "refer"

describe("refer.pick_resume", function()
    local picker

    after_each(function()
        if picker then
            pcall(function()
                picker:close()
            end)
            picker = nil
        end
        local Picker = require "refer.picker"
        Picker.close_existing()
    end)

    it("exposes pick_resume as a callable function", function()
        assert.are.same("function", type(refer.pick_resume))
    end)

    it("captures and reruns the last picker with its query", function()
        local items = { "alpha", "beta", "gamma", "delta" }

        -- First pick run
        picker = refer.pick(items, function() end)

        vim.wait(500, function()
            return #picker.current_matches == 4
        end)

        -- Type a query
        vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { "be" })
        picker:refresh()

        vim.wait(300)

        -- Close the picker (this triggers on_close which captures state)
        picker:close()
        vim.wait(50)

        -- Rerun
        picker = refer.pick_resume()

        -- The new picker should exist
        assert.is_not_nil(picker)

        -- The new picker should have the previous query as default text
        local lines = vim.api.nvim_buf_get_lines(picker.input_buf, 0, -1, false)
        assert.equals("be", lines[1])
    end)

    it("does not capture state from vim.ui.select calls", function()
        -- First, set up a regular picker
        picker = refer.pick({ "x", "y", "z" }, function() end)
        vim.wait(200)

        vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { "x" })
        picker:refresh()
        vim.wait(100)
        picker:close()
        vim.wait(50)

        -- Now use refer.select which is meant for vim.ui.select
        local select_picker
        refer.select({ "one", "two" }, { prompt = "pick:" }, function() end)
        select_picker = require("refer.picker").get_active()
        if select_picker then
            select_picker:close()
            vim.wait(50)
        end

        -- Suppress notify
        local original_notify = vim.notify
        vim.notify = function() end

        -- Rerun: should bring back the original {x,y,z} pick, not the select choices
        picker = refer.pick_resume()
        vim.notify = original_notify

        assert.is_not_nil(picker)

        -- The rerun should have x as default text from the original pick
        local lines = vim.api.nvim_buf_get_lines(picker.input_buf, 0, -1, false)
        assert.equals("x", lines[1])
    end)

    it("preserves original on_close across repeated resumes", function()
        local close_count = 0
        local items = { "foo", "bar", "baz" }

        picker = refer.pick(items, function() end, {
            on_close = function()
                close_count = close_count + 1
            end,
        })
        vim.wait(200)

        picker:close()
        vim.wait(50)
        assert.equals(1, close_count)

        local original_notify = vim.notify
        vim.notify = function() end
        picker = refer.pick_resume()
        vim.notify = original_notify
        assert.is_not_nil(picker)
        vim.wait(100)
        picker:close()
        vim.wait(50)
        assert.equals(2, close_count)

        vim.notify = function() end
        picker = refer.pick_resume()
        vim.notify = original_notify
        assert.is_not_nil(picker)
        vim.wait(100)
        picker:close()
        vim.wait(50)
        assert.equals(3, close_count)
    end)

    it("restores empty query correctly on resume", function()
        local items = { "alpha", "beta", "gamma" }

        picker = refer.pick(items, function() end, { default_text = "abc" })
        vim.wait(200)

        vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { "" })
        picker:refresh()
        vim.wait(100)

        picker:close()
        vim.wait(50)

        local original_notify = vim.notify
        vim.notify = function() end
        picker = refer.pick_resume()
        vim.notify = original_notify

        assert.is_not_nil(picker)

        local lines = vim.api.nvim_buf_get_lines(picker.input_buf, 0, -1, false)
        assert.equals("", lines[1])
    end)
end)
