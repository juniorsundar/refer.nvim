local api = vim.api
local util = require "refer.util"
local UI = require "refer.ui"
local fuzzy = require "refer.fuzzy"
local preview = require "refer.preview"

---@class ActionTable
---@field refresh fun() Refresh the picker
---@field next_item fun() Move to next item
---@field prev_item fun() Move to previous item
---@field complete_selection fun() Complete current selection
---@field toggle_mark fun() Toggle mark on current item
---@field select_input fun() Select raw input
---@field select_entry fun() Select current entry
---@field send_to_grep fun() Send marked items to grep buffer
---@field send_to_qf fun() Send marked items to quickfix
---@field close fun() Close the picker
---@field cycle_sorter fun() Cycle through available sorters

---@class BuiltinContext
---@field actions ActionTable Available actions
---@field parameters table Original window/buffer/cursor info
---@field marked table<string, boolean> Marked items

---@class ReferOptions
---@field prompt? string Prompt text (default: "> ")
---@field on_select? fun(selection: string, data: SelectionData|nil) Callback when item selected
---@field on_close? fun() Callback when picker closes
---@field on_change? fun(query: string, callback: fun(matches: table)) Live query handler
---@field parser? fun(selection: string): SelectionData|nil Parse selection into structured data
---@field selection_format? string Predefined format: "file", "grep", "lsp", "buffer"
---@field sorter? string|fun(items: table, query: string): table Custom sorter function or name
---@field available_sorters? table<string> List of sorter names (default: {"blink", "mini", "native", "lua"})
---@field keymaps? table<string, string|fun(selection: string, builtin: BuiltinContext)> Keymap definitions
---@field percent? number Window height percentage (default: 0.4)

---@class Picker
---@field items_or_provider table|fun(query: string): table
---@field opts ReferOptions
---@field on_select fun(selection: string, data: SelectionData|nil)|nil
---@field original_win number
---@field original_buf number
---@field original_cursor number[]
---@field available_sorters table<string>
---@field sorter_idx number
---@field custom_sorter fun(items: table, query: string): table|string|nil
---@field parser fun(selection: string): SelectionData|nil|nil
---@field use_blink boolean
---@field current_matches table<string>
---@field marked table<string, boolean>
---@field selected_index number
---@field is_previewing boolean
---@field debounce_timer uv.uv_timer_t|nil
---@field preview_timer uv.uv_timer_t|nil
---@field ui ReferUI
---@field input_buf number|nil
---@field actions ActionTable
local Picker = {}
Picker.__index = Picker

---@type Picker|nil Currently active picker instance
local active_picker = nil

---Close any existing picker and clean up windows
function Picker.close_existing()
    if active_picker then
        active_picker:close()
        active_picker = nil
    end

    for _, win in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_is_valid(win) then
            local buf = api.nvim_win_get_buf(win)
            local ft = vim.bo[buf].filetype
            if ft == "refer_input" or ft == "refer_results" then
                api.nvim_win_close(win, true)
            end
        end
    end
end

---Create a new Picker instance
---@param items_or_provider table|fun(query: string): table List of strings or provider function
---@param opts ReferOptions|nil Configuration options
---@return Picker picker New picker instance
function Picker.new(items_or_provider, opts)
    Picker.close_existing()

    ---@type Picker
    local self = setmetatable({}, Picker)

    self.items_or_provider = items_or_provider
    self.opts = opts or {}
    self.on_select = self.opts.on_select

    self.original_win = api.nvim_get_current_win()
    self.original_buf = api.nvim_win_get_buf(self.original_win)
    self.original_cursor = api.nvim_win_get_cursor(self.original_win)

    self.available_sorters = self.opts.available_sorters or { "blink", "mini", "native", "lua" }
    self.sorter_idx = 1
    self.custom_sorter = self.opts.sorter

    self.parser = self.opts.parser
    if not self.parser and self.opts.selection_format then
        self.parser = function(s)
            return util.parse_selection(s, self.opts.selection_format)
        end
    end

    -- Blink setup
    self.use_blink = fuzzy.has_blink() and type(items_or_provider) == "table" and not self.custom_sorter
    if self.use_blink then
        fuzzy.register_items(items_or_provider)
    end

    -- State
    self.current_matches = {}
    self.marked = {}
    self.selected_index = 1
    self.is_previewing = false
    self.debounce_timer = nil
    self.preview_timer = nil

    self.ui = UI.new(self.opts.prompt or "> ", self.opts)
    self.input_buf = nil

    active_picker = self
    return self
