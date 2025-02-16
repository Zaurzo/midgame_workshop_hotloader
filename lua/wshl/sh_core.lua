AddCSLuaFile()

if SERVER then
    util.AddNetworkString('WSHL.HotLoad')
    util.AddNetworkString('WSHL.PlayerMount')

    function WSHL:SetupQueue()
        local queue = {}

        for k, ply in ipairs(player.GetHumans()) do
            queue[ply] = true
        end

        timer.Create('wshl_player_queue', 0.1, 0, function()
            if table.IsEmpty(queue) then
                return self:FinishQueue(true)
            end

            for ply in pairs(queue) do
                if not ply:IsValid() then
                    queue[ply] = nil
                end
            end
        end)

        self._PlayerQueue = queue

        return queue
    end

    function WSHL:FinishQueue(successful)
        if not self._PlayerQueue then return end

        local thread = WSHL._HotLoadThread
    
        if thread then
            coroutine.resume(thread, successful)

            WSHL._HotLoadThread = nil
        end

        self._PlayerQueue = nil

        timer.Remove('wshl_player_queue')
    end

    net.Receive('WSHL.Hotload', function(_, ply)
        if ply:IsListenServerHost() then
            WSHL:HotLoad(net.ReadString(), ply)
        end
    end)

    net.Receive('WSHL.PlayerMount', function(_, ply)
        local playerQueue = WSHL._PlayerQueue
        if not playerQueue or not playerQueue[ply] then return end

        local failure = net.ReadBool()

        if ply:IsListenServerHost() then
            local failure = net.ReadBool()

            if failure then
                return WSHL:FinishQueue(false)
            else
                WSHL.UI:SetState('Waiting for Players...', true, ply)
            end
        else
            local host = WSHL:GetServerHost()

            if not playerQueue[host] then
                local count = player.GetHumans()

                WSHL.UI:SetProgress('Player', count - table.Count(playerQueue), count, host)
            end
        end

        playerQueue[ply] = nil
    end)
else
    local downloadFilter = GetConVar('cl_downloadfilter')

    net.Receive('WSHL.PlayerMount', function(_, ply)
        local workshopQueue

        local function sendBack(failure)
            if failure then
                WSHL.UI:Error('An addon failed to mount!')

                workshopQueue = nil
            end

            net.Start('WSHL.PlayerMount')
            net.WriteBool(failure or false)
            net.SendToServer()
        end

        if downloadFilter:GetString() == 'all' and not LocalPlayer():IsListenServerHost() then
            return sendBack()
        end

        local nwsid = net.ReadUInt(32)
        local wsidList = {}

        for i = 1, nwsid do
            wsidList[i] = net.ReadString()
        end

        coroutine.wrap(function()
            WSHL.UI:SetState('Downloading and Mounting...', true)
            WSHL.UI:SetProgress('Addon', 0, nwsid)

            for i = 1, nwsid do
                local wsid = wsidList[i]
                local gmaPath = WSHL.Steamworks:GetGMAPath(wsid)

                if not gmaPath then
                    return sendBack(true)
                end

                local pass, files = WSHL.Steamworks:Mount(wsid, gmaPath)

                if not pass then
                    return sendBack(true)
                end

                WSHL.UI:SetProgress('Addon', i, nwsid)

                workshopQueue = workshopQueue or {}
                table.Add(workshopQueue, WSHL.Bundle:GetLoadable(files))
            end

            WSHL.UI:Finish()

            WSHL._WorkshopQueue = workshopQueue

            sendBack()
        end)()
    end)

    hook.Add('WSHL.WorkshopError', 'WSHL.WorkshopError', function()
        WSHL._WorkshopQueue = nil
    end)
end

function WSHL:AssertType(nparam, value, expectedType, level)
    local tn = type(value)
    if tn == expectedType then return end

    local msg = "bad argument #%s to '%s' (%s expected, got %s)"
    local name = debug.getinfo(level, 'n').name or '?'

    return error(Format(msg, nparam, name, expectedType, tn), level + 1)
end

function WSHL:GetServerHost()
    local host = self._ServerHost

    if not IsValid(host) then
        for k, ply in ipairs(player.GetHumans()) do
            if ply:IsListenServerHost() then
                host = ply
                break
            end
        end
    end

    return host
end

function WSHL:HotLoad(wsid, ply)
    self:AssertType(1, wsid, 'string', 2)

    if CLIENT then
        net.Start('WSHL.HotLoad')
        net.WriteString(wsid)
        net.SendToServer()

        return
    end

    ply = ply or self:GetServerHost()
    if not ply:IsValid() then return end

    coroutine.wrap(function()
        WSHL.UI:SetState('Fetching Required Addons...', false, ply)

        local wsidList = WSHL.Steamworks:GetAllRequiredAddons(wsid)
        local nwsid = #wsidList + 1

        wsidList[nwsid] = wsid

        net.Start('WSHL.PlayerMount')
        net.WriteUInt(nwsid, 32)

        for i = 1, nwsid do
            net.WriteString(wsidList[i])
        end

        net.Broadcast()

        WSHL._HotLoadThread = coroutine.running()

        self:SetupQueue()

        local status = coroutine.yield()
        if not status then return end

        WSHL.UI:SetState('Verifying...', true, ply)
        WSHL.UI:SetProgress('Addon', 0, nwsid, ply)

        local fileList

        for i = 1, nwsid do
            local wsid = wsidList[i]
            local gmaPath = WSHL.Steamworks:GetGMAPath(wsid)

            if not gmaPath then
                fileList = nil
                return WSHL.UI:Error('An addon failed to verify!', ply)
            end

            local pass, files = WSHL.Steamworks:Mount(wsid, gmaPath)

            if not pass then
                fileList = nil
                return WSHL.UI:Error('An addon failed to verify!', ply)
            end

            WSHL.UI:SetProgress('Addon', i, nwsid, ply)

            fileList = fileList or {}
            table.Add(fileList, WSHL.Bundle:GetLoadable(files))
        end

        -- hotload

        WSHL.UI:SetState('Loading Server Files...', false, ply)
        WSHL.UI:SetProgress('Freezes may occur!', nil, nil, ply)

        --print('Hotloading', unpack(wsidList))
        --PrintTable(fileList)

        --timer.Simple(3, function()
        --    WSHL.UI:Finish(ply)
        --end)
    end)()
end