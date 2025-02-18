local downloadFilter = GetConVar('cl_downloadfilter')

net.Receive('WSHL.PlayerMount', function(_, ply)
    local workshopQueue

    local function sendBack(failure)
        if failure then
            WSHL.UI:Error('An addon failed to mount!')

            workshopQueue = nil
        end

        WSHL.Util:StartNet('WSHL.PlayerMount')
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