end

---Show the picker UI
function Picker:show()
    local input_buf, _ = self.ui:create_windows()
    self.input_buf = input_buf

    -- Setup actions and keymaps
    self:setup_actions()
    self:setup_keymaps()
    self:setup_autocmds()

    self:refresh()
    vim.cmd "startinsert"
end

---Close the picker and clean up resources
function Picker:close()
    if self.debounce_timer then
        self.debounce_timer:stop()
        self.debounce_timer:close()
        self.debounce_timer = nil
    end
    if self.preview_timer then
        self.preview_timer:stop()
        self.preview_timer:close()
        self.preview_timer = nil
    end

    if not self.ui then
        return
    end

    if self.opts.on_close then
        self.opts.on_close()
    end

    if api.nvim_win_is_valid(self.original_win) and api.nvim_buf_is_valid(self.original_buf) then
        api.nvim_win_set_buf(self.original_win, self.original_buf)
    end

    preview.cleanup()

    self.ui:close()
    if active_picker == self then
        active_picker = nil
    end

    self.current_matches = nil
    self.items_or_provider = nil
    self.marked = nil
end

---Cancel picker and restore original state
function Picker:cancel()
    if api.nvim_win_is_valid(self.original_win) and api.nvim_buf_is_valid(self.original_buf) then
        api.nvim_win_set_buf(self.original_win, self.original_buf)
        api.nvim_win_set_cursor(self.original_win, self.original_cursor)
    end
    self:close()
end

---Update preview window with current selection
function Picker:update_preview()
    if #self.current_matches == 0 then
        return
    end

    if self.preview_timer then
        self.preview_timer:stop()
    else
        self.preview_timer = vim.uv.new_timer()
    end

    self.preview_timer:start(
        50,
        0,
        vim.schedule_wrap(function()
            if self.preview_timer then
                self.preview_timer:stop()
                self.preview_timer:close()
                self.preview_timer = nil
            end

            if not active_picker or active_picker ~= self then
                return
            end

            local selection = self.current_matches[self.selected_index]
            if not selection then
                return
            end

            local data = self.parser and self.parser(selection)
            if data and data.filename and api.nvim_win_is_valid(self.original_win) then
                self.is_previewing = true
                preview.show {
                    filename = data.filename,
                    lnum = data.lnum,
                    col = data.col,
                    target_win = self.original_win,
                }
                self.is_previewing = false
            end
        end)
    )
end

---Render current matches to the UI
function Picker:render()
    self.ui:render(self.current_matches, self.selected_index, self.marked)
    self:update_preview()
end

---Refresh matches based on current input
function Picker:refresh()
    if self.debounce_timer then
        self.debounce_timer:stop()
    else
        self.debounce_timer = vim.uv.new_timer()
    end

    local input = api.nvim_get_current_line()

    self.debounce_timer:start(
        20, -- 20ms debounce for filtering
        0,
        vim.schedule_wrap(function()
            if self.debounce_timer then
                self.debounce_timer:stop()
                self.debounce_timer:close()
                self.debounce_timer = nil
            end

            if not active_picker or active_picker ~= self then
                return
            end

            if self.opts.on_change then
                self.opts.on_change(input, function(matches)
                    if api.nvim_get_current_line() ~= input then
                        return
                    end

                    if active_picker ~= self then
                        return
                    end

                    self.current_matches = matches or {}
                    self.selected_index = 1
                    self:render()
                end)
                return
            end

            self.current_matches = fuzzy.filter(self.items_or_provider, input, {
                sorter = self.custom_sorter,
                use_blink = self.use_blink,
            })

            self.selected_index = 1
            self:render()
        end)
    )
end

