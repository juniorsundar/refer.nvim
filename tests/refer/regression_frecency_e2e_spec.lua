local refer = require "refer"
local frecency = require "refer.frecency"
local db = require "refer.frecency.db"

describe("Frecency regression end-to-end tracer", function()
    local picker
    local active_frecency_path

    local function setup_frecency()
        active_frecency_path = vim.fn.tempname() .. "_e2e_test.json"
        frecency.configure {
            enabled = true,
            db_path = active_frecency_path,
            buckets = false,
            neighborhood_size = 10,
        }
    end

    before_each(function()
        setup_frecency()
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

    it("select item → reopen with lua sorter → item ranked higher", function()
        -- First picker: select "item_b"
        picker = refer.pick({ "item_a", "item_b", "item_c" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "e2e_test" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- Select item_b (index 2)
        picker.selected_index = 2
        picker.actions.select_entry()
        vim.wait(100)
        picker = nil

        -- Second picker: reopen, item_b should be first
        picker = refer.pick({ "item_a", "item_b", "item_c" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "e2e_test" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- item_b should now rank higher (first for empty query)
        assert.are.equal("item_b", picker.current_matches[1].text)
    end)

    it("empty query shows frecent items first", function()
        -- Record frecency for items
        frecency.record("e2e_empty", "item_c")
        frecency.record("e2e_empty", "item_c")
        frecency.record("e2e_empty", "item_c")
        frecency.record("e2e_empty", "item_a")

        picker = refer.pick({ "item_a", "item_b", "item_c" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "e2e_empty" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- Empty query: item_c (3x) should be first, item_a (1x) second, item_b (0x) last
        assert.are.equal("item_c", picker.current_matches[1].text)
        assert.are.equal("item_a", picker.current_matches[2].text)
        assert.are.equal("item_b", picker.current_matches[3].text)
    end)

    it("cycling sorter away from lua disables reorder", function()
        frecency.record("e2e_cycle", "item_b")
        frecency.record("e2e_cycle", "item_b")

        picker = refer.pick({ "item_a", "item_b" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "e2e_cycle" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        -- With lua sorter: item_b first
        assert.are.equal("item_b", picker.current_matches[1].text)

        -- Cycle to blink (non-lua) sorter
        picker.actions.cycle_sorter()
        vim.wait(200)

        -- With blink sorter: no frecency reorder → original order
        assert.are.equal("item_a", picker.current_matches[1].text)

        -- Cycle back to lua
        picker.actions.cycle_sorter()
        vim.wait(100)
        picker.actions.cycle_sorter()
        vim.wait(100)
        picker.actions.cycle_sorter()
        vim.wait(200)

        -- Back to lua: frecency reorder active again
        assert.are.equal("item_b", picker.current_matches[1].text)
    end)

    it("duplicate text items with different filepaths remain distinct", function()
        local items = {
            { text = "duplicate", data = { filename = "/path/a.lua" } },
            { text = "duplicate", data = { filename = "/path/b.lua" } },
            { text = "unique", data = { filename = "/path/c.lua" } },
        }

        -- Record frecency for item with filepath strategy
        frecency.record("e2e_dup", vim.fn.fnamemodify("/path/b.lua", ":p"))
        frecency.record("e2e_dup", vim.fn.fnamemodify("/path/b.lua", ":p"))

        picker = refer.pick(items, function() end, {
            default_sorter = "lua",
            frecency = { provider = "e2e_dup", key_strategy = "filepath" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- All 3 items should be present (no deduplication)
        assert.are.equal(3, #picker.current_matches)

        -- The frecent duplicate (b.lua) should come first
        assert.are.equal("/path/b.lua", picker.current_matches[1].data.filename)
    end)

    it("no-op mode does not crash the picker", function()
        -- Create a path that will fail to write (directory already exists at that path)
        local bad_path = active_frecency_path .. "_dir"
        vim.fn.mkdir(bad_path, "p")
        frecency.configure { db_path = bad_path }

        -- Trigger no-op mode by attempting a write that fails
        frecency.record("e2e_noop", "item")
        assert.is_false(frecency.is_available())

        -- Picker should still work normally without frecency
        picker = refer.pick({ "item_a", "item_b" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "e2e_noop" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        -- Items should be in original order (no reorder since no-op)
        assert.are.equal("item_a", picker.current_matches[1].text)
        assert.are.equal("item_b", picker.current_matches[2].text)

        -- Selecting should not crash
        picker.actions.select_entry()
        vim.wait(100)
        picker = nil

        -- Clean up the bad directory
        vim.fn.delete(bad_path, "rf")
    end)

    it("global disable takes precedence over corrupt store", function()
        -- Write corrupt JSON
        vim.fn.mkdir(vim.fn.fnamemodify(active_frecency_path, ":h"), "p")
        vim.fn.writefile({ "{not json" }, active_frecency_path)

        -- Globally disable frecency
        frecency.configure { enabled = false, db_path = active_frecency_path }

        -- Status should show disabled, not no-op
        local s = frecency.status()
        assert.is_false(s.enabled)
        assert.is_false(s.active)
        assert.is_false(s.no_op)
        assert.are.equal("disabled by config", s.reason)

        -- record() should be a no-op without touching store
        frecency.record("p", "key")
        -- File should still be corrupt (untouched)
        assert.are.same({ "{not json" }, vim.fn.readfile(active_frecency_path))

        -- score() should return empty (not trigger no-op from corrupt file)
        local scores = frecency.score("p", { "key" })
        assert.are.same({}, scores)
    end)

    it("picker survives when frecency is globally disabled", function()
        frecency.configure { enabled = false, db_path = active_frecency_path }

        picker = refer.pick({ "item_a", "item_b" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "e2e_disabled" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        -- Items should be in original order (no reorder)
        assert.are.equal("item_a", picker.current_matches[1].text)
        assert.are.equal("item_b", picker.current_matches[2].text)

        -- Selecting should not crash
        picker.actions.select_entry()
        vim.wait(100)
        picker = nil
    end)
end)
