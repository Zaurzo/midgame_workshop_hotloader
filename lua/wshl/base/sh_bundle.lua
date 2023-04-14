local isLinux = system.IsLinux()
local Bundle = {}

Bundle.__index = Bundle

-- File Environment
-- We use a custom environment to avoid detouring, because in most cases it creates tons of conflicts.
-- This will also better deal with addons that have timed includes or include more than once.

--   Note: In very unlikely cases, addons could use functions that were declared in the Global Environment
--   These functions will instead use the _G functions instead of ours, and will fail and error the hotload.
--   In any case, this will only happen if the addon uses a function from a required addon NOT loaded by WSHL.

local file_Read = file.Read

local FileEnvMetaTable, FileEnv do
    local isfunction, istable, package, setmetatable, rawget, setfenv, getfenv
    =     isfunction, istable, package, setmetatable, rawget, setfenv, getfenv

    local Hooks = hook.GetTable()

    FileEnv = {
        hook = {
            __lookup = hook,

            Remove = function(self, event, identifier, ...)
                local tab = self.Hooks[event]
                local mainTab = Hooks[event]
        
                if tab then
                    tab[identifier] = nil
                end

                if mainTab then
                    mainTab[identifier] = nil
                end
        
                --hook_Remove(event, identifier, ...)
            end,
        
            Add = function(self, event, identifier, callback, ...)
                local self_hooks = self.Hooks

                local tab = self_hooks[event]
                local mainTab = Hooks[event]
        
                if not tab then
                    tab = {}
                    self_hooks[event] = tab
                end

                if not mainTab then
                    mainTab = {}
                    Hooks[event] = mainTab
                end
        
                tab[identifier] = callback
                mainTab[identifier] = callback

                --hook_Add(event, identifier, callback, ...)
            end
        },

        CompileFile = function(self, path)
            return self:CompileFileBody(self:GetAbsolutePath(path))
        end,
    
        IncludeCS = function(self, path)
            if SERVER then
                FileEnv.AddCSLuaFile(self, path)
            end
    
            FileEnv.include(self, path)
        end,
    
        pairs = function(self, tbl, ...)
            if not istable(tbl) then return end

            local WSHL_LOOKUP = rawget(tbl, 'WSHL_LOOKUP')
    
            if istable(WSHL_LOOKUP) then
                return FileEnv.pairs(self, WSHL_LOOKUP, ...)
            end
    
            return pairs(tbl, ...)
        end,
    
        require = function(self, modulename, ...)
            local path = 'includes/modules/' .. modulename .. '.lua'
            local body = file_Read(path, 'LUA')
    
            if body then
                self:InitializeFile(path)
            else
                _G.require(modulename, ...)
            end
        end,
    
        include = function(self, path)
            local call = self:CompileFileBody(self:GetAbsolutePath(path))
    
            if call then
                for i = 16, 1, -1 do
                    if debug.getinfo(i, 'f') then
                        local fenv = getfenv(i)
        
                        -- If you call module() and run an include() after it, it will
                        -- run the file with the same environment made from the call
                        if fenv.WSHL_IsModule then
                            setfenv(call.func, fenv)
                            break
                        end
                    end
                end
    
                return call:Fire()
            end
        end,
    
        AddCSLuaFile = function(self, path, ...)
            local absolute do
                if not path then
                    local src = debug.getinfo(2, 'S').source
                    local start, endpos = string.find(src, 'lua/')
                    local path = string.sub(src, endpos + 1)
    
                    if file_Read(path, 'LUA') then
                        absolute = path
                    end
                end
    
                if not absolute then
                    absolute = self:GetAbsolutePath(path)
                end
            end
    
            return _G.AddCSLuaFile(absolute, ...)
        end,
    
        module = function(self, name, ...)
            local env = getfenv(2)
            local moduleEnv = { WSHL_IsModule = true }

            local hasSeeAll do
                local loaders = {...}
    
                for i = 1, #loaders do
                    if loaders[i] == package.seeall then
                        hasSeeAll = true
                        break
                    end
                end
            end

            local _M = _G[name]
            _M = (istable(_M) and _M) or {}

            setmetatable(moduleEnv, {
                __index = function(self, key)
                    if hasSeeAll then
                        if env[key] ~= nil then
                            return env[key]
                        end
                    end
    
                    return _M[key]
                end,
    
                __newindex = function(self, key, value)
                    _M[key] = value
                end,
            })
    
            setfenv(2, moduleEnv)
            _G[name] = _M
        end
    }

    do
        -- Some functions return specific values that are only returned during load time
        -- We force them to return these values until we set the bundle.InitPostEntity value to true
        local function CreatePostInitFunc(func, retval)
            if not func then return end
            
            return function(self, ...)
                if not self.InitPostEntity then
                    if retval == 'table' then
                        return {}
                    end

                    return retval
                end

                return func(...)
            end
        end

        if CLIENT then
            local Entity = Entity

            FileEnv.Player = CreatePostInitFunc(Player, NULL)
            FileEnv.LocalPlayer = CreatePostInitFunc(LocalPlayer, NULL)

            FileEnv.player = {
                __lookup = player,

                GetAll = CreatePostInitFunc(player.GetAll, 'table'),
                GetHumans = CreatePostInitFunc(player.GetHumans, 'table'),
                GetCount = CreatePostInitFunc(player.GetCount, 0),
                GetByAccountID = CreatePostInitFunc(player.GetByAccountID, false),
                GetBySteamID = CreatePostInitFunc(player.GetBySteamID, false),
                GetBySteamID64 = CreatePostInitFunc(player.GetBySteamID64, false),
                GetByUniqueID = CreatePostInitFunc(player.GetByUniqueID, false)
            }

            FileEnv.Entity = function(self, ...)
                local ent = Entity(...)

                if not self.InitPostEntity and ent:IsPlayer() then
                    return NULL
                end

                return ent
            end
        end

        FileEnv.ents = {
            __lookup = ents,

            GetAll = CreatePostInitFunc(ents.GetAll, 'table'),
            GetCount = CreatePostInitFunc(ents.GetCount, 0)
        }
    end

    -- It's ugly but it'll do for now
    FileEnvMetaTable = {
        __index = function(self, key)
            local WSHL_MAIN = rawget(self, 'WSHL_MAIN')
            local WSHL_SELF = rawget(self, 'WSHL_SELF')
            local WSHL_LOOKUP = rawget(self, 'WSHL_LOOKUP')
    
            local retval = rawget(WSHL_MAIN, key)
            local cacheKey = tostring(WSHL_MAIN) .. key
    
            if WSHL_SELF[cacheKey] ~= nil then
                return WSHL_SELF[cacheKey]
            end
    
            if istable(retval) and retval.__lookup then
                local cacheValue = setmetatable({
                    WSHL_MAIN = retval,
                    WSHL_SELF = WSHL_SELF,
                    WSHL_LOOKUP = retval.__lookup
                }, FileEnvMetaTable)
    
                WSHL_SELF[cacheKey] = cacheValue

                return cacheValue
            elseif isfunction(retval) then
                local function cacheValue(...)
                    return retval(WSHL_SELF, ...)
                end
    
                WSHL_SELF[cacheKey] = cacheValue

                return cacheValue
            end
    
            return WSHL_LOOKUP[key]
        end,

        __newindex = function(self, key, value)
            local WSHL_LOOKUP = rawget(self, 'WSHL_LOOKUP')
            local WSHL_SELF = rawget(self, 'WSHL_SELF')
            local WSHL_MAIN = rawget(self, 'WSHL_MAIN')
    
            if WSHL_MAIN[key] ~= nil then
                WSHL_SELF[tostring(WSHL_MAIN) .. key] = value
            end
    
            WSHL_LOOKUP[key] = value
        end
    }
