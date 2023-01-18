AddCSLuaFile()
setfenv(1, _G)

local SERVER = SERVER
local CLIENT = CLIENT

local hook_Table = hook.GetTable()
local addonfiles = {}

local initialHookList = {
    'PreGamemodeLoaded',
    'OnGamemodeLoaded',
    'PostGamemodeLoaded',
    'Initialize',
    'InitPostEntity',
    'PlayerInitialSpawn',
}

local InitFile do
    local function getabsolute(path)
        local filename = path

        for i = 2, 15 do
            local stack = debug.getinfo(i, 'S')

            if not stack then
                break
            end

            local source = stack.source
            local luaPos, luaEndPos = string.find(source, 'lua/')

            if luaEndPos then
                source = string.sub(source, luaEndPos + 1)

                local relativePath do
                    relativePath = source

                    if string.find(source, '/') then
                        local path = source
                
                        -- This is faster than string.GetPathFromFilename
                        -- Patterns are expensive
                        for i = #path, 0, -1 do
                            if string.sub(path, i, i) == '/' then
                                path = string.sub(path, 1, i)
                                break
                            end
                        end

                        relativePath = path
                    end
                end

                local fixedFilePath do
                    fixedFilePath = relativePath .. path
    
                    if string.find(fixedFilePath, '/./', 1, true) then
                        for i = #fixedFilePath, 0, -1 do
                            local n = i + 1
                            local b = i - 1
                
                            if string.sub(fixedFilePath, b, b) == '/' and string.sub(fixedFilePath, i, i) == '.' and string.sub(fixedFilePath, n, n) == '/' then
                                fixedFilePath = string.sub(fixedFilePath, i + 2)
                                break
                            end
                        end
                    elseif string.find(fixedFilePath, '/../', 1, true) then
                        local pattern = '[_%w]+/%.%./'
                
                        while string.find(fixedFilePath, pattern) do
                            fixedFilePath = string.gsub(fixedFilePath, pattern, '')
                        end
                    end
                end

                if file.Read(fixedFilePath, 'LUA') then
                    filename = fixedFilePath
                    break
                end
            end
        end

        return filename
    end

    local file_env = {}

    local assert = assert
    local require = require
    local warning = Color(255, 100, 100)

    local ProtectedCall = ProtectedCall
    local CompileString = CompileString
    local AddCSLuaFile = AddCSLuaFile

    local createCall do
        local envMeta = {
            __index = _G,
            __newindex = function(self, key, value)
                _G[key] = value
            end
        }

        createCall = function(...)
            local call = CompileString(...)

            if isfunction(call) then
                local env = {}

                for k, v in pairs(file_env) do
                    env[k] = v
                end
    
                return setfenv(call, setmetatable(env, envMeta))
            end

            return nil
        end
    end

    local function ForceNoHaltError(err)
        ProtectedCall(function()
            assert(false, err)
        end)
    end
    
    file_env.module = function(name, ...)
        local currentEnv = getfenv(2)
        local _M, moduleEnv = {}, {}

        local canSeeAll do
            local loaders = {...}

            if istable(package) then
                for i = 1, #loaders do
                    if loaders[i] == package.seeall then
                        canSeeAll = true
                        break
                    end
                end
            end

            moduleEnv.WSHL_IsModule = true
        end

        setmetatable(moduleEnv, {
            __index = function(self, k, v)
                if canSeeAll then
                    if currentEnv[k] ~= nil then
                        return currentEnv[k]
                    end
                end

                return _M[k]
            end,

            __newindex = function(self, k, v)
                _M[k] = v
            end,
        })

        setfenv(2, moduleEnv)

        _G[name] = _M
    end

    file_env.AddCSLuaFile = function(path)
        local absolute

        if not path then
            local source = debug.getinfo(2, 'S').source
            local _, luaEnd = string.find(source, 'lua/')

            local newPath = string.sub(source, luaEnd + 1)

            if file.Read(newPath, 'LUA') then
                absolute = newPath
            end
        end

        if not absolute then 
            absolute = getabsolute(path)
        end

        if file.Read(absolute, 'LUA') then
            return AddCSLuaFile(absolute)
        else
            ForceNoHaltError('[WSHL] Attempt to AddCSLua non-existant file (' .. path ..')')
        end
    end

    file_env.include = function(path)
        local absolute = getabsolute(path)
        local srcstr = file.Read(absolute, 'LUA')

        local mEnv do
            for i = 2, 6 do
                if not debug.getinfo(i, 'f') then break end

                local env = getfenv(i)

                if env.WSHL_IsModule then
                    mEnv = env
                    break
                end
            end
        end

        if srcstr then
            local ff = createCall(srcstr, 'lua/' .. absolute)

            if ff then
                addonfiles[absolute] = true

                if mEnv then
                    setfenv(ff, mEnv)
                end

                return ff()
            else
                ForceNoHaltError('[WSHL] File "' .. absolute .. '" failed to compile, skipping. (Syntax Error?)')
            end
        else
            ForceNoHaltError('[WSHL] Attempt to include non-existant file (' .. path ..')')
        end
    end

    file_env.CompileFile = function(path)
        local absolute = getabsolute(path)
        local srcstr = file.Read(absolute, 'LUA')

        if srcstr then
            addonfiles[absolute] = true

            return createCall(srcstr, 'lua/' .. absolute)
        else
            ForceNoHaltError('[WSHL] Attempt to Compile non-existant file (' .. path ..')')
        end
    end

    file_env.require = function(modulename, ...)
        local moduledir = 'includes/modules/' .. modulename .. '.lua'
        local fileBody = file.Read(moduledir, 'LUA')

        if fileBody then
            InitFile(moduledir)

            addonfiles[moduledir] = true
        else
            require(modulename, ...)
        end
    end

    file_env.IncludeCS = function(path)
        file_env.include(path)

        if SERVER then
            file_env.AddCSLuaFile(path)
        end
    end

    InitFile = function(filename)
        local fileBody = file.Read(filename, 'LUA')

        if not fileBody then
            return ForceNoHaltError('[WSHL] File "' .. filename .. '" does not exist.')
        end

        local call = createCall(fileBody, 'lua/' .. filename)

        if call then
            call()

            addonfiles[filename] = true
        else
            ForceNoHaltError('[WSHL] File "' .. filename .. '" failed to compile, skipping. (Syntax Error?)')
        end
    end
