local api = vim.api
local util = require "refer.util"

---@class PreviewModule
local M = {}

---@type number|nil Cached preview buffer handle
local preview_buf = nil

---@class PreviewOpts
---@field filename string File path to preview
---@field lnum? number Line number to jump to (1-indexed)
---@field col? number Column number to jump to (1-indexed)
---@field target_win number Window handle to show preview in

---Show preview in the target window
---@param opts PreviewOpts Preview options
function M.show(opts)
    local filename = opts.filename
    local lnum = opts.lnum or 1
    local col = opts.col or 1
    local target_win = opts.target_win

    if not api.nvim_win_is_valid(target_win) then
        return
    end

    api.nvim_win_call(target_win, function()
        local bufnr = vim.fn.bufnr(filename)

        if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
            if api.nvim_win_get_buf(target_win) ~= bufnr then
                api.nvim_win_set_buf(target_win, bufnr)
            end
        else
            if not preview_buf or not api.nvim_buf_is_valid(preview_buf) then
                preview_buf = api.nvim_create_buf(false, true)
                vim.bo[preview_buf].bufhidden = "hide"
                vim.bo[preview_buf].buftype = "nofile"
                vim.bo[preview_buf].swapfile = false
            end

            local buf = preview_buf

            local display_name = filename .. " (Preview)"
            pcall(api.nvim_buf_set_name, buf, display_name)

            if util.is_binary(filename) then
                api.nvim_buf_set_lines(buf, 0, -1, false, { "[Binary File - Preview Disabled]" })
            else
                local lines = {}
                if vim.fn.filereadable(filename) == 1 then
                    lines = vim.fn.readfile(filename, "", 1000)
                end

                for i, line in ipairs(lines) do
                    if line:find "[\r\n]" then
                        lines[i] = line:gsub("[\r\n]", " ")
                    end
                end

                api.nvim_buf_set_lines(buf, 0, -1, false, lines)

                local ft = vim.filetype.match { filename = filename }
                if ft then
                    vim.bo[buf].filetype = ft
                end
            end

            api.nvim_win_set_buf(target_win, buf)
        end

        if lnum and col then
            pcall(api.nvim_win_set_cursor, target_win, { lnum, col - 1 })
            vim.cmd "normal! zz"
        end
    end)
end

---Clean up the preview buffer
function M.cleanup()
    if preview_buf and api.nvim_buf_is_valid(preview_buf) then
        api.nvim_buf_delete(preview_buf, { force = true })
    end
    preview_buf = nil
end

return M
