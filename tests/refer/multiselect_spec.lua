local refer = require "refer"
local Picker = require "refer.picker"

describe("refer multiselect mode", function()
    local picker
    local received

    after_each(function()
        local active = Picker.get_active()
        if active then
            active:close()
        end
    end)

    describe("select_marked action", function()
        before_each(function()
            received = nil
            picker = refer.pick({ "item1", "item2", "item3" }, function(selection)
                received = selection
            end, { multiselect = true })
        end)

        it("delivers marked entries as a list in original item order", function()
            -- mark out of order: item3 first, then item1
            picker.current_matches = picker.items_or_provider
            picker.selected_index = 3
            picker.actions.toggle_mark()
            picker.selected_index = 1
            picker.actions.toggle_mark()

            picker.actions.select_marked()

            assert.is_same({ "item1", "item3" }, received)
        end)

        it("delivers marks that are filtered out of the visible matches", function()
            picker.current_matches = picker.items_or_provider
            picker.selected_index = 1
            picker.actions.toggle_mark() -- marks "item1"

            -- simulate a query that filters item1 away
            picker.current_matches = { { text = "item2" }, { text = "item3" } }
            picker.selected_index = 1

            picker.actions.select_marked()

            assert.is_same({ "item1" }, received)
        end)

        it("falls back to the highlighted entry as a one-item list when nothing is marked", function()
            picker.current_matches = picker.items_or_provider
            picker.selected_index = 2

            picker.actions.select_marked()

            assert.is_same({ "item2" }, received)
        end)

        it("is a no-op with no matches and no marks; the picker stays open", function()
            picker.current_matches = {}
            picker.selected_index = 1

            picker.actions.select_marked()

            assert.is_nil(received)
            assert.is_true(vim.api.nvim_win_is_valid(picker.ui.input_win))
            assert.equals(picker, Picker.get_active())
        end)

        it("closes the picker after delivering", function()
            picker.current_matches = picker.items_or_provider
            picker.actions.select_marked()

            assert.is_same({ "item1" }, received)
            assert.is_false(vim.api.nvim_win_is_valid(picker.ui.input_win))
            assert.is_nil(Picker.get_active())
        end)

        it("delivers exactly once even if on_select is invoked repeatedly by the caller flow", function()
            -- on_select fires once per action; guard is on the glue side, but
            -- the action must not double-deliver for a single invocation.
            local calls = 0
            picker.on_select = function()
                calls = calls + 1
            end
            picker.current_matches = picker.items_or_provider
            picker.selected_index = 1
            picker.actions.toggle_mark()
            picker.actions.select_marked()

            assert.equals(1, calls)
        end)

        it("marks all visible matches with select_all and delivers them in item order", function()
            picker.current_matches = { { text = "item2" }, { text = "item3" } }
            picker.selected_index = 1

            picker.actions.select_all()
            picker.actions.select_marked()

            assert.is_same({ "item2", "item3" }, received)
        end)
    end)

    describe("keymap wiring", function()
        it("binds Tab/CR/<C-Space> for marking in multiselect mode", function()
            picker = refer.pick({ "a" }, function() end, { multiselect = true })

            assert.equals("toggle_mark", picker.opts.keymaps["<Tab>"].action)
            assert.equals("select_marked", picker.opts.keymaps["<CR>"].action)
            assert.equals("select_all", picker.opts.keymaps["<C-Space>"].action)

            -- and the maps are actually applied to the input buffer
            local bound = {}
            for _, map in ipairs(vim.api.nvim_buf_get_keymap(picker.input_buf, "i")) do
                bound[map.lhs] = true
            end
            assert.is_true(bound["<Tab>"])
            assert.is_true(bound["<CR>"])
            assert.is_true(bound["<C-Space>"])
        end)

        it("respects user keymaps over the multiselect defaults", function()
            picker = refer.pick({ "a" }, function() end, {
                multiselect = true,
                keymaps = {
                    ["<CR>"] = { action = "select_entry" },
                },
            })

            assert.equals("select_entry", picker.opts.keymaps["<CR>"].action)
            assert.equals("toggle_mark", picker.opts.keymaps["<Tab>"].action)
        end)

        it("leaves the default keymaps untouched without multiselect", function()
            picker = refer.pick({ "a" }, function() end)

            assert.equals("complete_selection", picker.opts.keymaps["<Tab>"].action)
            assert.equals("select_input", picker.opts.keymaps["<CR>"].action)
            assert.is_nil(picker.opts.keymaps["<C-Space>"])

            -- and the legacy single-entry contract is unchanged
            local received_single
            picker.current_matches = { { text = "only" } }
            picker.selected_index = 1
            picker.on_select = function(sel)
                received_single = sel
            end
            picker.actions.select_entry()
            assert.equals("only", received_single)
        end)
    end)

    describe("abort", function()
        it("fires on_close without delivering a selection", function()
            local closed = false
            picker = refer.pick({ "a" }, function() end, {
                multiselect = true,
                on_close = function()
                    closed = true
                end,
            })

            picker.actions.close()

            assert.is_true(closed)
        end)

        it("fires on_close before on_select when choosing (order glue relies on)", function()
            -- Selection actions call picker:close() first and then on_select,
            -- so on_close fires BEFORE on_select within the same tick. Callers
            -- that treat on_close as "aborted" must defer that decision to a
            -- later tick (see the neogit glue in the user config).
            local order = {}
            picker = refer.pick({ "a", "b" }, function()
                order[#order + 1] = "on_select"
            end, {
                multiselect = true,
                on_close = function()
                    order[#order + 1] = "on_close"
                end,
            })

            picker.current_matches = picker.items_or_provider
            picker.selected_index = 1
            picker.actions.toggle_mark()
            picker.actions.select_marked()

            assert.is_same({ "on_close", "on_select" }, order)
        end)
    end)
end)
