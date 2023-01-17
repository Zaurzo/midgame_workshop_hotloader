AddCSLuaFile()
setfenv(1, _G)

local steamworks = table.Copy(steamworks) or {}

function steamworks.IsMounted(title)
    local _, dirs = file.Find('*', title)

    return #dirs > 0
end

if CLIENT then
    local titles = {}

    function steamworks.GetUGCCache()
        return titles
    end

    function steamworks.DownloadWSB(wsid, callback)
        steamworks.DownloadUGC(wsid, function(path, gma)
            if path and gma then
                callback(path, gma)

                local title = steamworks.GetGMATitle(gma)

                if title then
                    titles[#titles + 1] = {wsid, title}
                end
            end
        end)
    end

    function steamworks.GetRequiredAddons(wsid, tab, callback)
        tab = tab or {}

        if not getmetatable(tab) then
            local timerName = 'wshl_getrequireditems_' .. wsid

            -- Wait for the HTTP requests
            if not timer.Exists(timerName) then
                timer.Create(timerName, 2.5, 1, function()
                    if callback then
                        callback(tab)
                    end
                end)
            end

            -- Reset the timer back to 2.5 seconds when an ID is added to the table
            -- I'm making sure we get everything
            setmetatable(tab, {
                __index = rawget,
                __newindex = function(...)
                    timer.Adjust(timerName, 2.5)
                    rawset(...)
                end,
            })
        end

        http.Fetch('https://steamcommunity.com/sharedfiles/filedetails/?id=' .. wsid, function(body)
            for id in string.gmatch(body, '<a href="https://steamcommunity%.com/workshop/filedetails/%?id=(%d+)" target="_blank">') do
                tab[id] = true
                steamworks.GetRequiredAddons(id, tab)
            end
        end)
    end

    -- Code adapted from https://github.com/Facepunch/garrysmod-issues/issues/5143#issuecomment-1014786514
    function steamworks.GetGMATitle(gma)
        if gma:Read(4) ~= 'GMAD' then return end

        gma:Skip(1) -- Version
        gma:Skip(8) -- Steamid64
        gma:Skip(8) -- Timestamp
        
        -- Required content
        while not gma:EndOfFile() and gma:Read(1) ~= '\0' do end

        local title = {}

        while not gma:EndOfFile() do
            local char = gma:Read(1)

            if char == '\0' then 
                break 
            end

            title[#title + 1] = char
        end

        return table.concat(title)
    end
end

return steamworks
