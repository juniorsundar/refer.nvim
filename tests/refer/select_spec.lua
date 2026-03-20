local refer = require "refer"
local stub = require "luassert.stub"

describe("refer.select", function()
    local pick_stub

    before_each(function()
        pick_stub = stub(refer, "pick")
    end)

    after_each(function()
        pick_stub:revert()
    end)

    it("formats items and delegates to refer.pick", function()
        local items = {
            { name = "Option A", id = 1 },
            { name = "Option B", id = 2 },
        }
        local format_item = function(item)
            return item.name
        end

        local on_choice_called = false
        local choice_item, choice_idx

        refer.select(items, { format_item = format_item, prompt = "Test>" }, function(item, idx)
            on_choice_called = true
            choice_item = item
            choice_idx = idx
        end)

        assert.stub(pick_stub).was_called(1)
        local args = pick_stub.calls[1].refs
        local choices = args[1]
        local opts = args[3]

        assert.are.same(2, #choices)
        assert.are.same("Option A", choices[1].text)
        assert.are.same("Option B", choices[2].text)
        assert.are.same("Test>", opts.prompt)

        opts.on_select("Option B", choices[2].data)
        assert.is_true(on_choice_called)
        assert.are.same(items[2], choice_item)
        assert.are.same(2, choice_idx)
    end)

    it("handles duplicates by appending counter", function()
        local items = { "foo", "bar", "foo", "foo" }

        refer.select(items, {}, function() end)

        local args = pick_stub.calls[1].refs
        local choices = args[1]

        assert.are.same("foo", choices[1].text)
        assert.are.same("bar", choices[2].text)
        assert.are.same("foo (1)", choices[3].text)
        assert.are.same("foo (2)", choices[4].text)
    end)

    it("correctly maps duplicate selection back to original item index", function()
        local items = { "foo", "bar", "foo", "foo" }
        local captured_idx

        refer.select(items, {}, function(_, idx)
            captured_idx = idx
        end)

        local args = pick_stub.calls[1].refs
        local choices = args[1]
        local opts = args[3]

        opts.on_select("foo (2)", choices[4].data)

        assert.are.same(4, captured_idx)
    end)

    it("handles cancellation correctly", function()
        local on_choice_called = false
        local captured_item

        refer.select({ "a", "b" }, {}, function(item, idx)
            on_choice_called = true
            captured_item = item
        end)

        local opts = pick_stub.calls[1].refs[3]

        opts.on_close()

        assert.is_true(on_choice_called)
        assert.is_nil(captured_item)
    end)

    it("handles selection via CR keymap correctly", function()
        local on_choice_called = false

        refer.select({ "a", "b" }, {}, function(item, idx)
            on_choice_called = true
            if item == nil then
                error "Should not be called with nil if item selected"
            end
        end)

        local opts = pick_stub.calls[1].refs[3]
        local cr_handler = opts.keymaps["<CR>"]

        assert.is_not_nil(cr_handler)

        local select_entry_called = false
        local builtin = {
            picker = {
                current_matches = { { text = "a", data = {} }, { text = "b", data = {} } },
                selected_index = 2,
            },
            actions = {
                select_entry = function()
                    select_entry_called = true
                end,
            },
        }

        cr_handler(nil, builtin)

        assert.is_true(select_entry_called)

        opts.on_close()

        assert.is_false(on_choice_called)
    end)

    it("can setup global vim.ui.select", function()
        local original_select = vim.ui.select
        refer.setup_ui_select()
        assert.are.same(refer.select, vim.ui.select)

        vim.ui.select = original_select
    end)

    it("item.data carries original item and index without lookup table", function()
        local items = { { id = 10 }, { id = 20 }, { id = 30 } }

        refer.select(items, {
            format_item = function(x)
                return "item-" .. x.id
            end,
        }, function() end)

        local choices = pick_stub.calls[1].refs[1]

        assert.are.same(3, #choices)
        assert.are.same(items[1], choices[1].data.item)
        assert.are.same(1, choices[1].data.idx)
        assert.are.same(items[2], choices[2].data.item)
        assert.are.same(2, choices[2].data.idx)
        assert.are.same(items[3], choices[3].data.item)
        assert.are.same(3, choices[3].data.idx)
    end)
end)
