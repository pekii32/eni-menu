-- eni.menu — FiveM executor menu (Red Engine / Eulen / any script runner)
-- Renders a hosted HTML UI through DUI. All input + state lives in lua,
-- because DUI has no page->lua channel (NUI callbacks never fire from a DUI).
--
-- F5 open/close · mouse to navigate · ESC close

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

local sw, sh = GetActiveScreenResolution()
local panelX = math.floor((sw - PANEL_W) / 2)
local panelY = math.floor((sh - PANEL_H) / 2)
local contentX = panelX + SIDEBAR_W

-- ── state ────────────────────────────────────────────────────────────────
local open      = false
local tabIndex  = 1
local hoverRow  = 0
local hoverTab  = 0
local subject   = nil          -- server id when inside a player submenu
local notifyTxt, notifyUntil = nil, 0

local S = {
    god = false, invis = false, noclip = false, superJump = false,
    fastRun = false, infStam = false, infAmmo = false, noReload = false,
    vehGod = false, vehBoost = false, espNames = false, blockInput = true,
}

local VEHICLES = {
    'adder','zentorno','t20','osiris','entityxf','banshee','infernus','cheetah',
    'sultanrs','elegy2','kuruma','dominator','police','police2','ambulance',
    'firetruk','buzzard','maverick','lazer','rhino','insurgent','technical',
    'sanchez','bati','akuma','rebel','blazer','toros','krieger','deveste'
}
local vehIdx = 1

local WEATHERS = { 'CLEAR','EXTRASUNNY','CLOUDS','OVERCAST','RAIN','THUNDER','CLEARING','SMOG','FOGGY','XMAS','SNOWLIGHT','BLIZZARD' }
local wIdx = 1

local SPOTS = {
    { 'Legion Square',      195.0,  -933.0,  30.7 },
    { 'Los Santos Airport', -1037.0, -2737.0, 20.2 },
    { 'Mount Chiliad',      501.0,   5604.0, 797.9 },
    { 'Sandy Shores',       1961.0,  3740.0,  32.3 },
    { 'Paleto Bay',         -103.0,  6462.0,  31.6 },
    { 'Vinewood Sign',      711.0,   1198.0, 348.5 },
    { 'Maze Bank Roof',     -75.0,  -818.0,  326.1 },
    { 'Del Perro Pier',     -1850.0, -1231.0, 13.0 },
}
local spotIdx = 1

local hour = 12

-- ── helpers ──────────────────────────────────────────────────────────────
local function me() return PlayerPedId() end
local function myCoords() return GetEntityCoords(me()) end

local function notify(t)
    notifyTxt = t
    notifyUntil = GetGameTimer() + 2200
end

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

