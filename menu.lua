-- eni.menu — FiveM executor menu (Red Engine / Eulen / any script runner)
-- Hosted HTML UI rendered through DUI. All state and input live in lua because
-- DUI has no page->lua channel (NUI callbacks never fire from a DUI browser).
--
-- F5 open/close · mouse to click · wheel to page · <-/-> tabs · ESC back

local URL = 'https://pekii32.github.io/eni-menu/?dui=1'

if _G.__eni and _G.__eni.destroy then pcall(_G.__eni.destroy) end

local ENI = {}
_G.__eni = ENI
ENI.alive = true

-- ── geometry (must match style.css exactly) ──────────────────────────────
local PANEL_W, PANEL_H = 880, 580
local SIDEBAR_W        = 208
local TAB_TOP, TAB_STEP, TAB_H = 62, 38, 34
local HEADER_H         = 74
local ROW_H, SEC_H     = 46, 34
local PAD_X            = 20
local CONTENT_H        = PANEL_H - HEADER_H

local sw, sh = GetActiveScreenResolution()
local panelX = math.floor((sw - PANEL_W) / 2)
local panelY = math.floor((sh - PANEL_H) / 2)
local contentX = panelX + SIDEBAR_W

-- ── state ────────────────────────────────────────────────────────────────
local open, tabIndex, page = false, 1, 1
local hoverRow, hoverTab = 0, 0
local subject = nil
local notifyTxt, notifyUntil = nil, 0

local S = {
    god = false, invis = false, noclip = false, freecam = false,
    superJump = false, fastRun = false, infStam = false,
    infAmmo = false, noReload = false, silentAim = false, aimHead = true,
    rapidFire = false, vehGod = false, vehBoost = false,
    espNames = false, espBox = false, espHealth = false,
    blockInput = true,
}

local VEHICLES = {
    'adder','zentorno','t20','osiris','entityxf','banshee','infernus','cheetah',
    'sultanrs','elegy2','kuruma','dominator','police','police3','ambulance',
    'firetruk','buzzard','maverick','lazer','rhino','insurgent','technical',
    'sanchez','bati','akuma','rebel','blazer','toros','krieger','deveste',
}
local WEATHERS = { 'CLEAR','EXTRASUNNY','CLOUDS','OVERCAST','RAIN','THUNDER','CLEARING','SMOG','FOGGY','XMAS','SNOWLIGHT','BLIZZARD' }
local SPOTS = {
    { 'Legion Square',      195.0,   -933.0,  30.7 },
    { 'LS Airport',        -1037.0, -2737.0,  20.2 },
    { 'Mount Chiliad',       501.0,  5604.0, 797.9 },
    { 'Sandy Shores',       1961.0,  3740.0,  32.3 },
    { 'Paleto Bay',         -103.0,  6462.0,  31.6 },
    { 'Vinewood Sign',       711.0,  1198.0, 348.5 },
    { 'Maze Bank Roof',      -75.0,  -818.0, 326.1 },
    { 'Del Perro Pier',    -1850.0, -1231.0,  13.0 },
}
local vehIdx, wIdx, spotIdx, hour = 1, 1, 1, 12

-- ── helpers ──────────────────────────────────────────────────────────────
local function me() return PlayerPedId() end
local function myCoords() return GetEntityCoords(me()) end

local function notify(t) notifyTxt = t; notifyUntil = GetGameTimer() + 2400 end

