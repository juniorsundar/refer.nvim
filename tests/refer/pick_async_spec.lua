local refer = require "refer"

describe("refer.pick_async", function()
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

    it("runs async command and returns results", function()
        local generator = function(query)
            return { "echo", "result_" .. query }
        end

        picker = refer.pick_async(generator, nil, { debounce_ms = 10, min_query_len = 1 })

        set_input(picker, "foo")

        vim.wait(500, function()
            return #picker.current_matches > 0
        end)

        assert.are.same(1, #picker.current_matches)
        assert.are.same("result_foo", picker.current_matches[1].text)
    end)

    it("handles multiple lines of output", function()
        local generator = function(query)
            return { "sh", "-c", "echo A; echo B" }
        end

        picker = refer.pick_async(generator, nil, { debounce_ms = 10, min_query_len = 1 })

        set_input(picker, "x")

        vim.wait(500, function()
            return #picker.current_matches >= 2
        end)

        assert.are.same(2, #picker.current_matches)
        assert.are.same("A", picker.current_matches[1].text)
        assert.are.same("B", picker.current_matches[2].text)
    end)

    it("can post-process results", function()
        local generator = function(query)
            return { "echo", "foo" }
        end
        local post_process = function(lines, query)
            table.insert(lines, "bar_" .. query)
            return lines
        end

        picker = refer.pick_async(generator, nil, {
            debounce_ms = 10,
            min_query_len = 1,
            post_process = post_process,
        })

        set_input(picker, "baz")

        vim.wait(500, function()
            return #picker.current_matches >= 2
        end)

        assert.are.same(2, #picker.current_matches)
        assert.are.same("foo", picker.current_matches[1].text)
        assert.are.same("bar_baz", picker.current_matches[2].text)
    end)

    it("preserves selected_index across streaming timer ticks", function()
        local generator = function(query)
            return { "sh", "-c", "printf 'line1\\nline2\\nline3\\n'" }
        end

        picker = refer.pick_async(generator, nil, { debounce_ms = 10, min_query_len = 1 })

        set_input(picker, "x")

        vim.wait(500, function()
            return #picker.current_matches >= 3
        end)

        assert.are.same(3, #picker.current_matches)
        assert.are.same(1, picker.selected_index)

        picker:navigate(1)
        assert.are.same(2, picker.selected_index)

        vim.wait(150)

        assert.are.same(2, picker.selected_index)
    end)

    it("respects minimum query length", function()
        local called = false
        local generator = function(query)
            called = true
            return { "echo", "foo" }
        end

        picker = refer.pick_async(generator, nil, { debounce_ms = 10, min_query_len = 3 })

        set_input(picker, "ab")
        vim.wait(100)

        assert.is_false(called)
        assert.are.same(0, #picker.current_matches)

        set_input(picker, "abc")

        vim.wait(500, function()
            return called and #picker.current_matches > 0
        end)

        assert.is_true(called)
        assert.are.same(1, #picker.current_matches)
    end)
end)
