local api = vim.api
local highlight = require "refer.highlight"

local M = {}

---@class ReferUI
---@field base_prompt string The prompt text to display
---@field opts table Options table
---@field ns_cursor number Namespace ID for cursor/selection highlight extmarks
---@field ns_matches number Namespace ID for match/syntax highlight extmarks
---@field ns_marks number Namespace ID for multi-selection mark extmarks
---@field ns_id number Alias for ns_matches (backward compat for highlight.lua)
---@field prompt_ns number Namespace ID for prompt extmark
---@field is_rendering boolean Guard flag to prevent CursorMoved re-entrancy
---@field input_buf number|nil Input buffer handle
---@field input_win number|nil Input window handle
---@field results_buf number|nil Results buffer handle
---@field results_win number|nil Results window handle
local UI = {}
UI.__index = UI

---Create a new UI instance
---@param prompt_text string The prompt text
---@param opts table|nil Options table
---@return ReferUI ui New UI instance
function M.new(prompt_text, opts)
    ---@type ReferUI
    local self = setmetatable({}, UI)
    self.base_prompt = prompt_text
    self.opts = opts or {}
    self.ns_cursor = api.nvim_create_namespace "refer_cursor"
    self.ns_matches = api.nvim_create_namespace "refer_matches"
    self.ns_marks = api.nvim_create_namespace "refer_marks"
    self.ns_id = self.ns_matches -- backward-compat alias used by highlight.lua
    self.prompt_ns = api.nvim_create_namespace "refer_prompt"
    self.is_rendering = false
    return self
end

---Calculate window height based on item count
---@param count number Number of items to display
---@return number height Calculated height
function UI:get_height(count)
    local max_lines = self.opts.max_height
    if not max_lines then
        local max_height_percent = self.opts.max_height_percent or 0.4
        max_lines = math.floor(vim.o.lines * max_height_percent)
    end

    local height = math.min(max_lines, count)
    local min_lines = self.opts.min_height or 1
    return math.max(min_lines, height)
end

---Create picker windows
---@param initial_count number|nil Initial number of items to pre-size the results window
---@return number input_buf Input buffer handle
---@return number input_win Input window handle
function UI:create_windows(initial_count)
    self.input_buf = api.nvim_create_buf(false, true)
    self.results_buf = api.nvim_create_buf(false, true)

    vim.bo[self.input_buf].filetype = "refer_input"
    vim.bo[self.results_buf].filetype = "refer_results"

    local input_pos = "top"
    if self.opts.ui and self.opts.ui.input_position then
        input_pos = self.opts.ui.input_position
    end

    local initial_height = self:get_height(initial_count or 0)

    if input_pos == "bottom" then
        vim.cmd "botright 1split"
        self.input_win = api.nvim_get_current_win()
        api.nvim_win_set_buf(self.input_win, self.input_buf)
        self:_configure_window(self.input_win)
        vim.wo[self.input_win].winfixheight = true

        vim.cmd("leftabove " .. initial_height .. "split")
        self.results_win = api.nvim_get_current_win()
        api.nvim_win_set_buf(self.results_win, self.results_buf)
        self:_configure_window(self.results_win)

        -- Force correct heights after Neovim's automatic split redistribution
        if api.nvim_win_is_valid(self.results_win) then
            api.nvim_win_set_height(self.results_win, initial_height)
        end
        if api.nvim_win_is_valid(self.input_win) then
            api.nvim_win_set_height(self.input_win, 1)
        end
    else
        vim.cmd("botright " .. initial_height .. "split")
        self.results_win = api.nvim_get_current_win()
        api.nvim_win_set_buf(self.results_win, self.results_buf)
        self:_configure_window(self.results_win)

        vim.cmd "leftabove 1split"
        self.input_win = api.nvim_get_current_win()
        api.nvim_win_set_buf(self.input_win, self.input_buf)
        self:_configure_window(self.input_win)
        vim.wo[self.input_win].winfixheight = true
        vim.cmd "resize 1"

        -- Force correct heights after Neovim's automatic split redistribution
        if api.nvim_win_is_valid(self.results_win) then
            api.nvim_win_set_height(self.results_win, initial_height)
        end
        if api.nvim_win_is_valid(self.input_win) then
            api.nvim_win_set_height(self.input_win, 1)
        end
    end

    api.nvim_set_current_win(self.input_win)
    self:update_prompt_virtual_text(self.base_prompt)

    return self.input_buf, self.input_win
