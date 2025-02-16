AddCSLuaFile()

WSHL.Steamworks = WSHL.Steamworks or {}

file.CreateDir('wshl')
file.CreateDir('wshl/cache')

local function cacheGMAPath(wsid, path)
    file.Write('wshl/cache/' .. wsid .. '.dat', path)
end

function WSHL.Steamworks:GetTitle(gma)
    local pointerPosition = gma:Tell()

    gma:Seek(0)

    if gma:Read(4) ~= 'GMAD' then 
        return gma:Seek(pointerPosition)
    end

    gma:Skip(1) -- version
    gma:Skip(8) -- steamid64
    gma:Skip(8) -- timestamp

    -- Required content, probably unused
    while not gma:EndOfFile() and gma:Read(1) ~= '\0' do end

    local i = 0
    local title = {}

    while not gma:EndOfFile() do
        local char = gma:Read(1)
        if char == '\0' then break end

        i = i + 1
        title[i] = char
    end

    title = table.concat(title)

    gma:Seek(pointerPosition)

    return title
end

function WSHL.Steamworks:GetGMAPath(wsid)
    local cachePath = 'cache/workshop/' .. wsid .. '.gma'
    local gmaPath, lastUpdated

    if file.Exists(cachePath, 'MOD') then
        gmaPath = cachePath
        lastUpdated = file.Time(gmaPath, 'MOD')
    else
        cachePath = 'wshl/cache/' .. wsid .. '.dat'
        gmaPath = file.Read(cachePath, 'DATA')

        if gmaPath then
            lastUpdated = file.Time(cachePath, 'DATA')
        else
            for k, addon in ipairs(engine.GetAddons()) do
                if addon.wsid == wsid and addon.file then
                    gmaPath = addon.file
                    lastUpdated = addon.updated

                    break
                end
            end
        end
    end

    local thread = coroutine.running()

    if not thread then 
        return gmaPath
    end

    local downloadAddon
    
    if steamworks.DownloadUGC then
        function downloadAddon(path, gma)
            if path and gma then
                gma:Close()

                gmaPath = path

                cacheGMAPath(wsid, path)
            end

            return coroutine.resume(thread, gmaPath)
        end
    end

    -- Check if we have an older version, and re-download
    if gmaPath then
        steamworks.FileInfo(wsid, function(ugcInfo)
            if not ugcInfo then
                return coroutine.resume(thread, gmaPath)
            end

            if downloadAddon and ugcInfo.updated > lastUpdated then
                steamworks.DownloadUGC(wsid, downloadAddon)
            else
                return coroutine.resume(thread, gmaPath)
            end
        end)
    else
        if downloadAddon then
            steamworks.DownloadUGC(wsid, downloadAddon)
        else
            return gmaPath
        end
    end

    return coroutine.yield()
end

function WSHL.Steamworks:GetAllRequiredAddons(wsid, callback)
    local threadOrCallback = callback or coroutine.running()
    if not threadOrCallback then return end

    local isCallback = isfunction(threadOrCallback)

    local requests = 0
    local addonIDs = {}

    local function onRequestProcessed()
        requests = requests - 1
        if requests > 0 then return end

        if isCallback then
            threadOrCallback(table.GetKeys(addonIDs))
        else
            coroutine.resume(threadOrCallback, table.GetKeys(addonIDs))
        end
    end

    local function fetchAndProcess(fwsid)
        local url = 'https://steamcommunity.com/sharedfiles/filedetails/?id=' .. fwsid

        requests = requests + 1

        http.Fetch(url, function(body)
            if body then
                for k in body:gmatch('href="https://steamcommunity%.com/workshop/filedetails/%?id=(%d+)"') do
                    if k ~= wsid and not addonIDs[k] then
                        addonIDs[k] = true

                        fetchAndProcess(k)
                    end
                end
            end

            onRequestProcessed()
        end, onRequestProcessed)
    end

    fetchAndProcess(wsid)

    return not isCallback and coroutine.yield() or nil
end

function WSHL.Steamworks:Mount(wsid, path)
    if not path then
        path = self:GetGMAPath(wsid)
    end

    if not path then
        return false
    end

    local pass, files = game.MountGMA(path)

    -- If it failed, it probably isn't cached anymore - re-download it
    if not pass and steamworks.DownloadUGC then
        local thread = coroutine.running()

        if not thread then 
            return pass, files
        end

        steamworks.DownloadUGC(wsid, function(newPath, gma)
            if newPath and gma then
                cacheGMAPath(wsid, newPath)

                gma:Close()

                return coroutine.resume(thread, game.MountGMA(newPath))
            end

            return coroutine.resume(thread, false)
        end)

        return coroutine.yield()
    end

    return pass, files
end

concommand.Add('wshl_flush_cache' .. (SERVER and '_sv' or ''), function(ply)
    if CLIENT or ply:IsListenServerHost() then
        sql.Query('DELETE FROM wshl_stored')
    end
end)