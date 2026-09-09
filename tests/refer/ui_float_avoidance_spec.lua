local UI = require "refer.ui"
local refer = require "refer"
local Picker = require "refer.picker"

---Create a floating window with a scratch buffer
local function make_float(config)
    local buf = vim.api.nvim_create_buf(false, true)
    return vim.api.nvim_open_win(buf, false, vim.tbl_extend("force", { style = "minimal" }, config))
end

---Popup-like float: SW-anchored at the bottom, occupying most of the
---screen (editor grid is 40 rows: rows [0, 39), cmdheight = 1, area_bottom = 39)
local function make_popup()
    return make_float {
        relative = "editor",
        anchor = "SW",
        row = 38,
        col = 0,
        width = 120,
        height = 36,
        zindex = 50,
        border = { "─", "", "", "", "", "", "", "" },
        title = " Log ",
        title_pos = "center",
    }
end

local function config_of(win)
    return vim.api.nvim_win_get_config(win)
end

local function count_stash(ui)
    local n = 0
    for _ in pairs(ui.float_stash) do
        n = n + 1
    end
    return n
end

describe("refer.ui float avoidance", function()
    local ui

    before_each(function()
        vim.o.lines = 40
        vim.o.columns = 120
        vim.o.cmdheight = 1
        vim.o.laststatus = 2
        ui = UI.new("> ", {})
    end)

    after_each(function()
        local picker = Picker.get_active()
        if picker then
            picker:close()
        end
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
            if ok and cfg.relative ~= "" then
                local buf = vim.api.nvim_win_get_buf(win)
                pcall(vim.api.nvim_win_close, win, true)
                -- Also delete the scratch buffer: leftover [No Name] buffers
                -- accumulate swap-file names and can exhaust them suite-wide
                -- (E303: Unable to open swap file).
                if vim.api.nvim_buf_is_valid(buf) then
                    pcall(vim.api.nvim_buf_delete, buf, { force = true })
                end
            end
        end
    end)

    describe("_reserve_bottom_space", function()
        it("shrinks and raises an SW-anchored float overlapping the strip", function()
            local popup = make_popup()

            ui:_reserve_bottom_space(6)

            local c = config_of(popup)
            -- strip_top = 39 - 6 = 33; new bottom edge = 32
            assert.equals(32, c.row)
            assert.equals(30, c.height)
            -- untouched fields
            assert.equals("SW", c.anchor)
            assert.equals(0, c.col)
            assert.equals(120, c.width)
            assert.equals(50, c.zindex)
        end)

        it("trims an NW-anchored float that reaches into the strip", function()
            local float = make_float { relative = "editor", row = 30, col = 0, width = 40, height = 15 }

            ui:_reserve_bottom_space(6)

            local c = config_of(float)
            -- keeps its top edge, shrinks so the bottom edge clears strip_top (33)
            assert.equals(30, c.row)
            assert.equals(3, c.height)
        end)

        it("leaves a float whose bottom edge exactly clears the strip untouched", function()
            -- strip_top = 33; bottom edge 32 == strip_top - 1 -> no overlap
            local float = make_float { relative = "editor", anchor = "SW", row = 32, col = 0, width = 10, height = 8 }

            ui:_reserve_bottom_space(6)

            local c = config_of(float)
            assert.equals(32, c.row)
            assert.equals(8, c.height)
            assert.equals(0, count_stash(ui))
        end)

        it("adjusts a float whose bottom edge is exactly at the strip top", function()
            local float = make_float { relative = "editor", anchor = "SW", row = 33, col = 0, width = 10, height = 8 }

            ui:_reserve_bottom_space(6)

            local c = config_of(float)
            assert.equals(32, c.row)
            assert.equals(7, c.height)
        end)

        it("ignores window-relative floats", function()
            local base = vim.api.nvim_get_current_win()
            local float =
                make_float { relative = "win", win = base, row = 37, col = 0, width = 120, height = 1, zindex = 10 }

            ui:_reserve_bottom_space(6)

            local c = config_of(float)
            assert.equals(37, c.row)
            assert.equals(1, c.height)
            assert.equals(0, count_stash(ui))
        end)

        it("recomputes from the original geometry so adjustments do not compound", function()
            local popup = make_popup()

            ui:_reserve_bottom_space(6)
            ui:_reserve_bottom_space(10)

            -- from original row=38/h=36: strip_top = 29 -> row=28, height=26
            -- (compounding from 32/30 would wrongly give height=24)
            local c = config_of(popup)
            assert.equals(28, c.row)
            assert.equals(26, c.height)
        end)

        it("never shrinks the reservation on smaller requests", function()
            local popup = make_popup()

            ui:_reserve_bottom_space(10)
            ui:_reserve_bottom_space(6)

            local c = config_of(popup)
            assert.equals(28, c.row)
            assert.equals(26, c.height)
        end)

        it("clamps oversized requests and leaves floats that cannot fit", function()
            local popup = make_popup()

            ui:_reserve_bottom_space(45) -- clamps to area_bottom - 2 = 37

            -- strip_top = 2 -> popup would need height -1: left alone
            local c = config_of(popup)
            assert.equals(38, c.row)
            assert.equals(36, c.height)
        end)

        it("can be disabled via ui.avoid_floats = false", function()
            ui = UI.new("> ", { ui = { avoid_floats = false } })
            local popup = make_popup()

            ui:_reserve_bottom_space(6)

            local c = config_of(popup)
            assert.equals(38, c.row)
            assert.equals(36, c.height)
            assert.equals(0, count_stash(ui))
        end)
    end)

    describe("_restore_floats", function()
        it("restores the original geometry exactly", function()
            local popup = make_popup()

            ui:_reserve_bottom_space(6)
            ui:_reserve_bottom_space(10)
            ui:_restore_floats()

            local c = config_of(popup)
            assert.equals(38, c.row)
            assert.equals(36, c.height)
            assert.equals("SW", c.anchor)
            assert.equals(0, c.col)
            assert.equals(120, c.width)
            assert.equals(50, c.zindex)
            assert.equals("─", c.border[1])
            assert.equals(" Log ", c.title[1][1])
        end)

        it("clears the stash so a repeated restore is a no-op", function()
            local popup = make_popup()
            ui:_reserve_bottom_space(6)
            ui:_restore_floats()
            ui:_restore_floats()

            assert.equals(0, count_stash(ui))
            local c = config_of(popup)
            assert.equals(38, c.row)
            assert.equals(36, c.height)
        end)

        it("drops stash entries for floats closed while the picker is open", function()
            local popup = make_popup()
            ui:_reserve_bottom_space(6)

            vim.api.nvim_win_close(popup, true)
            ui:_restore_floats()

            assert.equals(0, count_stash(ui))
        end)

        it("allows a fresh reservation after restore", function()
            local popup = make_popup()
            ui:_reserve_bottom_space(10)
            ui:_restore_floats()

            ui:_reserve_bottom_space(6)

            local c = config_of(popup)
            assert.equals(32, c.row)
            assert.equals(30, c.height)
        end)
    end)

    describe("picker integration", function()
        it("refer.pick shrinks an overlapping popup and restores it on close", function()
            local popup = make_popup()

            local picker = refer.pick({ "a", "b", "c" }, function() end)

            -- 3 results + 1 input + 2 split statuslines -> reserve 6
            local c = config_of(popup)
            assert.equals(32, c.row)
            assert.equals(30, c.height)

            -- the picker windows actually exist
            assert.is_true(vim.api.nvim_win_is_valid(picker.ui.input_win))
            assert.is_true(vim.api.nvim_win_is_valid(picker.ui.results_win))

            -- growing the match list grows the reservation
            picker.current_matches = {}
            for i = 1, 20 do
                picker.current_matches[i] = "match" .. i
            end
            picker:render()

            -- 16 results + 1 input + 2 statuslines -> reserve 19; strip_top = 20
            c = config_of(popup)
            assert.equals(19, c.row)
            assert.equals(17, c.height)

            picker:close()

            c = config_of(popup)
            assert.equals(38, c.row)
            assert.equals(36, c.height)
            assert.is_false(vim.api.nvim_win_is_valid(picker.ui.input_win))
        end)

        it("does not touch floats that do not overlap the picker", function()
            local float = make_float { relative = "editor", row = 0, col = 0, width = 40, height = 5 }

            local picker = refer.pick({ "a", "b", "c" }, function() end)

            local c = config_of(float)
            assert.equals(0, c.row)
            assert.equals(5, c.height)
            assert.equals(0, count_stash(picker.ui))

            picker:close()

            c = config_of(float)
            assert.equals(0, c.row)
            assert.equals(5, c.height)
        end)
    end)
end)
