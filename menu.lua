-- eni.menu — DUI-based, works in Red Engine / Eulen / any FiveM executor
-- execute this script, press F5 in-game

local RESOURCE = (GetCurrentResourceName and GetCurrentResourceName()) or 'default'
local MENU_URL = 'https://pekii32.github.io/eni-menu/?resource='..RESOURCE

-- kill any prior instance
if _G.__eniMenuInstance then
    pcall(function() _G.__eniMenuInstance.destroy() end)
end

local menuOpen = false
local state = {
    god = false, invisible = false, noclip = false,
    superJump = false, superRun = false, vehGod = false, infAmmo = false,
}

local WEAPONS = {
    'WEAPON_PISTOL50','WEAPON_COMBATPISTOL','WEAPON_APPISTOL',
    'WEAPON_SMG','WEAPON_ASSAULTRIFLE','WEAPON_CARBINERIFLE',
    'WEAPON_COMBATMG','WEAPON_PUMPSHOTGUN','WEAPON_ASSAULTSHOTGUN',
    'WEAPON_SNIPERRIFLE','WEAPON_HEAVYSNIPER','WEAPON_RPG',
    'WEAPON_GRENADELAUNCHER','WEAPON_MINIGUN','WEAPON_GRENADE',
    'WEAPON_STICKYBOMB','WEAPON_MOLOTOV','WEAPON_KNIFE',
    'WEAPON_MACHETE','WEAPON_RAILGUN'
}

-- DUI setup ---------------------------------------------------------------
local sw, sh = GetActiveScreenResolution()
local dui = CreateDui(MENU_URL, sw, sh)
local txdName = 'eni_menu_txd_'..(GetGameTimer() % 100000)
local txd = CreateRuntimeTxd(txdName)
local tx  = CreateRuntimeTextureFromDuiHandle(txd, 'menu', GetDuiHandle(dui))

local function ped() return PlayerPedId() end
local function coords() return GetEntityCoords(ped()) end
local function notify(t) SendDuiMessage(dui, json.encode({ action='notify', text=t })) end

local function toggleMenu(force)
    if force ~= nil then menuOpen = force else menuOpen = not menuOpen end
    SetNuiFocus(menuOpen, menuOpen)
    SendDuiMessage(dui, json.encode({ action='setVisible', visible=menuOpen, state=state }))
end

local function targetPed(sid)
    local pid = GetPlayerFromServerId(tonumber(sid))
    if pid == -1 then return nil end
    return GetPlayerPed(pid), pid
end

local function loadModel(name)
    local h = type(name) == 'number' and name or GetHashKey(name)
    RequestModel(h)
    local t = GetGameTimer()
    while not HasModelLoaded(h) do
        Wait(0)
        if GetGameTimer() - t > 5000 then return nil end
    end
    return h
end

-- Render + input loop -----------------------------------------------------
local renderThread = CreateThread(function()
    while _G.__eniMenuInstance == nil or _G.__eniMenuInstance.id == txdName do
        Wait(0)

        if IsControlJustPressed(0, 166) then toggleMenu() end -- F5

        if menuOpen then
            DrawSprite(txdName, 'menu', 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)

            local cx, cy = GetNuiCursorPosition()
            if cx and cy then
                SendDuiMouseMove(dui, cx, cy)
                if IsDisabledControlJustPressed(0, 237) then SendDuiMouseDown(dui, 'left')  end
                if IsDisabledControlJustReleased(0, 237) then SendDuiMouseUp(dui, 'left')   end
                if IsDisabledControlJustPressed(0, 238) then SendDuiMouseDown(dui, 'right') end
                if IsDisabledControlJustReleased(0, 238) then SendDuiMouseUp(dui, 'right')  end
            end
            if IsDisabledControlJustPressed(0, 322) then toggleMenu(false) end -- ESC
        end
    end
end)

-- State loops -------------------------------------------------------------
CreateThread(function()
    while _G.__eniMenuInstance == nil or _G.__eniMenuInstance.id == txdName do
        Wait(0)
        local p = ped()
        if state.god then SetEntityInvincible(p, true) SetPedCanRagdoll(p, false) end
        if state.invisible then SetEntityVisible(p, false, false) end
        if state.superJump then SetSuperJumpThisFrame(PlayerId()) end
        if state.superRun then
            SetRunSprintMultiplierForPlayer(PlayerId(), 1.49)
            SetSwimMultiplierForPlayer(PlayerId(), 1.49)
        end
        if state.infAmmo then
            local w = GetSelectedPedWeapon(p)
            if w then SetPedInfiniteAmmo(p, true, w) end
        end
        if state.vehGod then
            local v = GetVehiclePedIsIn(p, false)
            if v ~= 0 then
                SetEntityInvincible(v, true)
                SetVehicleCanBeVisiblyDamaged(v, false)
                SetVehicleTyresCanBurst(v, false)
            end
        end
    end
end)

