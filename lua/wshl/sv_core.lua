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

WSHL.Util:SetNetReceiver('WSHL.Hotload', function(_, ply)
    if ply:IsListenServerHost() then
        WSHL:HotLoad(net.ReadString(), ply)
    end
end)

WSHL.Util:SetNetReceiver('WSHL.PlayerMount', function(_, ply)
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
        local host = WSHL.Util:GetServerHost()

        if not playerQueue[host] then
            local count = player.GetHumans()

            WSHL.UI:SetProgress('Player', count - table.Count(playerQueue), count, host)
        end
    end

    playerQueue[ply] = nil
end)