AddCSLuaFile()
setfenv(1, _G)

if SERVER then return end

local steamworks = table.Copy(steamworks)
local cacheDir = 'wshl_gma_cache'

if not file.Exists(cacheDir, 'DATA') then
    file.CreateDir(cacheDir)
end

function steamworks.DownloadWSB(wsid, callback)
    local cache = 'data/' .. cacheDir .. '/' .. wsid .. '.txt'

    if file.Exists(cache, 'GAME') then
        return callback(cache, file.Open(cache, 'rb', 'GAME'))
    end

    steamworks.DownloadUGC(wsid, function(path, gma)
        if path then
            callback(path, gma)

            file.Write(cacheDir .. '/' .. wsid .. '.txt', gma:Read(gma:Size()))
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

return steamworks
