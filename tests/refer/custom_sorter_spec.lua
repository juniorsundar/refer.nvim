local fuzzy = require "refer.fuzzy"
local refer = require "refer"

describe("refer (custom sorters)", function()
    it("can register and use a custom sorter directly", function()
        local function reverse_match(items, query)
            local matches = {}
            for _, item in ipairs(items) do
                if item == string.reverse(query) then
                    table.insert(matches, item)
                end
            end
            return matches
        end

        fuzzy.register_sorter("reverse", reverse_match)

        local items = { "abc", "cba", "xyz" }
        local res = fuzzy.filter(items, "abc", { sorter = "reverse" })

        assert.are.same({ "cba" }, res)
    end)

    it("can register custom sorters via setup options", function()
        local function prefix_match(items, query)
            local matches = {}
            for _, item in ipairs(items) do
                if vim.startswith(item, query) then
                    table.insert(matches, item)
                end
            end
            return matches
        end

        refer.setup {
            custom_sorters = {
                prefix = prefix_match,
            },
        }

        assert.is_not_nil(fuzzy.sorters["prefix"])

        local items = { "apple", "banana", "apricot" }
        local res = fuzzy.filter(items, "ap", { sorter = "prefix" })

        assert.are.same({ "apple", "apricot" }, res)
    end)

    it("ignores invalid sorter registration", function()
        fuzzy.register_sorter("invalid_1", 123)
        assert.is_nil(fuzzy.sorters["invalid_1"])

        fuzzy.register_sorter(123, function() end)
        assert.is_nil(fuzzy.sorters[123])
    end)
end)