local function loadModel(m)
    local h = type(m) == 'number' and m or GetHashKey(m)
    if not IsModelInCdimage(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer()
    while not HasModelLoaded(h) do
        Wait(0)
        if GetGameTimer() - t > 6000 then return nil end
    end
    return h
end

local function curVehicle()
    local v = GetVehiclePedIsIn(me(), false)
    if v == 0 then return nil end
    return v
end

-- Troll actions only land if we own the entity on the network first.
local function takeControl(ent, ms)
    if not DoesEntityExist(ent) then return false end
    if not NetworkGetEntityIsNetworked(ent) then return true end
    local t = GetGameTimer()
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() - t < (ms or 700) do
        NetworkRequestControlOfEntity(ent)
        Wait(0)
    end
    return NetworkHasControlOfEntity(ent)
end

local function pedByServerId(sid)
    local pid = GetPlayerFromServerId(tonumber(sid) or -1)
    if pid == -1 then return nil end
    local pd = GetPlayerPed(pid)
    if not DoesEntityExist(pd) then return nil end
    return pd, pid
end

local function playerList()
    local out, mc = {}, myCoords()
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= PlayerId() then
            local pd = GetPlayerPed(id)
            if DoesEntityExist(pd) then
                out[#out+1] = {
                    serverId = GetPlayerServerId(id),
                    name = GetPlayerName(id) or '?',
                    dist = math.floor(#(GetEntityCoords(pd) - mc)),
                    hp = GetEntityHealth(pd),
                    veh = GetVehiclePedIsIn(pd, false),
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

local function rotToDir(rx, rz)
    local x, z = math.rad(rx), math.rad(rz)
    local n = math.abs(math.cos(x))
    return -math.sin(z) * n, math.cos(z) * n, math.sin(x)
end

-- ── actions ──────────────────────────────────────────────────────────────
local A = {}

function A.heal()
    local p = me()
    SetEntityHealth(p, GetEntityMaxHealth(p)); SetPedArmour(p, 100); ClearPedBloodDamage(p)
    notify('Healed')
end

function A.revive()
    local p, c = me(), myCoords()
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(p), true, false)
    SetEntityHealth(p, GetEntityMaxHealth(p)); ClearPedBloodDamage(p)
    notify('Revived')
end

function A.suicide() SetEntityHealth(me(), 0) end

function A.giveWeapons()
    local list = {
        'WEAPON_PISTOL','WEAPON_COMBATPISTOL','WEAPON_PISTOL50','WEAPON_APPISTOL',
        'WEAPON_MICROSMG','WEAPON_SMG','WEAPON_ASSAULTSMG','WEAPON_ASSAULTRIFLE',
        'WEAPON_CARBINERIFLE','WEAPON_SPECIALCARBINE','WEAPON_BULLPUPRIFLE',
        'WEAPON_COMBATMG','WEAPON_PUMPSHOTGUN','WEAPON_ASSAULTSHOTGUN',
        'WEAPON_SNIPERRIFLE','WEAPON_HEAVYSNIPER','WEAPON_RPG','WEAPON_GRENADELAUNCHER',
        'WEAPON_MINIGUN','WEAPON_GRENADE','WEAPON_STICKYBOMB','WEAPON_MOLOTOV',
        'WEAPON_KNIFE','WEAPON_BAT','WEAPON_MACHETE','WEAPON_PARACHUTE',
    }
    for _, w in ipairs(list) do GiveWeaponToPed(me(), GetHashKey(w), 9999, false, false) end
    notify('All weapons given')
end

function A.tpWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then notify('No waypoint set') return end
    local c = GetBlipInfoIdCoord(blip)
    local ent = curVehicle() or me()
    for z = 1, 1000, 25 do
        SetEntityCoordsNoOffset(ent, c.x, c.y, z + 0.0, false, false, false)
        Wait(0)
        local found, gz = GetGroundZFor_3dCoord(c.x, c.y, z + 0.0, false)
        if found then
            SetEntityCoordsNoOffset(ent, c.x, c.y, gz + 1.0, false, false, false)
            notify('Teleported to waypoint'); return
        end
    end
    notify('Teleported (no ground found)')
end

function A.tpSpot()
    local s = SPOTS[spotIdx]
    SetEntityCoordsNoOffset(curVehicle() or me(), s[2], s[3], s[4], false, false, false)
    notify('Teleported to ' .. s[1])
end

function A.spawnVehicle()
    local name = VEHICLES[vehIdx]
    local h = loadModel(name)
    if not h then notify('Bad model: ' .. name) return end
    local p, c = me(), myCoords()
    local hd = GetEntityHeading(p)
    local old = curVehicle()
    local v = CreateVehicle(h, c.x + math.sin(-math.rad(hd)) * 4.0, c.y + math.cos(-math.rad(hd)) * 4.0, c.z, hd, true, false)
    SetVehicleHasBeenOwnedByPlayer(v, true); SetVehicleNeedsToBeHotwired(v, false)
    SetVehRadioStation(v, 'OFF'); SetEntityAsMissionEntity(v, true, true)
    local nid = NetworkGetNetworkIdFromEntity(v)
    SetNetworkIdCanMigrate(nid, true); SetNetworkIdExistsOnAllMachines(nid, true)
    SetPedIntoVehicle(p, v, -1); SetModelAsNoLongerNeeded(h)
    if old and old ~= v then SetEntityAsMissionEntity(old, true, true); DeleteVehicle(old) end
    notify('Spawned ' .. name)
end

function A.repairVehicle()
    local v = curVehicle(); if not v then notify('Not in a vehicle') return end
    SetVehicleFixed(v); SetVehicleDeformationFixed(v); SetVehicleUndriveable(v, false)
    SetVehicleEngineHealth(v, 1000.0); SetVehicleBodyHealth(v, 1000.0)
    SetVehiclePetrolTankHealth(v, 1000.0); SetVehicleDirtLevel(v, 0.0)
    SetVehicleEngineOn(v, true, true, false)
    notify('Repaired')
end

function A.upgradeVehicle()
    local v = curVehicle(); if not v then notify('Not in a vehicle') return end
    SetVehicleModKit(v, 0)
    for i = 0, 16 do
        local n = GetNumVehicleMods(v, i)
        if n > 0 then SetVehicleMod(v, i, n - 1, false) end
    end
    ToggleVehicleMod(v, 18, true); SetVehicleWheelType(v, 6)
    SetVehicleTyresCanBurst(v, false); SetVehicleWindowTint(v, 1)
    notify('Vehicle maxed')
end

function A.flipVehicle()
    local v = curVehicle(); if not v then notify('Not in a vehicle') return end
    SetVehicleOnGroundProperly(v); notify('Flipped')
end

function A.deleteVehicle()
    local v = curVehicle(); if not v then notify('Not in a vehicle') return end
    SetEntityAsMissionEntity(v, true, true); DeleteVehicle(v); notify('Deleted')
end

function A.applyWeather()
    local w = WEATHERS[wIdx]
    SetOverrideWeather(w); SetWeatherTypeNowPersist(w); SetWeatherTypePersist(w)
    notify('Weather: ' .. w .. ' (server may resync)')
end

function A.applyTime()
    NetworkOverrideClockTime(hour, 0, 0)
    notify(string.format('Time %02d:00 (client only)', hour))
end

function A.clearArea()
    local c = myCoords()
    ClearAreaOfPeds(c.x, c.y, c.z, 120.0, 1)
    ClearAreaOfVehicles(c.x, c.y, c.z, 120.0, false, false, false, false, false)
    notify('Area cleared')
end

-- ── freecam ──────────────────────────────────────────────────────────────
local cam, camPos, camRot = nil, nil, nil

local function startFreecam()
    local gp, gr = GetGameplayCamCoord(), GetGameplayCamRot(2)
    camPos = { x = gp.x, y = gp.y, z = gp.z }
    camRot = { x = gr.x, z = gr.z }
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, camRot.x, 0.0, camRot.z, GetGameplayCamFov(), true, 2)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    local p = me()
    FreezeEntityPosition(p, true); SetEntityInvincible(p, true); SetEntityVisible(p, false, false)
    notify('Freecam on — WASD move, Shift boost')
end

local function stopFreecam()
    RenderScriptCams(false, false, 0, true, true)
    if cam then DestroyCam(cam, false); cam = nil end
    local p = me()
    FreezeEntityPosition(p, false)
    if not S.god then SetEntityInvincible(p, false) end
    if not S.invis then SetEntityVisible(p, true, false) end
    notify('Freecam off')
end

function A.tpToFreecam()
    if not S.freecam or not camPos then notify('Freecam is off') return end
    local ent = curVehicle() or me()
    local found, gz = GetGroundZFor_3dCoord(camPos.x, camPos.y, camPos.z, false)
    SetEntityCoordsNoOffset(ent, camPos.x, camPos.y, (found and gz + 1.0) or camPos.z, false, false, false)
    S.freecam = false; stopFreecam()
    notify('Teleported to freecam')
end

-- ── silent aim ───────────────────────────────────────────────────────────
-- Picks the player nearest your crosshair and redirects the bullet there.
local function aimTarget()
    local mc = myCoords()
    local best, bestScore = nil, 0.14   -- max normalised screen distance
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= PlayerId() then
            local pd = GetPlayerPed(id)
            if DoesEntityExist(pd) and not IsEntityDead(pd) then
                local c = GetEntityCoords(pd)
                local d = #(c - mc)
                if d < 300.0 and HasEntityClearLosToEntity(me(), pd, 17) then
                    local on, sx, sy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z)
                    if on then
                        local score = math.sqrt((sx - 0.5) ^ 2 + (sy - 0.5) ^ 2)
                        if score < bestScore then best, bestScore = pd, score end
                    end
                end
            end
        end
    end
    return best