end

-- Bundle Object

function Bundle:Create(files, name)
    local bundle = setmetatable({}, self)

    bundle.Name = name
    bundle.Files = {}
    bundle.Hooks = {}
    bundle.Errors = {}

    bundle.Information = {
        ['models'] = 0,
        ['materials'] = 0,
        ['lua'] = 0,
        ['sound'] = 0,
    }

    bundle.Environment = setmetatable({
        WSHL_MAIN = FileEnv,
        WSHL_SELF = bundle,
        WSHL_LOOKUP = _G
    }, FileEnvMetaTable)

    for i = 1, #files do
        local filename = files[i]
        local folder = string.match(filename, '%w+')

        if folder then
            local count = bundle.Information[folder]

            if count then
                bundle.Information[folder] = count + 1
            end
        end

        if folder == 'lua' or folder == 'gamemodes' then
            local dirs = string.Split(filename, '/')
            local curdir = bundle.Files
    
            for i = 1, #dirs do
                local name = dirs[i]
    
                if string.sub(name, -4) == '.lua' then
                    curdir[#curdir + 1] = name
                else
                    if not curdir[name] then
                        curdir[name] = {}
                    end
                    
                    curdir = curdir[name]
                end
            end
        end
    end

    return bundle
end

function Bundle:GetAbsolutePath(path)
    for i = 2, 15 do
        local callst = debug.getinfo(i, 'S')
        if not callst then break end

        local source = callst.source
        local _, endpos = string.find(source, 'lua/')

        if endpos then
            source = string.sub(source, endpos + 1)

            if string.find(source, '/') then
                for i = #source, 0, -1 do
                    if string.sub(source, i, i) == '/' then
                        source = string.sub(source, 1, i)
                        break
                    end
                end
            end

            local fixedPath = source .. path

            if file_Read(fixedPath, 'LUA') then
                path = fixedPath
                break
            end
        end
    end

    return path
end

function Bundle:Find(...)
    local dirs = {...}
    local curdir = self.Files

    for i = 1, #dirs do
        local name = dirs[i]

        if curdir[name] then
            curdir = curdir[name]
        else
            curdir = nil
            break
        end
    end

    local files, dirs = {}, {}

    if curdir then
        for key, value in pairs(curdir) do
            if istable(value) then
                dirs[#dirs + 1] = key
            else
                files[#files + 1] = value
            end
        end

        table.sort(files, function(a, b)
            if isLinux then
                return a > b
            end

            return a < b
        end)
    end

    return files, dirs
end

function Bundle:CompileFileBody(filepath)
    local body = file_Read(filepath, 'LUA')

    if body then
        local ff = CompileString(body, 'lua/' .. filepath)
        
        if not ff then
            self:AddError('File ' .. filepath .. ' failed to Compile. (Syntax Error?)')
        else
            return {
                bundle = self,
                func = setfenv(ff, self.Environment),

                Fire = function(self)
                    local results = { pcall(self.func) }
    
                    if not results[1] then
                        return self.bundle:AddError(results[2])
                    end

                    return unpack(results, 2)
                end
            }
        end
    else
        self:AddError('Attempt to Compile non-existent file. (' .. filepath .. ')')

        self.NonExistentFileEncountered = true
    end
end

function Bundle:CallHooks(event, ...)
    local eventCallbacksList = self.Hooks[event]

    if eventCallbacksList then
        for k, callback in pairs(eventCallbacksList) do
            callback(...)
        end
    end
end

function Bundle:DeepFind(basedir, ...)
    local files, dirs = self:Find(basedir, ...)

    if files[1] == nil and dirs[1] == nil then
        files, dirs = self:Find('gamemodes', engine.ActiveGamemode(), 'entities', ...)
    end

    return files, dirs
end

function Bundle:InitializeFile(filepath)
    local call = self:CompileFileBody(filepath)

    if call then
        return call:Fire()
    end
end

function Bundle:AddError(msg)
    --local realm = SERVER and '[SERVER ERROR] ' or '[CLIENT ERROR] '
    table.insert(self.Errors, msg)
    
    --[[
    ProtectedCall(function() 
        error('[WSHL] [' .. self.Name .. '] ' .. msg)
    end)
    --]]
end

do
    local SERVER, CLIENT = SERVER, CLIENT
    local ClassTypes = {}

    ClassTypes['entities'] = {'ENT', scripted_ents, 2}
    ClassTypes['weapons'] = {'SWEP', weapons, 3}

    if CLIENT then
        ClassTypes['effects'] = {'EFFECT', effects, 2}
        ClassTypes['vgui'] = {'PANEL', vgui, 2}
    end

    local function IsClassClient(typename)
        return typename == 'vgui' or typename == 'effects'
    end

    local function CreateNewClass(classtype)
        local dat = ClassTypes[classtype]

        if dat then
            local CLASS = {}
            local tblname = dat[1]

            if classtype == 'weapons' then
                CLASS.Primary = {}
                CLASS.Secondary = {}
            end

            _G[tblname] = CLASS

            return tblname, dat[2], dat[3]
        end
    end

    local function RegisterNewClass(classtype, classname, tblname, basetable, registercount)
        local CLASS = _G[tblname]

        if CLASS and table.Count(CLASS) >= registercount then
            if classtype == 'vgui' then
                if not basetable.GetControlTable(classname) then
                    basetable.Register(classname, CLASS, CLASS.Base)
                end
            else
                if basetable.Register then
                    basetable.Register(CLASS, classname)

                    if not IsClassClient(classtype) and basetable.Get then
                        timer.Simple(0.1, function()
                            baseclass.Set(classname, basetable.Get(classname))
                        end)
                    end
                end
            end
        end

        _G[tblname] = nil
    end

    function Bundle:InitializeAutorun()
        local InitializeFolder = function(...)
            local filelist = self:Find('lua', ...)
            local dir = table.concat({...}, '/') .. '/'

            for i = 1, #filelist do
                self:InitializeFile(dir .. filelist[i])
            end
        end

        InitializeFolder('autorun')

        if SERVER then
            InitializeFolder('autorun', 'server')
        else
            InitializeFolder('autorun', 'client')
        end
    end

    function Bundle:InitializeScriptedClasses(classtype)
        local dat = ClassTypes[classtype]

        if dat then
            local files, dirs = self:DeepFind('lua', classtype)

            for i = 1, #files do
                local filename = files[i]
                local classname = string.sub(filename, 1, -5)
                local tblname, basetable, registercount = CreateNewClass(classtype)

                _G[tblname].Folder = classtype .. '/' .. classname
                self:InitializeFile(classtype .. '/' .. filename)

                RegisterNewClass(classtype, classname, tblname, basetable, registercount)
            end

            for i = 1, #dirs do
                local classname = dirs[i]

                if classtype ~= 'weapons' or classname ~= 'gmod_tool' then
                    local files = self:DeepFind('lua', classtype, classname)
                    local tblname, basetable, registercount = CreateNewClass(classtype)

                    _G[tblname].Folder = classtype .. '/' .. classname

                    for i = 1, #files do
                        local filename = files[i]
                        local path = classtype .. '/' .. classname .. '/' .. filename

                        if filename == 'init.lua' and (SERVER or IsClassClient(classtype)) then
                            self:InitializeFile(path)
                        elseif filename == 'cl_init.lua' and CLIENT then
                            self:InitializeFile(path)
                        elseif filename == 'shared.lua' then
                            self:InitializeFile(path)
                        end
                    end

                    RegisterNewClass(classtype, classname, tblname, basetable, registercount)
                end
            end
        end
    end

    function Bundle:InitializeTools()
        local tools = self:DeepFind('lua', 'weapons', 'gmod_tool', 'stools')

        if #tools > 0 then
            local players = player.GetAll()

            SWEP = weapons.GetStored('gmod_tool')
            ToolObj = getmetatable(SWEP.Tool.axis)

            for i = 1, #tools do
                local filename = tools[i]
                local toolname = string.sub(filename, 1, -5)

                TOOL = ToolObj:Create()
                TOOL.Mode = toolname

                self:InitializeFile('weapons/gmod_tool/stools/' .. filename)

                TOOL:CreateConVars()
                SWEP.Tool[toolname] = TOOL

                for k, ply in ipairs(players) do
                    local toolgun = ply:GetWeapon('gmod_tool')

                    if IsValid(toolgun) and toolgun.Tool then
                        local tool = table.Copy(TOOL)

                        tool.SWEP = toolgun
                        tool.Weapon = toolgun
                        tool.Owner = ply

                        tool:Init()

                        toolgun.Tool[toolname] = TOOL
                    end
                end

                TOOL = nil
            end

            SWEP = nil
            ToolObj = nil
        end
    end

    local allowReceiveBundleLogs = CreateClientConVar('wshl_receive_logs', 0)
    local tagColor = Color(150, 250, 255)
    local mainColor = Color(185, 185, 185)
    
    local MsgC = MsgC

    function Bundle:Message(msg)
        if SERVER then
            WSHL.Net:Start('wshl_bundle_message')
            net.WriteString(msg)
            net.WriteString(self.Name)
            net.Broadcast()
        elseif allowReceiveBundleLogs:GetBool() then
            MsgC(tagColor, '[WSHL] ', mainColor, msg .. '\n')
        end
    end

    WSHL.Net:Receive('wshl_bundle_message', function()
        if not allowReceiveBundleLogs:GetBool() then return end

        local msg = net.ReadString()
        local name = net.ReadString()

        MsgC(tagColor, '[WSHL] ', mainColor, msg .. '\n')
    end)
end

function Bundle:Initialize()
    local time = SysTime()

    self:InitializeAutorun()
    self:InitializeScriptedClasses('vgui')
    self:InitializeScriptedClasses('weapons')
    self:InitializeTools()
    self:InitializeScriptedClasses('entities')
    self:InitializeScriptedClasses('effects')

    self:CallHooks('PreGamemodeLoaded')
    self:CallHooks('OnGamemodeLoaded')
    self:CallHooks('PostGamemodeLoaded')
    self:CallHooks('Initialize')
    self:CallHooks('InitPostEntity')

    self.InitPostEntity = true

    if SERVER then
        for k, ply in ipairs(player.GetAll()) do
            self:CallHooks('PlayerInitialSpawn', ply, false)
        end
    end

    time = math.Round(SysTime() - time, 3)
    hook.Run('WSHL.BundleInitialized', self)

    do
        local tag = SERVER and 'Server: ' or 'Client: '
        local hookcount = 0

        for k, tab in pairs(self.Hooks) do
            hookcount = hookcount + table.Count(tab)
        end

        self:Message(tag .. 'Loaded ' .. hookcount .. ' hooks.')
        self:Message(tag .. 'Initialized in ' .. time .. ' seconds.')
    end

    if CLIENT then
        self:Message('Finished initialization.')
    end

    timer.Simple(1, function()
        local realm = SERVER and 'SERVER' or 'CLIENT'
        local realmTag = '[' .. realm .. ']'

        if CLIENT then
            RunConsoleCommand('spawnmenu_reload')
        end

        if self.Errors[1] ~= nil then
            MsgC(Color(185, 185, 185), '\n' .. realmTag .. ' Bundle Errors Found:\n\n')

            local errors = table.concat(self.Errors, '\n')

            local sendname = string.sub(realmTag .. ' [' .. self.Name .. ']\n', 1, 500)
            local sendstack = string.sub(errors, 1, 5000)

            -- Send the errors that were found during the hotload to gerror
            -- If will be truncated if it's too long, though I think it will be enough for me to get the idea of what's wrong.
            http.Post('https://gerror.xalalau.com/add.php', {
                realm = realm,
                databaseName = 'midgame_workshop_hotloader',
                msg = sendname,
                stack = sendstack,
                map = game.GetMap(),
                quantity = '1',
                versionDate = WSHL.VersionDate
            })

            MsgC(Color(150, 250, 255), errors .. '\n')
            --self:Error('Bundle Errors:\n\n' .. errors .. '\n\nStack Traceback:')
        end
    end)
end

WSHL.Bundle = Bundle
