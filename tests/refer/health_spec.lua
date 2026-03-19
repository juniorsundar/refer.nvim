local stub = require "luassert.stub"

describe("refer.health", function()
    local health
    local records
    local original_health
    local executable_stub
    local system_stub
    local refer_stub
    local blink_stub

    local function load_health()
        package.loaded["refer.health"] = nil
        return require "refer.health"
    end

    before_each(function()
        records = {}
        original_health = vim.health
        vim.health = {
            start = function(msg)
                table.insert(records, { kind = "start", msg = msg })
            end,
            ok = function(msg)
                table.insert(records, { kind = "ok", msg = msg })
            end,
            warn = function(msg)
                table.insert(records, { kind = "warn", msg = msg })
            end,
            error = function(msg)
                table.insert(records, { kind = "error", msg = msg })
            end,
            info = function(msg)
                table.insert(records, { kind = "info", msg = msg })
            end,
        }
    end)

    after_each(function()
        vim.health = original_health
        package.loaded["refer.health"] = nil
        if executable_stub then
            executable_stub:revert()
        end
        if system_stub then
            system_stub:revert()
        end
        if refer_stub then
            package.loaded["refer"] = refer_stub
        end
        if blink_stub then
            package.loaded["refer.blink"] = blink_stub
        end
    end)

    local function messages(kind)
        local result = {}
        for _, record in ipairs(records) do
            if record.kind == kind then
                table.insert(result, record.msg)
            end
        end
        return result
    end

    it("warns when fd/fdfind and rg are missing", function()
        executable_stub = stub(vim.fn, "executable", function(cmd)
            if cmd == "fd" or cmd == "fdfind" or cmd == "rg" then
                return 0
            end
            return 1
        end)
        system_stub = stub(vim.fn, "system", function(cmd)
            if cmd[1] == "curl" then
                return "curl 1.0\n"
            end
            return ""
        end)

        refer_stub = package.loaded["refer"]
        package.loaded["refer"] = {
            get_opts = function()
                return {
                    providers = {
                        files = { find_command = { "fd" } },
                        grep = { grep_command = { "rg" } },
                    },
                }
            end,
        }

        blink_stub = package.loaded["refer.blink"]
        package.loaded["refer.blink"] = {
            is_available = function()
                return true
            end,
        }

        health = load_health()
        health.check()

        assert.is_true(vim.tbl_contains(messages "warn", "fd/fdfind not found. File picker will not work unless configured manually."))
        assert.is_true(vim.tbl_contains(messages "warn", "ripgrep (rg) not found. Grep picker will not work unless configured manually."))
        assert.is_true(vim.tbl_contains(messages "error", "Files command 'fd' is not executable"))
        assert.is_true(vim.tbl_contains(messages "error", "Grep command 'rg' is not executable"))
    end)

    it("reports configured command executability and versions", function()
        executable_stub = stub(vim.fn, "executable", function(cmd)
            if cmd == "fd" or cmd == "rg" or cmd == "curl" then
                return 1
            end
            return 0
        end)
        system_stub = stub(vim.fn, "system", function(cmd)
            if cmd[1] == "fd" then
                return "fd 9.0.0\n"
            end
            if cmd[1] == "rg" then
                return "ripgrep 14.1.0\n"
            end
            return ""
        end)

        refer_stub = package.loaded["refer"]
        package.loaded["refer"] = {
            get_opts = function()
                return {
                    providers = {
                        files = { find_command = { "fd", "--hidden" } },
                        grep = { grep_command = { "rg", "--vimgrep" } },
                    },
                }
            end,
        }

        blink_stub = package.loaded["refer.blink"]
        package.loaded["refer.blink"] = {
            is_available = function()
                return true
            end,
        }

        health = load_health()
        health.check()

        assert.is_true(vim.tbl_contains(messages "ok", "Found 'fd' (for file finding)"))
        assert.is_true(vim.tbl_contains(messages "ok", "Found 'rg' (for grep/live_grep)"))
        assert.is_true(vim.tbl_contains(messages "ok", "Files command 'fd' is executable"))
        assert.is_true(vim.tbl_contains(messages "ok", "Grep command 'rg' is executable"))
        assert.is_true(vim.tbl_contains(messages "info", "Version: fd 9.0.0"))
        assert.is_true(vim.tbl_contains(messages "info", "Version: 14.1.0"))
    end)

    it("accepts custom command functions", function()
        executable_stub = stub(vim.fn, "executable", function(cmd)
            return cmd == "curl" and 1 or 0
        end)
        system_stub = stub(vim.fn, "system", function()
            return ""
        end)

        refer_stub = package.loaded["refer"]
        package.loaded["refer"] = {
            get_opts = function()
                return {
                    providers = {
                        files = { find_command = function() end },
                        grep = { grep_command = function() end },
                    },
                }
            end,
        }

        blink_stub = package.loaded["refer.blink"]
        package.loaded["refer.blink"] = {
            is_available = function()
                return true
            end,
        }

        health = load_health()
        health.check()

        assert.is_true(vim.tbl_contains(messages "info", "Files command is a custom function"))
        assert.is_true(vim.tbl_contains(messages "info", "Grep command is a custom function"))
    end)
end)
