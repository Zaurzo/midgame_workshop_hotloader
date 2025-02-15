AddCSLuaFile()

WSHL.UI = WSHL.UI or {}

if SERVER then
    util.AddNetworkString('WSHL.UpdateWorkshopUI')
else
    net.Receive('WSHL.UpdateWorkshopUI', function()
        local setType = net.ReadUInt(3)

        if setType == 0 then
            WSHL.UI:Begin()
        elseif setType == 1 then
            WSHL.UI:SetState(net.ReadString(), net.ReadBool())
        elseif setType == 2 then
            local hasProgress = net.ReadBool()

            if hasProgress then
                WSHL.UI:SetProgress(net.ReadString(), net.ReadUInt(32), net.ReadUInt(32))
            else
                WSHL.UI:SetProgress(net.ReadString())
            end
        elseif setType == 3 then
            WSHL.UI:Error(net.ReadString())
        elseif setType == 4 then
            WSHL.UI:Finish()
        end
    end)
end

function WSHL.UI:GetPanel()
    local panel = self._Panel

    if IsValid(panel) then 
        return panel
    end

    panel = vgui.Create('wshl_workshop')

    self._Panel = panel

    return panel
end

function WSHL.UI:Begin(ply)
    if ply and SERVER then
        net.Start('WSHL.UpdateWorkshopUI')
        net.WriteUInt(0, 3)
        net.Send(ply)
    end

    if SERVER then return end

    local panel = self._Panel

    if IsValid(panel) then
        panel:Remove()
    end

    panel = vgui.Create('wshl_workshop')

    self._Panel = panel

    return panel
end

function WSHL.UI:Finish(ply)
    if ply and SERVER then
        net.Start('WSHL.UpdateWorkshopUI')
        net.WriteUInt(4, 3)
        net.Send(ply)
    end

    if SERVER then return end

    local panel = self._Panel

    if IsValid(panel) then 
        panel:Remove()
    end
end

function WSHL.UI:SetState(text, isProgress, ply)
    if ply and SERVER then
        net.Start('WSHL.UpdateWorkshopUI')
        net.WriteUInt(1, 3)
        net.WriteString(text)
        net.WriteBool(isProgress)
        net.Send(ply)
    end

    if SERVER then return end

    local panel = WSHL.UI:GetPanel()
    if not IsValid(panel) then return end

    panel:SetState(text, isProgress)
end

function WSHL.UI:SetProgress(name, progress, max, ply)
    if ply and SERVER then
        local hasProgress = progress ~= nil and max ~= nil

        net.Start('WSHL.UpdateWorkshopUI')
        net.WriteUInt(2, 3)
        net.WriteBool(hasProgress)
        net.WriteString(name)

        if hasProgress then
            net.WriteUInt(progress, 32)
            net.WriteUInt(max, 32)
        end

        net.Send(ply)
    end

    if SERVER then return end

    local panel = WSHL.UI:GetPanel()
    if not IsValid(panel) then return end

    panel:UpdateProgress(name, progress, max)
end

function WSHL.UI:Error(errorMessage, ply)
    errorMessage = errorMessage or ''

    if ply and SERVER then
        net.Start('WSHL.UpdateWorkshopUI')
        net.WriteUInt(3, 3)
        net.WriteString(errorMessage)
        net.Send(ply)

        hook.Run('WSHL.WorkshopError', errorMessage)
    end

    if SERVER then return end

    local panel = WSHL.UI:GetPanel()
    if not IsValid(panel) then return end

    panel:Error(errorMessage)

    hook.Run('WSHL.WorkshopError', errorMessage)
end