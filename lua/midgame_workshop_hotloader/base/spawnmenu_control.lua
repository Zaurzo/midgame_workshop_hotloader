AddCSLuaFile()

if SERVER then return end

local spawnmenu_control = {}
local unmountedAddonsList = {}

function spawnmenu_control.AddAddon(addon)
    unmountedAddonsList[#unmountedAddonsList + 1] = addon
end

do
    local icon_Color = Color(205, 92, 92, 255)
    local tick = Material('materials/wshl/tick.png')

    local hotloaded = {}

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
        local whats_hot = tree:AddNode('What\'s Hot', 'wshl/clock_fire16.png')
        local hotloaded = tree:AddNode('Hotloaded Addons', 'icon16/cut_red.png')
        local unloaded = tree:AddNode('Unloaded Addons', 'icon16/cut.png')

        unloaded.DoClick = function(self)
            if not self.ListPanel then
                self.ListPanel = vgui.Create('ContentContainer', panel)

                self.ListPanel:SetVisible(false)
                self.ListPanel:SetTriggerSpawnlistChange(false)

                self.ListPanel.Addons = {}
            end

            for k, addon in ipairs(unmountedAddonsList) do
                local wsid = addon.wsid

                if hotloaded[wsid] or self.ListPanel.Addons[wsid] then continue end

                local iconMat = 'data/midgame_workshop_hotloader/' .. wsid .. '/icon.png'
                local author = spawnmenu_control.GetAddonAuthorName(wsid)
                local panel = nil

                do
                    local callback1, callback2

                    if not file.Exists(iconMat, 'GAME') then
                        callback1 = function(material)
                            if panel then
                                panel:SetMaterial(material)
                            end
                        end
                    end

                    if not author then
                        callback2 = function(authorname)
                            if panel then
                                panel:SetTooltip('Created by ' .. authorname)
                            end
                        end
                    end

                    spawnmenu_control.CacheAddon(wsid, callback1, callback2)
                end

                panel = spawnmenu.CreateContentIcon('workshop_addon', self.ListPanel, {
                    title = addon.title,
                    wsid = wsid,
                    material = iconMat,
                    mode = 'unmounted',
                    author = author,
                })

                self.ListPanel.Addons[wsid] = true
                --panel.unmountedNum = panel.unmountedNum + 1
            end

            panel:SwitchPanel(self.ListPanel)
        end

        unloaded:DoClick()
        unloaded:SetSelected(true)
    end

    local function WorkshopAddon_Constructor(container, object)
        if not object.title or not object.material or not object.wsid then return end

        local icon = vgui.Create('ContentIcon', container)
        
        local PaintAt = icon.Image.PaintAt
        local wsid = object.wsid

        icon:SetContentType('entity')
        icon:SetSpawnName(object.title)
        icon:SetMaterial(object.material)
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

            if self.ws_MultiSelect then
                self.Image.ws_Ticked = not self.Image.ws_Ticked
            else
            end
        end

        icon.OpenMenu = function(self)
            local menu = DermaMenu()

            menu:AddOption('Copy Addon Title', function()
                SetClipboardText(self:GetSpawnName())
            end):SetIcon('icon16/page_copy.png')

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

    hook.Add('PopulateWorkshopSpawnmenu', 'PopulateWorkshopSpawnmenu', PopulateWorkshopSpawnmenu)

    spawnmenu.AddCreationTab('Workshop', AddWorkshopTab, 'icon16/cog.png', 1000, 'Workshop Hotload Control (What\'s Hot, Unmounted Addons, Hotloaded Addons)')
    spawnmenu.AddContentType('workshop_addon', WorkshopAddon_Constructor)
end

do
    local savePath = 'midgame_workshop_hotloader'
    local addonAuthorNames = {}

    -- Clear cache
    do
        local _, wsids = file.Find(savePath .. '/*', 'DATA')

        for i = 1, #wsids do
            file.Delete(savePath .. '/' .. wsids[i] .. '/icon.png')
        end
    end

    function spawnmenu_control.GetAddonAuthorName(wsid)
        return addonAuthorNames[wsid]
    end

    function spawnmenu_control.CacheAddon(wsid, callback1, callback2)
        if not callback1 and not callback2 then return end

        local cachePath = savePath .. '/' .. wsid
        local iconPath = cachePath .. '/icon.png'

        if not file.Exists(savePath, 'DATA') then
            file.CreateDir(savePath)
        end

        if not file.Exists(cachePath, 'DATA') then
            file.CreateDir(cachePath)
        end

        steamworks.FileInfo(wsid, function(addonInfo)
            if not addonInfo then return end
            
            local authorID = addonInfo.owner
            local previewid = addonInfo.previewid

            if (previewid and callback1) and not file.Exists(iconPath, 'DATA') then
                steamworks.Download(previewid, true, function(path)
                    if not path then return end

                    local iconData = file.Read(path, 'GAME')

                    if iconData then
                        file.Write(iconPath, iconData)
                        callback1('data/' .. iconPath)
                    end
                end)
            end

            if (authorID and callback2) and not addonAuthorNames[wsid] then
                steamworks.RequestPlayerInfo(authorID, function(username)
                    if not addonAuthorNames[wsid] then
                        addonAuthorNames[wsid] = username or '<could not fetch>'
                        callback2(addonAuthorNames[wsid])
                    end
                end)
            end
        end)
    end
end

return spawnmenu_control
