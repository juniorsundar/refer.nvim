local refer = require "refer"
local repo_root = vim.fn.getcwd()

describe("refer extras find_file", function()
    local original_loaded_refer
    local original_registry
    local temp_dir

    local function reset_setup_state()
        package.loaded["refer"] = nil
        package.loaded["refer.extras"] = nil
        package.loaded["refer.extras.find_file"] = nil
        refer = require "refer"
    end

    local function load_plugin_commands()
        pcall(vim.api.nvim_del_user_command, "Refer")
        refer._registry = {}
        vim.g.loaded_refer = nil
        package.loaded["refer.commands"] = nil
        dofile(repo_root .. "/plugin/refer.lua")
    end

    local function mkdirp(path)
        vim.fn.mkdir(path, "p")
    end

    local function write_file(path, lines)
        vim.fn.writefile(lines, path)
    end

    local function wait_for(predicate, message)
        local ok = vim.wait(1000, predicate, 20)
        assert.is_true(ok, message or "timed out")
    end

    local function wait_for_matches(picker)
        wait_for(function()
            return picker.debounce_timer == nil
        end, "picker never finished rendering")
    end

    local function find_item(picker, predicate)
        for index, item in ipairs(picker.current_matches or {}) do
            if predicate(item) then
                return item, index
            end
        end
    end

    local function open_find_file(opts)
        opts = opts or {}
        load_plugin_commands()
        refer.setup { extras = { find_file = true } }

        vim.api.nvim_cmd({ cmd = "Refer", args = { "Extras", "FindFile" } }, {})

        local picker = refer._active_picker
        assert.is_not_nil(picker)
        wait_for_matches(picker)

        if opts.path then
            vim.api.nvim_set_current_line(opts.path)
            picker:refresh()
            wait_for_matches(picker)
        end

        return picker
    end

    before_each(function()
        vim.cmd("cd " .. vim.fn.fnameescape(repo_root))
        original_loaded_refer = vim.g.loaded_refer
        original_registry = vim.deepcopy(refer.get_commands())
        temp_dir = vim.fn.tempname()
        mkdirp(temp_dir)
        reset_setup_state()
    end)

    after_each(function()
        if refer._active_picker then
            refer._active_picker:close()
        end

        vim.cmd("cd " .. vim.fn.fnameescape(repo_root))
        pcall(vim.api.nvim_del_user_command, "Refer")
        vim.g.loaded_refer = original_loaded_refer
        refer._registry = original_registry or {}
        package.loaded["refer"] = nil
        package.loaded["refer.extras"] = nil
        package.loaded["refer.extras.find_file"] = nil
        package.loaded["refer.commands"] = nil
        refer = require "refer"

        if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
            vim.fn.delete(temp_dir, "rf")
        end
    end)

    it("opens the opt-in extra without replacing core Files", function()
        load_plugin_commands()
        refer.setup { extras = { find_file = true } }
        local commands = refer.get_commands()

        assert.is_function(commands.Files)
        assert.is_table(commands.Extras)
        assert.is_function(commands.Extras.FindFile)

        vim.api.nvim_cmd({ cmd = "Refer", args = { "Extras", "FindFile" } }, {})

        assert.is_not_nil(refer._active_picker)
        assert.is_function(refer.get_commands().Files)
    end)

    it("renders filename-first rows with metadata in secondary detail", function()
        local file_path = temp_dir .. "/alpha.txt"
        write_file(file_path, { "hello world" })

        local picker = open_find_file { path = temp_dir }
        local item = find_item(picker, function(candidate)
            return candidate.data and candidate.data.filename == file_path
        end)

        assert.is_not_nil(item)
        assert.is_true(vim.startswith(item.text, "alpha.txt"))
        assert.is_truthy(item.text:find(vim.fn.getfperm(file_path), 1, true))
        assert.is_truthy(item.text:find(tostring(vim.fn.getfsize(file_path)), 1, true))
        assert.are.same(file_path, item.data.filename)
        assert.is_true(item.data.exists)
        assert.is_false(item.data.is_dir)
    end)

    it("offers a create candidate for a missing path and opens it on confirm", function()
        local missing_path = temp_dir .. "/notes/new-file.md"
        local picker = open_find_file { path = temp_dir }

        vim.api.nvim_set_current_line(missing_path)
        picker:refresh()
        wait_for_matches(picker)

        local item, index = find_item(picker, function(candidate)
            return candidate.data and candidate.data.filename == missing_path and candidate.data.create == true
        end)

        assert.is_not_nil(item)
        picker.selected_index = index
        picker.actions.select_entry()

        wait_for(function()
            return vim.fn.expand "%:p" == missing_path
        end, "missing path was not opened")
    end)

    it("descends into directories by rewriting the path context in place", function()
        local nested_dir = temp_dir .. "/docs"
        local nested_file = nested_dir .. "/guide.txt"
        mkdirp(nested_dir)
        write_file(nested_file, { "guide" })

        local picker = open_find_file { path = temp_dir }
        local item, index = find_item(picker, function(candidate)
            return candidate.data and candidate.data.filename == nested_dir
        end)

        assert.is_not_nil(item)
        picker.selected_index = index
        picker.actions.select_entry()

        wait_for(function()
            local active = refer._active_picker
            if not active then
                return false
            end

            local nested_item = find_item(active, function(candidate)
                return candidate.data and candidate.data.filename == nested_file
            end)

            return vim.api.nvim_get_current_line() == nested_dir and nested_item ~= nil
        end, "directory selection did not refresh in place")
    end)
end)
