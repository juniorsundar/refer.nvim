local refer = require "refer"
local frecency = require "refer.frecency"
local db = require "refer.frecency.db"

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

    describe("sorter_name tracking", function()
        it("initializes sorter_name from default_sorter", function()
            picker = refer.pick({ "a" }, function() end, { default_sorter = "lua" })
            vim.wait(500, function()
                return picker.sorter_name ~= nil
            end)
            assert.are.equal("lua", picker.sorter_name)
        end)

        it("defaults sorter_name to blink when no default_sorter", function()
            picker = refer.pick({ "a" }, function() end)
            vim.wait(500, function()
                return picker.sorter_name ~= nil
            end)
            assert.are.equal("blink", picker.sorter_name)
        end)

        it("cycle_sorter updates sorter_name", function()
            picker = refer.pick({ "a" }, function() end, { default_sorter = "blink" })
            vim.wait(500, function()
                return picker.sorter_name ~= nil
            end)
            assert.are.equal("blink", picker.sorter_name)

            picker.actions.cycle_sorter()
            vim.wait(100)
            assert.are.equal("mini", picker.sorter_name)

            picker.actions.cycle_sorter()
            vim.wait(100)
            assert.are.equal("native", picker.sorter_name)

            picker.actions.cycle_sorter()
            vim.wait(100)
            assert.are.equal("lua", picker.sorter_name)

            picker.actions.cycle_sorter()
            vim.wait(100)
            assert.are.equal("blink", picker.sorter_name)
        end)

        it("resolves sorter_name from opts.sorter string", function()
            picker = refer.pick({ "a" }, function() end, { sorter = "lua" })
            vim.wait(500, function()
                return picker.sorter_name ~= nil
            end)
            assert.are.equal("lua", picker.sorter_name)
        end)

        it("resolves sorter_name from registered custom sorter", function()
            local custom_fn = function(items, query)
                return items
            end
            require("refer.fuzzy").register_sorter("custom_test", custom_fn)
            picker = refer.pick({ "a" }, function() end, { sorter = "custom_test" })
            vim.wait(500, function()
                return picker.sorter_name ~= nil
            end)
            assert.are.equal("custom_test", picker.sorter_name)
        end)
    end)

    describe("frecency options", function()
        it("picker stores frecency opts from pick() call", function()
            picker = refer.pick({ "a" }, function() end, {
                frecency = { provider = "test", key_strategy = "filepath" },
            })
            vim.wait(500, function()
                return picker.opts.frecency ~= nil
            end)
            assert.are.equal("test", picker.opts.frecency.provider)
            assert.are.equal("filepath", picker.opts.frecency.key_strategy)
        end)

        it("frecency.enabled defaults to true", function()
            picker = refer.pick({ "a" }, function() end)
            vim.wait(500, function()
                return picker.input_buf ~= nil
            end)
            -- Default from setup: frecency.enabled = true
            assert.is_true(picker.opts.frecency.enabled)
        end)

        it("frecency.enabled can be disabled per-picker", function()
            picker = refer.pick({ "a" }, function() end, {
                frecency = { provider = "test", enabled = false },
            })
            vim.wait(500, function()
                return picker.opts.frecency ~= nil
            end)
            assert.is_false(picker.opts.frecency.enabled)
        end)
    end)

    describe("frecency reorder integration", function()
        local active_frecency_path

        local function setup_frecency_for_test()
            active_frecency_path = vim.fn.tempname() .. "_reorder_test.json"
            frecency.configure {
                db_path = active_frecency_path,
                buckets = false,
                neighborhood_size = 10,
            }
        end

        before_each(function()
            setup_frecency_for_test()
        end)

        after_each(function()
            if picker then
                picker:close()
                picker = nil
            end
            if active_frecency_path then
                vim.fn.delete(active_frecency_path, "rf")
                vim.fn.delete(vim.fn.fnamemodify(active_frecency_path, ":h"), "rf")
                active_frecency_path = nil
            end
            db._reset()
        end)

        it("reorders items by frecency when lua sorter + provider are active", function()
            -- Record frecency: select "item_b" multiple times so it ranks higher
            frecency.record("test_reorder", "item_b")
            frecency.record("test_reorder", "item_b")
            frecency.record("test_reorder", "item_a")

            picker = refer.pick({ "item_a", "item_b", "item_c" }, function() end, {
                default_sorter = "lua",
                frecency = { provider = "test_reorder" },
            })

            vim.wait(500, function()
                return #picker.current_matches == 3
            end)

            -- Empty query: items should be sorted by frecency
            -- item_b (2 selections) > item_a (1 selection) > item_c (0 selections)
            assert.are.equal("item_b", picker.current_matches[1].text)
            assert.are.equal("item_a", picker.current_matches[2].text)
            assert.are.equal("item_c", picker.current_matches[3].text)
        end)

        it("does not reorder when blink sorter is active", function()
            frecency.record("test_blink", "item_b")
            frecency.record("test_blink", "item_b")

            picker = refer.pick({ "item_a", "item_b", "item_c" }, function() end, {
                default_sorter = "blink",
                frecency = { provider = "test_blink" },
            })

            vim.wait(500, function()
                return #picker.current_matches == 3
            end)

            -- Blink sorter: no frecency reorder, items in original order (or blink order)
            -- At minimum, item_b should NOT be boosted to first
            -- Original order is preserved for empty query
            assert.are.equal("item_a", picker.current_matches[1].text)
        end)

        it("does not reorder when no provider identity", function()
            frecency.record("test_noprov", "item_b")
            frecency.record("test_noprov", "item_b")

            picker = refer.pick({ "item_a", "item_b" }, function() end, {
                default_sorter = "lua",
                -- No frecency.provider set
            })

            vim.wait(500, function()
                return #picker.current_matches == 2
            end)

            -- No provider → no reorder, items in original order
            assert.are.equal("item_a", picker.current_matches[1].text)
            assert.are.equal("item_b", picker.current_matches[2].text)
        end)

        it("does not reorder when frecency.enabled is false", function()
            frecency.record("test_disabled", "item_b")
            frecency.record("test_disabled", "item_b")

            picker = refer.pick({ "item_a", "item_b" }, function() end, {
                default_sorter = "lua",
                frecency = { provider = "test_disabled", enabled = false },
            })

            vim.wait(500, function()
                return #picker.current_matches == 2
            end)

            -- Frecency disabled → no reorder
            assert.are.equal("item_a", picker.current_matches[1].text)
        end)
    end)

    describe("frecency action recording", function()
        local active_frecency_path

        local function setup_frecency_for_test()
            active_frecency_path = vim.fn.tempname() .. "_record_test.json"
            frecency.configure {
                db_path = active_frecency_path,
                buckets = false,
                neighborhood_size = 10,
            }
        end

        before_each(function()
            setup_frecency_for_test()
        end)

        after_each(function()
            if picker then
                picker:close()
                picker = nil
            end
            if active_frecency_path then
                vim.fn.delete(active_frecency_path, "rf")
                vim.fn.delete(vim.fn.fnamemodify(active_frecency_path, ":h"), "rf")
                active_frecency_path = nil
            end
            db._reset()
        end)

        it("select_entry records frecency before close", function()
            local selected
            picker = refer.pick({ "item_a", "item_b" }, function(sel)
                selected = sel
            end, {
                frecency = { provider = "test_record" },
            })

            vim.wait(500, function()
                return #picker.current_matches == 2
            end)

            picker.actions.select_entry()
            vim.wait(100)

            -- Verify frecency was recorded
            local scores = frecency.score("test_record", { "item_a" })
            assert.is_not_nil(scores["item_a"])
            assert.are.equal("item_a", selected)
        end)

        it("select_entry does not record when no provider", function()
            local selected
            picker = refer.pick({ "item_a" }, function(sel)
                selected = sel
            end)

            vim.wait(500, function()
                return #picker.current_matches == 1
            end)

            picker.actions.select_entry()
            vim.wait(100)

            -- No provider → no recording, db file should not exist
            assert.is_false(vim.fn.filereadable(active_frecency_path) == 1)
        end)

        it("select_entry does not record when frecency.enabled is false", function()
            picker = refer.pick({ "item_a" }, function() end, {
                frecency = { provider = "test_disabled", enabled = false },
            })

            vim.wait(500, function()
                return #picker.current_matches == 1
            end)

            picker.actions.select_entry()
            vim.wait(100)

            -- Frenecy disabled → no recording
            assert.is_false(vim.fn.filereadable(active_frecency_path) == 1)
        end)

        it("navigation actions do not record", function()
            picker = refer.pick({ "item_a", "item_b" }, function() end, {
                frecency = { provider = "test_nav" },
            })

            vim.wait(500, function()
                return #picker.current_matches == 2
            end)

            picker.actions.next_item()
            picker.actions.prev_item()
            picker.actions.toggle_mark()
            picker.actions.select_all()
            picker.actions.deselect_all()

            -- Navigation should not record
            assert.is_false(vim.fn.filereadable(active_frecency_path) == 1)
        end)

        it("edit_entry records frecency before close", function()
            picker = refer.pick({ "item_a" }, function() end, {
                frecency = { provider = "test_edit" },
            })
            vim.wait(500, function()
                return #picker.current_matches == 1
            end)
            picker.actions.edit_entry()
            vim.wait(100)
            local scores = frecency.score("test_edit", { "item_a" })
            assert.is_not_nil(scores["item_a"])
        end)

        it("open_marked records each marked item", function()
            picker = refer.pick({ "item_a", "item_b" }, function() end, {
                frecency = { provider = "test_marked" },
            })
            vim.wait(500, function()
                return #picker.current_matches == 2
            end)
            -- Mark both items
            picker.actions.toggle_mark()
            picker.actions.toggle_mark()
            vim.wait(50)
            picker.actions.open_marked()
            vim.wait(100)
            local scores = frecency.score("test_marked", { "item_a", "item_b" })
            assert.is_not_nil(scores["item_a"])
            assert.is_not_nil(scores["item_b"])
        end)

        it("select_input records when input matches existing item", function()
            picker = refer.pick({ "item_a", "item_b" }, function() end, {
                frecency = { provider = "test_input" },
            })
            vim.wait(500, function()
                return #picker.current_matches == 2
            end)
            -- Type the exact text of an item
            vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { "item_a" })
            picker:refresh()
            vim.wait(200)
            picker.actions.select_input()
            vim.wait(100)
            local scores = frecency.score("test_input", { "item_a" })
            assert.is_not_nil(scores["item_a"])
        end)

        it("global frecency.enabled = false disables reorder", function()
            frecency.configure { enabled = false }
            frecency.record("test_global_off", "item_b")
            frecency.record("test_global_off", "item_b")

            picker = refer.pick({ "item_a", "item_b" }, function() end, {
                default_sorter = "lua",
                frecency = { provider = "test_global_off" },
            })
            vim.wait(500, function()
                return #picker.current_matches == 2
            end)
            -- Globally disabled: no reorder, original order preserved
            assert.are.equal("item_a", picker.current_matches[1].text)

            -- Re-enable for subsequent tests
            frecency.configure { enabled = true }
        end)
    end)
end)
