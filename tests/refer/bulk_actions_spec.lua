local refer = require "refer"
local Picker = require "refer.picker"

describe("refer.bulk_actions", function()
    local picker

    before_each(function()
        picker = refer.pick({ "item1", "item2", "item3" }, function() end)
        picker.current_matches = { "item1", "item2", "item3" }
        picker.ui = {
            render = function() end,
            close = function() end,
            create_windows = function()
                return 1, 1
            end,
            update_input = function() end,
        }
    end)

    after_each(function()
        if picker then
            picker:close()
        end
    end)

    it("select_all marks all visible items", function()
        picker.actions.select_all()

        assert.is_true(picker.marked["item1"])
        assert.is_true(picker.marked["item2"])
        assert.is_true(picker.marked["item3"])
    end)

    it("deselect_all clears all marks", function()
        picker.marked = { ["item1"] = true, ["item3"] = true }

        picker.actions.deselect_all()

        assert.is_nil(picker.marked["item1"])
        assert.is_nil(picker.marked["item2"])
        assert.is_nil(picker.marked["item3"])
        local count = 0
        for _ in pairs(picker.marked) do
            count = count + 1
        end
        assert.are.same(0, count)
    end)

    it("toggle_all inverts marks for visible items", function()
        picker.marked = { ["item1"] = true }

        picker.actions.toggle_all()

        assert.is_false(picker.marked["item1"])
        assert.is_true(picker.marked["item2"])
        assert.is_true(picker.marked["item3"])
    end)

    it("toggle_all works with a subset of visible items", function()
        picker.current_matches = { "item2", "item3" }
        picker.marked = { ["item1"] = true, ["item2"] = true }

        picker.actions.toggle_all()

        assert.is_true(picker.marked["item1"])

        assert.is_false(picker.marked["item2"])

        assert.is_true(picker.marked["item3"])
    end)
end)
