local files = require "refer.providers.files"
local refer = require "refer"
local fuzzy = require "refer.fuzzy"
local frecency = require "refer.frecency"
local db = require "refer.frecency.db"

describe("refer.providers.files", function()
    describe("_escape_fd_regex", function()
        it("passes through plain alphanumeric strings", function()
            assert.are.same("init", files._escape_fd_regex "init")
            assert.are.same("fooBar123", files._escape_fd_regex "fooBar123")
        end)

        it("passes through dashes and underscores", function()
            assert.are.same("foo-bar_baz", files._escape_fd_regex "foo-bar_baz")
        end)

        it("escapes dots", function()
            assert.are.same("init\\.lua", files._escape_fd_regex "init.lua")
        end)

        it("escapes plus", function()
            assert.are.same("foo\\+bar", files._escape_fd_regex "foo+bar")
        end)

        it("escapes asterisk", function()
            assert.are.same("test\\*", files._escape_fd_regex "test*")
        end)

        it("escapes question mark", function()
            assert.are.same("file\\?", files._escape_fd_regex "file?")
        end)

        it("escapes square brackets", function()
            assert.are.same("a\\[0\\]", files._escape_fd_regex "a[0]")
        end)

        it("escapes parentheses", function()
            assert.are.same("fn\\(x\\)", files._escape_fd_regex "fn(x)")
        end)

        it("escapes curly braces", function()
            assert.are.same("a\\{1\\}", files._escape_fd_regex "a{1}")
        end)

        it("escapes pipe", function()
            assert.are.same("a\\|b", files._escape_fd_regex "a|b")
        end)

        it("escapes caret and dollar", function()
            assert.are.same("\\^start", files._escape_fd_regex "^start")
            assert.are.same("end\\$", files._escape_fd_regex "end$")
        end)

        it("escapes backslash", function()
            assert.are.same("path\\\\to", files._escape_fd_regex "path\\to")
        end)

        it("escapes multiple special chars in one string", function()
            assert.are.same("foo\\.bar\\+baz\\*", files._escape_fd_regex "foo.bar+baz*")
        end)

        it("returns empty string for empty input", function()
            assert.are.same("", files._escape_fd_regex "")
        end)
    end)

    describe("_build_path_regex", function()
        it("builds regex for two segments", function()
            assert.are.same("prov[^/]*/.*files", files._build_path_regex "prov/files")
        end)

        it("builds regex for three segments", function()
            assert.are.same("lua[^/]*/.*ref[^/]*/.*init", files._build_path_regex "lua/ref/init")
        end)

        it("handles trailing slash", function()
            assert.are.same("providers", files._build_path_regex "providers/")
        end)

        it("handles leading slash", function()
            assert.are.same("providers[^/]*/.*files", files._build_path_regex "/providers/files")
        end)

        it("handles double slashes", function()
            assert.are.same("foo[^/]*/.*[^/]*/.*bar", files._build_path_regex "foo//bar")
        end)

        it("escapes dots in segments", function()
            assert.are.same("ref[^/]*/.*init\\.lua", files._build_path_regex "ref/init.lua")
        end)

        it("escapes special chars in each segment independently", function()
            assert.are.same("src\\.main[^/]*/.*test\\+spec\\.lua", files._build_path_regex "src.main/test+spec.lua")
        end)

        it("handles single segment (no joining)", function()
            assert.are.same("foo", files._build_path_regex "foo")
        end)

        it("handles many segments", function()
            assert.are.same("a[^/]*/.*b[^/]*/.*c[^/]*/.*d", files._build_path_regex "a/b/c/d")
        end)
    end)

    describe("files post_process", function()
        local frecency_path

        before_each(function()
            frecency_path = vim.fn.tempname() .. "_files_post_process.json"
            frecency.configure {
                db_path = frecency_path,
                buckets = false,
                neighborhood_size = 10,
            }
        end)

        after_each(function()
            if frecency_path then
                vim.fn.delete(frecency_path, "rf")
                frecency_path = nil
            end
            db._reset()
        end)

        it("converts fd relative paths to ReferItems with absolute data.filename", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.files {}

            refer.pick_async = orig_pick_async

            assert.is_not_nil(captured_opts)
            assert.is_not_nil(captured_opts.post_process)

            -- Simulate fd output with relative paths
            local cwd = vim.fn.getcwd()
            local output_lines = { "lua/refer/init.lua", "tests/refer/pick_spec.lua" }
            local result = captured_opts.post_process(output_lines, "")

            assert.is_true(#result >= 2)
            for _, item in ipairs(result) do
                assert.is_table(item)
                assert.is_not_nil(item.data)
                assert.is_not_nil(item.data.filename)
                -- filename should be absolute and normalized
                assert.truthy(vim.startswith(item.data.filename, "/"))
                assert.are.same(item.data.filename, vim.fn.fnamemodify(cwd .. "/" .. item.text, ":p"))
            end
        end)

        it("passes frecency = { provider = 'files', key_strategy = 'filepath' }", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.files {}

            refer.pick_async = orig_pick_async

            assert.is_not_nil(captured_opts)
            assert.is_not_nil(captured_opts.frecency)
            assert.are.same("files", captured_opts.frecency.provider)
            assert.are.same("filepath", captured_opts.frecency.key_strategy)
        end)

        it("applies frecency reorder in post_process when lua sorter is active", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.files { default_sorter = "lua" }

            refer.pick_async = orig_pick_async

            assert.is_not_nil(captured_opts)
            assert.is_not_nil(captured_opts.post_process)

            local cwd = vim.fn.getcwd()
            local rel1 = "a_file.lua"
            local rel2 = "b_file.lua"
            local abs1 = vim.fn.fnamemodify(cwd .. "/" .. rel1, ":p")
            local abs2 = vim.fn.fnamemodify(cwd .. "/" .. rel2, ":p")

            -- Record frecency for b_file
            frecency.record("files", abs2)
            frecency.record("files", abs2)

            -- post_process with lua sorter
            local result = captured_opts.post_process({ rel1, rel2 }, "")

            assert.are.same(2, #result)
            -- b_file (rel2/abs2) should be first due to frecency
            assert.are.same(abs2, result[1].data.filename)
            assert.are.same(abs1, result[2].data.filename)
        end)

        it("does NOT apply frecency reorder in post_process when per-provider frecency is disabled", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.files { default_sorter = "lua", frecency = { enabled = false } }

            refer.pick_async = orig_pick_async

            assert.is_not_nil(captured_opts)
            assert.is_not_nil(captured_opts.post_process)

            local cwd = vim.fn.getcwd()
            local rel1 = "a_file.lua"
            local rel2 = "b_file.lua"
            local abs1 = vim.fn.fnamemodify(cwd .. "/" .. rel1, ":p")
            local abs2 = vim.fn.fnamemodify(cwd .. "/" .. rel2, ":p")

            frecency.record("files", abs2)
            frecency.record("files", abs2)

            local result = captured_opts.post_process({ rel1, rel2 }, "")

            assert.are.same(2, #result)
            assert.are.same(abs1, result[1].data.filename)
            assert.are.same(abs2, result[2].data.filename)
        end)

        it("does NOT apply frecency reorder in post_process when non-lua sorter is active", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.files { default_sorter = "native" }

            refer.pick_async = orig_pick_async

            assert.is_not_nil(captured_opts)
            assert.is_not_nil(captured_opts.post_process)

            local cwd = vim.fn.getcwd()
            local rel1 = "a_file.lua"
            local rel2 = "b_file.lua"
            local abs1 = vim.fn.fnamemodify(cwd .. "/" .. rel1, ":p")
            local abs2 = vim.fn.fnamemodify(cwd .. "/" .. rel2, ":p")

            -- Record frecency for b_file
            frecency.record("files", abs2)
            frecency.record("files", abs2)

            -- post_process with native sorter (non-lua) → frecency should NOT apply
            local result = captured_opts.post_process({ rel1, rel2 }, "")

            assert.are.same(2, #result)
            -- Without frecency, original order should be preserved (a_file first)
            assert.are.same(abs1, result[1].data.filename)
            assert.are.same(abs2, result[2].data.filename)
        end)

        it("does NOT apply frecency reorder under default blink sorter", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.files {}

            refer.pick_async = orig_pick_async

            local cwd = vim.fn.getcwd()
            local rel1 = "a_file.lua"
            local rel2 = "b_file.lua"
            local abs1 = vim.fn.fnamemodify(cwd .. "/" .. rel1, ":p")
            local abs2 = vim.fn.fnamemodify(cwd .. "/" .. rel2, ":p")

            -- Record frecency for b_file
            frecency.record("files", abs2)
            frecency.record("files", abs2)

            -- Default sorter is blink → frecency should NOT apply
            local result = captured_opts.post_process({ rel1, rel2 }, "")

            assert.are.same(2, #result)
            -- Without frecency, original order should be preserved (a_file first)
            assert.are.same(abs1, result[1].data.filename)
            assert.are.same(abs2, result[2].data.filename)
        end)

        it("empty-query via post_process shows frecent files first with lua sorter (C9)", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.files { default_sorter = "lua" }

            refer.pick_async = orig_pick_async

            local cwd = vim.fn.getcwd()
            local rel1 = "x_file.lua"
            local rel2 = "y_file.lua"
            local abs1 = vim.fn.fnamemodify(cwd .. "/" .. rel1, ":p")
            local abs2 = vim.fn.fnamemodify(cwd .. "/" .. rel2, ":p")

            -- Record frecency for y_file
            frecency.record("files", abs2)
            frecency.record("files", abs2)
            frecency.record("files", abs2)

            -- Empty query → sort_by_frecency path (lua sorter active)
            local result = captured_opts.post_process({ rel1, rel2 }, "")

            assert.are.same(2, #result)
            -- y_file should be first due to frecency (sort_by_frecency on empty query)
            assert.are.same(abs2, result[1].data.filename)
            assert.are.same(abs1, result[2].data.filename)
        end)
    end)

    describe("lines", function()
        local function make_named_buf(lines, name)
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.api.nvim_buf_set_name(buf, name)
            return buf
        end

        local function capture_items(fn)
            local captured = nil
            local orig_pick = refer.pick
            refer.pick = function(items, _, _)
                captured = items
                return {}
            end
            fn()
            refer.pick = orig_pick
            return captured
        end

        it("formats lines as grep-style entries", function()
            local buf = make_named_buf({ "hello world", "foo bar" }, "/tmp/test_lines.lua")
            vim.api.nvim_set_current_buf(buf)

            local items = capture_items(function()
                files.lines {}
            end)

            assert.are.same(2, #items)
            assert.truthy(items[1]:match "^.-:1:1:hello world$")
            assert.truthy(items[2]:match "^.-:2:1:foo bar$")

            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("handles empty lines in buffer", function()
            local buf = make_named_buf({ "line1", "", "line3" }, "/tmp/test_empty.lua")
            vim.api.nvim_set_current_buf(buf)

            local items = capture_items(function()
                files.lines {}
            end)

            assert.are.same(3, #items)
            assert.truthy(items[2]:match "^.-:2:1:$")

            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("handles unnamed buffer", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "only line" })
            vim.api.nvim_set_current_buf(buf)

            local items = capture_items(function()
                files.lines {}
            end)

            assert.are.same(1, #items)
            assert.truthy(items[1]:match "^%[No Name%]:1:1:only line$")

            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    describe("non-participating providers", function()
        it("live_grep does not pass frecency opts", function()
            local captured_opts = nil
            local orig_pick_async = refer.pick_async
            refer.pick_async = function(cmd_gen, _, opts)
                captured_opts = opts
                return {}
            end

            files.live_grep {}

            refer.pick_async = orig_pick_async

            assert.is_nil(captured_opts.frecency)
        end)

        it("grep_word does not pass frecency opts", function()
            local captured_opts = nil
            local orig_pick = refer.pick
            refer.pick = function(items, _, opts)
                captured_opts = opts
                return {}
            end

            local tmp_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(tmp_buf, 0, -1, false, { "test_word" })
            vim.api.nvim_set_current_buf(tmp_buf)
            vim.api.nvim_win_set_cursor(0, { 1, 0 })

            pcall(files.grep_word, {})

            refer.pick = orig_pick
            vim.api.nvim_buf_delete(tmp_buf, { force = true })

            assert.is_nil(captured_opts.frecency)
        end)

        it("lines does not pass frecency opts", function()
            local captured_opts = nil
            local orig_pick = refer.pick
            refer.pick = function(items, _, opts)
                captured_opts = opts
                return {}
            end

            local tmp_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(tmp_buf, 0, -1, false, { "line1" })
            vim.api.nvim_set_current_buf(tmp_buf)

            pcall(files.lines, {})

            refer.pick = orig_pick
            vim.api.nvim_buf_delete(tmp_buf, { force = true })

            assert.is_nil(captured_opts.frecency)
        end)
    end)
end)