end

---Configure window options
---@param win_id number Window handle
function UI:_configure_window(win_id)
    vim.wo[win_id].number = false
    vim.wo[win_id].relativenumber = false
    vim.wo[win_id].signcolumn = "yes"
    vim.wo[win_id].cursorline = false
    vim.wo[win_id].foldcolumn = "0"
    vim.wo[win_id].spell = false
    vim.wo[win_id].list = false

    local winhighlight = "Normal:Normal,FloatBorder:Normal,WinSeparator:Normal,StatusLine:Normal,StatusLineNC:Normal"
    if self.opts.ui and self.opts.ui.winhighlight then
        winhighlight = self.opts.ui.winhighlight
    end
    vim.wo[win_id].winhighlight = winhighlight

    vim.wo[win_id].fillchars = "eob: ,horiz: ,horizup: ,horizdown: ,vert: ,vertleft: ,vertright: ,verthoriz: "
    vim.wo[win_id].statusline = " "
end

---Update the virtual text prompt
---@param text string Text to display as prompt
function UI:update_prompt_virtual_text(text)
    if self.input_buf and api.nvim_buf_is_valid(self.input_buf) then
        local hl_group = "Title"
        if self.opts.ui and self.opts.ui.highlights and self.opts.ui.highlights.prompt then
            hl_group = self.opts.ui.highlights.prompt
        end

        api.nvim_buf_set_extmark(self.input_buf, self.prompt_ns, 0, 0, {
            id = 1,
            virt_text = { { text, hl_group } },
            virt_text_pos = "inline",
            right_gravity = false,
        })
    end
end