---Setup all picker actions
function Picker:setup_actions()
    self.actions = {}

    self.actions.refresh = function()
        self:refresh()
    end

    self.actions.next_item = function()
        if #self.current_matches > 0 then
            self.selected_index = (self.selected_index % #self.current_matches) + 1
            self:render()
        end
    end

    self.actions.prev_item = function()
        if #self.current_matches > 0 then
            self.selected_index = ((self.selected_index - 2) % #self.current_matches) + 1
            self:render()
        end
    end

    self.actions.complete_selection = function()
        local selection = self.current_matches[self.selected_index]
        local input = api.nvim_get_current_line()

        if selection then
            local new_line = util.complete_line(input, selection)
            self.ui:update_input { new_line }
            self:refresh()
        end
    end

    self.actions.toggle_mark = function()
        local selection = self.current_matches[self.selected_index]
        if selection then
            self.marked[selection] = not self.marked[selection]
            self.ui:render(self.current_matches, self.selected_index, self.marked)
        end
        self.actions.next_item()
    end

    self.actions.select_input = function()
        local current_input = api.nvim_get_current_line()
        self:close()

        if self.on_select and current_input ~= "" then
            self.on_select(current_input, nil)
        end
    end

    self.actions.select_entry = function()
        local selection = self.current_matches[self.selected_index]
        if selection then
            self:close()
            local data = self.parser and self.parser(selection)
            self.on_select(selection, data)
        end
    end

    self.actions.send_to_grep = function()
        local lines = {}
        for item, is_marked in pairs(self.marked) do
            if is_marked then
                table.insert(lines, item)
            end
        end

        if #lines == 0 then
            local selection = self.current_matches[self.selected_index]
            if selection then
                table.insert(lines, selection)
            end
        end

        if #lines > 0 then
            self:close()
            local ok, grep_buf = pcall(require, "buffers.grep")
            if ok then
                grep_buf.create_buffer(lines)
            else
                vim.notify("buffers.grep module not found", vim.log.levels.WARN)
            end
        end
    end

    self.actions.send_to_qf = function()
        local items = {}
        local what = { title = self.opts.prompt or "Refer Selection" }

        local candidates = {}
        local has_marked = false
        for item, is_marked in pairs(self.marked) do
            if is_marked then
                has_marked = true
                table.insert(candidates, item)
            end
        end

        if not has_marked then
            local selection = self.current_matches[self.selected_index]
            if selection then
                table.insert(candidates, selection)
            end
        end

        if #candidates == 0 then
            return
        end

        self:close()

        for _, candidate in ipairs(candidates) do
            local item_data = { text = candidate }
            if self.parser then
                local parsed = self.parser(candidate)
                if parsed then
                    if parsed.filename then
                        item_data.filename = parsed.filename
                    end
                    if parsed.lnum then
                        item_data.lnum = parsed.lnum
                    end
                    if parsed.col then
                        item_data.col = parsed.col
                    end
                end
            end
            table.insert(items, item_data)
        end

        what.items = items
        vim.fn.setqflist({}, " ", what)
        vim.cmd "copen"
    end

    self.actions.close = function()
        self:cancel()
    end

    self.actions.cycle_sorter = function()
        self.sorter_idx = (self.sorter_idx % #self.available_sorters) + 1
        local name = self.available_sorters[self.sorter_idx]
        self.opts.sorter = fuzzy.sorters[name]
        self.custom_sorter = fuzzy.sorters[name]

        vim.notify("Sorter switched to: " .. name, vim.log.levels.INFO)
        self:refresh()
    end
end

---Update the items in the picker
---@param new_items table New list of items
function Picker:set_items(new_items)
    self.items_or_provider = new_items
    if self.use_blink then
        fuzzy.register_items(new_items)
    end
    self:refresh()
end

---Setup keymaps for the picker
function Picker:setup_keymaps()
    local default_keymaps = {
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
    }

    local keymaps = vim.tbl_extend("force", default_keymaps, self.opts.keymaps or {})

    ---@param key string Key to map
    ---@param func function Callback function
    local function map(key, func)
        vim.keymap.set("i", key, func, { buffer = self.input_buf })
    end

    local parameters = {
        original_win = self.original_win,
        original_buf = self.original_buf,
        original_cursor = self.original_cursor,
    }

    for key, handler in pairs(keymaps) do
        if type(handler) == "string" then
            if self.actions[handler] then
                map(key, self.actions[handler])
            end
        elseif type(handler) == "function" then
            map(key, function()
                local selection = self.current_matches[self.selected_index]
                ---@type BuiltinContext
                local builtin = {
                    picker = self,
                    actions = self.actions,
                    parameters = parameters,
                    marked = self.marked,
                }
                handler(selection, builtin)
            end)
        end
    end
end

---Setup autocommands for the picker
function Picker:setup_autocmds()
    local group = api.nvim_create_augroup("ReferLive", { clear = true })

    api.nvim_create_autocmd("TextChangedI", {
        buffer = self.input_buf,
        group = group,
        callback = function()
            self:refresh()
        end,
    })

    api.nvim_create_autocmd("WinLeave", {
        buffer = self.input_buf,
        group = group,
        callback = function()
            if self.is_previewing then
                return
            end
            self:cancel()
        end,
    })
end

return Picker
