---@class HighlightModule
local M = {}

---@type table<string, string|nil> Cache of language names by filetype
local lang_cache = {}

---Safely set an extmark with error handling
---@param buf number Buffer handle
---@param ns number Namespace ID
---@param line number Line number (0-indexed)
---@param col number Column number (0-indexed)
---@param opts table Extmark options
---@return boolean success Whether extmark was set
---@return number|nil extmark_id The extmark ID or error message
local function safe_extmark(buf, ns, line, col, opts)
    return pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, col, opts)
end

---Get treesitter language for a filename
---@param filename string File path
---@return string|nil lang Language name or nil
local function get_lang(filename)
    local ft = vim.filetype.match { filename = filename }
    if not ft then
        local ext = vim.fn.fnamemodify(filename, ":e")
        if ext ~= "" then
            ft = ext
        end
    end

    if not ft then
        return nil
    end

    if lang_cache[ft] then
        return lang_cache[ft]
    end

    ---@type string|nil
    local lang = vim.treesitter.language.get_lang(ft) or ft
    local has_lang = pcall(vim.treesitter.language.add, lang)
    if not has_lang then
        lang = nil
    end

    lang_cache[ft] = lang
    return lang
end

---Highlight a single entry line
---@param buf number Buffer handle
---@param ns number Namespace ID
---@param line_idx number Line index (0-indexed)
---@param line string Line content
---@param highlight_code boolean Whether to highlight code content
function M.highlight_entry(buf, ns, line_idx, line, highlight_code)
    local bufnr = line:match "^(%d+): "
    if bufnr then
        safe_extmark(buf, ns, line_idx, 0, {
            end_col = #bufnr,
            hl_group = "WarningMsg",
            priority = 100,
        })

        local path_start = #bufnr + 3
        local path_part = line:sub(path_start)
        local dir_str = path_part:match "^(.*/)"
        if dir_str then
            safe_extmark(buf, ns, line_idx, path_start - 1, {
                end_col = path_start - 1 + #dir_str,
                hl_group = "Comment",
                priority = 100,
            })
        end
        return
    end

    local suffix_start = line:find ":%d+:%d+"
    local path_end = suffix_start and (suffix_start - 1) or #line
    local path_part = line:sub(1, path_end)

    local dir_str = path_part:match "^(.*/)"
    if dir_str then
        safe_extmark(buf, ns, line_idx, 0, {
            end_col = #dir_str,
            hl_group = "Comment",
            priority = 100,
        })
    end

    if suffix_start then
        local s, e = line:find(":%d+:", suffix_start)
        if s then
            safe_extmark(buf, ns, line_idx, s, {
                end_col = e - 1,
                hl_group = "String",
                priority = 100,
            })
        end

        if highlight_code then
            local _, coords_end = line:find(":%d+:%d+", suffix_start)
            if coords_end then
                local content_start = line:find(":", coords_end)
                if content_start then
                    local content = line:sub(content_start + 1)
                    M.highlight_code(buf, ns, line_idx, content_start, content, path_part)
                end
            end
        end
    end
end

---Highlight code content with treesitter
---@param buf number Buffer handle
---@param ns number Namespace ID
---@param row number Row index (0-indexed)
---@param start_col number Starting column
---@param content string Code content to highlight
---@param filename string Filename for language detection
function M.highlight_code(buf, ns, row, start_col, content, filename)
    local lang = get_lang(filename)
    if not lang then
        return
    end

    local ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
    if not ok or not parser then
        return
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    local query = vim.treesitter.query.get(lang, "highlights")
    if not query then
        return
    end

    for id, node, _ in query:iter_captures(root, content, 0, -1) do
        local capture_name = query.captures[id]
        local hl_group = "@" .. capture_name

        local _, c1, _, c2 = node:range()

        safe_extmark(buf, ns, row, start_col + c1, {
            end_col = start_col + c2,
            hl_group = hl_group,
            priority = 110,
        })
    end
end

return M