---Render matches to the results window
---@param matches table<string> List of match strings
---@param selected_index number Currently selected index
---@param marked table<string, boolean>|nil Map of marked items
function UI:render(matches, selected_index, marked)
    self.is_rendering = true

    local total = #matches
    local current = selected_index

    local win_height = self:get_height(total)

    if self.results_win and api.nvim_win_is_valid(self.results_win) then
        api.nvim_win_set_height(self.results_win, win_height)
        if self.input_win and api.nvim_win_is_valid(self.input_win) then
            api.nvim_win_set_height(self.input_win, 1)
        end
    end

    local count_str = ""
    if total > 0 then
        count_str = string.format("%d/%d ", current, total)
    else
        count_str = "0/0 "
    end

    local input_cursor
    if self.input_win and api.nvim_win_is_valid(self.input_win) then
        input_cursor = api.nvim_win_get_cursor(self.input_win)
    end
    self:update_prompt_virtual_text(count_str .. self.base_prompt)
    if input_cursor and self.input_win and api.nvim_win_is_valid(self.input_win) then
        pcall(api.nvim_win_set_cursor, self.input_win, input_cursor)
    end

    if total == 0 then
        api.nvim_buf_set_lines(self.results_buf, 0, -1, false, { " " })
        self.is_rendering = false
        return
    end

    local start_idx = 1
    local end_idx = total

    if total > win_height then
        local half_height = math.floor(win_height / 2)
        start_idx = math.max(1, selected_index - half_height)
        end_idx = math.min(total, start_idx + win_height - 1)

        if end_idx - start_idx + 1 < win_height then
            start_idx = math.max(1, end_idx - win_height + 1)
        end
    end

    local reverse_result = self.opts.ui and self.opts.ui.reverse_result

    local visible_matches = {}
    if reverse_result then
        for i = end_idx, start_idx, -1 do
            table.insert(visible_matches, matches[i])
        end
    else
        for i = start_idx, end_idx do
            table.insert(visible_matches, matches[i])
        end
    end

    -- Extract text strings for buffer writing (items may be ReferItem tables)
    local function item_text(item)
        return (type(item) == "table") and item.text or (item or "")
    end

    local current_lines = api.nvim_buf_get_lines(self.results_buf, 0, -1, false)
    local current_count = #current_lines
    local new_count = #visible_matches

    local first_diff
    if current_count ~= new_count then
        local min_count = math.min(current_count, new_count)
        first_diff = min_count + 1
        for i = 1, min_count do
            if (current_lines[i] or "") ~= item_text(visible_matches[i]) then
                first_diff = i
                break
            end
        end

        local tail = {}
        for i = first_diff, new_count do
            table.insert(tail, item_text(visible_matches[i]))
        end
        api.nvim_buf_set_lines(self.results_buf, first_diff - 1, -1, false, tail)
    else
        first_diff = new_count + 1
        for i = 1, new_count do
            local old_line = current_lines[i] or ""
            local new_line = item_text(visible_matches[i])
            if old_line ~= new_line then
                if first_diff > i then
                    first_diff = i
                end
                api.nvim_buf_set_lines(self.results_buf, i - 1, i, false, { new_line })
            end
        end
    end

    api.nvim_buf_clear_namespace(self.results_buf, self.ns_cursor, 0, -1)
    if first_diff <= new_count then
        api.nvim_buf_clear_namespace(self.results_buf, self.ns_matches, first_diff - 1, -1)
        api.nvim_buf_clear_namespace(self.results_buf, self.ns_marks, first_diff - 1, -1)
    end

    if first_diff <= new_count then
        for i = first_diff, new_count do
            local line = item_text(visible_matches[i])
            local line_idx = i - 1
            local hl_code = true
            if self.opts.highlight_code ~= nil then
                hl_code = self.opts.highlight_code
            end
            -- ns_matches (== ns_id) is passed so highlight.lua continues to work unchanged
            highlight.highlight_entry(self.results_buf, self.ns_matches, line_idx, line, hl_code, self.opts)

            if marked and marked[line] then
                local mark_char = "●"
                local mark_hl = "String"
                if self.opts.ui then
                    mark_char = self.opts.ui.mark_char or mark_char
                    mark_hl = self.opts.ui.mark_hl or mark_hl
                end

                api.nvim_buf_set_extmark(self.results_buf, self.ns_marks, line_idx, 0, {
                    sign_text = mark_char,
                    sign_hl_group = mark_hl,
                    priority = 105,
                })
            end
        end
    end

    local relative_selected_idx
    if self.opts.ui and self.opts.ui.reverse_result then
        relative_selected_idx = end_idx - selected_index + 1
    else
        relative_selected_idx = selected_index - start_idx + 1
    end
    if relative_selected_idx > 0 and relative_selected_idx <= #visible_matches then
        local selected_text = item_text(visible_matches[relative_selected_idx])
        local selection_hl = "Visual"
        if self.opts.ui and self.opts.ui.highlights and self.opts.ui.highlights.selection then
            selection_hl = self.opts.ui.highlights.selection
        end

        api.nvim_buf_set_extmark(self.results_buf, self.ns_cursor, relative_selected_idx - 1, 0, {
            end_row = relative_selected_idx - 1,
            end_col = #selected_text,
            hl_group = selection_hl,
            priority = 100,
        })
        pcall(api.nvim_win_set_cursor, self.results_win, { relative_selected_idx, 0 })
    end

    self.is_rendering = false
end

