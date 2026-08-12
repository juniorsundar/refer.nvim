local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

function M.check()
    start "refer.nvim"

    if vim.fn.has "nvim-0.10" == 1 then
        ok "Neovim version >= 0.10 (Required for vim.system)"
    else
        error "Neovim version < 0.10 (Required for vim.system)"
    end

    local fd_cmd = "fd"
    if vim.fn.executable "fdfind" == 1 then
        fd_cmd = "fdfind"
    end

    if vim.fn.executable(fd_cmd) == 1 then
        ok(string.format("Found '%s' (for file finding)", fd_cmd))
        local v = vim.fn.system({ fd_cmd, "--version" }):gsub("\n", "")
        info("Version: " .. v)
    else
        warn "fd/fdfind not found. File picker will not work unless configured manually."
    end

    if vim.fn.executable "rg" == 1 then
        ok "Found 'rg' (for grep/live_grep)"
        local v = vim.fn.system({ "rg", "--version" }):match "ripgrep ([%d%.]+)"
        info("Version: " .. (v or "unknown"))
    else
        warn "ripgrep (rg) not found. Grep picker will not work unless configured manually."
    end

    if vim.fn.executable "curl" == 1 then
        ok "Found 'curl' (for downloading fuzzy matcher)"
    else
        warn "curl not found. Automatic download of fuzzy matcher binary will fail."
    end

    local has_refer, refer = pcall(require, "refer")
    if has_refer then
        local config = refer.get_opts()

        local files_cmd = config.providers.files.find_command
        if type(files_cmd) == "table" then
            if vim.fn.executable(files_cmd[1]) == 1 then
                ok(string.format("Files command '%s' is executable", files_cmd[1]))
            else
                error(string.format("Files command '%s' is not executable", files_cmd[1]))
            end
        elseif type(files_cmd) == "function" then
            info "Files command is a custom function"
        else
            error "Invalid files command configuration"
        end

        local grep_cmd = config.providers.grep.grep_command
        if type(grep_cmd) == "table" then
            if vim.fn.executable(grep_cmd[1]) == 1 then
                ok(string.format("Grep command '%s' is executable", grep_cmd[1]))
            else
                error(string.format("Grep command '%s' is not executable", grep_cmd[1]))
            end
        elseif type(grep_cmd) == "function" then
            info "Grep command is a custom function"
        else
            error "Invalid grep command configuration"
        end
    else
        error "Could not load refer module"
    end

    local has_blink, blink = pcall(require, "refer.blink")
    if has_blink then
        if blink.is_available() then
            ok "Blink fuzzy matcher is available"
        else
            if not (pcall(require, "blink.cmp") or pcall(require, "blink.cmp.fuzzy.rust")) then
                info "blink.cmp is not installed. Refer.nvim will prompt to download the pre-built v1.10.2 fuzzy matcher on first use (opt-in)."
            else
                info "blink.cmp is installed but the fuzzy Rust module is not built yet. Run :h blink.cmp.build() (v2) or ensure the pre-built binary is present (v1)."
            end
            if vim.fn.executable "curl" ~= 1 then
                warn "curl is missing; the pre-built fuzzy matcher cannot be downloaded."
            end

            local os_name = jit.os:lower()
            local arch = jit.arch:lower()
            info(string.format("System detected: OS=%s, Arch=%s", os_name, arch))

            if not (os_name == "linux" or os_name == "osx" or os_name == "mac" or os_name == "windows") then
                warn "Unsupported OS for pre-built binaries"
            end
        end
    else
        error "Could not load refer.blink module"
    end
end

return M
