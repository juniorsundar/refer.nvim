local refer = require "refer"
local builtin = require "refer.providers.builtin"
local util = require "refer.util"

describe("builtin.buffers", function()
    local picker
    local tmpdir = vim.fn.tempname()

    before_each(function()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        if picker then
            picker:close()
            picker = nil
        end
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end
        vim.fn.delete(tmpdir, "rf")
    end)

    it("lists currently listed buffers", function()
        local file1 = tmpdir .. "/file1.lua"
        local file2 = tmpdir .. "/file2.lua"
        local f1 = io.open(file1, "w")
        f1:write "content1\n"
        f1:close()
        local f2 = io.open(file2, "w")
        f2:write "content2\n"
        f2:close()

        vim.cmd("edit " .. vim.fn.fnameescape(file1))
        vim.cmd("edit " .. vim.fn.fnameescape(file2))

        picker = builtin.buffers()

        local found_file1 = false
        local found_file2 = false
        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("file1.lua", 1, true) then
                found_file1 = true
            end
            if text:find("file2.lua", 1, true) then
                found_file2 = true
            end
        end

        assert.is_true(found_file1)
        assert.is_true(found_file2)
    end)

    it("formats entries as bufnr: path:lnum:col", function()
        local file = tmpdir .. "/formatted.lua"
        local f = io.open(file, "w")
        f:write "line\n"
        f:close()

        vim.cmd("edit " .. vim.fn.fnameescape(file))

        picker = builtin.buffers()

        local found = false
        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("formatted.lua", 1, true) then
                assert.is_truthy(text:match "^%d+: .+:%d+:%d+$")
                found = true
                break
            end
        end
        assert.is_true(found)
    end)

    it("clamps a stale terminal-buffer cursor location when selected", function()
        vim.cmd "terminal"
        local terminal_buf = vim.api.nvim_get_current_buf()
        local channel = vim.bo[terminal_buf].channel

        vim.api.nvim_chan_send(channel, "for i in $(seq 1 80); do echo line$i; done\n")
        assert.is_true(vim.wait(1500, function()
            return vim.api.nvim_buf_line_count(terminal_buf) >= 80
        end))

        local terminal_name = vim.api.nvim_buf_get_name(terminal_buf)
        vim.cmd "enew"

        picker = refer.pick(
            {
                {
                    text = "terminal",
                    data = { filename = terminal_name, lnum = 50, col = 1 },
                },
            },
            util.jump_to_location,
            {
                available_sorters = { "lua" },
                default_sorter = "lua",
                preview = { enabled = false },
            }
        )
        picker.current_matches = picker.items_or_provider

        vim.api.nvim_chan_send(channel, "clear\n")
        assert.is_true(vim.wait(1500, function()
            return vim.api.nvim_buf_line_count(terminal_buf) < 50
        end))

        local ok, err = pcall(picker.actions.select_entry)
        picker = nil
        assert.is_true(ok, err)

        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.are.same(vim.api.nvim_buf_line_count(terminal_buf), cursor[1])
    end)

    it("skips unlisted buffers", function()
        local file = tmpdir .. "/unlisted.lua"
        local f = io.open(file, "w")
        f:write "content\n"
        f:close()

        vim.cmd("edit " .. vim.fn.fnameescape(file))
        local bufnr = vim.fn.bufnr(file)
        vim.bo[bufnr].buflisted = false

        picker = builtin.buffers()

        local found = false
        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("unlisted.lua", 1, true) then
                found = true
                break
            end
        end
        assert.is_false(found)
    end)

    it("removes deleted buffer from picker list when <C-x> is pressed", function()
        local file1 = tmpdir .. "/file1.lua"
        local file2 = tmpdir .. "/file2.lua"
        local f1 = io.open(file1, "w")
        f1:write "content1\n"
        f1:close()
        local f2 = io.open(file2, "w")
        f2:write "content2\n"
        f2:close()

        vim.cmd("edit " .. vim.fn.fnameescape(file1))
        vim.cmd("edit " .. vim.fn.fnameescape(file2))

        picker = builtin.buffers()

        local count_before = #picker.items_or_provider
        assert.is_true(count_before >= 2)

        local picker_obj = picker
        local buf_to_delete = vim.fn.bufnr(file1)

        local item_to_delete = nil
        local delete_index = 0
        for i, item in ipairs(picker_obj.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("file1.lua", 1, true) then
                item_to_delete = type(item) == "table" and item or { text = item }
                delete_index = i
                break
            end
        end

        assert.is_not_nil(item_to_delete)

        local builtin = {
            picker = picker_obj,
            actions = picker_obj.actions,
            parameters = { original_win = vim.api.nvim_get_current_win() },
            marked = {},
        }

        local keymap_handler = picker_obj.opts.keymaps["<C-x>"]
        assert.is_not_nil(keymap_handler)
        assert.is_true(type(keymap_handler) == "function")
        keymap_handler(item_to_delete, builtin)

        assert.is_false(vim.api.nvim_buf_is_valid(buf_to_delete))

        local found_deleted = false
        for _, item in ipairs(picker_obj.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("file1.lua", 1, true) then
                found_deleted = true
                break
            end
        end
        assert.is_false(found_deleted)
    end)

    it("removes all marked buffers from picker list when <C-x> is pressed", function()
        local file1 = tmpdir .. "/marked1.lua"
        local file2 = tmpdir .. "/marked2.lua"
        local file3 = tmpdir .. "/kept.lua"
        local files = {
            { file1, "content1\n" },
            { file2, "content2\n" },
            { file3, "content3\n" },
        }

        for _, spec in ipairs(files) do
            local f = io.open(spec[1], "w")
            f:write(spec[2])
            f:close()
            vim.cmd("edit " .. vim.fn.fnameescape(spec[1]))
        end

        picker = builtin.buffers()

        local item1, item2, item3
        local buf1 = vim.fn.bufnr(file1)
        local buf2 = vim.fn.bufnr(file2)
        local buf3 = vim.fn.bufnr(file3)

        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("marked1.lua", 1, true) then
                item1 = type(item) == "table" and item or { text = item }
            elseif text:find("marked2.lua", 1, true) then
                item2 = type(item) == "table" and item or { text = item }
            elseif text:find("kept.lua", 1, true) then
                item3 = type(item) == "table" and item or { text = item }
            end
        end

        assert.is_not_nil(item1)
        assert.is_not_nil(item2)
        assert.is_not_nil(item3)

        picker.marked[item1.text] = true
        picker.marked[item2.text] = true

        local builtin_ctx = {
            picker = picker,
            actions = picker.actions,
            parameters = { original_win = vim.api.nvim_get_current_win() },
            marked = picker.marked,
        }

        local keymap_handler = picker.opts.keymaps["<C-x>"]
        assert.is_true(type(keymap_handler) == "function")
        keymap_handler(item1, builtin_ctx)

        assert.is_false(vim.api.nvim_buf_is_valid(buf1))
        assert.is_false(vim.api.nvim_buf_is_valid(buf2))
        assert.is_true(vim.api.nvim_buf_is_valid(buf3))

        local found_marked1 = false
        local found_marked2 = false
        local found_kept = false
        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("marked1.lua", 1, true) then
                found_marked1 = true
            end
            if text:find("marked2.lua", 1, true) then
                found_marked2 = true
            end
            if text:find("kept.lua", 1, true) then
                found_kept = true
            end
        end

        assert.is_false(found_marked1)
        assert.is_false(found_marked2)
        assert.is_true(found_kept)
    end)
end)

describe("builtin.old_files", function()
    local picker
    local tmpdir = vim.fn.tempname()

    before_each(function()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        if picker then
            picker:close()
            picker = nil
        end
        vim.fn.delete(tmpdir, "rf")
    end)

    it("lists readable files from v:oldfiles", function()
        local file = tmpdir .. "/old.lua"
        local f = io.open(file, "w")
        f:write "old content\n"
        f:close()

        vim.v.oldfiles = { file }

        picker = builtin.old_files()

        assert.is_true(#picker.items_or_provider >= 1)
        local first_text = type(picker.items_or_provider[1]) == "table" and picker.items_or_provider[1].text
            or picker.items_or_provider[1]
        assert.are.same(file, first_text)
    end)

    it("skips non-readable files", function()
        vim.v.oldfiles = { tmpdir .. "/nonexistent.lua" }

        picker = builtin.old_files()

        assert.are.same(0, #picker.items_or_provider)
    end)

    it("opens picker with correct prompt", function()
        vim.v.oldfiles = {}

        picker = builtin.old_files()

        assert.are.same("Recent Files > ", picker.opts.prompt)
    end)
end)

describe("benchmark: <C-x> handler to UI update delay", function()
    local picker
    local tmpdir = vim.fn.tempname()

    before_each(function()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        if picker then
            picker:close()
            picker = nil
        end
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end
        vim.fn.delete(tmpdir, "rf")
    end)

    it("measures perceived delay from <C-x> to UI refresh (10 iterations)", function()
        local ITERATIONS = 10
        local ASYNC_TIMEOUT_MS = 500 -- max wait for schedule_wrap round-trip

        local sync_delays = {} -- handler start → set_items returns
        local async_delays = {} -- handler start → current_matches updated
        local total_delays = {} -- same as async (perceived delay)
        local filter_delays = {} -- just the fuzzy.filter execution time
        local preview_pending_count = 0 -- how often preview_timer was still armed

        local fuzzy = require "refer.fuzzy"

        for iter = 1, ITERATIONS do
            local file1 = tmpdir .. "/bench_a_" .. iter .. ".lua"
            local file2 = tmpdir .. "/bench_b_" .. iter .. ".lua"
            local f1 = io.open(file1, "w")
            f1:write "a\n"
            f1:close()
            local f2 = io.open(file2, "w")
            f2:write "b\n"
            f2:close()

            vim.cmd("edit " .. vim.fn.fnameescape(file1))
            vim.cmd("edit " .. vim.fn.fnameescape(file2))

            picker = builtin.buffers()

            local item_to_delete = nil
            for _, item in ipairs(picker.items_or_provider) do
                local text = type(item) == "table" and item.text or item
                if text:find("bench_a_" .. iter .. ".lua", 1, true) then
                    item_to_delete = type(item) == "table" and item or { text = item }
                    break
                end
            end
            assert.is_not_nil(item_to_delete, "bench_a item not found in iteration " .. iter)

            local builtin_ctx = {
                picker = picker,
                actions = picker.actions,
                parameters = { original_win = vim.api.nvim_get_current_win() },
                marked = {},
            }

            local orig_filter = fuzzy.filter
            local filter_ns_this_iter = 0
            fuzzy.filter = function(items, query, opts_f)
                local t0 = vim.uv.hrtime()
                local result = orig_filter(items, query, opts_f)
                filter_ns_this_iter = vim.uv.hrtime() - t0
                return result
            end

            local t_start = vim.uv.hrtime()

            local keymap_handler = picker.opts.keymaps["<C-x>"]
            keymap_handler(item_to_delete, builtin_ctx)

            local t_after_handler = vim.uv.hrtime()
            local sync_ms = (t_after_handler - t_start) / 1e6
            table.insert(sync_delays, sync_ms)

            local removed = vim.wait(ASYNC_TIMEOUT_MS, function()
                if not picker or not picker.current_matches then
                    return true
                end
                for _, m in ipairs(picker.current_matches) do
                    local t = type(m) == "table" and m.text or m
                    if t:find("bench_a_" .. iter .. ".lua", 1, true) then
                        return false
                    end
                end
                return true
            end, 1)

            local t_async_done = vim.uv.hrtime()
            local total_ms = (t_async_done - t_start) / 1e6
            local async_ms = total_ms - sync_ms
            table.insert(async_delays, async_ms)
            table.insert(total_delays, total_ms)
            table.insert(filter_delays, filter_ns_this_iter / 1e6)

            if picker and picker.preview_timer then
                preview_pending_count = preview_pending_count + 1
            end

            fuzzy.filter = orig_filter

            assert.is_true(removed ~= false, "vim.wait timed out – item not removed from current_matches")

            local still_present = false
            for _, item in ipairs(picker.items_or_provider) do
                local text = type(item) == "table" and item.text or item
                if text:find("bench_a_" .. iter .. ".lua", 1, true) then
                    still_present = true
                    break
                end
            end
            assert.is_false(still_present, "item should have been removed from items_or_provider")

            picker:close()
            picker = nil
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
                end
            end
        end

        local function stats(t)
            local sum, mn, mx = 0, t[1], t[1]
            for _, v in ipairs(t) do
                sum = sum + v
                if v < mn then
                    mn = v
                end
                if v > mx then
                    mx = v
                end
            end
            return sum / #t, mn, mx
        end

        local sync_avg, sync_min, sync_max = stats(sync_delays)
        local async_avg, async_min, async_max = stats(async_delays)
        local total_avg, total_min, total_max = stats(total_delays)
        local filter_avg, filter_min, filter_max = stats(filter_delays)

        -- ── report ─────────────────────────────────────────────────────────────
        print(
            string.format(
                [[

[benchmark] <C-x> perceived delay breakdown (%d iterations)
┌─────────────────────────────────────────────────────────────────┐
│ Phase                │   avg (ms) │   min (ms) │   max (ms) │
├─────────────────────────────────────────────────────────────────┤
│ 1. Sync (handler)    │ %10.4f │ %10.4f │ %10.4f │
│ 2. Async (sched_wrap)│ %10.4f │ %10.4f │ %10.4f │
│    └ fuzzy.filter    │ %10.4f │ %10.4f │ %10.4f │
│ 3. Total perceived   │ %10.4f │ %10.4f │ %10.4f │
└─────────────────────────────────────────────────────────────────┘
  preview_timer still armed after async: %d/%d iterations
  (preview adds a further 50 ms timer on top of total perceived)

Bottleneck guide:
  • If async >> sync   → vim.schedule_wrap round-trip dominates
  • If fuzzy ≈ async   → fuzzy.filter + render dominates
  • preview_timer > 0  → 50 ms preview deferment adds to perceived delay
]],
                ITERATIONS,
                sync_avg,
                sync_min,
                sync_max,
                async_avg,
                async_min,
                async_max,
                filter_avg,
                filter_min,
                filter_max,
                total_avg,
                total_min,
                total_max,
                preview_pending_count,
                ITERATIONS
            )
        )

        assert.is_true(sync_avg < 10, string.format("sync avg %.4f ms exceeds 10 ms", sync_avg))
        assert.is_true(
            total_avg < ASYNC_TIMEOUT_MS,
            string.format("total perceived avg %.4f ms exceeds timeout %d ms", total_avg, ASYNC_TIMEOUT_MS)
        )
    end)
end)
