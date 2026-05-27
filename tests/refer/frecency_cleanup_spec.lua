local refer = require "refer"
local frecency = require "refer.frecency"
local db = require "refer.frecency.db"
local stub = require "luassert.stub"

local function temp_path()
    return vim.fn.tempname() .. "_cleanup_test.json"
end

local function cleanup_path(path)
    if path and path ~= "" then
        vim.fn.delete(path, "rf")
        vim.fn.delete(vim.fn.fnamemodify(path, ":h"), "rf")
    end
end

local function read_json(path)
    local content = table.concat(vim.fn.readfile(path), "\n")
    return vim.json.decode(content)
end

local function table_size(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

local function read_lines(path)
    return vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
end

describe("refer.frecency cleanup", function()
    local path

    before_each(function()
        path = temp_path()
        db._reset()
        frecency.configure {
            enabled = true,
            buckets = false,
            neighborhood_size = 10,
            db_path = path,
        }
    end)

    after_each(function()
        db._reset()
        frecency.configure {
            enabled = true,
            buckets = false,
            neighborhood_size = 10,
        }
        cleanup_path(path)
    end)

    it("deletes records older than cleanup_max_age_days", function()
        local now = 2000000
        local thirty_days = 30 * 86400

        frecency.configure { cleanup_max_age_days = 30 }
        frecency.record("buffers", "old", {
            clock_fn = function()
                return now - thirty_days - 1
            end,
        })
        frecency.record("buffers", "fresh", {
            clock_fn = function()
                return now - thirty_days
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }

        assert.is_true(frecency.cleanup())

        local store = read_json(path)
        assert.is_nil(store.providers.buffers.old)
        assert.is_table(store.providers.buffers.fresh)
    end)

    it("caps each Provider by deleting the lowest frecency entries", function()
        local now = 2000000

        frecency.configure {
            max_entries_per_provider = 2,
            cleanup_max_age_days = 3650,
        }
        frecency.record("files", "low", {
            clock_fn = function()
                return now - 604800
            end,
        })
        frecency.record("files", "medium", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("files", "high", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("files", "high", {
            clock_fn = function()
                return now
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }

        assert.is_true(frecency.cleanup())

        local provider_store = read_json(path).providers.files
        assert.are.equal(2, table_size(provider_store))
        assert.is_nil(provider_store.low)
        assert.is_table(provider_store.medium)
        assert.is_table(provider_store.high)
    end)

    it("uses deterministic cap tie-breaking by item_key", function()
        local now = 2000000

        frecency.configure {
            max_entries_per_provider = 1,
            cleanup_max_age_days = 3650,
        }
        frecency.record("commands", "alpha", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("commands", "beta", {
            clock_fn = function()
                return now
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }

        assert.is_true(frecency.cleanup())

        local provider_store = read_json(path).providers.commands
        assert.are.equal(1, table_size(provider_store))
        assert.is_nil(provider_store.alpha)
        assert.is_table(provider_store.beta)
    end)

    it("uses last_selected_at before selected_count and item_key when cap scores tie", function()
        local now = 2000000

        frecency.configure {
            buckets = { { max_age = math.huge, divisor = math.huge } },
            max_entries_per_provider = 1,
            cleanup_max_age_days = 3650,
        }
        frecency.record("commands", "older", {
            clock_fn = function()
                return now - 10
            end,
        })
        frecency.record("commands", "newer", {
            clock_fn = function()
                return now
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }

        assert.is_true(frecency.cleanup())

        local provider_store = read_json(path).providers.commands
        assert.are.equal(1, table_size(provider_store))
        assert.is_nil(provider_store.older)
        assert.is_table(provider_store.newer)
    end)

    it("uses selected_count before item_key when cap scores and timestamps tie", function()
        local now = 2000000

        frecency.configure {
            buckets = { { max_age = math.huge, divisor = math.huge } },
            max_entries_per_provider = 1,
            cleanup_max_age_days = 3650,
        }
        frecency.record("commands", "lower_count", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("commands", "higher_count", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("commands", "higher_count", {
            clock_fn = function()
                return now
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }

        assert.is_true(frecency.cleanup())

        local provider_store = read_json(path).providers.commands
        assert.are.equal(1, table_size(provider_store))
        assert.is_nil(provider_store.lower_count)
        assert.is_table(provider_store.higher_count)
    end)

    it("does not rewrite providers at or below the cap", function()
        local now = 2000000

        frecency.configure {
            max_entries_per_provider = 2,
            cleanup_max_age_days = 3650,
        }
        frecency.record("help_tags", "one", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("help_tags", "two", {
            clock_fn = function()
                return now
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }

        assert.is_false(frecency.cleanup())

        local provider_store = read_json(path).providers.help_tags
        assert.are.equal(2, table_size(provider_store))
        assert.is_table(provider_store.one)
        assert.is_table(provider_store.two)
    end)

    it("does not touch the store when globally disabled", function()
        local now = 2000000

        frecency.record("buffers", "old", {
            clock_fn = function()
                return now - 365 * 86400
            end,
        })
        local before = read_lines(path)
        frecency.configure {
            enabled = false,
            cleanup_max_age_days = 30,
            clock_fn = function()
                return now
            end,
        }

        assert.is_false(frecency.cleanup())
        assert.are.same(before, read_lines(path))
    end)

    it("skips cleanup when no Frecency operations occurred", function()
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile({
            vim.json.encode {
                version = 1,
                providers = {
                    buffers = {
                        old = { selected_count = 1, last_selected_at = 1 },
                    },
                },
            },
        }, path)
        frecency.configure {
            cleanup_max_age_days = 30,
            clock_fn = function()
                return 2000000
            end,
        }
        local before = read_lines(path)

        assert.is_false(frecency.cleanup())
        assert.are.same(before, read_lines(path))
    end)

    it("runs cleanup after a read operation occurred", function()
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile({
            vim.json.encode {
                version = 1,
                providers = {
                    buffers = {
                        old = { selected_count = 1, last_selected_at = 1 },
                    },
                },
            },
        }, path)
        frecency.configure {
            cleanup_max_age_days = 30,
            clock_fn = function()
                return 4000000
            end,
        }

        assert.is_not_nil(frecency.score("buffers", { "old" }).old)
        assert.is_true(frecency.cleanup())
        assert.is_nil(read_json(path).providers.buffers.old)
    end)

    it("does not touch the store when the session is in no-op mode", function()
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile({ "{not json" }, path)
        local before = read_lines(path)

        assert.are.same({}, frecency.score("buffers", { "old" }))
        assert.is_false(frecency.cleanup())
        assert.are.same(before, read_lines(path))
    end)

    it("does not eagerly delete aged or stale entries during reads", function()
        local now = 2000000

        frecency.record("buffers", "stale", {
            clock_fn = function()
                return now - 365 * 86400
            end,
        })
        local before = read_lines(path)

        assert.are.same(
            {},
            frecency.score("buffers", { "current" }, {
                clock_fn = function()
                    return now
                end,
            })
        )
        assert.are.same(before, read_lines(path))
    end)

    it("does not eagerly delete aged or excess entries during writes", function()
        local now = 2000000

        frecency.configure {
            max_entries_per_provider = 1,
            cleanup_max_age_days = 30,
        }
        frecency.record("buffers", "old", {
            clock_fn = function()
                return now - 365 * 86400
            end,
        })
        frecency.record("buffers", "new", {
            clock_fn = function()
                return now
            end,
        })

        local provider_store = read_json(path).providers.buffers
        assert.are.equal(2, table_size(provider_store))
        assert.is_table(provider_store.old)
        assert.is_table(provider_store.new)
    end)

    it("logs one WARN and does not raise when cleanup rewrite fails", function()
        local now = 2000000
        local original_notify = vim.notify
        local notifications = {}

        frecency.configure { cleanup_max_age_days = 30 }
        frecency.record("buffers", "old", {
            clock_fn = function()
                return now - 365 * 86400
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end
        local rename_stub = stub(vim.fn, "rename", function()
            return 1
        end)

        local ok, result = pcall(frecency.cleanup)
        local ok_again = pcall(frecency.cleanup)
        rename_stub:revert()
        vim.notify = original_notify

        assert.is_true(ok)
        assert.is_false(result)
        assert.is_true(ok_again)
        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.WARN, notifications[1].level)
        assert.is_true(notifications[1].message:find("Could not replace JSON store", 1, true) ~= nil)
        assert.is_table(read_json(path).providers.buffers.old)
    end)

    it("accepts cleanup options through setup().frecency", function()
        local now = 2000000

        refer.setup {
            frecency = {
                db_path = path,
                cleanup_max_age_days = 30,
                max_entries_per_provider = 1,
                clock_fn = function()
                    return now
                end,
            },
        }
        frecency.record("buffers", "aged", {
            clock_fn = function()
                return now - 31 * 86400
            end,
        })
        frecency.record("buffers", "lower", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("buffers", "higher", {
            clock_fn = function()
                return now
            end,
        })
        frecency.record("buffers", "higher", {
            clock_fn = function()
                return now
            end,
        })
        frecency.configure {
            clock_fn = function()
                return now
            end,
        }

        assert.is_true(frecency.cleanup())

        local provider_store = read_json(path).providers.buffers
        assert.are.equal(1, table_size(provider_store))
        assert.is_nil(provider_store.aged)
        assert.is_nil(provider_store.lower)
        assert.is_table(provider_store.higher)
    end)

    it("registers a single VimLeavePre cleanup autocmd", function()
        frecency.configure { db_path = path }
        local autocmds = vim.api.nvim_get_autocmds { group = "ReferFrecencyCleanup", event = "VimLeavePre" }
        assert.are.equal(1, #autocmds)

        frecency.configure { db_path = path }
        autocmds = vim.api.nvim_get_autocmds { group = "ReferFrecencyCleanup", event = "VimLeavePre" }
        assert.are.equal(1, #autocmds)
    end)

    it("registers VimLeavePre cleanup during setup with default frecency options", function()
        pcall(vim.api.nvim_del_augroup_by_name, "ReferFrecencyCleanup")

        refer.setup {}

        local autocmds = vim.api.nvim_get_autocmds { group = "ReferFrecencyCleanup", event = "VimLeavePre" }
        assert.are.equal(1, #autocmds)
    end)

    it("does not raise from VimLeavePre when cleanup errors", function()
        local original_cleanup = frecency.cleanup
        frecency.cleanup = function()
            error "cleanup failed"
        end

        local ok = pcall(vim.api.nvim_exec_autocmds, "VimLeavePre", {
            group = "ReferFrecencyCleanup",
            modeline = false,
        })
        frecency.cleanup = original_cleanup

        assert.is_true(ok)
    end)
end)