---Fast path: update only the selection highlight without redrawing the buffer.
---Called by the picker for pure up/down navigation (no query or items change).
---@param old_abs_idx number Previous selected_index (1-based, absolute in matches list)
---@param new_abs_idx number New selected_index (1-based, absolute in matches list)
---@param total number Total number of matches
---@param selected_text string The text of the newly selected line (for hl end_col)
---@param count_str string Updated "N/M " prompt prefix
function UI:update_selection(old_abs_idx, new_abs_idx, total, selected_text, count_str)
    if self.is_rendering then
        return
    end
    if not self.results_buf or not api.nvim_buf_is_valid(self.results_buf) then
        return
    end
    if not self.results_win or not api.nvim_win_is_valid(self.results_win) then
        return
    end

    self.is_rendering = true

    local input_cursor
    if self.input_win and api.nvim_win_is_valid(self.input_win) then
        input_cursor = api.nvim_win_get_cursor(self.input_win)
    end
    self:update_prompt_virtual_text(count_str .. self.base_prompt)
    if input_cursor and self.input_win and api.nvim_win_is_valid(self.input_win) then
        pcall(api.nvim_win_set_cursor, self.input_win, input_cursor)
    end

    local win_height = self:get_height(total)
    local reverse_result = self.opts.ui and self.opts.ui.reverse_result

    local start_idx = 1
    local end_idx = total
    if total > win_height then
        local half_height = math.floor(win_height / 2)
        start_idx = math.max(1, new_abs_idx - half_height)
        end_idx = math.min(total, start_idx + win_height - 1)
        if end_idx - start_idx + 1 < win_height then
            start_idx = math.max(1, end_idx - win_height + 1)
        end
    end

    local old_start_idx = start_idx
    if total > win_height then
        local half_height = math.floor(win_height / 2)
        old_start_idx = math.max(1, old_abs_idx - half_height)
        local old_end_idx = math.min(total, old_start_idx + win_height - 1)
        if old_end_idx - old_start_idx + 1 < win_height then
            old_start_idx = math.max(1, old_end_idx - win_height + 1)
        end
    end

    if old_start_idx ~= start_idx then
        self.is_rendering = false
        return false
    end

    local old_rel, new_rel
    if reverse_result then
        old_rel = end_idx - old_abs_idx + 1
        new_rel = end_idx - new_abs_idx + 1
    else
        old_rel = old_abs_idx - start_idx + 1
        new_rel = new_abs_idx - start_idx + 1
    end

    if old_rel >= 1 then
        api.nvim_buf_clear_namespace(self.results_buf, self.ns_cursor, old_rel - 1, old_rel)
    end

    local buf_line_count = api.nvim_buf_line_count(self.results_buf)
    if new_rel >= 1 and new_rel <= (end_idx - start_idx + 1) and (new_rel - 1) < buf_line_count then
        local selection_hl = "Visual"
        if self.opts.ui and self.opts.ui.highlights and self.opts.ui.highlights.selection then
            selection_hl = self.opts.ui.highlights.selection
        end
        local buf_line = api.nvim_buf_get_lines(self.results_buf, new_rel - 1, new_rel, false)[1] or ""
        api.nvim_buf_set_extmark(self.results_buf, self.ns_cursor, new_rel - 1, 0, {
            end_row = new_rel - 1,
            end_col = #buf_line,
            hl_group = selection_hl,
            priority = 100,
        })
        pcall(api.nvim_win_set_cursor, self.results_win, { new_rel, 0 })
    end

    self.is_rendering = false
    return true
end

---Set a new prompt text
---@param text string New prompt text
function UI:set_prompt(text)
    self.base_prompt = text
    self:update_prompt_virtual_text(text)
end

---Update input buffer with new lines
---@param lines table<string> Lines to set
function UI:update_input(lines)
    api.nvim_buf_set_lines(self.input_buf, 0, -1, false, lines)
    api.nvim_win_set_cursor(self.input_win, { 1, #lines[1] })
end

---Close all picker windows and buffers
function UI:close()
    if self.results_win and api.nvim_win_is_valid(self.results_win) then
        pcall(api.nvim_win_close, self.results_win, true)
    end
    if self.input_win and api.nvim_win_is_valid(self.input_win) then
        pcall(api.nvim_win_close, self.input_win, true)
    end

    if self.results_buf and api.nvim_buf_is_valid(self.results_buf) then
        api.nvim_buf_delete(self.results_buf, { force = true })
    end
    if self.input_buf and api.nvim_buf_is_valid(self.input_buf) then
        api.nvim_buf_delete(self.input_buf, { force = true })
    end
    vim.cmd "stopinsert"
end

return M