end

-- ── player / troll actions ───────────────────────────────────────────────
local function withSubject(fn, needControl)
    local pd = pedByServerId(subject)
    if not pd then notify('Player not found') return end
    if needControl and not takeControl(pd) then
        notify('Could not take control of that player')
        return
    end
    fn(pd)
end

function A.tpToPlayer()
    withSubject(function(pd)
        local c = GetEntityCoords(pd)
        SetEntityCoordsNoOffset(curVehicle() or me(), c.x + 1.5, c.y + 1.5, c.z, false, false, false)
        notify('Teleported to player')
    end)
end

function A.bringPlayer()
    withSubject(function(pd)
        local c = myCoords()
        SetEntityCoordsNoOffset(pd, c.x + 1.5, c.y + 1.5, c.z, false, false, false)
        notify('Player brought')
    end, true)
end

function A.spectate()
    withSubject(function(pd) NetworkSetInSpectatorMode(true, pd); notify('Spectating') end)
end

function A.stopSpectate()
    NetworkSetInSpectatorMode(false, me()); notify('Spectate off')
end

function A.markPlayer()
    withSubject(function(pd)
        local c = GetEntityCoords(pd); SetNewWaypoint(c.x, c.y); notify('Waypoint set')
    end)
end

function A.explodePlayer()
    withSubject(function(pd)
        local c = GetEntityCoords(pd)
        AddExplosion(c.x, c.y, c.z, 2, 100.0, true, false, 1.0)
        notify('Exploded')
    end)
