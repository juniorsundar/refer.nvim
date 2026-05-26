local refer = require "refer"
local builtin = require "refer.providers.builtin"
local util = require "refer.util"
local frecency = require "refer.frecency"
local db = require "refer.frecency.db"

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

describe("builtin.old_files frecency", function()
    local picker
    local tmpdir
    local frecency_path

    local function setup_frecency()
        frecency_path = vim.fn.tempname() .. "_old_files_e2e.json"
        frecency.configure {
            db_path = frecency_path,
            buckets = false,
            neighborhood_size = 10,
        }
    end

    before_each(function()
        tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir, "p")
        setup_frecency()
    end)

    after_each(function()
        if picker then
            picker:close()
            picker = nil
        end
        if frecency_path then
            vim.fn.delete(frecency_path, "rf")
            frecency_path = nil
        end
        if tmpdir then
            vim.fn.delete(tmpdir, "rf")
            tmpdir = nil
        end
        db._reset()
    end)

    it("items have data.filename set to absolute paths (normalized via :p)", function()
        local file = tmpdir .. "/old_file.lua"
        local f = io.open(file, "w")
        f:write "content\n"
        f:close()

        vim.v.oldfiles = { file }

        picker = builtin.old_files()

        assert.is_true(#picker.items_or_provider >= 1)
        local item = picker.items_or_provider[1]
        assert.is_table(item)
        assert.is_not_nil(item.data)
        assert.is_not_nil(item.data.filename)
        -- filename should be absolute and normalized via :p
        local expected = vim.fn.fnamemodify(file, ":p")
        assert.are.same(expected, item.data.filename)
    end)

    it("passes frecency = { provider = 'old_files', key_strategy = 'filepath' }", function()
        local file = tmpdir .. "/frec_file.lua"
        local f = io.open(file, "w")
        f:write "content\n"
        f:close()

        vim.v.oldfiles = { file }

        picker = builtin.old_files()

        assert.is_not_nil(picker.opts.frecency)
        assert.are.same("old_files", picker.opts.frecency.provider)
        assert.are.same("filepath", picker.opts.frecency.key_strategy)
    end)

    it("selecting an old file records frecency; reopening with lua sorter ranks it higher", function()
        local file_a = tmpdir .. "/a_file.lua"
        local file_b = tmpdir .. "/b_file.lua"
        local file_c = tmpdir .. "/c_file.lua"

        for _, fpath in ipairs { file_a, file_b, file_c } do
            local f = io.open(fpath, "w")
            f:write "content\n"
            f:close()
        end

        vim.v.oldfiles = { file_a, file_b, file_c }

        -- First picker: select file_b
        picker = builtin.old_files { default_sorter = "lua" }

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- Select file_b (second item alphabetically: a_file, b_file, c_file)
        picker.selected_index = 2
        picker.actions.select_entry()
        vim.wait(100)
        picker = nil

        -- Second picker: file_b should rank higher
        picker = builtin.old_files { default_sorter = "lua" }

        vim.wait(500, function()
            return #picker.current_matches == 3
        end)

        -- file_b (b_file.lua) should now be first
        assert.are.same(vim.fn.fnamemodify(file_b, ":p"), picker.current_matches[1].data.filename)
    end)

    it("frecency keys from buffers provider do not affect old_files ranking", function()
        local file_a = tmpdir .. "/iso_a.lua"
        local file_b = tmpdir .. "/iso_b.lua"

        for _, fpath in ipairs { file_a, file_b } do
            local f = io.open(fpath, "w")
            f:write "content\n"
            f:close()
        end

        -- Record frecency for file_b under "buffers" provider
        local abs_b = vim.fn.fnamemodify(file_b, ":p")
        frecency.record("buffers", abs_b)
        frecency.record("buffers", abs_b)
        frecency.record("buffers", abs_b)

        -- Open old_files picker — buffers recording should NOT affect ranking
        vim.v.oldfiles = { file_a, file_b }
        picker = builtin.old_files { default_sorter = "lua" }

        vim.wait(500, function()
            return #picker.current_matches == 2
        end)

        -- Without old_files frecency, original order (alphabetical: a_file before b_file)
        assert.are.same(vim.fn.fnamemodify(file_a, ":p"), picker.current_matches[1].data.filename)
    end)

    it("frecency keys from old_files do not affect buffers or files", function()
        local file = tmpdir .. "/cross_provider.lua"
        local f = io.open(file, "w")
        f:write "content\n"
        f:close()

        local abs = vim.fn.fnamemodify(file, ":p")

        -- Record under old_files provider
        frecency.record("old_files", abs)
        frecency.record("old_files", abs)

        -- Verify buffers provider does NOT see the old_files recording
        local buffers_scores = frecency.score("buffers", { abs })
        assert.is_true(
            buffers_scores[abs] == nil or buffers_scores[abs] == 0,
            "buffers provider should not see old_files frecency"
        )

        -- Verify files provider does NOT see the old_files recording
        local files_scores = frecency.score("files", { abs })
        assert.is_true(
            files_scores[abs] == nil or files_scores[abs] == 0,
            "files provider should not see old_files frecency"
        )
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
