AddCSLuaFile()

WSHL.Steamworks = WSHL.Steamworks or {}

file.CreateDir('wshl')

sql.Query('CREATE TABLE IF NOT EXISTS wshl_stored ( wsid TEXT NOT NULL PRIMARY KEY, data TEXT );')

local function getGMADataInternal(wsid)
    local data = sql.QueryValue("SELECT data FROM wshl_stored WHERE wsid = " .. SQLStr(wsid))
    if not data then return end

    local lines = string.Explode('\n', data)

    local path = lines[1]
    local time = lines[2]
    local title = string.sub(data, #path + #time + 3)

    return path, title, tonumber(time)
end

local function storeGMADataInternal(wsid, path, title)
    local data = SQLStr(path .. '\n' .. os.time() .. '\n' .. title)
    local query = "INSERT OR REPLACE INTO wshl_stored ( wsid, data ) VALUES ( " ..  SQLStr(wsid) .. ", " .. data .. " )"

    sql.Query(query)
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

function WSHL.Steamworks:GetGMA(wsid)
    local cachePath = 'cache/workshop/' .. wsid .. '.gma'
    local gmaPath, lastUpdated, gmaTitle

    if file.Exists(cachePath, 'MOD') then
        gmaPath = cachePath
        lastUpdated = file.Time(gmaPath, 'MOD')

        local gma = file.Open(gmaPath, 'rb', 'MOD')
        assert(gma, 'how did this even happen')

        gmaTitle = self:GetTitle(gma)
    else
        cachePath, gmaTitle, lastUpdated = getGMADataInternal(wsid)

        if cachePath then
            gmaPath = cachePath
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
                gmaPath = path
                gmaTitle = self:GetTitle(gma)

                gma:Close()

                storeGMADataInternal(wsid, path, gmaTitle)
            end

            return coroutine.resume(thread, gmaPath, gmaTitle, lastUpdated)
        end
    end

    local function resume()
        if not gmaTitle and downloadAddon then
            steamworks.DownloadUGC(wsid, downloadAddon)
        else
            return coroutine.resume(thread, gmaPath, gmaTitle, lastUpdated)
        end
    end

    if gmaPath then
        steamworks.FileInfo(wsid, function(ugcInfo)
            if not ugcInfo then
                return resume()
            end

            if downloadAddon and ugcInfo.updated > lastUpdated then
                steamworks.DownloadUGC(wsid, downloadAddon)
            else
                return resume()
            end
        end)
    elseif downloadAddon then
        steamworks.DownloadUGC(wsid, downloadAddon)
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
        path = self:GetGMA(wsid)
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
                storeGMADataInternal(wsid, newPath, self:GetTitle(gma))

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