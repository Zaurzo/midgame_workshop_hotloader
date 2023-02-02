AddCSLuaFile()
setfenv(1, _G)

if SERVER then return end

local spawnmenu_control = {}
local unmountedAddonsList = {}
local mountedaddonslist = {}

function spawnmenu_control.AddAddon(addon, mounted)
    if mounted then
        mountedaddonslist[#mountedaddonslist + 1] = addon
    else
        unmountedAddonsList[#unmountedAddonsList + 1] = addon
    end
end

do
    local icon_Color = Color(205, 92, 92, 255)
    local tick = Material('materials/wshl/tick.png')

    local hotloadedList = {}
    local doMultiSelect = false

    local function AddWorkshopTab()
        local control = vgui.Create('SpawnmenuContentPanel')
        
        if not IsValid(control) then return end

        if control.EnableSearch then
            control:EnableSearch('workshop', 'PopulateWorkshopSpawnmenu')
        end

        if control.CallPopulateHook then
            control:CallPopulateHook('PopulateWorkshopSpawnmenu')
        end

        return control
    end

    local function PopulateWorkshopSpawnmenu(panel, tree, node)
        local loaded = tree:AddNode('Loaded Addons', 'icon16/cut_red.png')
        local unloaded = tree:AddNode('Unloaded Addons', 'icon16/cut.png')

        unloaded.DoClick = function(self)
            if not self.ListPanel then
                self.ListPanel = vgui.Create('ContentContainer', panel)

                self.ListPanel:SetVisible(false)
                self.ListPanel:SetTriggerSpawnlistChange(false)

                for k, addon in ipairs(unmountedAddonsList) do
                    local wsid = addon.wsid
    
                    if hotloadedList[wsid] then continue end
    
                    local author = spawnmenu_control.GetAddonAuthorName(wsid)
                    local panel = spawnmenu.CreateContentIcon('workshop_addon', self.ListPanel, {
                        title = addon.title,
                        wsid = wsid,
                        mode = 'unmounted',
                        author = author or '<could not fetch>',
                    })
    
                    spawnmenu_control.CacheAddon(wsid, function(material)
                        if IsValid(panel) then
                            panel.Image:SetMaterial(material)
                        end
                    end, function(authorname)
                        if IsValid(panel) then
                            panel:SetTooltip('Created by ' .. authorname)
                        end
                    end)
                end
            end

            panel:SwitchPanel(self.ListPanel)
            self:SetSelected(true)
        end

        loaded.DoClick = function(self)
            if not self.ListPanel then
                self.ListPanel = vgui.Create('ContentContainer', panel)

                self.ListPanel:SetVisible(false)
                self.ListPanel:SetTriggerSpawnlistChange(false)

                local list do
                    list = {}

                    for k, tab in ipairs(table.Copy(spawnmenu_control.steamworks.GetUGCCache())) do
                        list[tab[1]] = tab[2]
                    end

                    for k, tab in ipairs(mountedaddonslist) do
                        list[tab.wsid] = tab.title
                    end
                end

                for wsid, title in pairs(list) do
                    if spawnmenu_control.steamworks.IsMounted(title) then
                        local author = spawnmenu_control.GetAddonAuthorName(wsid)
                        local panel = spawnmenu.CreateContentIcon('workshop_addon', self.ListPanel, {
                            title = title,
                            wsid = wsid,
                            mode = 'hotloaded',
                            author = author or '<could not fetch>',
                        })
    
                        spawnmenu_control.CacheAddon(wsid, function(material)
                            if IsValid(panel) then
                                panel.Image:SetMaterial(material)
                            end
                        end, function(authorname)
                            if IsValid(panel) then
                                panel:SetTooltip('Created by ' .. authorname)
                            end
                        end)
                    end
                end
            end

            panel:SwitchPanel(self.ListPanel)
            unloaded:SetSelected(false)
            self:SetSelected(true)
        end

        unloaded:DoClick()
        unloaded:SetSelected(true)
    end

    local function WorkshopAddon_Constructor(container, object)
        if not object.title or not object.wsid then return end

        local icon = vgui.Create('ContentIcon', container)
        
        local PaintAt = icon.Image.PaintAt
        local wsid = object.wsid

        icon:SetContentType('workshop_addon')
        icon:SetSpawnName(object.title)
        icon:SetMaterial('wshl/unknown_icon.png')
        icon:SetName(object.title)

        icon:SetSize(192, 192)
        icon:SetColor(icon_Color)

        icon.OpenMenuExtra = nil
        icon.mode = object.mode
        icon.wsid = wsid

        icon.Label:SetTall(32)

        icon.Image.PaintAt = function(self, w, h)
            PaintAt(self, 5 + icon.Border, 5 + icon.Border, 192 - 10 - icon.Border * 2, 192 - 10 - icon.Border * 2)

            if self.ws_Ticked then
                surface.SetMaterial(tick)
                surface.DrawTexturedRect(icon:GetWide() - 30 - icon.Border, 6 + icon.Border, 24, 24)

                draw.NoTexture()
                surface.SetDrawColor(255, 255, 255, 255)
            end
        end

        icon.DoClick = function(self)
            surface.PlaySound('ui/buttonclickrelease.wav')

            if LocalPlayer() ~= Entity(1) then return end

            if doMultiSelect then
                self.Image.ws_Ticked = not self.Image.ws_Ticked
            elseif self.mode == 'unmounted' then
                net.Start('wshl_broadcast_ugc')
                net.WriteString(self.wsid)
                net.SendToServer()

                hotloadedList[self.wsid] = true

                self:Remove()
            end
        end

        icon.OpenMenu = function(self)
            local menu = DermaMenu()

            menu:AddOption('Copy Addon Title', function()
                SetClipboardText(self:GetSpawnName())
            end):SetIcon('icon16/page_copy.png')

            if LocalPlayer() ~= Entity(1) then
                return menu:Open()
            end

            if self.mode == 'hotloaded' then
                menu:AddOption('Reload', function()
                    net.Start('wshl_broadcast_ugc')
                    net.WriteString(self.wsid)
                    net.SendToServer()
                end)

                return menu:Open()
            end

            menu:AddOption('Multi-Select', function()
                local state = not doMultiSelect
                doMultiSelect = state

                if not state then
                    local addonContentIcons = container:GetChildren()[1]:GetChildren()[1]:GetChildren()

                    for i = 1, #addonContentIcons do
                        local contenticon = addonContentIcons[i]

                        if IsValid(contenticon) then
                            contenticon.Image.ws_Ticked = false
                        end
                    end
                end
            end)

            if doMultiSelect then
                menu:AddOption('Hotload Selected', function()
                    local addonContentIcons = container:GetChildren()[1]:GetChildren()[1]:GetChildren()
                    local wsids = {}
    
                    for i = 1, #addonContentIcons do
                        local contenticon = addonContentIcons[i]

                        if IsValid(contenticon) and contenticon.Image.ws_Ticked then
                            wsids[#wsids + 1] = contenticon.wsid
                            hotloadedList[contenticon.wsid] = true
                            contenticon:Remove()
                        end
                    end

                    -- More than 100 addons at a time is absurd
                    if #wsids > 100 or #wsids <= 0 then
                        return
                    end

                    local json = util.Compress(util.TableToJSON(wsids))
                    
                    net.Start('wshl_broadcast_ugc')
                    net.WriteString('n')
                    net.WriteUInt(#json, 16)
                    net.WriteData(json, #json)
                    net.SendToServer()
                end)
            end

            menu:Open()
        end

        if object.author then
            icon:SetTooltip('Created by ' .. object.author)
        end

        if IsValid(container) then
            container:Add(icon)
        end

        return icon
    end

    function spawnmenu_control.SetHotloaded(wsid)
        hotloaded[wsid] = true
    end

    timer.Simple(0.5, function()
        RunConsoleCommand('spawnmenu_reload')
    end)

    hook.Add('PopulateWorkshopSpawnmenu', 'PopulateWorkshopSpawnmenu', PopulateWorkshopSpawnmenu)

    spawnmenu.AddContentType('workshop_addon', WorkshopAddon_Constructor)
    spawnmenu.AddCreationTab('Steamworks', AddWorkshopTab, 'icon16/cog.png', 1000, 'Workshop Hotload Control (What\'s Hot, Unmounted Addons, Hotloaded Addons)')
end

do
    local addonAuthorNames = {}
    local addonIcons = {}

    function spawnmenu_control.GetAddonAuthorName(wsid)
        return addonAuthorNames[wsid]
    end

    function spawnmenu_control.CacheAddon(wsid, callback1, callback2)
        if callback1 and addonIcons[wsid] then
            callback1(addonIcons[wsid])
            callback1 = nil
        end

        if callback2 and addonAuthorNames[wsid] then
            callback2(addonAuthorNames[wsid])
            callback2 = nil
        end

        if not callback1 and not callback2 then return end

        steamworks.FileInfo(wsid, function(addonInfo)
            if not addonInfo then return end
            
            local authorID = addonInfo.owner
            local previewid = addonInfo.previewid

            if previewid and callback1 then
                steamworks.Download(previewid, true, function(path)
                    if not addonIcons[wsid] then
                        local mat = AddonMaterial(path)

                        addonIcons[wsid] = mat
                        callback1(mat)
                    end
                end)
            end

            if authorID and callback2 then
                steamworks.RequestPlayerInfo(authorID, function(username)
                    if not addonAuthorNames[wsid] then
                        local name = username or '<could not fetch>'

                        addonAuthorNames[wsid] = name
                        callback2(name)
                    end
                end)
            end
        end)
    end
end

return spawnmenu_control
