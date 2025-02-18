WSHL.Util = WSHL.Util or {}
WSHL.Util._NetPool = WSHL.Util._NetPool or {}

if SERVER then
    util.AddNetworkString('WSHL.Net')
end

function WSHL.Util:FindIn(needle, ...)
    local count = select('#', ...)

    if count == 0 then
        return nil
    end

    if count == 1 then
        local value = ...

        if value == nil then
            return nil
        end

        local startPos, endPos, match = string.find(value, needle)
        
        if startPos then
            return needle, startPos, endPos, match
        end
    else
        for i = 1, count do
            local value = select(i, ...)

            if value ~= nil then
                local startPos, endPos, match = string.find(value, needle)

                if startPos then
                    return needle, startPos, endPos, match
                end
            end
        end
    end

    return false
end

function WSHL.Util:AssertType(nparam, value, expectedType, level)
    local tn = type(value)
    if tn == expectedType then return end

    local msg = "bad argument #%s to '%s' (%s expected, got %s)"
    local name = debug.getinfo(level, 'n').name or '?'

    error(Format(msg, nparam, name, expectedType, tn), level + 1)
end

function WSHL.Util:GetServerHost()
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

function WSHL.Util:SetNetReceiver(name, receiver)
    self._NetPool[string.lower(name)] = receiver
end

function WSHL.Util:StartNet(name)
    assert(self._NetPool[name], 'a receiver for this net message is not set')

    net.Start('WSHL.Net')
    net.WriteString(name)
end

net.Receive('WSHL.Net', function(...)
    local name = net.ReadString()
    local receiver = WSHL._NetPool[name]

    if receiver then
        receiver(...)
    end
end)