local refer = require "refer"

describe("refer.pick", function()
    local picker

    local function set_input(p, text)
        vim.api.nvim_buf_set_lines(p.input_buf, 0, -1, false, { text })
        p:refresh()
    end

    after_each(function()
        if picker then
            picker:close()
            picker = nil
        end
    end)

    it("can pick from a simple list of items", function()
        local items = { "apple", "banana", "cherry" }
        local selected_item
        local on_select = function(item)
            selected_item = item
        end

        picker = refer.pick(items, on_select)

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        assert.are.same(#items, #picker.current_matches)
        -- current_matches now contains ReferItem tables
        assert.are.same("table", type(picker.current_matches[1]))

        set_input(picker, "app")

        vim.wait(500, function()
            return #picker.current_matches == 1
        end)

        assert.are.same(1, #picker.current_matches)
        assert.are.same("apple", picker.current_matches[1].text)

        picker.actions.select_entry()

        assert.are.same("apple", selected_item)
    end)

    it("handles provider functions", function()
        local provider = function(query)
            if query == "foo" then
                return { "foobar" }
            else
                return { "something", "else" }
            end
        end

        local selected_item
        picker = refer.pick(provider, function(item)
            selected_item = item
        end)

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        -- Default query ""
        assert.are.same(2, #picker.current_matches)

        set_input(picker, "foo")

        vim.wait(500, function()
            return #picker.current_matches == 1
        end)

        assert.are.same(1, #picker.current_matches)
        assert.are.same("foobar", picker.current_matches[1].text)

        picker.actions.select_entry()
        assert.are.same("foobar", selected_item)
    end)

    it("can cycle through items", function()
        local items = { "a", "b", "c" }
        picker = refer.pick(items, function() end)

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        assert.are.same(1, picker.selected_index)

        picker.actions.next_item()
        assert.are.same(2, picker.selected_index)

        picker.actions.next_item()
        assert.are.same(3, picker.selected_index)

        picker.actions.next_item()
        assert.are.same(1, picker.selected_index) -- Cycle back

        picker.actions.prev_item()
        assert.are.same(3, picker.selected_index) -- Cycle back reverse
    end)

    it("respects initial options", function()
        local items = { "one" }
        local prompt = "Test Prompt > "
        picker = refer.pick(items, function() end, { prompt = prompt })

        vim.wait(500, function()
            return #picker.current_matches == 1
        end)

        assert.are.same(prompt, picker.ui.base_prompt)
    end)

    it("parses selection and passes data to callback", function()
        local items = { "file1.lua", "file2.lua" }
        local parser = function(selection)
            return { filename = selection, type = "file" }
        end

        local captured_data
        local on_select = function(selection, data)
            captured_data = data
        end

        picker = refer.pick(items, on_select, { parser = parser })

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        picker.actions.select_entry()

        assert.are.same({ filename = "file1.lua", type = "file" }, captured_data)
    end)

    it("calls on_close when closed", function()
        local closed = false
        picker = refer.pick({}, function() end, {
            on_close = function()
                closed = true
            end,
        })
        vim.wait(500, function()
            return picker.input_buf ~= nil
        end)

        vim.wait(50)

        picker:close()
        assert.is_true(closed)
        picker = nil
    end)

    -- ReferItem contract tests (Task 2 behaviors)

    it("current_matches contains ReferItem tables after refresh from string list", function()
        picker = refer.pick({ "foo", "bar" }, function() end)

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        assert.are.same(2, #picker.current_matches)
        assert.are.same("table", type(picker.current_matches[1]))
        assert.are.same("foo", picker.current_matches[1].text)
        assert.are.same("table", type(picker.current_matches[2]))
        assert.are.same("bar", picker.current_matches[2].text)
    end)

    it("current_matches retains item.data payloads from structured items", function()
        local items = { { text = "foo", data = { lnum = 1 } }, { text = "bar" } }
        picker = refer.pick(items, function() end)

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        assert.are.same(2, #picker.current_matches)
        assert.are.same("foo", picker.current_matches[1].text)
        assert.are.same(1, picker.current_matches[1].data.lnum)
        assert.are.same("bar", picker.current_matches[2].text)
    end)

    it("results buffer renders item.text strings (not table representations)", function()
        picker = refer.pick({ "alpha", "beta" }, function() end)

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        -- Wait a bit more for rendering
        vim.wait(100)

        local lines = vim.api.nvim_buf_get_lines(picker.ui.results_buf, 0, -1, false)
        -- The first line should be the text string "alpha", not a table representation
        assert.is_true(
            lines[1] == "alpha" or lines[1] == "beta",
            "Expected 'alpha' or 'beta', got: " .. tostring(lines[1])
        )
        -- Definitely not a table repr
        assert.is_false(vim.startswith(lines[1], "table:"))
    end)

    it("select_entry passes item.data to on_select when structured item has data", function()
        local items = { { text = "myfile.lua", data = { filename = "myfile.lua", lnum = 10 } } }
        local captured_selection, captured_data

        picker = refer.pick(items, function(sel, data)
            captured_selection = sel
            captured_data = data
        end)

        vim.wait(500, function()
            return #picker.current_matches == 1
        end)

        picker.actions.select_entry()

        assert.are.same("myfile.lua", captured_selection)
        assert.are.same("myfile.lua", captured_data.filename)
        assert.are.same(10, captured_data.lnum)
    end)

    it("toggle_mark keys marked table by item.text", function()
        picker = refer.pick({ "alpha", "beta", "gamma" }, function() end)

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- selected_index is 1 (alpha)
        picker.actions.toggle_mark()

        -- marked should have "alpha" as key (the text string), not a table
        assert.is_true(
            picker.marked["alpha"] == true or picker.marked["alpha"] == false,
            "Expected marked key to be text string 'alpha'"
        )
        -- No table key should be present
        for k, _ in pairs(picker.marked) do
            assert.are.same("string", type(k), "Expected marked keys to be strings, got: " .. type(k))
        end
    end)
end)
