local Picker = require "refer.picker"

---@class ReferModule
local M = {}

---@type table<string, function> The central registry of subcommands
M._registry = {}

---Register a new subcommand for :Refer
---@param name string The name of the command (e.g., "GitStatus")
---@param fn function The function to execute when the command is run
function M.add_command(name, fn)
    if M._registry[name] then
        vim.notify("Refer: Overwriting existing command '" .. name .. "'", vim.log.levels.WARN)
    end
    M._registry[name] = fn
end

---Get all registered commands (useful for completion)
---@return table<string, function>
function M.get_commands()
    return M._registry
end

setmetatable(M, {
    __index = function(t, k)
        if k == "_active_picker" then
            return Picker.get_active()
        end
        return rawget(t, k)
    end,
})

-- Detect fd command (handle fdfind on Ubuntu/Debian)
local fd_cmd = "fd"
if vim.fn.executable "fdfind" == 1 then
    fd_cmd = "fdfind"
end

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
        input_position = "top",
        reverse_result = false,
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
            find_command = { fd_cmd, "-H", "--type", "f", "--color", "never" },
        },
        grep = {
            grep_command = { "rg", "--vimgrep", "--smart-case" },
        },
    },
    preview = {
        enabled = true,
        max_lines = 1000,
    },
    keymaps = {
        ["<Tab>"] = { action = "complete_selection", desc = "Complete selection" },
        ["<C-n>"] = { action = "next_item", desc = "Next item" },
        ["<C-p>"] = { action = "prev_item", desc = "Previous item" },
        ["<Down>"] = { action = "next_item", desc = "Next item (arrow)" },
        ["<Up>"] = { action = "prev_item", desc = "Previous item (arrow)" },
        ["<CR>"] = { action = "select_input", desc = "Confirm selection" },
        ["<Esc>"] = { action = "close", desc = "Close picker" },
        ["<C-c>"] = { action = "close", desc = "Close picker" },
        ["<C-g>"] = { action = "send_to_grep", desc = "Send to grep buffer" },
        ["<C-q>"] = { action = "send_to_qf", desc = "Send to quickfix" },
        ["<C-s>"] = { action = "cycle_sorter", desc = "Cycle sorter" },
        ["<C-v>"] = { action = "toggle_preview", desc = "Toggle preview" },
        ["<C-u>"] = { action = "scroll_preview_up", desc = "Scroll preview up" },
        ["<C-d>"] = { action = "scroll_preview_down", desc = "Scroll preview down" },
        ["<M-a>"] = { action = "select_all", desc = "Select all" },
        ["<M-d>"] = { action = "deselect_all", desc = "Deselect all" },
        ["<M-t>"] = { action = "toggle_all", desc = "Toggle all marks" },
    },
}

---Configure default options for all pickers
---@param opts ReferOptions|nil Configuration options
function M.setup(opts)
    opts = opts or {}
    if opts.custom_sorters then
        local fuzzy = require "refer.fuzzy"
        for name, fn in pairs(opts.custom_sorters) do
            fuzzy.register_sorter(name, fn)
        end
    end
    if opts.custom_parsers then
        local util = require "refer.util"
        for name, schema in pairs(opts.custom_parsers) do
            util.register_parser(name, schema)
        end
    end
    default_opts = vim.tbl_deep_extend("force", default_opts, opts)
end

---Get combined options
---@param opts ReferOptions|nil User overrides
---@return ReferOptions options Merged options
function M.get_opts(opts)
    return vim.tbl_deep_extend("force", default_opts, opts or {})
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

---Use refer as the UI for vim.ui.select
---@param items table Arbitrary items
---@param opts table|nil Options (prompt, format_item, etc.)
---@param on_choice fun(item: any|nil, idx: number|nil) Callback
function M.select(items, opts, on_choice)
    vim.validate {
        items = { items, "t", false },
        on_choice = { on_choice, "f", false },
    }
    opts = opts or {}

    local choices = {}
    local seen_texts = {}  -- for dedup collision detection only

    local format_item = opts.format_item or tostring

    for i, item in ipairs(items) do
        local text = format_item(item)

        local unique_text = text
        if seen_texts[unique_text] then
            local count = 1
            while seen_texts[unique_text .. " (" .. count .. ")"] do
                count = count + 1
            end
            unique_text = unique_text .. " (" .. count .. ")"
        end
        seen_texts[unique_text] = true

        table.insert(choices, { text = unique_text, data = { item = item, idx = i } })
    end

    local selected = false

    -- After Plan 02, picker.on_select is called as on_select(item.text, item.data)
    local function on_select(selection_text, item_data)
        if item_data then
            selected = true
            on_choice(item_data.item, item_data.idx)
        end
    end

    local function on_close()
        if not selected then
            on_choice(nil, nil)
        end
    end

    local picker_opts = {
        prompt = opts.prompt or "Select: ",
        on_select = on_select,
        on_close = on_close,
        keymaps = {
            ["<CR>"] = function(_, builtin)
                local selection = builtin.picker.current_matches[builtin.picker.selected_index]
                if selection then
                    selected = true
                    builtin.actions.select_entry()
                end
            end,
        },
    }

    M.pick(choices, nil, picker_opts)
end

function M.setup_ui_select()
    vim.ui.select = M.select
end

return M
