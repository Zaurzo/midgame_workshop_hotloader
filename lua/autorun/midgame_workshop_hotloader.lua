if game.IsDedicated() then return end
-- Support for dedicated later

setfenv(1, _G)

local AddCSLuaFile = AddCSLuaFile
local SERVER = SERVER

local spawnmenu_control = include('midgame_workshop_hotloader/base/spawnmenu_control.lua')
local CreateFullBundle = include('midgame_workshop_hotloader/base/fullbundlecreator.lua')
local steamworks = include('midgame_workshop_hotloader/base/steamworks.lua')

local hotloaded = {}

local svblue = Color(3, 200, 255)
local errred = Color(255, 125, 125)
local greenc = Color(125, 255, 125)
local orange = Color(255, 125, 0)

local mounted, unmounted, addons do
    local addonList = engine.GetAddons()

    addons = {}
    mounted = {}
    unmounted = {}

    for i = 1, #addonList do
        local addon = addonList[i]
        
        if addon.mounted then
            mounted[addon.title] = true
        else
            unmounted[addon.title] = true

            if CLIENT then
                spawnmenu_control.AddAddon(addon)
            end
        end

        addons[addon.title] = addon
    end
end

local function Log(...)
    MsgC(...)

    if CLIENT then
        local args = {...}

        for i = 1, #args do
            local str = args[i]

            if isstring(str) then
                args[i] = string.sub(str, 1, -2)
            end
        end

        chat.AddText(unpack(args))
    end
end

if SERVER then
    util.AddNetworkString('wshl_broadcast_ugc')

    net.Receive('wshl_broadcast_ugc', function(len, ply)
        if ply:IsSuperAdmin() then
            local wsid = net.ReadString()

            net.Start('wshl_broadcast_ugc')
            net.WriteString(wsid)

            if wsid == 'n' then
                net.WriteTable(net.ReadTable())
            end
            
            net.Broadcast()
        end
    end)
else
    local function WSHL_HotloadAddon(wsid, callback)
        if hotloaded[wsid] then return end

        steamworks.DownloadWSB(wsid, function(_path, _file)
            Log(svblue, '[WSHL] Looking for addon requirements, give me a couple seconds...\n')

            steamworks.GetRequiredAddons(wsid, nil, function(requiredAddons)
                local count = table.Count(requiredAddons)
                local pass, files = game.MountGMA(_path)

                assert(pass, '[WSHL] Addon failed to mount, aborting...')

                local filebundles = {files}

                if count > 0 then
                    local ids = {wsid}
                    local mounted = 0

                    for wsid in pairs(requiredAddons) do
                        steamworks.DownloadWSB(wsid, function(path, file)
                            local pass, files = game.MountGMA(path)

                            if pass and not hotloaded[wsid] then
                                filebundles[#filebundles + 1] = files
                                ids[#ids + 1] = wsid
                            end

                            mounted = mounted + 1

                            if mounted >= count then
                                if callback then
                                    callback(filebundles)
                                    return
                                else
                                    local Bundle = CreateFullBundle(filebundles)
                                    Bundle()

                                    for i = 1, #ids do
                                        hotloaded[ids[i]] = true
                                    end
                                end
                            end
                        end)
                    end
                else
                    if callback then
                        callback(filebundles)
                        return
                    else
                        local Bundle = CreateFullBundle(filebundles)
                        Bundle()

                        hotloaded[wsid] = true
                    end
                end
            end) 
        end)
    end

    net.Receive('wshl_broadcast_ugc', function()
        local wsid = net.ReadString()
        local wsidsList = {}

        if wsid == 'n' then
            wsidsList = net.ReadTable()
        else
            if hotloaded[wsid] then
                return
            end
        end

        if #wsidsList > 0 then
            local fullFileBundle = {}
            local total = #wsidsList
            local count = 0

            for i = 1, total do
                WSHL_HotloadAddon(wsidsList[i], function(filebundles)
                    for i = 1, #filebundles do
                        fullFileBundle[#fullFileBundle + 1] = filebundles[i]
                    end

                    count = count + 1

                    if count >= total then
                        local Bundle = CreateFullBundle(fullFileBundle)
                        Bundle()
                    end
                end)
            end
        else
            WSHL_HotloadAddon(wsid)
            Log(greenc, '[WSHL] Fetched and started hotload for addon "' .. wsid .. '" ...\n')
        end
    end)

    hook.Add('GameContentChanged', 'wshl_gamecontentchanged', function()
        local addonList = engine.GetAddons()
        local newest = addonList[#addonList]

        local title, wsid = newest.title

        if addons[title] then
            for i = 1, #addonList do
                local addon = addonList[i]
                local title = addon.title

                if addon.mounted and unmounted[title] then
                    net.Start('wshl_broadcast_ugc')
                    net.WriteString(addon.wsid)
                    net.SendToServer()

                    unmounted[title] = nil
                    mounted[title] = true

                    break
                end
            end

            return
        end

        net.Start('wshl_broadcast_ugc')
        net.WriteString(newest.wsid)
        net.SendToServer()
    end)
end

MsgC(Color(40, 225, 50), '[GitHub] [' .. (SERVER and 'Server' or 'Client') .. ']', Color(226, 226, 226), ' Midgame Workshop Hotloader loaded.\n')
