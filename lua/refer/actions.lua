local api = vim.api
local util = require "refer.util"
local fuzzy = require "refer.fuzzy"

local M = {}

---Get default actions for a picker instance
---@param picker Picker The picker instance
---@return table<string, function> actions
function M.get_defaults(picker)
    local function get_selection_data()
        local item = picker.current_matches[picker.selected_index]
        if not item then
            return nil, nil
        end
        local selection = type(item) == "table" and item.text or item
        local data = (type(item) == "table" and item.data) or (picker.parser and picker.parser(selection))
        return selection, data
    end

    local function open_entry(cmd)
        local selection, data = get_selection_data()
        if not selection then
            return
        end

        picker:close()
        if cmd then
            vim.cmd(cmd)
        end
        util.jump_to_location(selection, data)
    end

    return {
        refresh = function()
            picker:refresh()
        end,

        next_item = function()
            picker:navigate(1)
        end,

        prev_item = function()
            picker:navigate(-1)
        end,

        complete_selection = function()
            local item = picker.current_matches[picker.selected_index]
            local input = api.nvim_get_current_line()

            if item then
                local selection
                if type(item) == "table" then
                    selection = (item.data and item.data.filename) or item.text
                else
                    selection = item
                end
                local new_line = util.complete_line(input, selection)
                picker.ui:update_input { new_line }
                picker:refresh()
            end
        end,

        toggle_mark = function()
            local item = picker.current_matches[picker.selected_index]
            if item then
                local key = type(item) == "table" and item.text or item
                picker.marked[key] = not picker.marked[key]
                picker.ui:render(picker.current_matches, picker.selected_index, picker.marked)
            end
            picker.actions.next_item()
        end,

        select_input = function()
            local current_input = api.nvim_get_current_line()
            picker:close()

            if picker.on_select and current_input ~= "" then
                picker.on_select(current_input, nil)
            end
        end,

        select_entry = function()
            local selection, data = get_selection_data()
            if not selection then
                return
            end

            picker:close()
            picker.on_select(selection, data)
        end,

        edit_entry = function()
            open_entry(nil)
        end,

        split_entry = function()
            open_entry "split"
        end,

        vsplit_entry = function()
            open_entry "vsplit"
        end,

        tab_entry = function()
            open_entry "tabnew"
        end,

        select_all = function()
            for _, item in ipairs(picker.current_matches) do
                local key = type(item) == "table" and item.text or item
                picker.marked[key] = true
            end
            picker.ui:render(picker.current_matches, picker.selected_index, picker.marked)
        end,

        deselect_all = function()
            picker.marked = {}
            picker.ui:render(picker.current_matches, picker.selected_index, picker.marked)
        end,

        toggle_all = function()
            for _, item in ipairs(picker.current_matches) do
                local key = type(item) == "table" and item.text or item
                picker.marked[key] = not picker.marked[key]
            end
            picker.ui:render(picker.current_matches, picker.selected_index, picker.marked)
        end,

        send_to_grep = function()
            local lines = {}
            for item_key, is_marked in pairs(picker.marked) do
                if is_marked then
                    table.insert(lines, item_key)
                end
            end

            if #lines == 0 then
                local item = picker.current_matches[picker.selected_index]
                if item then
                    local text = type(item) == "table" and item.text or item
                    table.insert(lines, text)
                end
            end

            if #lines > 0 then
                picker:close()
                local ok, grep_buf = pcall(require, "buffers.grep")
                if ok then
                    grep_buf.create_buffer(lines)
                else
                    vim.notify("buffers.grep module not found", vim.log.levels.WARN)
                end
            end
        end,

        send_to_qf = function()
            local items = {}
            local what = { title = picker.opts.prompt or "Refer Selection" }

            local candidates = {}
            local has_marked = false
            for item_key, is_marked in pairs(picker.marked) do
                if is_marked then
                    has_marked = true
                    table.insert(candidates, item_key)
                end
            end

            if not has_marked then
                local item = picker.current_matches[picker.selected_index]
                if item then
                    local text = type(item) == "table" and item.text or item
                    table.insert(candidates, text)
                end
            end

            if #candidates == 0 then
                return
            end

            -- Build a lookup from text -> ReferItem for data access
            local item_by_text = {}
            for _, item in ipairs(picker.current_matches) do
                if type(item) == "table" then
                    item_by_text[item.text] = item
                end
            end

            picker:close()

            for _, candidate in ipairs(candidates) do
                local refer_item = item_by_text[candidate]
                local item_data = { text = candidate }

                local parsed = (refer_item and refer_item.data) or (picker.parser and picker.parser(candidate))

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

                    if parsed.content then
                        item_data.text = parsed.content
                    elseif parsed.filename and parsed.lnum then
                        local prefix_col = string.format("%s:%d:%d:", parsed.filename, parsed.lnum, parsed.col or 0)
                        local prefix_no_col = string.format("%s:%d:", parsed.filename, parsed.lnum)

                        if vim.startswith(candidate, prefix_col) then
                            item_data.text = candidate:sub(#prefix_col + 1)
                        elseif vim.startswith(candidate, prefix_no_col) then
                            item_data.text = candidate:sub(#prefix_no_col + 1)
                        end
                    end
                end
                table.insert(items, item_data)
            end

            what.items = items
            vim.fn.setqflist({}, " ", what)
            vim.cmd "copen"
        end,

        close = function()
            picker:cancel()
        end,

        cycle_sorter = function()
            picker.sorter_idx = (picker.sorter_idx % #picker.available_sorters) + 1
            local name = picker.available_sorters[picker.sorter_idx]
            picker.opts.sorter = fuzzy.sorters[name]
            picker.custom_sorter = fuzzy.sorters[name]

            vim.notify("Sorter switched to: " .. name, vim.log.levels.INFO)
            picker:refresh()
        end,

        toggle_preview = function()
            picker.preview_enabled = not picker.preview_enabled
            if picker.preview_enabled then
                picker:update_preview()
                vim.notify("Preview enabled", vim.log.levels.INFO)
            else
                if api.nvim_win_is_valid(picker.original_win) and api.nvim_buf_is_valid(picker.original_buf) then
                    api.nvim_win_set_buf(picker.original_win, picker.original_buf)
                    api.nvim_win_set_cursor(picker.original_win, picker.original_cursor)
                end
                vim.notify("Preview disabled", vim.log.levels.INFO)
            end
        end,

        scroll_preview_up = function()
            if not picker.preview_enabled then
                return
            end
            if api.nvim_win_is_valid(picker.original_win) then
                api.nvim_win_call(picker.original_win, function()
                    vim.cmd "normal! \21"
                end)
            end
        end,

        scroll_preview_down = function()
            if not picker.preview_enabled then
                return
            end
            if api.nvim_win_is_valid(picker.original_win) then
                api.nvim_win_call(picker.original_win, function()
                    vim.cmd "normal! \4"
                end)
            end
        end,
    }
end

return M
