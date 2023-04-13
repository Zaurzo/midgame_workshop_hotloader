if game.IsDedicated() then return end

AddCSLuaFile('wshl/core.lua')

if file.Exists('wshl/core.lua', 'LUA') then
    WSHL = {
        Workshop = {},
        Detours = {},
        Net = {
            Receivers = {},
        },
        Addons = {
            Unmounted = {},
            Mounted = {},
            All = {}
        }
    }

    local function Include(filename)
        AddCSLuaFile(filename)

        if file.Exists(filename, 'LUA') then
            include(filename)
        end
    end

    -- Error API by Xalalau Xubilozo
    Include('wshl/errorapi.lua')

    Include('wshl/base/sh_net.lua')
    Include('wshl/base/sh_workshop.lua')
    Include('wshl/base/sh_bundle.lua')
    Include('wshl/base/sh_ammo.lua')

    Include('wshl/core.lua')
end
