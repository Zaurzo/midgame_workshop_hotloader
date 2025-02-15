AddCSLuaFile()

WSHL.Bundle = WSHL.Bundle or {}

local whitelistedPaths = {
    'lua/autorun/*.lua',
    'lua/autorun/server/*.lua',
    'lua/autorun/client/*.lua',
    'lua/autorun/server/sensorbones/*.lua',
    'lua/entities/*.lua',
    'lua/entities/*/*.lua',
    'lua/weapons/*.lua',
    'lua/weapons/*/*.lua',
    'lua/vgui/*.lua',
    'lua/weapons/*.lua',
    'lua/postprocess/*.lua',
    'lua/effects/*.lua',
    'lua/effects/*/init.lua',
    'lua/matproxy/*.lua',
    'resource/localization/*/*.properties'
}

for k, path in ipairs(whitelistedPaths) do
    whitelistedPaths[k] = string.gsub(path, '*', '(.+)')
end

function WSHL.Bundle:IsLoadable(filePath)
    for k, path in ipairs(whitelistedPaths) do
        if string.match(filePath, path) then
            return true
        end
    end

    return false
end

function WSHL.Bundle:GetLoadable(fileList)
    local loadableList = {}
    local n = 0

    for k, filePath in ipairs(fileList) do
        if self:IsLoadable(filePath) then
            n = n + 1
            loadableList[n] = filePath
        end
    end

    return loadableList, n
end