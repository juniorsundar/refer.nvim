local refer = require "refer"
local util = require "refer.util"

local M = {}

local uv = vim.uv

local function path_join(...)
    return vim.fs.normalize(table.concat({ ... }, "/"))
end

local function path_parent(path)
    return vim.fs.dirname(path)
end

local function expand_path(raw)
    local text = vim.trim(raw or "")
    if text == "" then
        return vim.fs.normalize(uv.cwd() or vim.fn.getcwd())
    end

    local expanded = vim.fn.expand(text)
    if expanded == "" then
        expanded = text
    end

    return vim.fs.normalize(vim.fn.fnamemodify(expanded, ":p"))
end

local function get_stat(path)
    return uv.fs_stat(path)
end

local function permissions_for(path)
    local perm = vim.fn.getfperm(path)
    if perm == "" then
        return "---------"
    end
    return perm
end

local function nearest_existing_dir(path)
    local current = path

    while current and current ~= "" do
        local stat = get_stat(current)
        if stat then
            if stat.type == "directory" then
                return current
            end
            return path_parent(current)
        end

        local parent = path_parent(current)
        if not parent or parent == current then
            break
        end
        current = parent
    end

    return vim.fs.normalize(uv.cwd() or vim.fn.getcwd())
end

local function classify_query(query)
    local absolute = expand_path(query)
    local stat = get_stat(absolute)

    if stat and stat.type == "directory" then
        return {
            absolute = absolute,
            scan_dir = absolute,
            create_target = nil,
            prefix = nil,
        }
    end

    if stat then
        return {
            absolute = absolute,
            scan_dir = path_parent(absolute),
            create_target = nil,
            prefix = vim.fs.basename(absolute),
        }
    end

    local parent = path_parent(absolute)
    local parent_stat = parent and get_stat(parent) or nil
    if parent_stat and parent_stat.type == "directory" then
        return {
            absolute = absolute,
            scan_dir = parent,
            create_target = absolute,
            prefix = vim.fs.basename(absolute),
        }
    end

    return {
        absolute = absolute,
        scan_dir = nearest_existing_dir(absolute),
        create_target = absolute,
        prefix = nil,
    }
end

local function build_metadata(data)
    local width = vim.o.columns or 120
    local details = { data.permissions }

    if data.is_dir then
        table.insert(details, "<dir>")
    else
        table.insert(details, tostring(data.size or 0))
    end

    if width >= 100 and data.detail and data.detail ~= "" then
        table.insert(details, data.detail)
    end

    if width < 70 and #details > 2 then
        details = { details[1], details[2] }
    end

    return table.concat(details, "  ")
end

local function display_text(name, data, name_width)
    return string.format("%-" .. tostring(name_width) .. "s  %s", name, build_metadata(data))
end

local function list_dir(scan_dir, prefix)
    local handle = uv.fs_scandir(scan_dir)
    if not handle then
        return {}
    end

    local pending = {}
    while true do
        local name = uv.fs_scandir_next(handle)
        if not name then
            break
        end

        if prefix and prefix ~= "" and not vim.startswith(name, prefix) then
            goto continue
        end

        local absolute = path_join(scan_dir, name)
        local stat = get_stat(absolute)
        if not stat then
            goto continue
        end

        local data = {
            filename = absolute,
            exists = true,
            is_dir = stat.type == "directory",
            create = false,
            permissions = permissions_for(absolute),
            size = stat.size or 0,
            detail = util.get_relative_path(absolute),
        }

        table.insert(pending, {
            name = name,
            data = data,
        })

        ::continue::
    end

    local name_width = 0
    for _, entry in ipairs(pending) do
        name_width = math.max(name_width, vim.fn.strdisplaywidth(entry.name))
    end

    local items = {}
    for _, entry in ipairs(pending) do
        table.insert(items, {
            text = display_text(entry.name, entry.data, name_width),
            data = entry.data,
        })
    end

    table.sort(items, function(left, right)
        if left.data.is_dir ~= right.data.is_dir then
            return left.data.is_dir
        end
        return left.data.filename < right.data.filename
    end)

    return items
end

local function make_create_item(path, name_width)
    local data = {
        filename = path,
        exists = false,
        is_dir = false,
        create = true,
        permissions = "---------",
        size = 0,
        detail = util.get_relative_path(path_parent(path) or path),
    }

    local name = string.format("[Create] %s", vim.fs.basename(path))
    return {
        text = string.format("%-" .. tostring(name_width) .. "s  %s", name, data.detail),
        data = data,
    }
end

local function build_items(query)
    local resolved = classify_query(query)
    local items = list_dir(resolved.scan_dir, resolved.prefix)

    if resolved.create_target and not get_stat(resolved.create_target) then
        local create_name = string.format("[Create] %s", vim.fs.basename(resolved.create_target))
        local name_width = vim.fn.strdisplaywidth(create_name)
        for _, item in ipairs(items) do
            local filename = vim.fs.basename(item.data.filename)
            name_width = math.max(name_width, vim.fn.strdisplaywidth(filename))
        end
        table.insert(items, 1, make_create_item(resolved.create_target, name_width))
    end

    return items
end

local function open_target(path)
    local parent = path_parent(path)
    if parent and vim.fn.isdirectory(parent) == 0 then
        vim.fn.mkdir(parent, "p")
    end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
end

local function confirm_item(selection, builtin)
    local item = type(selection) == "table" and selection
        or builtin.picker.current_matches[builtin.picker.selected_index]
    if not item or not item.data then
        local raw = vim.api.nvim_get_current_line()
        if raw ~= "" then
            builtin.picker:close()
            open_target(expand_path(raw))
        end
        return
    end

    local data = item.data
    if data.is_dir then
        builtin.picker.ui:update_input { data.filename }
        vim.api.nvim_win_set_cursor(builtin.picker.ui.input_win, { 1, #data.filename })
        builtin.picker:refresh()
        return
    end

    builtin.picker:close()
    if data.create then
        open_target(data.filename)
        return
    end

    util.jump_to_location(item.text, data)
end

function M.run(_opts)
    local start_dir = vim.fs.normalize(uv.cwd() or vim.fn.getcwd())

    local picker = refer.pick({}, nil, {
        prompt = "FindFile > ",
        default_text = start_dir,
        on_change = function(query, callback)
            callback(build_items(query))
        end,
        keymaps = {
            ["<CR>"] = confirm_item,
        },
        on_select = function(selection, data)
            if data and data.filename then
                open_target(data.filename)
                return
            end

            open_target(expand_path(selection))
        end,
    })

    picker.actions.select_entry = function()
        confirm_item(picker.current_matches[picker.selected_index], { picker = picker, actions = picker.actions })
    end

    picker.actions.select_input = function()
        local raw = vim.api.nvim_get_current_line()
        if raw == "" then
            return
        end

        picker:close()
        open_target(expand_path(raw))
    end

    return picker
end

return M
