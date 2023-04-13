game.AddAmmoType({name = '_wshl_refammo_ammo'})

timer.Simple(0.25, function()
    if CLIENT then
        WSHL.Net:Receive('wshl_ammo_control', function()
            hook.Run('HUDAmmoPickedUp', net.ReadString(), net.ReadInt(32))
            surface.PlaySound('items/ammo_pickup.wav')
        end)
    end

    local _R = debug.getregistry()

    local Entity = _R.Entity
    local Player = _R.Player

    local ammoTypes = {}
    local isWSHLAmmo = {}

    local function WSHL_Detour(basetbl, key, func)
        local old = WSHL.Detours[key] or basetbl[key]

        if old then
            basetbl[key] = function(...)
                local retval = func(...)

                if retval ~= nil then
                    return retval
                end

                return old(...)
            end

            WSHL.Detours[key] = old
        end
    end

    do
        local function GetAmmoData(any)
            local data

            if isnumber(any) then
                data = ammoTypes[any]
            else
                local id = isWSHLAmmo[any]

                if id then
                    data = ammoTypes[id]
                end
            end
    
            return data
        end

        local function WSHL_QuickDetour(key, valuename)
            WSHL_Detour(game, key, function(id)
                local data = ammoTypes[id]

                if data then
                    return data[valuename]
                end
            end)
        end

        WSHL_Detour(Player, 'GiveAmmo', function(self, count, ammoType, hidePopup)
            local data = GetAmmoData(ammoType)

            if data then
                local keyname = 'WSHL_AmmoCount_' .. data.name
                local oldCount = self:GetNW2Int(keyname)
                
                self:SetNW2Int(keyname, oldCount + count)

                if not hidePopup then
                    WSHL.Net:Start('wshl_ammo_control')
                    net.WriteString(data.name)
                    net.WriteInt(count, 32)
                    net.Send(self)
                end
            end
        end)

        WSHL_Detour(Player, 'RemoveAmmo', function(self, count, ammoName)
            local data = GetAmmoData(ammoName)

            if data then
                local keyname = 'WSHL_AmmoCount_' .. data.name
                local newCount = self:GetNW2Int(keyname) - count

                if newCount < 0 then
                    newCount = 0
                end
                
                self:SetNW2Int(keyname, newCount)
            end
        end)

        WSHL_Detour(Player, 'SetAmmo', function(self, count, ammoType)
            local data = GetAmmoData(ammoType)

            if data then
                self:SetNW2Int('WSHL_AmmoCount_' .. data.name, count)
            end
        end)

        WSHL_Detour(Player, 'GetAmmoCount', function(self, ammoType)
            local data = GetAmmoData(ammoType)

            if data then
                return self:GetNW2Int('WSHL_AmmoCount_' .. data.name)
            end
        end)

        WSHL_QuickDetour('GetAmmoMax', 'maxcarry')
        WSHL_QuickDetour('GetAmmoName', 'name')
        WSHL_QuickDetour('GetAmmoForce', 'force')
        WSHL_QuickDetour('GetAmmoNPCDamage', 'npcdmg')
        WSHL_QuickDetour('GetAmmoDamageType', 'dmgtype')
        WSHL_QuickDetour('GetAmmoPlayerDamage', 'plydmg')

        WSHL_QuickDetour = nil
    end

    do
        local game_GetAmmoTypes = game.GetAmmoTypes
        local GetAmmo = Player.GetAmmo

        WSHL_Detour(game, 'GetAmmoTypes', function()
            local gameAmmoTypes = game_GetAmmoTypes()

            for k, ammoData in pairs(ammoTypes) do
                gameAmmoTypes[k] = ammoData.name
            end

            return gameAmmoTypes
        end)

        WSHL_Detour(Player, 'GetAmmo', function(self)
            local ammo = GetAmmo(self)

            for k, ammoData in pairs(ammoTypes) do
                local ammoCount = self:GetNW2Int('WSHL_AmmoCount_' .. ammoData.name)

                if ammoCount > 0 then
                    ammo[k] = ammoCount
                end
            end

            return ammo
        end)
    end

    do
        local Weapon = _R.Weapon
        local IsScripted = Weapon.IsScripted
        local IsValid = Entity.IsValid

        local function WSHL_QuickDetour(key, ammoTabKey)
            WSHL_Detour(Weapon, key, function(self)
                local tab = self[ammoTabKey]

                if (IsValid(self) and IsScripted(self)) and (tab and tab.Ammo) then
                    return isWSHLAmmo[tab.Ammo]
                end
            end)
        end

        WSHL_QuickDetour('GetPrimaryAmmoType', 'Primary')
        WSHL_QuickDetour('GetSecondaryAmmoType', 'Secondary')
    end             

    WSHL_Detour(game, 'AddAmmoType', function(ammoData)
        local name = ammoData.name
        
        if not isWSHLAmmo[name] and game.GetAmmoID(name) == -1 then
            local id = #game.GetAmmoTypes() + 1

            ammoTypes[id] = ammoData
            isWSHLAmmo[name] = id
        end
    end)

    WSHL_Detour(game, 'GetAmmoID', function(name)
        return isWSHLAmmo[name]
    end)

    WSHL_Detour(game, 'GetAmmoData', function(id)
        return ammoTypes[id]
    end)

    WSHL_Detour(Entity, 'FireBullets', function(self, bulletData)
        local ammoType = bulletData.AmmoType
        local id = isWSHLAmmo[ammoType]

        if id then
            local data = ammoTypes[id]

            bulletData.AmmoType = '_wshl_refammo_ammo'
            bulletData.Tracer = data.tracer or bulletData.Tracer
            bulletData.Force = data.force or bulletData.Force
        end
    end)

    local PlayerCanPickupWeapon = GAMEMODE.PlayerCanPickupWeapon

    function GAMEMODE:PlayerCanPickupWeapon(ply, wep, ...)
        local canPickup = PlayerCanPickupWeapon(self, ply, wep, ...)

        if canPickup and wep:IsScripted() then
            local primary = wep.Primary
            local secondary = wep.Secondary

            if primary then
                local prAmmo = primary.Ammo
                local prDefaultClip = primary.DefaultClip
    
                if isWSHLAmmo[prAmmo] and prDefaultClip then
                    ply:GiveAmmo(prDefaultClip, prAmmo)
                end
            end
    
            if secondary then
                local seAmmo = secondary.Ammo
                local seDefaultClip = secondary.DefaultClip
    
                if isWSHLAmmo[seAmmo] and seDefaultClip then
                    ply:GiveAmmo(seDefaultClip, seAmmo)
                end
            end
        end

        return canPickup
    end
end)
