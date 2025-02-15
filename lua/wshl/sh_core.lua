AddCSLuaFile()

if SERVER then
    util.AddNetworkString('WSHL.Hotload')
    util.AddNetworkString('WSHL.PlayerVerify')

    local playerQueue
    local queueCount
    local host

    local function HotLoadIt(ply)
        if not playerQueue then return end

        playerQueue = nil

        local humans = player.GetHumans()

        WSHL.UI:SetState('Loading Server Lua...', false, humans)
        WSHL.UI:SetProgress('Freezes may occur!', nil, nil, humans)

        -- hotload

        timer.Simple(4, function()
            WSHL.UI:Finish(humans)
        end)

        return timer.Remove('wshl_validate_player_queue')
    end

    hook.Add('WSHL.WorkshopError', 'WSHL.WorkshopError', function()
        playerQueue = nil
        queueCount = nil
        host = nil
    end)
    
    net.Receive('WSHL.Hotload', function(len, ply)
        if not ply:IsListenServerHost() then return end

        local pathList = util.JSONToTable(net.ReadString())

        if not pathList then
            return WSHL.UI:Error('Failed to verify mounts!', ply)
        end

        local name = net.ReadString()
        local queue = {}

        for k, path in ipairs(pathList) do
            local pass, files = game.MountGMA(path)

            if not pass then
                queue = nil

                return WSHL.UI:Error('Failed to verify mounts!', ply)
            end

            table.Add(queue, WSHL.Bundle:GetLoadable(files))
        end

        WSHL.queue = queue

        local players = player.GetHumans()

        playerQueue = {}
        queueCount = 0
        host = ply

        for k, human in ipairs(players) do
            if human ~= ply then
                queueCount = queueCount + 1
                playerQueue[human] = true
            end
        end

        WSHL.UI:SetState('Waiting for Players...', true, ply)
        WSHL.UI:SetProgress('Player', 0, queueCount, ply)

        timer.Create('wshl_validate_player_queue', 0.1, 0, function()
            if next(playerQueue) == nil then
                return HotLoadIt(ply)
            end

            for ply in pairs(playerQueue) do
                if not ply:IsValid() then
                    playerQueue[ply] = nil
                end
            end
        end)

        net.Start('WSHL.PlayerVerify')
        net.WriteUInt(#queue, 32)
        net.WriteString(name)
        net.SendOmit(ply)
    end)

    net.Receive('WSHL.PlayerVerify', function(_, ply)
        if not playerQueue or not playerQueue[ply] then return end

        playerQueue[ply] = nil

        if next(playerQueue) == nil then
            return HotLoadIt(host)
        end
    end)

    return
end

net.Receive('WSHL.PlayerVerify', function(len, ply)
    local function sendBack(fail)
        if fail then
            WSHL.queue = nil
        end

        net.Start('WSHL.PlayerVerify')
        net.SendToServer()
    end

    local queue = WSHL.queue

    if not queue or #queue ~= net.ReadUInt(32) then
        return sendBack()
    end

    local wsids = string.Explode(',', net.ReadString())
    local n = #wsids

    coroutine.wrap(function()
        WSHL.UI:SetState('Mounting Addons...', true)
        WSHL.UI:SetProgress('Addon', 0, n)

        for k, wsid in ipairs(wsids) do
            local path = WSHL.Steamworks:GetGMA(wsid)
    
            if path then
                local pass, files = WSHL.Steamworks:Mount(wsid, path)
    
                if not pass then
                    sendBack(true)

                    return WSHL.UI:Error('An addon failed to mount! Aborting...')
                end
    
                WSHL.UI:SetProgress('Addon', k, n)
            end
        end

        sendBack()
    end)()
end)

function WSHL:Hotload(wsid)
    if not LocalPlayer():IsListenServerHost() then return end
    
    coroutine.wrap(function()
        WSHL.UI:SetState('Fetching Required Items...')
    
        local wsidList = WSHL.Steamworks:GetAllRequiredAddons(wsid)
        local n = #wsidList + 1

        table.insert(wsidList, wsid)
    
        WSHL.UI:SetState('Mounting Addons...', true)
        WSHL.UI:SetProgress('Addon', 0, n)

        local paths = {}
        local queue = {}

        local name = table.concat(wsidList, ',')
    
        for k, wsid in ipairs(wsidList) do
            local path = WSHL.Steamworks:GetGMA(wsid)
    
            if path then
                local pass, files = WSHL.Steamworks:Mount(wsid, path)
    
                if not pass then
                    queue = nil

                    return WSHL.UI:Error('An addon failed to mount! Aborting...')
                end
    
                WSHL.UI:SetProgress('Addon', k, n)

                table.Add(queue, WSHL.Bundle:GetLoadable(files))

                table.insert(paths, path)
            end
        end

        WSHL.queue = queue
    
        WSHL.UI:SetProgress('', 0, 0)
        WSHL.UI:SetState('Verifying Mounts...', false)

        net.Start('WSHL.Hotload')
        net.WriteString(util.TableToJSON(paths))
        net.WriteString(name)
        net.SendToServer()
    end)()
end

hook.Add('WSHL.WorkshopError', 'WSHL.WorkshopError', function()
    WSHL.queue = nil
end)