CreateThread(function()
    while _G.__eniMenuInstance == nil or _G.__eniMenuInstance.id == txdName do
        Wait(0)
        if state.noclip then
            local p = ped()
            SetEntityCollision(p, false, false)
            FreezeEntityPosition(p, true)
            local c = GetEntityCoords(p)
            local heading = GetGameplayCamRelativeHeading() + GetEntityHeading(p)
            local pitch = GetGameplayCamRelativePitch()
            local rx, ry = math.rad(pitch), math.rad(heading)
            local dx = -math.sin(ry) * math.cos(rx)
            local dy =  math.cos(ry) * math.cos(rx)
            local dz =  math.sin(rx)
            local mult = IsControlPressed(0, 21) and 4.0 or 1.5
            if IsControlPressed(0, 32) then SetEntityCoordsNoOffset(p, c.x+dx*mult, c.y+dy*mult, c.z+dz*mult, true, true, true) end
            if IsControlPressed(0, 33) then SetEntityCoordsNoOffset(p, c.x-dx*mult, c.y-dy*mult, c.z-dz*mult, true, true, true) end
            if IsControlPressed(0, 22) then SetEntityCoordsNoOffset(p, c.x, c.y, c.z+0.7*mult, true, true, true) end
            if IsControlPressed(0, 36) then SetEntityCoordsNoOffset(p, c.x, c.y, c.z-0.7*mult, true, true, true) end
        end
    end
end)

