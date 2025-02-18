if game.IsDedicated() then return end

WSHL = WSHL or {}

AddCSLuaFile('wshl/cl_core.lua')

include('wshl/libs/sh_util.lua')
include('wshl/libs/sh_bundle.lua')
include('wshl/libs/sh_steamworks.lua')
include('wshl/libs/sh_ui.lua')

include('wshl/sh_core.lua')

if SERVER then
    include('wshl/sv_core.lua')
else
    include('wshl/cl_core.lua')
end