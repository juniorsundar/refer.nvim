local api = vim.api
local highlight = require "refer.highlight"

local M = {}

---@class ReferUI
---@field base_prompt string The prompt text to display
---@field opts table Options table
---@field ns_id number Namespace ID for extmarks
---@field prompt_ns number Namespace ID for prompt extmark
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
    self.ns_id = api.nvim_create_namespace "refer"
    self.prompt_ns = api.nvim_create_namespace "refer_prompt"
    return self
end

---Calculate window height based on item count
---@param count number Number of items to display
---@return number height Calculated height
function UI:get_height(count)
    local percent = self.opts.percent or 0.4
    local max_height = math.floor(vim.o.lines * percent)
    local height = math.min(max_height, count)
    return math.max(1, height)
end

---Create picker windows
---@return number input_buf Input buffer handle
---@return number input_win Input window handle
function UI:create_windows()
    self.input_buf = api.nvim_create_buf(false, true)
    self.results_buf = api.nvim_create_buf(false, true)

    vim.bo[self.input_buf].filetype = "refer_input"
    vim.bo[self.results_buf].filetype = "refer_results"

    vim.cmd("botright " .. self:get_height(0) .. "split")
    self.results_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.results_win, self.results_buf)

    self:_configure_window(self.results_win)

    vim.cmd "leftabove 1split"
    self.input_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.input_win, self.input_buf)

    self:_configure_window(self.input_win)
    vim.wo[self.input_win].winfixheight = true
    vim.cmd "resize 1"

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
    vim.wo[win_id].winhighlight =
        "Normal:Normal,FloatBorder:Normal,WinSeparator:Normal,StatusLine:Normal,StatusLineNC:Normal"
    vim.wo[win_id].fillchars = "eob: ,horiz: ,horizup: ,horizdown: ,vert: ,vertleft: ,vertright: ,verthoriz: "
    vim.wo[win_id].statusline = " "
end

---Update the virtual text prompt
---@param text string Text to display as prompt
function UI:update_prompt_virtual_text(text)
    if self.input_buf and api.nvim_buf_is_valid(self.input_buf) then
        api.nvim_buf_clear_namespace(self.input_buf, self.prompt_ns, 0, -1)
        api.nvim_buf_set_extmark(self.input_buf, self.prompt_ns, 0, 0, {
            virt_text = { { text, "Title" } },
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

    self:update_prompt_virtual_text(count_str .. self.base_prompt)

    if total == 0 then
        api.nvim_buf_set_lines(self.results_buf, 0, -1, false, { " " })
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

    local visible_matches = {}
    for i = start_idx, end_idx do
        table.insert(visible_matches, matches[i])
    end

    api.nvim_buf_set_lines(self.results_buf, 0, -1, false, visible_matches)
    api.nvim_buf_clear_namespace(self.results_buf, self.ns_id, 0, -1)

    for i, line in ipairs(visible_matches) do
        local line_idx = i - 1
        highlight.highlight_entry(self.results_buf, self.ns_id, line_idx, line, true)

        if marked and marked[line] then
            api.nvim_buf_set_extmark(self.results_buf, self.ns_id, line_idx, 0, {
                sign_text = "●",
                sign_hl_group = "String",
                priority = 105,
            })
        end
    end

    local relative_selected_idx = selected_index - start_idx + 1
    if relative_selected_idx > 0 and relative_selected_idx <= #visible_matches then
        local selected_text = visible_matches[relative_selected_idx]

        api.nvim_buf_set_extmark(self.results_buf, self.ns_id, relative_selected_idx - 1, 0, {
            end_row = relative_selected_idx - 1,
            end_col = #selected_text,
            hl_group = "Visual",
            priority = 100,
        })
        pcall(api.nvim_win_set_cursor, self.results_win, { relative_selected_idx, 0 })
    end
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