-- players sorted by distance, nearest first
local function playerList()
    local out, mc = {}, myCoords()
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= PlayerId() then
            local pd = GetPlayerPed(id)
            if DoesEntityExist(pd) then
                out[#out+1] = {
                    ped = pd,
                    serverId = GetPlayerServerId(id),
                    name = GetPlayerName(id) or '?',
                    dist = math.floor(#(GetEntityCoords(pd) - mc)),
                    hp = GetEntityHealth(pd),
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

local function pedByServerId(sid)
    local pid = GetPlayerFromServerId(tonumber(sid) or -1)
    if pid == -1 then return nil end
    local pd = GetPlayerPed(pid)
    if not DoesEntityExist(pd) then return nil end
    return pd, pid
end

-- ── actions ──────────────────────────────────────────────────────────────
local A = {}

function A.heal()
    local p = me()
    SetEntityHealth(p, GetEntityMaxHealth(p))
    SetPedArmour(p, 100)
    ClearPedBloodDamage(p)
    notify('Healed')
end

function A.revive()
    local p = me()
    local c = GetEntityCoords(p)
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(p), true, false)
    SetEntityHealth(p, GetEntityMaxHealth(p))
    ClearPedBloodDamage(p)
    notify('Revived')
end

function A.suicide()
    SetEntityHealth(me(), 0)
end

function A.giveWeapons()
    local list = {
        'WEAPON_PISTOL','WEAPON_COMBATPISTOL','WEAPON_PISTOL50','WEAPON_APPISTOL',
        'WEAPON_MICROSMG','WEAPON_SMG','WEAPON_ASSAULTSMG','WEAPON_ASSAULTRIFLE',
        'WEAPON_CARBINERIFLE','WEAPON_SPECIALCARBINE','WEAPON_BULLPUPRIFLE',
        'WEAPON_COMBATMG','WEAPON_PUMPSHOTGUN','WEAPON_ASSAULTSHOTGUN',
        'WEAPON_SNIPERRIFLE','WEAPON_HEAVYSNIPER','WEAPON_RPG','WEAPON_GRENADELAUNCHER',
        'WEAPON_MINIGUN','WEAPON_GRENADE','WEAPON_STICKYBOMB','WEAPON_MOLOTOV',
        'WEAPON_KNIFE','WEAPON_BAT','WEAPON_MACHETE','WEAPON_PARACHUTE'
    }
    for _, w in ipairs(list) do
        GiveWeaponToPed(me(), GetHashKey(w), 9999, false, false)
    end
    notify('All weapons given')
end

function A.tpWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then notify('No waypoint set') return end
    local c = GetBlipInfoIdCoord(blip)
    local p = me()
    local veh = curVehicle()
    local ent = veh or p

    for z = 1, 1000, 25 do
        SetEntityCoordsNoOffset(ent, c.x, c.y, z + 0.0, false, false, false)
        Wait(0)
        local found, gz = GetGroundZFor_3dCoord(c.x, c.y, z + 0.0, false)
        if found then
            SetEntityCoordsNoOffset(ent, c.x, c.y, gz + 1.0, false, false, false)
            notify('Teleported to waypoint')
            return
        end
    end
    notify('Teleported (ground not found)')
end

function A.tpSpot()
    local s = SPOTS[spotIdx]
    local ent = curVehicle() or me()
    SetEntityCoordsNoOffset(ent, s[2], s[3], s[4], false, false, false)
    notify('Teleported to ' .. s[1])
end

function A.spawnVehicle()
    local name = VEHICLES[vehIdx]
    local h = loadModel(name)
    if not h then notify('Model not found: ' .. name) return end

    local p = me()
    local c = GetEntityCoords(p)
    local hd = GetEntityHeading(p)
    local old = curVehicle()

    local v = CreateVehicle(h, c.x + math.sin(-math.rad(hd)) * 4.0, c.y + math.cos(-math.rad(hd)) * 4.0, c.z, hd, true, false)
    SetVehicleHasBeenOwnedByPlayer(v, true)
    SetVehicleNeedsToBeHotwired(v, false)
    SetVehRadioStation(v, 'OFF')
    SetEntityAsMissionEntity(v, true, true)

    local nid = NetworkGetNetworkIdFromEntity(v)
    SetNetworkIdCanMigrate(nid, true)
    SetNetworkIdExistsOnAllMachines(nid, true)

    SetPedIntoVehicle(p, v, -1)
    SetModelAsNoLongerNeeded(h)

    if old and old ~= v then
        SetEntityAsMissionEntity(old, true, true)
        DeleteVehicle(old)
    end
    notify('Spawned ' .. name)
end

function A.repairVehicle()
    local v = curVehicle()
    if not v then notify('Not in a vehicle') return end
    SetVehicleFixed(v)
    SetVehicleDeformationFixed(v)
    SetVehicleUndriveable(v, false)
    SetVehicleEngineHealth(v, 1000.0)
    SetVehicleBodyHealth(v, 1000.0)
    SetVehiclePetrolTankHealth(v, 1000.0)
    SetVehicleDirtLevel(v, 0.0)
    SetVehicleEngineOn(v, true, true, false)
    notify('Vehicle repaired')
end

function A.upgradeVehicle()
    local v = curVehicle()
    if not v then notify('Not in a vehicle') return end
    SetVehicleModKit(v, 0)
    for i = 0, 16 do
        local n = GetNumVehicleMods(v, i)
        if n > 0 then SetVehicleMod(v, i, n - 1, false) end
    end
    ToggleVehicleMod(v, 18, true)   -- turbo
    SetVehicleWheelType(v, 6)
    SetVehicleTyresCanBurst(v, false)
    SetVehicleWindowTint(v, 1)
    notify('Vehicle maxed')
end

function A.flipVehicle()
    local v = curVehicle()
    if not v then notify('Not in a vehicle') return end
    SetVehicleOnGroundProperly(v)
    notify('Flipped')
end

function A.deleteVehicle()
    local v = curVehicle()
    if not v then notify('Not in a vehicle') return end
    SetEntityAsMissionEntity(v, true, true)
    DeleteVehicle(v)
    notify('Vehicle deleted')
end

function A.applyWeather()
    local w = WEATHERS[wIdx]
    SetOverrideWeather(w)
    SetWeatherTypeNowPersist(w)
    SetWeatherTypePersist(w)
    notify('Weather: ' .. w .. ' (server may resync)')
end

function A.applyTime()
    NetworkOverrideClockTime(hour, 0, 0)
    notify(string.format('Time set to %02d:00 (client only)', hour))
end

function A.clearArea()
    local c = myCoords()
    ClearAreaOfPeds(c.x, c.y, c.z, 120.0, 1)
    ClearAreaOfVehicles(c.x, c.y, c.z, 120.0, false, false, false, false, false)
    notify('Area cleared')
end

function A.tpToPlayer()
    local pd = pedByServerId(subject)
    if not pd then notify('Player not found') return end
    local c = GetEntityCoords(pd)
    local ent = curVehicle() or me()
    SetEntityCoordsNoOffset(ent, c.x + 1.5, c.y + 1.5, c.z, false, false, false)
    notify('Teleported to player')
end

function A.spectate()
    local pd = pedByServerId(subject)
    if not pd then notify('Player not found') return end
    NetworkSetInSpectatorMode(true, pd)
    notify('Spectating')
end

function A.stopSpectate()
    NetworkSetInSpectatorMode(false, me())
    notify('Spectate off')
end

function A.markPlayer()
    local pd = pedByServerId(subject)
    if not pd then notify('Player not found') return end
    local c = GetEntityCoords(pd)
    SetNewWaypoint(c.x, c.y)
    notify('Waypoint set on player')
end

function A.unload()
    notify('Unloading')
    ENI.destroy()
end

-- ── menu definition ──────────────────────────────────────────────────────
local TABS = { 'Self', 'Weapons', 'Teleport', 'Vehicle', 'Players', 'World', 'Visuals', 'Settings' }

local function buildRows()
    local t = TABS[tabIndex]
    local r = {}

    local function sec(l)              r[#r+1] = { t = 'section', label = l } end
    local function tog(k, l)           r[#r+1] = { t = 'toggle', label = l, on = S[k], key = k } end
    local function act(l, fn, danger)  r[#r+1] = { t = 'action', label = l, fn = fn, danger = danger } end
    local function val(l, v, fn)       r[#r+1] = { t = 'value', label = l, value = v, fn = fn } end

    if subject then
        local pd, pid = pedByServerId(subject)
        local name = pid and GetPlayerName(pid) or ('#' .. tostring(subject))
        sec(name .. '  ·  #' .. tostring(subject))
        act('Back to player list', function() subject = nil end)
        act('Teleport to Player', A.tpToPlayer)
        act('Spectate', A.spectate)
        act('Stop Spectating', A.stopSpectate)
        act('Set Waypoint on Player', A.markPlayer)
        return r
    end

    if t == 'Self' then
        sec('Protection')
        tog('god', 'Godmode')
        tog('invis', 'Invisible')
        sec('Movement')
        tog('noclip', 'Noclip')
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
        sec('Modifiers')
        tog('infAmmo', 'Infinite Ammo')
        tog('noReload', 'No Reload')

    elseif t == 'Teleport' then
        sec('Quick')
        act('Teleport to Waypoint', A.tpWaypoint)
        sec('Locations')
        val('Location', SPOTS[spotIdx][1], function()
            spotIdx = spotIdx % #SPOTS + 1
        end)
        act('Teleport to Location', A.tpSpot)

    elseif t == 'Vehicle' then
        sec('Spawn')
        val('Model', VEHICLES[vehIdx], function()
            vehIdx = vehIdx % #VEHICLES + 1
        end)
        act('Spawn Vehicle', A.spawnVehicle)
        sec('Current Vehicle')
        tog('vehGod', 'Vehicle Godmode')
        tog('vehBoost', 'Speed Boost')
        act('Repair', A.repairVehicle)
        act('Max Upgrade', A.upgradeVehicle)
        act('Flip Upright', A.flipVehicle)
        act('Delete Vehicle', A.deleteVehicle, true)

    elseif t == 'Players' then
        local list = playerList()
        sec(#list .. ' player' .. (#list == 1 and '' or 's') .. ' nearby')
        if #list == 0 then
            r[#r+1] = { t = 'empty', label = 'No other players' }
        end
        for i = 1, math.min(#list, 8) do
            local p = list[i]
            r[#r+1] = {
                t = 'player',
                label = p.name,
                sub = string.format('#%d  ·  %dm  ·  %d hp', p.serverId, p.dist, p.hp),
                sid = p.serverId,
            }
        end

    elseif t == 'World' then
        sec('Weather')
        val('Preset', WEATHERS[wIdx], function()
            wIdx = wIdx % #WEATHERS + 1
        end)
        act('Apply Weather', A.applyWeather)
        sec('Time')
        val('Hour', string.format('%02d:00', hour), function()
            hour = (hour + 1) % 24
        end)
        act('Apply Time', A.applyTime)
        sec('Cleanup')
        act('Clear Area (120m)', A.clearArea)

    elseif t == 'Visuals' then
        sec('ESP')
        tog('espNames', 'Player Names & Distance')

    elseif t == 'Settings' then
        sec('Input')
        tog('blockInput', 'Block Game Input While Open')
        sec('Menu')
        act('Unload Menu', A.unload, true)
    end

    return r
end

-- ── DUI ──────────────────────────────────────────────────────────────────
local dui = CreateDui(URL, sw, sh)
local txdName = 'eni_txd_' .. tostring(GetGameTimer())
local txd = CreateRuntimeTxd(txdName)
CreateRuntimeTextureFromDuiHandle(txd, 'ui', GetDuiHandle(dui))

local rows = {}
local mx, my = sw / 2, sh / 2

local function pushRender()
    local payload = {
        action = 'render',
        tabs = TABS,
        tabIndex = tabIndex,
        title = subject and 'Player' or TABS[tabIndex],
        hoverRow = hoverRow,
        hoverTab = hoverTab,
        cursor = { x = math.floor(mx), y = math.floor(my) },
        notify = (notifyUntil > GetGameTimer()) and notifyTxt or nil,
        rows = {},
    }
    for i, row in ipairs(rows) do
        payload.rows[i] = {
            t = row.t, label = row.label, sub = row.sub,
            on = row.on, value = row.value, danger = row.danger,
        }
    end
    SendDuiMessage(dui, json.encode(payload))
end

local function rowRects()
    local out = {}
    local y = panelY + HEADER_H
    for i, row in ipairs(rows) do
        local h = (row.t == 'section') and SEC_H or ROW_H
        out[i] = { y = y, h = h }
        y = y + h
    end
    return out
end

local function activate(i)
    local row = rows[i]
    if not row then return end
    if row.t == 'toggle' then
        S[row.key] = not S[row.key]
        if row.key == 'noclip' and not S.noclip then
            local p = me()
            SetEntityCollision(p, true, true)
            FreezeEntityPosition(p, false)
        end
        if row.key == 'god' and not S.god then
            SetEntityInvincible(me(), false)
            SetPlayerInvincible(PlayerId(), false)
        end
        if row.key == 'invis' and not S.invis then
            SetEntityVisible(me(), true, false)
        end
    elseif row.t == 'action' or row.t == 'value' then
        if row.fn then row.fn() end
    elseif row.t == 'player' then
        subject = row.sid
    end
end

local function setOpen(v)
    open = v
    SendDuiMessage(dui, json.encode({ action = 'visible', visible = v }))
    if not v then
        hoverRow, hoverTab = 0, 0
    end
end

-- ── main loop ────────────────────────────────────────────────────────────
CreateThread(function()
    while ENI.alive do
        Wait(0)

        if IsControlJustPressed(0, 166) then setOpen(not open) end   -- F5

        if open then
            rows = buildRows()

            if S.blockInput then
                DisableAllControlActions(0)
                EnableControlAction(0, 1, true)   -- LOOK_LR stays dead but camera pitch/yaw disabled anyway
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
            end

            SetMouseCursorActiveThisFrame()
            ShowCursorThisFrame()

            mx = GetDisabledControlNormal(0, 239) * sw
            my = GetDisabledControlNormal(0, 240) * sh

            -- hit test tabs
            hoverTab = 0
            if mx >= panelX + 12 and mx <= panelX + SIDEBAR_W - 12 then
                for i = 1, #TABS do
                    local ty = panelY + TAB_TOP + (i - 1) * TAB_STEP
                    if my >= ty and my <= ty + TAB_H then hoverTab = i break end
                end
            end

            -- hit test rows
            hoverRow = 0
            local rects = rowRects()
            if mx >= contentX + PAD_X and mx <= panelX + PANEL_W - PAD_X then
                for i, rect in ipairs(rects) do
                    local row = rows[i]
                    if row.t ~= 'section' and row.t ~= 'empty'
                       and my >= rect.y and my <= rect.y + rect.h then
                        hoverRow = i
                        break
                    end
                end
            end

            -- clicks
            if IsDisabledControlJustPressed(0, 237) or IsDisabledControlJustPressed(0, 24) then
                if hoverTab > 0 then
                    tabIndex = hoverTab
                    subject = nil
                elseif hoverRow > 0 then
                    activate(hoverRow)
                end
            end

            -- keyboard fallback
            if IsDisabledControlJustPressed(0, 174) then                     -- left
                tabIndex = (tabIndex - 2) % #TABS + 1; subject = nil
            elseif IsDisabledControlJustPressed(0, 175) then                 -- right
                tabIndex = tabIndex % #TABS + 1; subject = nil
            end
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 202) then
                if subject then subject = nil else setOpen(false) end
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
        local p = me()
        local pid = PlayerId()

        if S.god then
            SetEntityInvincible(p, true)
            SetPlayerInvincible(pid, true)
            SetPedCanRagdoll(p, false)
            ClearPedBloodDamage(p)
            if GetEntityHealth(p) < GetEntityMaxHealth(p) then
                SetEntityHealth(p, GetEntityMaxHealth(p))
            end
        end

        if S.invis then SetEntityVisible(p, false, false) end
        if S.superJump then SetSuperJumpThisFrame(pid) end
        if S.fastRun then
            SetRunSprintMultiplierForPlayer(pid, 1.49)
            SetSwimMultiplierForPlayer(pid, 1.49)
        end
        if S.infStam then RestorePlayerStamina(pid, 1.0) end

        if S.infAmmo then
            local w = GetSelectedPedWeapon(p)
            if w and w ~= GetHashKey('WEAPON_UNARMED') then
                SetPedInfiniteAmmo(p, true, w)
                SetPedInfiniteAmmoClip(p, true)
            end
        end
        if S.noReload then
            local _, w = GetCurrentPedWeapon(p, true)
            if w then
                local maxc = GetMaxAmmoInClip(p, w, true)
                if maxc and maxc > 0 then SetAmmoInClip(p, w, maxc) end
            end
        end

        local v = GetVehiclePedIsIn(p, false)
        if v ~= 0 then
            if S.vehGod then
                SetEntityInvincible(v, true)
                SetVehicleCanBeVisiblyDamaged(v, false)
                SetVehicleTyresCanBurst(v, false)
                SetVehicleEngineHealth(v, 1000.0)
                SetVehicleBodyHealth(v, 1000.0)
            end
            if S.vehBoost and GetPedInVehicleSeat(v, -1) == p then
                SetVehicleCheatPowerIncrease(v, 2.0)
                if IsControlPressed(0, 71) then
                    SetVehicleForwardSpeed(v, GetEntitySpeed(v) + 3.0)
                end
            end
        end
    end
end)

-- noclip
CreateThread(function()
    while ENI.alive do
        Wait(0)
        if S.noclip then
            local p = me()
            local ent = GetVehiclePedIsIn(p, false)
            if ent == 0 then ent = p end

            SetEntityCollision(ent, false, false)
            FreezeEntityPosition(ent, true)
            SetEntityInvincible(ent, true)

            local c = GetEntityCoords(ent)
            local yaw = GetGameplayCamRelativeHeading() + GetEntityHeading(ent)
            local pitch = GetGameplayCamRelativePitch()
            local rx, ry = math.rad(pitch), math.rad(yaw)
            local dx = -math.sin(ry) * math.cos(rx)
            local dy =  math.cos(ry) * math.cos(rx)
            local dz =  math.sin(rx)
            local spd = IsDisabledControlPressed(0, 21) and 4.0 or 1.2

            if not open then
                if IsControlPressed(0, 32) then SetEntityCoordsNoOffset(ent, c.x+dx*spd, c.y+dy*spd, c.z+dz*spd, true, true, true) end
                if IsControlPressed(0, 33) then SetEntityCoordsNoOffset(ent, c.x-dx*spd, c.y-dy*spd, c.z-dz*spd, true, true, true) end
                if IsControlPressed(0, 22) then SetEntityCoordsNoOffset(ent, c.x, c.y, c.z+spd, true, true, true) end
                if IsControlPressed(0, 36) then SetEntityCoordsNoOffset(ent, c.x, c.y, c.z-spd, true, true, true) end
            end
        end
    end
end)

-- ESP
CreateThread(function()
    while ENI.alive do
        Wait(0)
        if S.espNames then
            local mc = myCoords()
            for _, id in ipairs(GetActivePlayers()) do
                if id ~= PlayerId() then
                    local pd = GetPlayerPed(id)
                    if DoesEntityExist(pd) then
                        local c = GetEntityCoords(pd)
                        local d = #(c - mc)
                        if d < 250.0 then
                            local on, x, y = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 1.1)
                            if on then
                                local txt = string.format('%s [%d]  %dm', GetPlayerName(id) or '?', GetPlayerServerId(id), math.floor(d))
                                SetTextScale(0.30, 0.30)
                                SetTextFont(4)
                                SetTextCentre(true)
                                SetTextColour(255, 255, 255, 220)
                                SetTextOutline()
                                SetTextEntry('STRING')
                                AddTextComponentString(txt)
                                DrawText(x, y)
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
    local p = PlayerPedId()
    pcall(function()
        SetEntityCollision(p, true, true)
        FreezeEntityPosition(p, false)
        SetEntityVisible(p, true, false)
        SetEntityInvincible(p, false)
        SetPlayerInvincible(PlayerId(), false)
        NetworkSetInSpectatorMode(false, p)
    end)
    pcall(function() DestroyDui(dui) end)
    _G.__eni = nil
end

Citizen.Trace('^2eni.menu loaded^7 — press F5\n')
notify('eni.menu ready')
