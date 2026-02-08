---@class BlinkModule
local M = {}

local VERSION = "v1.8.0"
local BASE_URL = "https://github.com/Saghen/blink.cmp/releases/download"

---@type boolean Whether the module has been loaded
local has_loaded = false

---@type table|nil The loaded Rust module
local rust_module = nil

---@type boolean Whether a download is in progress
local is_downloading = false

---Get the library extension for the current OS
---@return string extension ".so", ".dylib", or ".dll"
local function get_lib_extension()
    if jit.os:lower() == "mac" or jit.os:lower() == "osx" then
        return ".dylib"
    elseif jit.os:lower() == "windows" then
        return ".dll"
    else
        return ".so"
    end
end

---Determine the system triple (e.g., x86_64-unknown-linux-gnu)
---@return string|nil triple System triple or nil if unsupported
local function get_system_triple()
    local os = jit.os:lower()
    local arch = jit.arch:lower()

    if os == "osx" or os == "mac" then
        if arch == "arm64" or arch == "aarch64" then
            return "aarch64-apple-darwin"
        end
        return "x86_64-apple-darwin"
    elseif os == "windows" then
        return "x86_64-pc-windows-msvc"
    elseif os == "linux" then
        local libc = "gnu"
        local f = io.open("/etc/alpine-release", "r")
        if f then
            libc = "musl"
            f:close()
        end

        if arch == "arm64" or arch == "aarch64" then
            return "aarch64-unknown-linux-" .. libc
        end
        return "x86_64-unknown-linux-" .. libc
    end
    return nil
end

---Get the local path for the library
---@return string path Path to the library file
local function get_lib_path()
    local info = debug.getinfo(1, "S")
    local script_path = info.source:sub(2)
    local script_dir = script_path:match "(.*/)" or "./"
    return script_dir .. "libblink_cmp_fuzzy" .. get_lib_extension()
end

---Download the binary if missing
---@return boolean started_download Whether download was started
local function ensure_binary()
    if has_loaded or is_downloading then
        return false
    end

    local lib_path = get_lib_path()
    if vim.uv.fs_stat(lib_path) then
        return false
    end

    local triple = get_system_triple()
    if not triple then
        vim.notify("Refer: System not supported for pre-built blink-fuzzy binaries.", vim.log.levels.ERROR)
        return false
    end

    local url = string.format("%s/%s/%s%s", BASE_URL, VERSION, triple, get_lib_extension())
    is_downloading = true

    vim.notify("Refer: Downloading fuzzy matcher library...", vim.log.levels.INFO)

    vim.system({
        "curl",
        "--fail",
        "--location",
        "--silent",
        "--show-error",
        "--create-dirs",
        "--output",
        lib_path,
        url,
    }, {}, function(out)
        is_downloading = false
        if out.code == 0 then
            vim.schedule(function()
                vim.notify("Refer: Fuzzy matcher downloaded successfully.", vim.log.levels.INFO)
            end)
        else
            vim.schedule(function()
                vim.notify(
                    "Refer: Failed to download fuzzy matcher: " .. (out.stderr or "unknown error"),
                    vim.log.levels.ERROR
                )
            end)
        end
    end)

    return true
end

---Load the Rust module
---@return table|nil module The loaded module or nil
local function load_module()
    local has_blink, blink = pcall(require, "blink.cmp.fuzzy.rust")
    if has_blink then
        return blink
    end

    if has_loaded then
        return rust_module
    end

    local lib_path = get_lib_path()
    if not vim.uv.fs_stat(lib_path) then
        ensure_binary()
        return nil
    end

    local open_func, err = package.loadlib(lib_path, "luaopen_blink_cmp_fuzzy")
    if not open_func then
        if not is_downloading then
            vim.notify("Refer: Failed to load fuzzy lib: " .. (err or "unknown"), vim.log.levels.ERROR)
            is_downloading = true
        end
        return nil
    end

    rust_module = open_func()
    has_loaded = true
    return rust_module
end

---Check if blink is available
---@return boolean available Whether blink fuzzy matcher is available
function M.is_available()
    return load_module() ~= nil
end

---Register items with the fuzzy matcher
---@param id string Context ID (e.g. "refer")
---@param items table List of items with label and sortText fields
function M.set_provider_items(id, items)
    local mod = load_module()
    if not mod then
        return
    end

    mod.set_provider_items(id, items)
end

---Perform fuzzy search
---@param query string Search query
---@param id string Context ID
---@return table|nil matches List of matched items
---@return table|nil indices List of matched indices
function M.fuzzy(query, id)
    local mod = load_module()
    if not mod then
        return nil, nil
    end

    -- Blink fuzzy signature: fuzzy(query, query_len, providers_list, opts)
    return mod.fuzzy(query, #query, { id }, {
        max_typos = 1,
        use_frecency = true,
        use_proximity = false,
        nearby_words = {},
        match_suffix = false,
        snippet_score_offset = 0,
        sorts = { "score", "sort_text" },
    })
end

return M