-- NUI callbacks (FiveM routes https://<RESOURCE>/<name> from DUI to here) -
RegisterNUICallback('close', function(_, cb) toggleMenu(false) cb('ok') end)

RegisterNUICallback('toggle', function(d, cb)
    if state[d.key] == nil then cb('nope') return end
    state[d.key] = d.value
    if d.key == 'noclip' and not d.value then
        local p = ped(); SetEntityCollision(p, true, true); FreezeEntityPosition(p, false)
    end
    if d.key == 'god' and not d.value then SetEntityInvincible(ped(), false); SetPedCanRagdoll(ped(), true) end
    if d.key == 'invisible' and not d.value then SetEntityVisible(ped(), true, false) end
    if d.key == 'infAmmo' and not d.value then SetPedInfiniteAmmo(ped(), false, GetSelectedPedWeapon(ped())) end
    notify(d.key..' -> '..tostring(d.value))
    cb('ok')
end)

RegisterNUICallback('heal', function(_, cb)
    local p = ped(); SetEntityHealth(p, GetEntityMaxHealth(p)); SetPedArmour(p, 100); notify('healed'); cb('ok')
end)
RegisterNUICallback('suicide', function(_, cb) SetEntityHealth(ped(), 0); cb('ok') end)
RegisterNUICallback('giveWeapons', function(_, cb)
    for _, w in ipairs(WEAPONS) do GiveWeaponToPed(ped(), GetHashKey(w), 999, false, false) end
    notify('loaded out'); cb('ok')
end)
RegisterNUICallback('wanted', function(d, cb)
    SetPlayerWantedLevel(PlayerId(), tonumber(d.level) or 0, false)
    SetPlayerWantedLevelNow(PlayerId(), false); cb('ok')
end)

RegisterNUICallback('tpWaypoint', function(_, cb)
    local wp = GetFirstBlipInfoId(8)
    if not DoesBlipExist(wp) then notify('no waypoint'); cb('nope'); return end
    local c = GetBlipInfoIdCoord(wp)
    local z
    for h = 1, 1000 do
        local ok, gz = GetGroundZFor_3dCoord(c.x, c.y, h+0.0, false)
        if ok then z = gz; break end
    end
    SetEntityCoords(ped(), c.x, c.y, z or 200.0, false, false, false, true)
    notify('tp to waypoint'); cb('ok')
end)
RegisterNUICallback('tpCoords', function(d, cb)
    SetEntityCoords(ped(), d.x+0.0, d.y+0.0, d.z+0.0, false, false, false, true); cb('ok')
end)
RegisterNUICallback('tpToPlayer', function(d, cb)
    local tp = targetPed(d.id); if not tp then notify('no target'); cb('nope'); return end
    local c = GetEntityCoords(tp)
    SetEntityCoords(ped(), c.x+1.5, c.y+1.5, c.z, false, false, false, true); cb('ok')
end)

RegisterNUICallback('spawnVehicle', function(d, cb)
    local h = loadModel(d.model or 'adder'); if not h then notify('bad model'); cb('nope'); return end
    local c = coords(); local heading = GetEntityHeading(ped())
    local v = CreateVehicle(h, c.x + math.cos(math.rad(heading))*3, c.y + math.sin(math.rad(heading))*3, c.z, heading, true, false)
    SetPedIntoVehicle(ped(), v, -1); SetModelAsNoLongerNeeded(h)
    notify('spawned '..(d.model or 'adder')); cb('ok')
end)
RegisterNUICallback('repairVehicle', function(_, cb)
    local v = GetVehiclePedIsIn(ped(), false); if v == 0 then cb('nope') return end
    SetVehicleFixed(v); SetVehicleDeformationFixed(v); SetVehicleEngineHealth(v, 1000.0); cb('ok')
end)
RegisterNUICallback('upgradeVehicle', function(_, cb)
    local v = GetVehiclePedIsIn(ped(), false); if v == 0 then cb('nope') return end
    SetVehicleModKit(v, 0)
    for i = 0, 49 do SetVehicleMod(v, i, GetNumVehicleMods(v, i) - 1, false) end
    ToggleVehicleMod(v, 18, true); SetVehicleWheelType(v, 6)
    SetVehicleTyresCanBurst(v, false); cb('ok')
end)
RegisterNUICallback('boomVehicle', function(_, cb)
    local v = GetVehiclePedIsIn(ped(), false); if v ~= 0 then NetworkExplodeVehicle(v, true, false, false) end
    cb('ok')
end)

RegisterNUICallback('setWeather', function(d, cb)
    SetOverrideWeather(d.type or 'CLEAR'); SetWeatherTypeNowPersist(d.type or 'CLEAR'); cb('ok')
end)
RegisterNUICallback('setTime', function(d, cb)
    NetworkOverrideClockTime(tonumber(d.hour) or 12, 0, 0); cb('ok')
end)
RegisterNUICallback('killPeds', function(_, cb)
    local myC = coords()
    for _, p in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(p) and #(GetEntityCoords(p) - myC) < 100.0 then SetEntityHealth(p, 0) end
    end
    cb('ok')
end)
RegisterNUICallback('ragdollPeds', function(_, cb)
    local myC = coords()
    for _, p in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(p) and #(GetEntityCoords(p) - myC) < 60.0 then
            SetPedToRagdoll(p, 5000, 5000, 0, true, true, false)
        end
    end
    cb('ok')
end)

RegisterNUICallback('getPlayers', function(_, cb)
    local list = {}; local myC = coords()
    for _, id in ipairs(GetActivePlayers()) do
        local pp = GetPlayerPed(id)
        list[#list+1] = {
            id = id, serverId = GetPlayerServerId(id),
            name = GetPlayerName(id),
            distance = math.floor(#(GetEntityCoords(pp) - myC)),
            health = GetEntityHealth(pp),
        }
    end
    cb(list)
end)

RegisterNUICallback('explodePlayer', function(d, cb)
    local tp = targetPed(d.id); if not tp then cb('nope') return end
    local c = GetEntityCoords(tp)
    AddExplosion(c.x, c.y, c.z, 2, 100.0, true, false, 1.0)
    notify('boomed '..d.id); cb('ok')
end)
RegisterNUICallback('firePlayer', function(d, cb)
    local tp = targetPed(d.id); if not tp then cb('nope') return end
    local c = GetEntityCoords(tp)
    StartScriptFire(c.x, c.y, c.z, 25, true); cb('ok')
end)
RegisterNUICallback('rainCars', function(d, cb)
    local tp = targetPed(d.id); if not tp then cb('nope') return end
    local c = GetEntityCoords(tp)
    local models = {'adder','zentorno','t20','banshee','infernus','cheetah'}
    CreateThread(function()
        for i = 1, 15 do
            local m = loadModel(models[math.random(#models)])
            if m then
                local v = CreateVehicle(m, c.x + math.random(-8,8), c.y + math.random(-8,8), c.z + 40 + i*3, 0.0, true, false)
                SetVehicleOnGroundProperly(v)
                SetModelAsNoLongerNeeded(m)
            end
            Wait(150)
        end
    end)
    notify('car rain on '..d.id); cb('ok')
end)
RegisterNUICallback('spectate', function(d, cb)
    local tp = targetPed(d.id); if not tp then cb('nope') return end
    NetworkSetInSpectatorMode(true, tp); notify('spectating '..d.id); cb('ok')
end)
RegisterNUICallback('unspectate', function(_, cb)
    NetworkSetInSpectatorMode(false, ped()); cb('ok')
end)

RegisterNUICallback('moonGravity', function(_, cb) SetGravityLevel(2); cb('ok') end)
RegisterNUICallback('normalGravity', function(_, cb) SetGravityLevel(0); cb('ok') end)
RegisterNUICallback('spawnCircle', function(_, cb)
    local c = coords(); local m = loadModel('adder')
    if not m then cb('nope') return end
    for i = 1, 12 do
        local a = (i / 12) * math.pi * 2
        local v = CreateVehicle(m, c.x + math.cos(a) * 8, c.y + math.sin(a) * 8, c.z, math.deg(a), true, false)
        SetVehicleEngineOn(v, true, true, false)
    end
    SetModelAsNoLongerNeeded(m); cb('ok')
end)

_G.__eniMenuInstance = {
    id = txdName,
    destroy = function()
        pcall(function() DestroyDui(dui) end)
        pcall(function() SetNuiFocus(false, false) end)
        _G.__eniMenuInstance = nil
    end,
}

Citizen.Trace('eni.menu (DUI) loaded — press F5\n')
