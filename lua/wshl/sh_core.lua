AddCSLuaFile()

function WSHL:HotLoad(wsid, ply)
    WSHL.Util:AssertType(1, wsid, 'string', 2)

    if CLIENT then
        WSHL.Util:StartNet('WSHL.HotLoad')
        net.WriteString(wsid)
        net.SendToServer()

        return
    end

    ply = ply or WSHL.Util:GetServerHost()
    if not ply:IsValid() then return end

    coroutine.wrap(function()
        WSHL.UI:SetState('Fetching Required Addons...', false, ply)

        local wsidList = WSHL.Steamworks:GetAllRequiredAddons(wsid)
        local nwsid = #wsidList + 1

        wsidList[nwsid] = wsid

        WSHL.Util:StartNet('WSHL.PlayerMount')
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