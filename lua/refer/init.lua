local Picker = require "refer.picker"

---@class ReferModule
local M = {}

---@type ReferOptions
local default_opts = {
    max_height_percent = 0.4,
    min_height = 1,
    debounce_ms = 100,
    min_query_len = 2,
    available_sorters = { "blink", "mini", "native", "lua" },
    default_sorter = "blink",
    ui = {
        mark_char = "●",
        mark_hl = "String",
        winhighlight = "Normal:Normal,FloatBorder:Normal,WinSeparator:Normal,StatusLine:Normal,StatusLineNC:Normal",
        highlights = {
            prompt = "Title",
            selection = "Visual",
            header = "WarningMsg",
        },
    },
    providers = {
        files = {
            ignored_dirs = { ".git", ".jj", "node_modules", ".cache" },
            find_command = { "fd", "-H", "--type", "f", "--color", "never" },
        },
        grep = {
            grep_command = { "rg", "--vimgrep", "--smart-case" },
        },
    },
    preview = {
        max_lines = 1000,
    },
    keymaps = {
        ["<Tab>"] = "complete_selection",
        ["<C-n>"] = "next_item",
        ["<C-p>"] = "prev_item",
        ["<Down>"] = "next_item",
        ["<Up>"] = "prev_item",
        ["<CR>"] = "select_input",
        ["<Esc>"] = "close",
        ["<C-c>"] = "close",
        ["<C-g>"] = "send_to_grep",
        ["<C-q>"] = "send_to_qf",
        ["<C-s>"] = "cycle_sorter",
    },
}

---Configure default options for all pickers
---@param opts ReferOptions|nil Configuration options
function M.setup(opts)
    default_opts = vim.tbl_deep_extend("force", default_opts, opts or {})
end

---Open a picker with items or a provider function
---@param items_or_provider table|fun(query: string): table List of strings or a function that returns items based on query
---@param on_select fun(selection: string, data: SelectionData|nil)|nil Callback when item is selected
---@param opts ReferOptions|nil Options to override defaults
---@return Picker picker The picker instance
function M.pick(items_or_provider, on_select, opts)
    opts = vim.tbl_deep_extend("force", default_opts, opts or {})
    if on_select then
        opts.on_select = on_select
    end

    local picker = Picker.new(items_or_provider, opts)
    picker:show()
    return picker
end

---Open an async picker with command generator
---@param command_generator fun(query: string): table|nil Function that returns command args based on query
---@param on_select fun(selection: string, data: SelectionData|nil)|nil Callback when item is selected
---@param opts ReferOptions|nil Options to override defaults
---@return Picker picker The picker instance
function M.pick_async(command_generator, on_select, opts)
    opts = vim.tbl_deep_extend("force", default_opts, opts or {})
    if on_select then
        opts.on_select = on_select
    end

    local picker = Picker.new_async(command_generator, opts)
    picker:show()
    return picker
end

return M