end

local LoadAutorun, LoadScripted, LoadTools, HandleHooks do
    local playerInitialSpawnCalls = {}
    local initialHookCalls = {}

    local classTypes = {
        ['entities'] = {'ENT', scripted_ents},
        ['weapons'] = {'SWEP', weapons, 3},
        ['effects'] = {'EFFECT', effects},
        ['vgui'] = {'PANEL', vgui},
    }

    local clientTypes = {
        ['effects'] = true,
        ['vgui'] = true,
    }

    local bundle_Find do
        local descend = function(a, b)
            return a > b
        end

        bundle_Find = function(bundle, ...)
            local dirs = {...}
            local subdir = bundle

            for i = 1, #dirs do
                local name = dirs[i]

                if subdir[name] then
                    subdir = subdir[name]
                else
                    subdir = nil
                    break
                end
            end

            local files, dirs = {}, {}

            if subdir then
                for k, v in pairs(subdir) do
                    if istable(v) then
                        dirs[#dirs + 1] = k
                    else
                        files[#files + 1] = v
                    end
                end

                if system.IsLinux() then
                    table.sort(files, descend)
                    table.sort(dirs, descend)
                else
                    table.sort(files)
                    table.sort(dirs)
                end
            end

            return files, dirs
        end
    end

    local function CreateClass(settings, classtype)
        local gclassname = settings[1]
        local classtable = settings[2]
        local regiscount = settings[3] or 2

        _G[gclassname] = {}

        if classtype == 'weapons' then
            _G[gclassname].Primary = {}
            _G[gclassname].Secondary = {}
        end

        return classtable, regiscount, gclassname
    end

    local function RegisterClass(classtype, classname, classtable, regiscount, gclassname)
        local CLASS = _G[gclassname]
        local keycount = 0

        if not CLASS then return end

        for k in pairs(CLASS) do
            keycount = keycount + 1

            if keycount >= regiscount then
                if classtype == 'vgui' then
                    if not classtable.GetControlTable(classname) then
                        classtable.Register(classname, CLASS, CLASS.Base)
                    end
                else
                    classtable.Register(CLASS, classname)

                    timer.Simple(0.1, function()
                        local retval = classtable.Get and classtable.Get(classname) or nil

                        if retval then
                            baseclass.Set(classname, retval)
                        elseif not clientTypes[classtype] then
                            baseclass.Set(classname, CLASS)
                        end
                    end)
                end

                break
            end
        end

        _G[gclassname] = nil
    end

    LoadScripted = function(classtype, bundle)
        local settings = classTypes[classtype]

        if not settings or not bundle[classtype] or (clientTypes[classtype] and SERVER) then 
            return 
        end
        
        local files, classes = bundle_Find(bundle, classtype)

        for i = 1, #files do
            local filename = files[i]
            local classname = string.sub(filename, 1, -5)
            local classtable, regiscount, gclassname = CreateClass(settings, classtype)

            _G[gclassname].Folder = classtype .. '/' .. classname

            InitFile(classtype .. '/' .. filename)
            RegisterClass(classtype, classname, classtable, regiscount, gclassname)
        end

        for i = 1, #classes do
            local classname = classes[i]

            if classtype == 'weapons' and classname == 'gmod_tool' then
                continue
            end

            local files = bundle_Find(bundle, classtype, classname)
            local classtable, regiscount, gclassname = CreateClass(settings, classtype)

            _G[gclassname].Folder = classtype .. '/' .. classname

            for i = 1, #files do
                local filename = files[i]
                local fullFilename = classtype .. '/' .. classname .. '/' .. filename

                if filename == 'init.lua' then
                    if SERVER then
                        InitFile(fullFilename)
                    elseif CLIENT and clientTypes[classtype] then
                        InitFile(fullFilename)
                    end
                elseif filename == 'cl_init.lua' and CLIENT then
                    InitFile(fullFilename)
                elseif filename == 'shared.lua' then
                    InitFile(fullFilename)
                end
            end

            RegisterClass(classtype, classname, classtable, regiscount, gclassname)
        end
    end

    LoadTools = function(bundle)
        local tools = bundle_Find(bundle, 'weapons', 'gmod_tool', 'stools')

        if #tools <= 0 then
            tools = bundle_Find(bundle, 'gamemodes', 'sandbox', 'entities', 'weapons', 'gmod_tool', 'stools')

            if #tools <= 0 then
                return
            end
        end

        SWEP = weapons.GetStored('gmod_tool')
        ToolObj = getmetatable(SWEP.Tool.axis)

        for i = 1, #tools do
            local filename = tools[i]
            local toolname = string.sub(filename, 1, -5)

            TOOL = ToolObj:Create()
            TOOL.Mode = toolname

            InitFile('weapons/gmod_tool/stools/' .. filename)

            TOOL:CreateConVars()

            SWEP.Tool[toolname] = TOOL
            
            do
                local players = player.GetAll()

                for i = 1, #players do
                    local ply = players[i]
                    local toolgun = ply:GetWeapon('gmod_tool')

                    if IsValid(toolgun) then
                        local tool = table.Copy(TOOL)

                        tool.SWEP = toolgun
                        tool.Weapon = toolgun
                        tool.Owner = toolgun.Owner

                        tool:Init()

                        toolgun.Tool[toolname] = tool
                    end
                end
            end

            TOOL = nil
        end

        SWEP = nil
        ToolObj = nil
    end

    LoadAutorun = function(bundle)
        local files = bundle_Find(bundle, 'autorun')

        for i = 1, #files do
            InitFile('autorun/' .. files[i])
        end

        if SERVER then
            files = bundle_Find(bundle, 'autorun', 'server')

            for i = 1, #files do
                InitFile('autorun/server/' .. files[i])
            end
        else
            files = bundle_Find(bundle, 'autorun', 'client')

            for i = 1, #files do
                InitFile('autorun/client/' .. files[i])
            end
        end
    end

    HandleHooks = function()
        for i = 1, #initialHookList do
            local name = initialHookList[i]
            local list = hook_Table[name]

            if not list then continue end

            for k, call in pairs(list) do
                if isfunction(call) then
                    if not addonfiles[string.sub(debug.getinfo(call, 'S').source, 6)] then
                        continue
                    end
                else
                    continue
                end

                if name == 'PlayerInitialSpawn' then
                    if not SERVER then continue end

                    for k2, ply in ipairs(player.GetAll()) do
                        if not playerInitialSpawnCalls[ply] then
                            playerInitialSpawnCalls[ply] = {}
                        end

                        if not playerInitialSpawnCalls[ply][k] then
                            playerInitialSpawnCalls[ply][k] = true

                            call(ply, false)
                        end
                    end
                else
                    if not initialHookCalls[name] then
                        initialHookCalls[name] = {}
                    end

                    if not initialHookCalls[name][k] then
                        initialHookCalls[name][k] = true

                        call()
                    end
                end
            end
        end
    end
end

-- I've added the ability to make it auto-hotload addon requirements (and requirements of requirements) to the hotloader.
-- My first thought was to make it download the requirements and then initialize them one by one, however some addons require
-- requirements to load before it. And if they are loaded after, it will error. My solution is to combine every lua file of the
-- requirements and the main addon together and create a file bundle, and initialize them in the same way Garry's Mod does. 
-- Some addons will have a lot of files making it unable to send it all in one net message, so I send the list in chunks 
-- (using Xalalau's way, thank you) to combat that issue.

local bundleSendList = {}
local hotloadedList = {}

-- Some addons rely on certain functions to return a value that is only returned during load-time
-- So I detour them and make them return those values when a hotload is in process
local WSHL_IsLoadingAddon do
    local entityCount = ents.GetCount()

    local function Detour(meta, key, retval)
        local originalFunction = meta[key]

        if originalFunction then
            meta[key] = function(self, ...)
                if WSHL_IsLoadingAddon then
                    return retval ~= nil and retval or nil
                end

                return originalFunction(self, ...)
            end
        end
    end

    if CLIENT then
        Detour(debug.getregistry().Player, 'IsPlayer', false)
    end

    Detour(ents, 'GetCount', entityCount)
end

if SERVER then
    util.AddNetworkString('wshl_send_bundle')

    net.Receive('wshl_send_bundle', function(len, ply)
        if not ply:IsListenServerHost() then return end

        local id = net.ReadString()
        local subid = net.ReadUInt(32)
        local strlen = net.ReadUInt(16)
        local strchunk = net.ReadData(strlen)
        local isLast = net.ReadBool()
    
        if not bundleSendList[id] or bundleSendList[id].subID ~= subid then
            bundleSendList[id] = {subID = subid, data = ""}
    
            timer.Create(id, 180, 1, function()
                bundleSendList[id] = nil
            end)
        end
    
        bundleSendList[id].data = bundleSendList[id].data .. strchunk
    
        if isLast then
            local bundle = bundleSendList[id].data

            bundle = util.JSONToTable(util.Decompress(bundle))
            WSHL_IsLoadingAddon = true

            LoadAutorun(bundle)
            LoadScripted('weapons', bundle)
            LoadTools(bundle)
            LoadScripted('entities', bundle)
            HandleHooks()

            WSHL_IsLoadingAddon = false
            bundleSendList[id] = nil
        end
    end)
else
    local function ReloadSpawnMenu()
        RunConsoleCommand('spawnmenu_reload')
    end

    return function(filebundles)
        local bundle = {}
    
        for i = 1, #filebundles do
            local filebundle = filebundles[i]
    
            for i = 1, #filebundle do
                local filename = filebundle[i]
                local isGameMode = string.StartWith(filename, 'gamemodes/')
    
                if string.StartWith(filename, 'lua/') or isGameMode then
                    if not isGameMode then
                        filename = string.sub(filename, 5)
                    end
    
                    local dirs = string.Split(filename, '/')
                    local subdir = bundle
            
                    for i = 1, #dirs do
                        local name = dirs[i]
            
                        if string.sub(name, -4) == '.lua' then
                            subdir[#subdir + 1] = name
                        else
                            if not subdir[name] then
                                subdir[name] = {}
                            end
                            
                            subdir = subdir[name]
                        end
                    end
                end
            end
        end
    
        -- Code adapted from
        -- https://github.com/Xalalau/SandEv/blob/70e41697864fd2d729696d0f77599f6933c7479e/lua/sandev/libs/sh_net.lua#L10
        -- (Thanks Xalalau Xubilozo)
        return function()
            local str = util.TableToJSON(bundle)
            local id, subid = util.MD5(str), SysTime()

            str = util.Compress(str)
        
            local size = #str
            local total = math.ceil(size / 42000)
            
            timer.Create(id, 180, 1, function()
                bundleSendList[id] = nil
            end)
        
            bundleSendList[id] = subid
        
            for i = 1, total, 1 do
                local startbyte = 45000 * (i - 1) + 1
                local remaining = size - (startbyte - 1)
                local endbyte = remaining < 42000 and (startbyte - 1) + remaining or 42000 * i
                local strchunk = string.sub(str, startbyte, endbyte)
        
                timer.Simple(i * 0.1, function()
                    if bundleSendList[id] ~= subid then return end
        
                    local isLast = i == total
        
                    net.Start('wshl_send_bundle')
                    net.WriteString(id)
                    net.WriteUInt(bundleSendList[id], 32)
                    net.WriteUInt(#strchunk, 16)
                    net.WriteData(strchunk, #strchunk)
                    net.WriteBool(isLast)
                    net.SendToServer()
        
                    if isLast then
                        bundleSendList[id] = nil

                        timer.Simple(0.5, function()
                            WSHL_IsLoadingAddon = true
        
                            LoadAutorun(bundle)
                            LoadScripted('vgui', bundle)
                            LoadScripted('weapons', bundle)
                            LoadTools(bundle)
                            LoadScripted('entities', bundle)
                            LoadScripted('effects', bundle)
                            HandleHooks()
        
                            WSHL_IsLoadingAddon = false
        
                            timer.Simple(0.5, ReloadSpawnMenu)
                        end)
                    end
                end)
            end
        end
    end
end
