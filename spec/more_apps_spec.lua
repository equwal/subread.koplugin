local MoreApps = require("subread.more_apps")

describe("MoreApps", function()
    it("gives each app a name, a line and an https address without parameters", function()
        assert.is_true(#MoreApps.list > 1)
        local seen = {}
        for _, app in ipairs(MoreApps.list) do
            assert.is_true(type(app.name) == "string" and app.name ~= "")
            assert.is_true(type(app.line) == "string" and app.line ~= "")
            -- No query and no fragment, so no tracking parameters.
            assert.is_not_nil(app.url:match("^https://[^?#%s]+$"))
            assert.is_nil(seen[app.url])
            seen[app.url] = true
        end
    end)

    it("does not list the plugin itself", function()
        for _, app in ipairs(MoreApps.list) do
            assert.is_nil(app.url:find("subread.koplugin", 1, true))
        end
    end)

    it("ends with the list of all projects", function()
        assert.equals("https://recentlywritten.com/projects.html", MoreApps.list[#MoreApps.list].url)
    end)

    it("shows the name, the line and the address of each app as text", function()
        local text = MoreApps.text()
        for _, app in ipairs(MoreApps.list) do
            assert.is_not_nil(text:find(app.name .. "\n" .. app.line .. "\n" .. app.url, 1, true))
        end
    end)
end)
