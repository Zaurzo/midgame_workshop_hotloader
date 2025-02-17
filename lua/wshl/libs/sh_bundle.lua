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
        local fileName = select(-1, string.match(filePath, path))

        if fileName and not string.find(fileName, '/', 1, true) then
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

function WSHL.Bundle:GetAbsolutePath(relativePath)
    WSHL:AssertType(1, relativePath, 'string', 2)

    if file.Exists('lua/' .. relativePath, 'GAME') or file.Exists(relativePath, 'GAME') then
        return relativePath
    end

    relativePath = string.gsub(relativePath, '\\', '/')

    while string.StartsWith(relativePath, './') do
        relativePath = string.sub(relativePath, 3)
    end

    local i = 1

    while true do
        local stackInfo = debug.getinfo(i, 'S')
        if not stackInfo then break end

        local absolutePath = stackInfo.source
        absolutePath = string.sub(absolutePath, 2)

        if string.find(absolutePath, '/') then
            for j = #absolutePath, 1, -1 do
                if string.sub(absolutePath, j, j) == '/' then
                    absolutePath = string.sub(absolutePath, 1, j) .. relativePath

                    break
                end
            end

            local apathDirs, j = string.Explode('/', absolutePath), 0
    
            -- Canonize
            while true do
                j = j + 1
        
                local dir = apathDirs[j]
                if not dir then break end
        
                if dir == '..' then
                    table.remove(apathDirs, j)
                    table.remove(apathDirs, j - 1)
        
                    j = j - 2
                end
            end

            absolutePath = table.concat(apathDirs, '/')
        else
            absolutePath = relativePath
        end

        if file.Exists(absolutePath, 'GAME') then
            return absolutePath
        end

        i = i + 1
    end
end