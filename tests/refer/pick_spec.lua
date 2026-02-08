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

        -- Initial state (debounce wait)
        vim.wait(50)

        assert.are.same(#items, #picker.current_matches)

        set_input(picker, "app")
        vim.wait(50)

        assert.are.same(1, #picker.current_matches)
        assert.are.same("apple", picker.current_matches[1])

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
        vim.wait(50)

        -- Default query ""
        assert.are.same(2, #picker.current_matches)

        set_input(picker, "foo")
        vim.wait(50)

        assert.are.same(1, #picker.current_matches)
        assert.are.same("foobar", picker.current_matches[1])

        picker.actions.select_entry()
        assert.are.same("foobar", selected_item)
    end)

    it("can cycle through items", function()
        local items = { "a", "b", "c" }
        picker = refer.pick(items, function() end)
        vim.wait(50)

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
        vim.wait(50)

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
        vim.wait(50)

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
        vim.wait(50)

        picker:close()
        assert.is_true(closed)
        picker = nil
    end)
end)
