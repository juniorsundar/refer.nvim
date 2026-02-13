local api = vim.api
local util = require "refer.util"
local fuzzy = require "refer.fuzzy"

local M = {}

---Get default actions for a picker instance
---@param picker Picker The picker instance
---@return table<string, function> actions
function M.get_defaults(picker)
    return {
        refresh = function()
            picker:refresh()
        end,

        next_item = function()
            if #picker.current_matches > 0 then
                picker.selected_index = (picker.selected_index % #picker.current_matches) + 1
                picker:render()
            end
        end,

        prev_item = function()
            if #picker.current_matches > 0 then
                picker.selected_index = ((picker.selected_index - 2) % #picker.current_matches) + 1
                picker:render()
            end
        end,

        complete_selection = function()
            local selection = picker.current_matches[picker.selected_index]
            local input = api.nvim_get_current_line()

            if selection then
                local new_line = util.complete_line(input, selection)
                picker.ui:update_input { new_line }
                picker:refresh()
            end
        end,

        toggle_mark = function()
            local selection = picker.current_matches[picker.selected_index]
            if selection then
                picker.marked[selection] = not picker.marked[selection]
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
            local selection = picker.current_matches[picker.selected_index]
            if selection then
                picker:close()
                local data = picker.parser and picker.parser(selection)
                picker.on_select(selection, data)
            end
        end,

        send_to_grep = function()
            local lines = {}
            for item, is_marked in pairs(picker.marked) do
                if is_marked then
                    table.insert(lines, item)
                end
            end

            if #lines == 0 then
                local selection = picker.current_matches[picker.selected_index]
                if selection then
                    table.insert(lines, selection)
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
            for item, is_marked in pairs(picker.marked) do
                if is_marked then
                    has_marked = true
                    table.insert(candidates, item)
                end
            end

            if not has_marked then
                local selection = picker.current_matches[picker.selected_index]
                if selection then
                    table.insert(candidates, selection)
                end
            end

            if #candidates == 0 then
                return
            end

            picker:close()

            for _, candidate in ipairs(candidates) do
                local item_data = { text = candidate }
                if picker.parser then
                    local parsed = picker.parser(candidate)
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
                -- Restore original buffer
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
