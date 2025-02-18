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
        if WSHL.Util:FindIn('/', string.match(filePath, path)) == false then
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

    return loadableList
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

--[[--------------------------------------------------------
    Vanilla Load Order

    This is to account for addons that replace vanilla Lua
    files to typically load a file quicker.
-----------------------------------------------------------]]

local vanillaLuaFiles = {}
local vanillaLuaLoadOrder = {}

do
    local function storeFiles(directory)
        local files, directories = file.Find(directory .. '/*', 'MOD')
    
        for k, fileName in ipairs(files) do
            if string.sub(fileName, -4) == '.lua' then
                vanillaLuaFiles[directory .. '/' .. fileName] = true
            end
        end
    
        for k, dir in ipairs(directories) do
            storeFiles(directory .. '/' .. dir)
        end
    end
    
    storeFiles('lua')
    storeFiles('gamemodes/base')
end

function WSHL.Bundle:IsFileNameVanilla(fileName)
    return vanillaLuaFiles[fileName] or false
end

--
-- Search for include() and require() calls in the file
-- and grab the Lua files they are going to load
--
function WSHL.Bundle:GetIncludesFromFile(fileToRead, path)
    path = path or 'MOD'

    local fileData = file.Read(fileToRead, path)
    if not fileData then return {} end

    local order = {}
    local fileCount = 0

    local folder = string.GetPathFromFilename(fileToRead)

    local function tryMatch(stringCapture)
        local pattern = '(%w+)%s*%(%s*(%b' .. stringCapture .. ')%s*%)'

        for funcName, relativePath in string.gmatch(fileData, pattern) do
            local filePath

            relativePath = string.sub(relativePath, 2, #relativePath - 1)

            if funcName == 'include' then
                filePath = folder .. relativePath

                if not file.Exists(filePath, path) then
                    filePath = 'lua/' .. relativePath
                end
            elseif funcName == 'require' then
                filePath = 'lua/includes/modules/' .. relativePath .. '.lua'
            end

            if filePath and file.Exists(filePath, path) then
                fileCount = fileCount + 1
                order[fileCount] = filePath
            end
        end
    end

    tryMatch("''")
    tryMatch('""')
    tryMatch('[]')

    return order
end

--
-- Creates a copy of the provided file list, sorted in the Lua load order
--
function WSHL.Bundle:GetInLuaLoadOrder(fileList)
    local sortedFileList = {}
    local vanillaFileReplacements

    if fileList then
        for k, fileName in ipairs(fileList) do
            if string.sub(fileName, -4) == '.lua' then
                if vanillaLuaLoadOrder[fileName] then
                    vanillaFileReplacements = table.ForceInsert(vanillaFileReplacements, fileName)
                elseif self:IsLoadable(fileName) then
                    table.insert(sortedFileList, fileName)
                end
            end
        end
    end

    table.sort(sortedFileList)

    if vanillaFileReplacements then
        table.sort(vanillaFileReplacements, function(a, b)
            return vanillaLuaLoadOrder[a] < vanillaLuaLoadOrder[b]
        end)

        for k, fileName in ipairs(vanillaFileReplacements) do
            table.insert(sortedFileList, k, fileName)
        end
    end

    return sortedFileList
end

do
    local position = 1

    vanillaLuaLoadOrder['lua/includes/init.lua'] = 1

    local function add(fileName)
        for k, filePath in ipairs(WSHL.Bundle:GetIncludesFromFile(fileName, 'MOD')) do
            if not vanillaLuaLoadOrder[filePath] then
                position = position + 1
                vanillaLuaLoadOrder[filePath] = position
            end
        end
    end

    add('lua/includes/init.lua')
    add('gamemodes/base/gamemode/init.lua')
    add('gamemodes/base/gamemode/cl_init.lua')
    add('gamemodes/base/gamemode/shared.lua')
end