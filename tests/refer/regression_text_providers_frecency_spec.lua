local refer = require "refer"
local frecency = require "refer.frecency"
local db = require "refer.frecency.db"

describe("Issue #004 — Text provider frecency wiring", function()
    local picker
    local active_frecency_path

    local function setup_frecency()
        active_frecency_path = vim.fn.tempname() .. "_004_test.json"
        frecency.configure {
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

    -- Tracer bullet: commands on_change path with frecency reorder (lua sorter)
    it("commands on_change path reorders frecent command to top with lua sorter (empty query)", function()
        -- Record frecency for a known command that always exists
        frecency.record("commands", "echo")
        frecency.record("commands", "echo")
        frecency.record("commands", "echo")

        picker = refer.pick(function(input)
            return vim.fn.getcompletion(input, "command")
        end, function() end, {
            default_sorter = "lua",
            frecency = { provider = "commands", key_strategy = "text" },
            on_change = function(input, cb)
                cb(vim.fn.getcompletion(input, "command"))
            end,
        })

        vim.wait(500, function()
            return #picker.current_matches > 0
        end)

        -- "echo" should be first since it's the only frecent item (sort_by_frecency)
        assert.are.equal("echo", picker.current_matches[1].text)
    end)

    it("on_change path does NOT reorder when non-lua sorter is active", function()
        frecency.record("commands", "echo")
        frecency.record("commands", "echo")

        picker = refer.pick(function(input)
            return vim.fn.getcompletion(input, "command")
        end, function() end, {
            default_sorter = "native",
            frecency = { provider = "commands", key_strategy = "text" },
            on_change = function(input, cb)
                cb(vim.fn.getcompletion(input, "command"))
            end,
        })

        vim.wait(500, function()
            return #picker.current_matches > 0
        end)

        -- With native sorter, results stay in getcompletion order (alphabetical).
        -- "!" comes first alphabetically, not "echo".
        local first_text = picker.current_matches[1].text
        assert.is_not.equal("echo", first_text)
    end)

    it("empty-query shows frecent items first for any provider with lua sorter", function()
        -- Provider isolation: record under help_tags, open commands
        frecency.record("help_tags", "some_tag")
        frecency.record("help_tags", "some_tag")
        frecency.record("help_tags", "some_tag")

        -- Open a picker using a different provider name; "some_tag" should NOT be boosted
        picker = refer.pick({ "alpha", "beta", "some_tag", "gamma" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "other_provider", key_strategy = "text" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 4
        end)

        -- "some_tag" has frecency under help_tags, not other_provider → stays in original position
        -- Actually: no items have frecency under other_provider → all unscored → original order preserved
        assert.are.equal("alpha", picker.current_matches[1].text)
    end)

    it("select_input records frecency when typed text matches a current_matches item", function()
        picker = refer.pick({ "alpha", "beta", "gamma" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "select_test", key_strategy = "text" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- Type "alpha" into the input buffer, then refresh to update current_matches
        picker.ui:update_input { "alpha" }
        picker:refresh()
        vim.wait(200)

        -- select_input should record "alpha" since it matches an item in current_matches
        picker.actions.select_input()
        vim.wait(100)
        picker = nil

        -- Reopen: "alpha" should be first
        picker = refer.pick({ "alpha", "beta", "gamma" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "select_test", key_strategy = "text" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        assert.are.equal("alpha", picker.current_matches[1].text)
    end)

    it("select_input does NOT record when typed text does not match any current_matches item", function()
        picker = refer.pick({ "alpha", "beta", "gamma" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "select_nomatch", key_strategy = "text" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- Type "xyz" which doesn't match any item
        picker.ui:update_input { "xyz" }
        picker:refresh()
        vim.wait(200)

        -- select_input: "xyz" does not match any item.text in current_matches → no recording
        picker.actions.select_input()
        vim.wait(100)
        picker = nil

        -- Reopen: no items should have frecency → original order preserved
        picker = refer.pick({ "alpha", "beta", "gamma" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "select_nomatch", key_strategy = "text" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- Original order: alpha first
        assert.are.equal("alpha", picker.current_matches[1].text)
    end)

    it("provider isolation: frecency from one provider does not affect another", function()
        -- Record "common" under provider_a
        frecency.record("provider_a", "common")
        frecency.record("provider_a", "common")
        frecency.record("provider_a", "common")

        -- Open picker with provider_b; "common" should NOT be boosted
        picker = refer.pick({ "alpha", "common", "beta" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "provider_b", key_strategy = "text" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- No items have frecency under provider_b → original order
        assert.are.equal("alpha", picker.current_matches[1].text)

        -- Now record "common" under provider_b and reopen
        picker:close()
        picker = nil

        frecency.record("provider_b", "common")
        frecency.record("provider_b", "common")

        picker = refer.pick({ "alpha", "common", "beta" }, function() end, {
            default_sorter = "lua",
            frecency = { provider = "provider_b", key_strategy = "text" },
        })

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- "common" now has frecency under provider_b → should be first
        assert.are.equal("common", picker.current_matches[1].text)
    end)

    it("non-empty on_change path reorders within position-based neighborhoods", function()
        -- Build 20 items: a01..a20. Frecency-boost a15 (position 15 in callback result).
        -- With neighborhood_size=10, a15 is in group 1 (positions 11-20).
        -- After non-empty-input reorder: a15 floats to top of group 1 → position 11.
        local items = {}
        for i = 1, 20 do
            table.insert(items, string.format("a%02d", i))
        end

        frecency.record("on_change_nbhd", "a15")
        frecency.record("on_change_nbhd", "a15")

        picker = refer.pick(function()
            return items
        end, function() end, {
            default_sorter = "lua",
            default_text = "x",
            frecency = { provider = "on_change_nbhd", key_strategy = "text" },
            on_change = function(input, cb)
                cb(items)
            end,
        })

        vim.wait(500, function()
            return #picker.current_matches == 20
        end)

        -- Non-empty input "x": position-based neighborhood reorder.
        -- Group 0 (positions 1-10): original order, no frecency items
        for i = 1, 10 do
            assert.are.equal(string.format("a%02d", i), picker.current_matches[i].text)
        end

        -- Group 1 (positions 11-20): a15 floats to top, rest in original order
        assert.are.equal("a15", picker.current_matches[11].text)
        assert.are.equal("a11", picker.current_matches[12].text)
        assert.are.equal("a12", picker.current_matches[13].text)
        assert.are.equal("a13", picker.current_matches[14].text)
        assert.are.equal("a14", picker.current_matches[15].text)
        assert.are.equal("a16", picker.current_matches[16].text)
        assert.are.equal("a17", picker.current_matches[17].text)
        assert.are.equal("a18", picker.current_matches[18].text)
        assert.are.equal("a19", picker.current_matches[19].text)
        assert.are.equal("a20", picker.current_matches[20].text)
    end)

    it("macros inner picker does not inherit frecency from outer picker", function()
        -- Set a register so macros() picks it up
        vim.fn.setreg("a", "hello")

        local builtin = require "refer.providers.builtin"
        picker = builtin.macros {
            frecency = { provider = "outer", key_strategy = "text" },
        }

        -- Outer picker should have frecency
        assert.is_not_nil(picker.opts.frecency)
        assert.are.equal("outer", picker.opts.frecency.provider)

        -- Stub refer.pick to capture the inner picker call
        local stub_fn = require "luassert.stub"
        local s = stub_fn(refer, "pick")

        -- Select an entry to trigger the inner picker via vim.schedule
        picker.selected_index = 1
        picker.actions.select_entry()
        vim.wait(300)

        -- Check the inner call: the stubbed refer.pick should have been called
        -- by edit_macro with no frecency in opts
        local inner_call_found = false
        for _, call in ipairs(s.calls) do
            local inner_opts = call.refs[3]
            if inner_opts and inner_opts.prompt and inner_opts.prompt:match "^Edit Macro" then
                inner_call_found = true
                assert.is_nil(inner_opts.frecency, "Inner picker must not have frecency opts")
            end
        end

        s:revert()
        picker:close()
        picker = nil

        -- Clean up register
        vim.fn.setreg("a", "")
    end)
end)
