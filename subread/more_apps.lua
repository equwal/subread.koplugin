--[[--
The other apps and sites of the author, for the "More apps" entry of the
menu.

Pure Lua. No KOReader dependency, so it can be unit tested on a PC.

KOReader cannot open a web browser on each device, so the menu shows each
address as text.
--]]--

local MoreApps = {}

-- The order of the link catalog: the sites, then the Android apps, then the
-- list of all projects. The plugin itself is not in the list.
MoreApps.list = {
    { name = "SubRead", url = "https://subread.space/",
      line = "Read along with an audiobook." },
    { name = "Book Simulator", url = "https://booksimulator.com/",
      line = "A reading room for Aozora Bunko and Project Gutenberg books." },
    { name = "honjimaku.com", url = "https://honjimaku.com/",
      line = "Subtitles for Japanese audiobooks." },
    { name = "sbm Sync", url = "https://sbmsync.com/",
      line = "Your bookmarks, the same on every device." },
    { name = "SubRead for Android", url = "https://github.com/equwal/subread-android/releases/latest",
      line = "Times an audiobook against its ebook on the device." },
    { name = "SubRead Overlay", url = "https://github.com/equwal/subread-overlay/releases/latest",
      line = "Subtitle lines over any Android media player." },
    { name = "SubRead Dictionary", url = "https://github.com/equwal/subread-dictionary/releases/latest",
      line = "Pop-up dictionary that reads Yomitan dictionaries." },
    { name = "SubRead Anki", url = "https://github.com/equwal/subread-anki",
      line = "One tap makes an Anki card from any app." },
    { name = "Subrep", url = "https://github.com/equwal/subrep-android/releases/latest",
      line = "Live captions of the sound of your phone." },
    { name = "sbm for Android", url = "https://github.com/equwal/sbm-android/releases/latest",
      line = "Fuzzy search for your bookmarks." },
    { name = "Rebind", url = "https://github.com/equwal/rebind/releases",
      line = "Remap the hardware buttons of e-ink readers and Android." },
    { name = "Ink Recents", url = "https://github.com/equwal/ink-recents/releases/latest",
      line = "A recent-apps switcher for e-ink." },
    { name = "Ink Dim", url = "https://github.com/equwal/ink-dim/releases/latest",
      line = "Frontlight below the lowest system level." },
    { name = "Ink Update", url = "https://github.com/equwal/ink-update/releases/latest",
      line = "Tells you when Rebind and its extensions update." },
    { name = "All projects", url = "https://recentlywritten.com/projects.html",
      line = "Everything, with source code." },
}

--- Returns the list as plain text: the name, the line and the address of
--- each app, with an empty line between two apps.
function MoreApps.text()
    local blocks = {}
    for _, app in ipairs(MoreApps.list) do
        blocks[#blocks + 1] = app.name .. "\n" .. app.line .. "\n" .. app.url
    end
    return table.concat(blocks, "\n\n")
end

return MoreApps
