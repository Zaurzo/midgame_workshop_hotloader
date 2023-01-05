AddCSLuaFile()

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

do
    local require = require
    local warning = Color(255, 100, 100)

    local CompileFile = CompileFile
    local AddCSLuaFile = AddCSLuaFile

    local function GetPathFromFilename(filename)
        if not string.find(filename, '/') then
            return filename
        end
    
        local path = filename
    
        -- This is faster than string.GetPathFromFilename
        -- Patterns are expensive
        for i = #filename, 0, -1 do
            if string.sub(filename, i, i) == '/' then
                path = string.sub(filename, 1, i)
                break
            end
        end
    
        return path
    end
    
    local function CorrectFilename(filename)
        local fixedFilename = filename
    
        if string.find(filename, '/./', 1, true) then
            for i = #filename, 0, -1 do
                local n = i + 1
                local b = i - 1
    
                if string.sub(filename, b, b) == '/' and string.sub(filename, i, i) == '.' and string.sub(filename, n, n) == '/' then
                    fixedFilename = string.sub(filename, i + 2)
                    break
                end
            end
        elseif string.find(filename, '/../', 1, true) then
            local pattern = '[_%w]+/%.%./'
    
            while string.find(filename, pattern) do
                filename = string.gsub(filename, pattern, '')
            end
    
            fixedFilename = filename
        end
    
        return fixedFilename
    end

    local function GetAbsolutePath(path)
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

                local relativePath = GetPathFromFilename(source)
                local fixedFilePath = CorrectFilename(relativePath .. path)

                if file.Read(fixedFilePath, 'LUA') then
                    filename = fixedFilePath
                    break
                end
            end
        end

        return filename
    end

    local function LuaLoader_Setup()
        _G.CompileFile = function(path, ...)
            local absolute = GetAbsolutePath(path)
            local srcstr = file.Read(absolute, 'LUA')

            if srcstr then
                addonfiles[absolute] = true

                return CompileString(srcstr, 'lua/' .. absolute)
            else
                MsgC(warning, '[WSHL] Attempt to Compile non-existant file (' .. path ..')\n')
            end
        end

        _G.AddCSLuaFile = function(path)
            if path then
                local absolute = GetAbsolutePath(path)

                if file.Read(absolute, 'LUA') then
                    return AddCSLuaFile(absolute)
                else
                    MsgC(warning, '[WSHL] Attempt to AddCSLua non-existant file (' .. path ..')\n')
                end
            end
        end

        _G.include = function(path)
            local absolute = GetAbsolutePath(path)
            local srcstr = file.Read(absolute, 'LUA')

            if srcstr then
                local ff = CompileString(srcstr, 'lua/' .. absolute)

                if isfunction(ff) then
                    addonfiles[absolute] = true

                    return ff()
                else
                    MsgC(warning, '[WSHL] File "' .. absolute .. '" failed to compile, skipping. (Syntax Error?)\n')
                end
            else
                MsgC(warning, '[WSHL] Attempt to include non-existant file (' .. path ..')\n')
            end
        end

        _G.require = function(modulename, ...)
            local moduledir = 'includes/modules/' .. modulename .. '.lua'

            if file.Read(moduledir, 'LUA') then
                addonfiles[moduledir] = true

                include(moduledir)
            else
                require(modulename, ...)
            end
        end
    end

    hook.Add('InitPostEntity', 'wshl_lualoader_setup', LuaLoader_Setup)
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

    local function bundle_Find(bundle, ...)
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
        end

        return files, dirs
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
                        elseif classtable.GetStored then
                            baseclass.Set(classname, classtable.GetStored(classname))
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

            include(classtype .. '/' .. filename)
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
                        include(fullFilename)
                    elseif CLIENT and clientTypes[classtype] then
                        include(fullFilename)
                    end
                elseif filename == 'cl_init.lua' and CLIENT then
                    include(fullFilename)
                elseif filename == 'shared.lua' then
                    include(fullFilename)
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

            TOOL:CreateConVars()

            include('weapons/gmod_tool/stools/' .. filename)

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
            include('autorun/' .. files[i])
        end

        if SERVER then
            files = bundle_Find(bundle, 'autorun', 'server')

            for i = 1, #files do
                include('autorun/server/' .. files[i])
            end
        else
            files = bundle_Find(bundle, 'autorun', 'client')

            for i = 1, #files do
                include('autorun/client/' .. files[i])
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

do
    local sendList = {}

    -- I've added the abillity to make it auto-hotload requirements (and requirements of requirements) to the hotloader.
    -- I only made it download the requirements and then initialize them one by one, however some addons require
    -- requirements to load before it, if not, it will error. My solution is to combine every lua file of all the
    -- requirements and the main addon together and create a file bundle, and initialize them in the
    -- same way Garry's Mod does. Some addons will have a lot of files, making it unable to send it all in one
    -- net message. So I send the list in chunks (using Xalalau's way, thank you) to combat that issue.
    
    if SERVER then
        local bundleLoads = {}

        util.AddNetworkString('wshl_send_bundle')

        net.Receive('wshl_send_bundle', function()
            local id = net.ReadString()

            if bundleLoads[id] then return end

            local subid = net.ReadUInt(32)
            local strlen = net.ReadUInt(16)
            local strchunk = net.ReadData(strlen)
            local isLast = net.ReadBool()
        
            if not sendList[id] or sendList[id].subID ~= subid then
                sendList[id] = {subID = subid, data = ""}
        
                timer.Create(id, 180, 1, function()
                    sendList[id] = nil
                end)
            end
        
            sendList[id].data = sendList[id].data .. strchunk
        
            if isLast then
                local bundle = sendList[id].data
                bundle = util.JSONToTable(util.Decompress(bundle))

                LoadAutorun(bundle)
                LoadScripted('weapons', bundle)
                LoadTools(bundle)
                LoadScripted('entities', bundle)
                HandleHooks()
                
                sendList[id] = nil
                bundleLoads[id] = true
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
            
                local size, sendspeed = #str, (64000 / 1000 / 1024)
                local total = math.ceil(size / 64000)
                
                timer.Create(id, 180, 1, function()
                    sendList[id] = nil
                end)
            
                sendList[id] = subid
            
                for i = 1, total, 1 do
                    local startbyte = 64000 * (i - 1) + 1
                    local remaining = size - (startbyte - 1)
                    local endbyte = remaining < 64000 and (startbyte - 1) + remaining or 64000 * i
                    local strchunk = string.sub(str, startbyte, endbyte)
            
                    timer.Simple(i * sendspeed, function()
                        if sendList[id] ~= subid then return end
            
                        local isLast = i == total
            
                        net.Start('wshl_send_bundle')
                        net.WriteString(id)
                        net.WriteUInt(sendList[id], 32)
                        net.WriteUInt(#strchunk, 16)
                        net.WriteData(strchunk, #strchunk)
                        net.WriteBool(isLast)
                        net.SendToServer()
            
                        if isLast then
                            sendList[id] = nil
                        end
                    end)
                end

                timer.Simple(0.5, function()
                    LoadAutorun(bundle)
                    LoadScripted('vgui', bundle)
                    LoadScripted('weapons', bundle)
                    LoadTools(bundle)
                    LoadScripted('entities', bundle)
                    LoadScripted('effects', bundle)
                    HandleHooks()

                    PrintTable(bundle)

                    timer.Simple(0.5, ReloadSpawnMenu)
                end)
            end
        end
    end
end
