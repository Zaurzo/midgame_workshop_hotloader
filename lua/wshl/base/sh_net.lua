if SERVER then
    util.AddNetworkString('midgame_workshop_hotloader')
end

net.Receive('midgame_workshop_hotloader', function(...)
    local name = net.ReadString()
    local callback = WSHL.Net.Receivers[name]

    if callback then
        callback(...)
    end
end)

function WSHL.Net:Receive(name, callback)
    self.Receivers[name] = callback
end

function WSHL.Net:Start(name, ply)
    net.Start('midgame_workshop_hotloader')
    net.WriteString(name)
end