end

function A.firePlayer()
    withSubject(function(pd)
        local c = GetEntityCoords(pd)
        StartScriptFire(c.x, c.y, c.z, 25, true)
        StartEntityFire(pd)
        notify('Set on fire')
    end, true)
end

function A.ragdollPlayer()
    withSubject(function(pd)
        SetPedToRagdoll(pd, 8000, 8000, 0, true, true, false)
        notify('Ragdolled')
    end, true)
end

function A.launchPlayer()
    withSubject(function(pd)
        SetPedToRagdoll(pd, 6000, 6000, 0, true, true, false)
        ApplyForceToEntity(pd, 1, 0.0, 0.0, 55.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
        notify('Launched')
    end, true)
end

function A.slapPlayer()
    withSubject(function(pd)
        local mc, c = myCoords(), GetEntityCoords(pd)
        local dx, dy = c.x - mc.x, c.y - mc.y
        local len = math.max(math.sqrt(dx * dx + dy * dy), 0.001)
        SetPedToRagdoll(pd, 3000, 3000, 0, true, true, false)
        ApplyForceToEntity(pd, 1, (dx / len) * 22.0, (dy / len) * 22.0, 12.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
        notify('Slapped')
    end, true)
end

function A.freezePlayer()
    withSubject(function(pd) FreezeEntityPosition(pd, true); notify('Frozen') end, true)
end

function A.unfreezePlayer()
    withSubject(function(pd) FreezeEntityPosition(pd, false); notify('Unfrozen') end, true)
end

function A.kickFromVehicle()
    withSubject(function(pd)
        local v = GetVehiclePedIsIn(pd, false)
        if v == 0 then notify('Not in a vehicle') return end
        takeControl(v)
        TaskLeaveVehicle(pd, v, 4160)
        notify('Ejected from vehicle')
    end, true)
end

function A.boomVehicle()
    withSubject(function(pd)
        local v = GetVehiclePedIsIn(pd, false)
        if v == 0 then notify('Not in a vehicle') return end
        takeControl(v)
        NetworkExplodeVehicle(v, true, false, false)
        notify('Vehicle exploded')
    end)
end

function A.delVehicle()
    withSubject(function(pd)
        local v = GetVehiclePedIsIn(pd, false)
        if v == 0 then notify('Not in a vehicle') return end
        if not takeControl(v) then notify('Could not take control') return end
        SetEntityAsMissionEntity(v, true, true); DeleteVehicle(v)
        notify('Vehicle deleted')
    end)
end

function A.rainCars()
    withSubject(function(pd)
        local c = GetEntityCoords(pd)
        CreateThread(function()
            for i = 1, 12 do
                if not ENI.alive then return end
                local m = loadModel(VEHICLES[math.random(#VEHICLES)])
                if m then
                    local v = CreateVehicle(m, c.x + math.random(-7, 7), c.y + math.random(-7, 7), c.z + 45 + i * 4, 0.0, true, false)
                    SetEntityAsMissionEntity(v, true, true)
                    SetModelAsNoLongerNeeded(m)
                end
                Wait(180)
            end
        end)
        notify('Raining cars')
    end)
end

function A.unload() notify('Unloading'); ENI.destroy() end

-- ── menu definition ──────────────────────────────────────────────────────
local TABS = { 'Self', 'Weapons', 'Vehicle', 'Teleport', 'Players', 'World', 'Visuals', 'Settings' }

local function buildRows()
    local t = TABS[tabIndex]
    local r = {}
    local function sec(l)             r[#r+1] = { t = 'section', label = l } end
    local function tog(k, l, s)       r[#r+1] = { t = 'toggle', label = l, sub = s, on = S[k], key = k } end
    local function act(l, fn, dg, s)  r[#r+1] = { t = 'action', label = l, fn = fn, danger = dg, sub = s } end
    local function val(l, v, fn)      r[#r+1] = { t = 'value', label = l, value = v, fn = fn } end

    if subject then
        local pd, pid = pedByServerId(subject)
        local name = pid and GetPlayerName(pid) or ('#' .. tostring(subject))
        local dist = pd and math.floor(#(GetEntityCoords(pd) - myCoords())) or 0
        sec(name .. '   #' .. tostring(subject) .. '   ' .. dist .. 'm')
        act('Back to Player List', function() subject = nil; page = 1 end)
        sec('Movement')
        act('Teleport to Player', A.tpToPlayer)
        act('Bring Player', A.bringPlayer)
        act('Spectate', A.spectate)
        act('Stop Spectating', A.stopSpectate)
        act('Set Waypoint on Player', A.markPlayer)
        sec('Troll')
        act('Slap', A.slapPlayer)
        act('Ragdoll', A.ragdollPlayer)
        act('Launch Into Air', A.launchPlayer)
        act('Set On Fire', A.firePlayer)
        act('Freeze', A.freezePlayer)
        act('Unfreeze', A.unfreezePlayer)
        act('Rain Cars', A.rainCars)
        act('Explode', A.explodePlayer, true)
        sec('Their Vehicle')
        act('Eject From Vehicle', A.kickFromVehicle)
        act('Explode Vehicle', A.boomVehicle, true)
        act('Delete Vehicle', A.delVehicle, true)
        return r
    end

    if t == 'Self' then
        sec('Protection')
        tog('god', 'Godmode')
        tog('invis', 'Invisible')
        sec('Movement')
        tog('noclip', 'Noclip', 'W/S/A/D · Shift boost · Space up · Ctrl down')
        tog('freecam', 'Freecam', 'Detached camera, body stays put')
        act('Teleport to Freecam', A.tpToFreecam)
        tog('superJump', 'Super Jump')
        tog('fastRun', 'Fast Run')
        tog('infStam', 'Infinite Stamina')
        sec('Health')
        act('Heal & Armor', A.heal)
        act('Revive', A.revive)
        act('Suicide', A.suicide, true)

    elseif t == 'Weapons' then
        sec('Loadout')
        act('Give All Weapons', A.giveWeapons)
        sec('Aim')
        tog('silentAim', 'Silent Aim', 'Redirects your shot to the nearest player')
        tog('aimHead', 'Target Head', 'Otherwise aims centre mass')
        sec('Modifiers')
        tog('infAmmo', 'Infinite Ammo')
        tog('noReload', 'No Reload')
        tog('rapidFire', 'Rapid Fire')

    elseif t == 'Vehicle' then
        sec('Spawn')
        val('Model', VEHICLES[vehIdx], function() vehIdx = vehIdx % #VEHICLES + 1 end)
        act('Spawn Vehicle', A.spawnVehicle)
        sec('Current Vehicle')
        tog('vehGod', 'Vehicle Godmode')
        tog('vehBoost', 'Speed Boost', 'Hold horn for a burst')
        act('Repair', A.repairVehicle)
        act('Max Upgrade', A.upgradeVehicle)
        act('Flip Upright', A.flipVehicle)
        act('Delete Vehicle', A.deleteVehicle, true)

    elseif t == 'Teleport' then
        sec('Quick')
        act('Teleport to Waypoint', A.tpWaypoint)
        act('Teleport to Freecam', A.tpToFreecam)
        sec('Locations')
        val('Location', SPOTS[spotIdx][1], function() spotIdx = spotIdx % #SPOTS + 1 end)
        act('Teleport to Location', A.tpSpot)

    elseif t == 'Players' then
        local list = playerList()
        sec(#list .. ' player' .. (#list == 1 and '' or 's') .. ' nearby')
        if #list == 0 then
            r[#r+1] = { t = 'empty', label = 'No other players' }
        end
        for _, p in ipairs(list) do
            r[#r+1] = {
                t = 'player',
                label = p.name,
                sub = string.format('#%d   %dm   %d hp%s', p.serverId, p.dist, p.hp, p.veh ~= 0 and '   in vehicle' or ''),
                sid = p.serverId,
            }
        end

    elseif t == 'World' then
        sec('Weather')
        val('Preset', WEATHERS[wIdx], function() wIdx = wIdx % #WEATHERS + 1 end)
        act('Apply Weather', A.applyWeather)
        sec('Time')
        val('Hour', string.format('%02d:00', hour), function() hour = (hour + 1) % 24 end)
        act('Apply Time', A.applyTime)
        sec('Cleanup')
        act('Clear Area (120m)', A.clearArea)

    elseif t == 'Visuals' then
        sec('Player ESP')
        tog('espNames', 'Names & Distance')
        tog('espBox', 'Boxes')
        tog('espHealth', 'Health Bars')

    elseif t == 'Settings' then
        sec('Input')
        tog('blockInput', 'Block Game Input While Open')
        sec('Menu')
        act('Unload Menu', A.unload, true)
    end

    return r
end

-- Scrolling would desync lua's hit-testing, so slice into fixed pages instead.
local function paginate(all)
    local pages, cur, h = {}, {}, 0
    for _, row in ipairs(all) do
        local rh = (row.t == 'section') and SEC_H or ROW_H
        if h + rh > CONTENT_H and #cur > 0 then
            -- never strand a section header alone at the foot of a page
            local carry = (cur[#cur].t == 'section') and table.remove(cur) or nil
            pages[#pages+1] = cur
            cur, h = {}, 0
            if carry then cur[1] = carry; h = SEC_H end
        end
        cur[#cur+1] = row; h = h + rh
    end
    if #cur > 0 then pages[#pages+1] = cur end
    if #pages == 0 then pages = { {} } end
    return pages
end

-- ── DUI ──────────────────────────────────────────────────────────────────
local dui = CreateDui(URL, sw, sh)
local txdName = 'eni_txd_' .. tostring(GetGameTimer())
CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd(txdName), 'ui', GetDuiHandle(dui))

local rows = {}
local pageCount = 1
local mx, my = sw / 2, sh / 2

local function pushRender()
    local hint = 'F5 close'
    if pageCount > 1 then hint = ('Page %d/%d   ·   wheel'):format(page, pageCount) end
    local payload = {
        action = 'render',
        tabs = TABS, tabIndex = tabIndex,
        title = subject and 'Player' or TABS[tabIndex],
        hint = hint,
        hoverRow = hoverRow, hoverTab = hoverTab,
        cursor = { x = math.floor(mx), y = math.floor(my) },
        notify = (notifyUntil > GetGameTimer()) and notifyTxt or nil,
        rows = {},
    }
    for i, row in ipairs(rows) do
        payload.rows[i] = { t = row.t, label = row.label, sub = row.sub, on = row.on, value = row.value, danger = row.danger }
    end
    SendDuiMessage(dui, json.encode(payload))
end

local function activate(i)
    local row = rows[i]
    if not row then return end
    if row.t == 'toggle' then
        S[row.key] = not S[row.key]
        local p = me()
        if row.key == 'noclip' and not S.noclip then
            SetEntityCollision(p, true, true); FreezeEntityPosition(p, false)
        elseif row.key == 'god' and not S.god then
            SetEntityInvincible(p, false); SetPlayerInvincible(PlayerId(), false)
        elseif row.key == 'invis' and not S.invis then
            SetEntityVisible(p, true, false)
        elseif row.key == 'freecam' then
            if S.freecam then startFreecam() else stopFreecam() end
        end
    elseif row.t == 'action' or row.t == 'value' then
        if row.fn then row.fn() end
    elseif row.t == 'player' then
        subject = row.sid; page = 1
    end
end

local function setOpen(v)
    open = v
    SendDuiMessage(dui, json.encode({ action = 'visible', visible = v }))
    if not v then hoverRow, hoverTab = 0, 0 end
end

-- ── main loop ────────────────────────────────────────────────────────────
CreateThread(function()
    while ENI.alive do
        Wait(0)

        if IsControlJustPressed(0, 166) or IsDisabledControlJustPressed(0, 166) then
            setOpen(not open)
        end

        if open then
            local pages = paginate(buildRows())
            pageCount = #pages
            if page > pageCount then page = pageCount end
            if page < 1 then page = 1 end
            rows = pages[page]

            if S.blockInput then DisableAllControlActions(0) end
            SetMouseCursorActiveThisFrame()

            mx = GetDisabledControlNormal(0, 239) * sw
            my = GetDisabledControlNormal(0, 240) * sh

            hoverTab = 0
            if mx >= panelX + 12 and mx <= panelX + SIDEBAR_W - 12 then
                for i = 1, #TABS do
                    local ty = panelY + TAB_TOP + (i - 1) * TAB_STEP
                    if my >= ty and my <= ty + TAB_H then hoverTab = i break end
                end
            end

            hoverRow = 0
            if mx >= contentX + PAD_X and mx <= panelX + PANEL_W - PAD_X then
                local y = panelY + HEADER_H
                for i, row in ipairs(rows) do
                    local h = (row.t == 'section') and SEC_H or ROW_H
                    if row.t ~= 'section' and row.t ~= 'empty' and my >= y and my <= y + h then
                        hoverRow = i break
                    end
                    y = y + h
                end
            end

            if IsDisabledControlJustPressed(0, 237) or IsDisabledControlJustPressed(0, 24) then
                if hoverTab > 0 then
                    tabIndex = hoverTab; subject = nil; page = 1
                elseif hoverRow > 0 then
                    activate(hoverRow)
                end
            end

            if IsDisabledControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 14) then
                page = math.max(1, page - 1)
            elseif IsDisabledControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 15) then
                page = math.min(pageCount, page + 1)
            end

            if IsDisabledControlJustPressed(0, 174) then
                tabIndex = (tabIndex - 2) % #TABS + 1; subject = nil; page = 1
            elseif IsDisabledControlJustPressed(0, 175) then
                tabIndex = tabIndex % #TABS + 1; subject = nil; page = 1
            end
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 202) then
                if subject then subject = nil; page = 1 else setOpen(false) end
            end

            DrawSprite(txdName, 'ui', 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
            pushRender()
        end
    end
end)

-- ── feature loops ────────────────────────────────────────────────────────
CreateThread(function()
    while ENI.alive do
        Wait(0)
        local p, pid = me(), PlayerId()

        if S.god then
            SetEntityInvincible(p, true); SetPlayerInvincible(pid, true)
            SetPedCanRagdoll(p, false); ClearPedBloodDamage(p)
            if GetEntityHealth(p) < GetEntityMaxHealth(p) then SetEntityHealth(p, GetEntityMaxHealth(p)) end
        end
        if S.invis then SetEntityVisible(p, false, false) end
        if S.superJump then SetSuperJumpThisFrame(pid) end
        if S.fastRun then
            SetRunSprintMultiplierForPlayer(pid, 1.49); SetSwimMultiplierForPlayer(pid, 1.49)
        end
        if S.infStam then RestorePlayerStamina(pid, 1.0) end

        if S.infAmmo then
            local w = GetSelectedPedWeapon(p)
            if w and w ~= GetHashKey('WEAPON_UNARMED') then
                SetPedInfiniteAmmo(p, true, w); SetPedInfiniteAmmoClip(p, true)
            end
        end
        if S.noReload then
            local _, w = GetCurrentPedWeapon(p, true)
            if w then
                local mx2 = GetMaxAmmoInClip(p, w, true)
                if mx2 and mx2 > 0 then SetAmmoInClip(p, w, mx2) end
            end
        end
        if S.rapidFire then SetPedShootRate(p, 1000) end

        local v = GetVehiclePedIsIn(p, false)
        if v ~= 0 then
            if S.vehGod then
                SetEntityInvincible(v, true); SetVehicleCanBeVisiblyDamaged(v, false)
                SetVehicleTyresCanBurst(v, false)
                SetVehicleEngineHealth(v, 1000.0); SetVehicleBodyHealth(v, 1000.0)
            end
            if S.vehBoost and GetPedInVehicleSeat(v, -1) == p then
                SetVehicleCheatPowerIncrease(v, 2.0)
                if IsDisabledControlPressed(0, 86) then
                    SetVehicleForwardSpeed(v, GetEntitySpeed(v) + 4.0)
                end
            end
        end
    end
end)

-- silent aim
CreateThread(function()
    while ENI.alive do
        Wait(0)
        if S.silentAim and not open and IsPlayerFreeAiming(PlayerId()) then
            if IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 24) then
                local target = aimTarget()
                if target then
                    local p = me()
                    local w = GetSelectedPedWeapon(p)
                    local muzzle = GetPedBoneCoords(p, 28422, 0.0, 0.0, 0.0)
                    local hit = S.aimHead and GetPedBoneCoords(target, 31086, 0.0, 0.0, 0.0)
                                or GetPedBoneCoords(target, 24818, 0.0, 0.0, 0.0)
                    ShootSingleBulletBetweenCoords(
                        muzzle.x, muzzle.y, muzzle.z,
                        hit.x, hit.y, hit.z,
                        150, true, w, p, true, false, 2000.0)
                end
            end
        end
    end
end)

-- noclip
CreateThread(function()
    while ENI.alive do
        Wait(0)
        if S.noclip and not S.freecam then
            local p = me()
            local ent = GetVehiclePedIsIn(p, false)
            if ent == 0 then ent = p end
            SetEntityCollision(ent, false, false)
            FreezeEntityPosition(ent, true)
            SetEntityInvincible(ent, true)
            if not open then
                local c = GetEntityCoords(ent)
                local yaw = GetGameplayCamRelativeHeading() + GetEntityHeading(ent)
                local dx, dy, dz = rotToDir(GetGameplayCamRelativePitch(), yaw)
                local spd = IsControlPressed(0, 21) and 4.0 or 1.2
                if IsControlPressed(0, 32) then SetEntityCoordsNoOffset(ent, c.x+dx*spd, c.y+dy*spd, c.z+dz*spd, true, true, true) end
                if IsControlPressed(0, 33) then SetEntityCoordsNoOffset(ent, c.x-dx*spd, c.y-dy*spd, c.z-dz*spd, true, true, true) end
                if IsControlPressed(0, 22) then SetEntityCoordsNoOffset(ent, c.x, c.y, c.z+spd, true, true, true) end
                if IsControlPressed(0, 36) then SetEntityCoordsNoOffset(ent, c.x, c.y, c.z-spd, true, true, true) end
            end
        end
    end
end)

-- freecam
CreateThread(function()
    while ENI.alive do
        Wait(0)
        if S.freecam and cam then
            if not open then
                camRot.z = camRot.z - GetDisabledControlNormal(0, 1) * 8.0
                camRot.x = math.max(-89.0, math.min(89.0, camRot.x - GetDisabledControlNormal(0, 2) * 8.0))
                SetCamRot(cam, camRot.x, 0.0, camRot.z, 2)

                local dx, dy, dz = rotToDir(camRot.x, camRot.z)
                local spd = IsDisabledControlPressed(0, 21) and 3.0 or 0.9
                local rz = math.rad(camRot.z)
                local rx, ry = -math.cos(rz), -math.sin(rz)   -- strafe vector

                if IsDisabledControlPressed(0, 32) then camPos.x = camPos.x + dx*spd; camPos.y = camPos.y + dy*spd; camPos.z = camPos.z + dz*spd end
                if IsDisabledControlPressed(0, 33) then camPos.x = camPos.x - dx*spd; camPos.y = camPos.y - dy*spd; camPos.z = camPos.z - dz*spd end
                if IsDisabledControlPressed(0, 34) then camPos.x = camPos.x + rx*spd; camPos.y = camPos.y + ry*spd end
                if IsDisabledControlPressed(0, 35) then camPos.x = camPos.x - rx*spd; camPos.y = camPos.y - ry*spd end
                if IsDisabledControlPressed(0, 22) then camPos.z = camPos.z + spd end
                if IsDisabledControlPressed(0, 36) then camPos.z = camPos.z - spd end

                SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
            end
            -- keep the world streamed in around the camera
            SetFocusPosAndVel(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)
        end
    end
end)

-- ESP
CreateThread(function()
    while ENI.alive do
        Wait(0)
        if S.espNames or S.espBox or S.espHealth then
            local mc = myCoords()
            for _, id in ipairs(GetActivePlayers()) do
                if id ~= PlayerId() then
                    local pd = GetPlayerPed(id)
                    if DoesEntityExist(pd) then
                        local c = GetEntityCoords(pd)
                        local d = #(c - mc)
                        if d < 300.0 then
                            local onH, hx, hy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 1.0)
                            local onF, fx, fy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z - 1.0)
                            if onH then
                                if S.espBox and onF then
                                    local h = math.abs(fy - hy)
                                    local w = h * 0.42
                                    local t = 0.0014
                                    DrawRect(hx, hy, w, t, 255, 255, 255, 190)
                                    DrawRect(hx, fy, w, t, 255, 255, 255, 190)
                                    DrawRect(hx - w/2, (hy+fy)/2, t*0.56, h, 255, 255, 255, 190)
                                    DrawRect(hx + w/2, (hy+fy)/2, t*0.56, h, 255, 255, 255, 190)
                                end
                                if S.espHealth and onF then
                                    local hp = math.max(0, math.min(1, (GetEntityHealth(pd) - 100) / 100))
                                    local h = math.abs(fy - hy)
                                    local w = h * 0.42
                                    local bx = hx - w/2 - 0.006
                                    DrawRect(bx, (hy+fy)/2, 0.0022, h, 0, 0, 0, 160)
                                    DrawRect(bx, fy - (h*hp)/2, 0.0022, h*hp,
                                        math.floor(255*(1-hp)), math.floor(200*hp), 60, 230)
                                end
                                if S.espNames then
                                    SetTextScale(0.30, 0.30); SetTextFont(4); SetTextCentre(true)
                                    SetTextColour(255, 255, 255, 220); SetTextOutline()
                                    SetTextEntry('STRING')
                                    AddTextComponentString(('%s [%d]  %dm'):format(GetPlayerName(id) or '?', GetPlayerServerId(id), math.floor(d)))
                                    DrawText(hx, hy - 0.028)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ── teardown ─────────────────────────────────────────────────────────────
ENI.destroy = function()
    ENI.alive = false
    pcall(function()
        if cam then RenderScriptCams(false, false, 0, true, true); DestroyCam(cam, false) end
        ClearFocus()
        local p = PlayerPedId()
        SetEntityCollision(p, true, true); FreezeEntityPosition(p, false)
        SetEntityVisible(p, true, false); SetEntityInvincible(p, false)
        SetPlayerInvincible(PlayerId(), false)
        NetworkSetInSpectatorMode(false, p)
    end)
    pcall(function() DestroyDui(dui) end)
    _G.__eni = nil
end

Citizen.Trace('^2eni.menu loaded^7 — press F5\n')
notify('eni.menu ready')
