-- =====================================================================
--  CLUTCH CLASH – Waffen auf dem Client: Feuer-Schleife, Vorhersage, Pakete (Client/Modules/WeaponClient)
--  Besitzer: WP4 (Kampf Client). Vertrag: DESIGN.md C7.4, B11, C8 (Fire/WeaponAction), C10 (Client-Teil), C11.
--  Der Server ist Autorität (Muss-Regel 3). Der Client sagt nur vorher und sendet Absichten:
--    * Feuer-Schleife Auto/Semi/Single/Burst bei RenderPriority.Camera + 3 (nach Kamera + Viewmodel), höchstens
--      ein Schuss pro Frame, Zeitstempel auf den geplanten Schuss-Zeitpunkt zurückgerechnet (exakte Abstände).
--    * Spread-Seed-Vorhersage: Spread.Directions(aim, def, scale, Spread.Seed(salt, shotId)) – salt vom Server
--      (Combat("Armed")). Der Anspruch "scale" ist nie kleiner als die Server-Untergrenze (gleiche Strahlen).
--    * Raycast von der Kamera (IncludeInstances = Kontext-Map + gegnerische Combatant-Modelle), Ziel-Id aus
--      dem Attribut CombatantId; zusätzlich analytische Hitbox (Shared/Hitbox) wie der Server.
--    * Sofort: Mündungsfeuer, Tracer, vorläufiger Hitmarker, Munition −1, Rückstoß (Spread.Recoil, lernbare Muster),
--      dann Fire(shotId, weaponId, t, origin, aim, scale, targets) mit #targets == Pellets (Projektil: {}).
--    * Munitions-/Nachlade-Vorhersage + Korrektur aus Combat("Ammo") (abzüglich Schüssen "im Flug").
--    * Ausrüsten/Quick-Swap (1–4, Mausrad, Q), Nahkampf, Block (Laserschwert), Wurf (halten = weiter), Benutzen.
--    * Touch-Auto-Feuer (85 % Feuerrate nach 0.15 s auf sichtbarem Gegner), Admin-Haken (Silent Aim/Triggerbot,
--      nur bei IsAdmin, über AdminTools.AimTarget/WantsFire oder eigene Zielsuche).
--    * Umschalten bei Armed/Disarmed/Pop/Revive: Kamera-Modus, Controls-Kontext, Viewmodel, HUD.
--
--  Öffentliche API (C7.4):
--    WeaponClient.IsArmed(): boolean
--    WeaponClient.Current(): (string?, any?)        Waffen-Key, WeaponDef der ausgerüsteten Waffe
--  Zusätzlich (für Movement/Replication/AimAssist/AdminTools, nil-sicher):
--    WeaponClient.IsAds(): boolean   WeaponClient.AdsAlpha(): number   WeaponClient.IsBlocking(): boolean
--    WeaponClient.IsReloading(): boolean   WeaponClient.IsSwinging(): boolean
--    WeaponClient.Team(): number   WeaponClient.CombatantId(): number   WeaponClient.Rules(): table
--    WeaponClient.Enemies(): { Model }   WeaponClient.Combatants(): { Model }   WeaponClient.ModelOf(id): Model?
--    WeaponClient.SetTrigger(down: boolean)          Feuer-Haken (Admin-Triggerbot, Tests)
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spread = require(Shared:WaitForChild("Spread"))
local Hitbox = require(Shared:WaitForChild("Hitbox"))
local Net = require(Shared:WaitForChild("Net"))

local WeaponClient = {}

type SlotName = "Primary" | "Secondary" | "Melee" | "Utility"
type AmmoLocal = { Mag: number, Charges: number, CooldownEnd: number }

local player = Players.LocalPlayer
local ctx: any = nil

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN
-- ---------------------------------------------------------------------
local SLOTS: { SlotName } = { "Primary", "Secondary", "Melee", "Utility" }
local SLOT_INDEX: { [string]: number } = { Primary = 1, Secondary = 2, Melee = 3, Utility = 4 }
local PRESS_BUFFER = 0.2 -- Semi/Single: zu früh gedrückt -> feuert, sobald bereit
local MAX_SHOT_TIMES = 64
local MAX_INFLIGHT = 32
local REGISTRY_INTERVAL = 0.5
local MIN_SEND_GAP = 0.6 -- × Intervall: Abstand echter Sende-Zeitpunkte (Server prüft ≥ 0.5)
local EQUIP_SAFETY = 0.03
local RELOAD_SAFETY = 0.05
local ADS_SAFETY = 0.03
local MOVE_MARGIN = 1.5 -- "bewegt" knapp unter Config.Combat.MovingSpeed (10) – nie kleiner als der Server
local MOVE_HOLD = 0.15 -- nach dem Anhalten noch so lange "bewegt" (History des Servers hinkt nach)
local AIR_HOLD = 0.15 -- nach der Landung noch so lange "in der Luft"
local SWING_FLAG = 0.3
local DRY_CLICK_GAP = 0.3
local AUTO_RELOAD_DELAY = 0.2
local MAX_TARGET_SCAN_DEPTH = 3

-- ---------------------------------------------------------------------
-- 2) ZUSTAND
-- ---------------------------------------------------------------------
local remotes: { [string]: Instance } = {}
local armed = false
local popped = false
local myId = 0
local salt = 0
local myCtx = ""
local myTeam = 0
local rules: { [string]: any } = {}
local loadout: { [string]: string } = {}
local mapModel: Instance? = nil

local equipped: SlotName = "Primary"
local lastSlot: SlotName = "Secondary"
local equipReadyAt = 0
local ammo: { [string]: AmmoLocal } = {}

local shotId = 0
local swingId = 0
local throwId = 0
local shotTimes: { number } = {}
local inflight: { number } = {}
local nextFireAt = 0
local lastSendAt = -10
local lastShotT = 0 -- Server-Zeit des letzten gesendeten Schusses

local triggerDown = false
local hookTrigger = false
local pressAt = -10
local pressUsed = true
local burstLeft = 0
local burstNext = 0
local spinStart: number? = nil

local adsInput = false
local adsToggled = false
local adsAlpha = 0
local adsSinceT = 0 -- Server-Zeit, die mit Ads(true) gesendet wurde (= Server-AdsSince)
local adsWanted = false
local adsSent = false

local reloading = false
local reloadEnd = 0
local reloadStart = 0
local autoReloadAt: number? = nil
local blocking = false
local blockStart = 0
local blockCooldownEnd = 0
local useUntil = 0
local throwCharging = false
local throwStart = 0
local swingUntil = 0
local fireBlockUntil = 0
local dryClickAt = 0
local lastMovingAt = -10
local lastAirAt = -10

local autoDwellSince: number? = nil
local lastSpreadShown = -1

local registryAt = -10
local allModels: { Model } = {}
local enemyModels: { Model } = {}
local byId: { [number]: Model } = {}
local includeKey = ""
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true
local excludeParams = RaycastParams.new()
excludeParams.FilterType = Enum.RaycastFilterType.Exclude
excludeParams.IgnoreWater = true

-- ---------------------------------------------------------------------
-- 3) HELFER
-- ---------------------------------------------------------------------
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function num(v: any, default: number): number
	return if finite(v) then v else default
end

local function modules(): { [string]: any }
	return if ctx and type(ctx.Modules) == "table" then ctx.Modules else {}
end

local function call(moduleName: string, fnName: string, ...: any): any
	local mod = modules()[moduleName]
	if mod and type(mod[fnName]) == "function" then
		local ok, result = pcall(mod[fnName], ...)
		if ok then
			return result
		end
	end
	return nil
end

local function config(): any
	return ctx and ctx.Config or {}
end

local function combatCfg(key: string, default: number): number
	local c = config().Combat
	return if type(c) == "table" then num(c[key], default) else default
end

local function playerCfg(key: string, default: number): number
	local p = config().Player
	return if type(p) == "table" then num(p[key], default) else default
end

local function setting(key: string): any
	local mod = modules().Settings
	if mod and type(mod.Get) == "function" then
		local ok, s = pcall(mod.Get)
		if ok and type(s) == "table" then
			return s[key]
		end
	end
	local state = ctx and ctx.State
	if type(state) == "table" and type(state.Settings) == "table" then
		return state.Settings[key]
	end
	return nil
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function ping(): number
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and finite(value) then math.clamp(value, 0, 1) else 0.1
end

local function defOfKey(key: string?): any
	if type(key) ~= "string" then
		return nil
	end
	local cfg = config()
	if type(cfg.Weapon) == "function" then
		local ok, d = pcall(cfg.Weapon, key)
		if ok and type(d) == "table" then
			return d
		end
	end
	return nil
end

local function defOf(slot: string): any
	return defOfKey(loadout[slot])
end

local function currentDef(): any
	return defOf(equipped)
end

local function isAdmin(): boolean
	return player:GetAttribute("IsAdmin") == true
end

local function adminPower(name: string): any
	if not isAdmin() then
		return nil
	end
	return player:GetAttribute(name)
end

local function rapidFactor(): number
	local f = adminPower("AdminRapidFire")
	return if finite(f) and f > 1 then math.clamp(f, 1, 5) else 1
end

-- Intervall-Faktor wie der Server: rules.IntervalMult ÷ Admin-RapidFire
local function intervalMult(): number
	return math.max(num(rules.IntervalMult, 1) / rapidFactor(), 0.05)
end

local function character(): Model?
	return player.Character
end

local function rootPart(): BasePart?
	local char = character()
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function humanoid(): Humanoid?
	local char = character()
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function windowOpen(): boolean
	local ui = ctx and ctx.UI
	if ui and type(ui.IsAnyWindowOpen) == "function" then
		local ok, open = pcall(ui.IsAnyWindowOpen)
		if ok then
			return open == true
		end
	end
	return false
end

local function cosmeticsFor(key: string): { Skin: string, Wrap: string, Charm: string }?
	local state = ctx and ctx.State
	local cos = type(state) == "table" and state.Cosmetics
	local per = type(cos) == "table" and cos.PerWeapon
	local entry = type(per) == "table" and per[key]
	if type(entry) ~= "table" then
		return nil
	end
	return {
		Skin = if type(entry.Skin) == "string" then entry.Skin else "",
		Wrap = if type(entry.Wrap) == "string" then entry.Wrap else "",
		Charm = if type(entry.Charm) == "string" then entry.Charm else "",
	}
end

local function tracerId(): string?
	local state = ctx and ctx.State
	local cos = type(state) == "table" and state.Cosmetics
	local eq = type(cos) == "table" and cos.Equipped
	local id = type(eq) == "table" and eq.Tracer
	return if type(id) == "string" and id ~= "" then id else nil
end

local function fireRemote(name: string, ...: any)
	local remote = remotes[name]
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(...)
	end
end

-- ---------------------------------------------------------------------
-- 4) COMBATANT-REGISTER (Spieler, Bots, Puppen im eigenen Kontext)
-- ---------------------------------------------------------------------
local function collect(container: Instance, depth: number, out: { Model }, seen: { [Instance]: boolean })
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			if child:GetAttribute("CombatantId") ~= nil and not seen[child] then
				seen[child] = true
				table.insert(out, child)
			end
		elseif child:IsA("Folder") and depth > 0 then
			collect(child, depth - 1, out, seen)
		end
	end
end

local function isEnemy(model: Model): boolean
	local id = model:GetAttribute("CombatantId")
	if not finite(id) or id == myId then
		return false
	end
	if model:GetAttribute("Alive") == false then
		return false
	end
	local team = model:GetAttribute("Team")
	if myTeam == 0 or not finite(team) then
		return true
	end
	return team ~= myTeam
end

local function rebuildInclude()
	local list: { Instance } = {}
	local key = ""
	if mapModel then
		table.insert(list, mapModel :: Instance)
	end
	for _, m in ipairs(enemyModels) do
		table.insert(list, m)
		key ..= tostring(m:GetAttribute("CombatantId")) .. ","
	end
	if key ~= includeKey or #list ~= #rayParams.IncludeInstances then
		includeKey = key
		rayParams.IncludeInstances = list
	end
	local char = character()
	local camera = workspace.CurrentCamera
	local ex: { Instance } = {}
	if char then
		table.insert(ex, char)
	end
	if camera then
		table.insert(ex, camera)
	end
	excludeParams.ExcludeInstances = ex
end

local function refreshRegistry()
	registryAt = os.clock()
	local found: { Model } = {}
	collect(workspace, MAX_TARGET_SCAN_DEPTH, found, {})
	table.clear(allModels)
	table.clear(enemyModels)
	table.clear(byId)
	local mine = character()
	for _, m in ipairs(found) do
		local id = m:GetAttribute("CombatantId")
		if m ~= mine and finite(id) and m:GetAttribute("Ctx") == myCtx and id ~= myId then
			table.insert(allModels, m)
			byId[id :: number] = m
			if isEnemy(m) then
				table.insert(enemyModels, m)
			end
		end
	end
	rebuildInclude()
end

local function combatantOf(inst: Instance): (Model?, number?)
	local node: Instance? = inst
	for _ = 1, 6 do
		if not node then
			break
		end
		if node:IsA("Model") then
			local id = node:GetAttribute("CombatantId")
			if finite(id) then
				return node, id
			end
		end
		node = node.Parent
	end
	return nil, nil
end

local function rootHead(model: Model): (BasePart?, BasePart?)
	local r = model:FindFirstChild("HumanoidRootPart")
	local h = model:FindFirstChild("Head")
	if r and r:IsA("BasePart") and h and h:IsA("BasePart") then
		return r, h
	end
	return nil, nil
end

-- ---------------------------------------------------------------------
-- 5) HUD
-- ---------------------------------------------------------------------
local function charges(): { [string]: number }
	local a = ammo.Utility
	return { Utility = if a then a.Charges else 0 }
end

local function updateHud()
	local d = currentDef()
	local a = ammo[equipped]
	if not d or not a then
		return
	end
	if d.Kind == "Hitscan" or d.Kind == "Projectile" then
		local progress: number? = nil
		if reloading then
			local now = os.clock()
			progress = math.clamp((now - reloadStart) / math.max(reloadEnd - reloadStart, 0.05), 0, 1)
		end
		call("CombatHud", "SetAmmo", a.Mag, num(d.Mag, 0), reloading, progress)
	else
		call("CombatHud", "SetAmmo", 0, 0, false, nil)
	end
end

local function updateSlots()
	call("CombatHud", "SetSlots", loadout, equipped, charges())
end

-- ---------------------------------------------------------------------
-- 6) ZUSTANDS-WECHSEL (Nachladen, Zielen, Block)
-- ---------------------------------------------------------------------
local function setAds(on: boolean)
	if on == adsSent then
		return
	end
	adsSent = on
	local t = serverNow()
	if on then
		adsSinceT = t
	end
	fireRemote("WeaponAction", "Ads", on, t)
end

local function cancelReload()
	if reloading then
		reloading = false
		call("Viewmodel", "CancelReload")
	end
	autoReloadAt = nil
end

local function endBlock(send: boolean)
	if not blocking then
		return
	end
	blocking = false
	blockCooldownEnd = os.clock()
		+ (function(): number
			local d = currentDef()
			local block = d and type(d.Melee) == "table" and d.Melee.Block
			return if type(block) == "table" then num(block.Cooldown, 3) else 3
		end)()
	call("Viewmodel", "SetBlock", false)
	if send then
		fireRemote("WeaponAction", "Block", false, serverNow())
	end
end

local function startReload(): boolean
	local d = currentDef()
	local a = ammo[equipped]
	if not (d and a) or reloading or (d.Kind ~= "Hitscan" and d.Kind ~= "Projectile") then
		return false
	end
	if a.Mag >= num(d.Mag, 0) then
		return false
	end
	local now = os.clock()
	if now < equipReadyAt then
		return false
	end
	burstLeft = 0
	spinStart = nil
	fireRemote("WeaponAction", "Reload")
	if adminPower("AdminNoReload") == true then
		a.Mag = math.floor(num(d.Mag, a.Mag))
		updateHud()
		return true
	end
	local duration = num(d.Reload, 2) * num(rules.ReloadMult, 1)
	reloading = true
	reloadStart = now
	reloadEnd = now + duration + RELOAD_SAFETY
	autoReloadAt = nil
	call("Movement", "StopSprint")
	call("Viewmodel", "Reload", duration)
	updateHud()
	return true
end

-- ---------------------------------------------------------------------
-- 7) SPREAD (Anspruch nie unter der Server-Untergrenze, C10 Schritt 7)
-- ---------------------------------------------------------------------
local function moveState(now: number): (number, boolean)
	local r = rootPart()
	local speed = 0
	if r then
		local v = r.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local h = humanoid()
	if h and h.FloorMaterial == Enum.Material.Air then
		lastAirAt = now
	end
	if speed > combatCfg("MovingSpeed", 10) - MOVE_MARGIN then
		lastMovingAt = now
	end
	return speed, now - lastAirAt <= AIR_HOLD
end

-- Gleiche Formel wie WeaponService.minScaleFor (Shared/Spread): Hüfte↔ADS-Mischung ab dem gesendeten
-- Ads-Zeitstempel (+ Config.Combat.AdsGrace), AdsSettleSpread im Übergang, × Spread.FirstShot; dazu Bloom
-- (+ Rutschen). Kleine Sicherheitsränder nur nach oben (der Server nimmt max(Anspruch, Untergrenze)).
local function spreadScale(d: any, tServer: number, now: number): number
	local speed, air = moveState(now)
	local movingSpeed = combatCfg("MovingSpeed", 10)
	local moving = now - lastMovingAt <= MOVE_HOLD
	local speedArg = if moving then math.max(speed, movingSpeed + 0.5) else speed
	local hipMin = Spread.MinScale(d, false, speedArg, air)
	local adsMin = Spread.MinScale(d, true, speedArg, air)
	local walk = playerCfg("Walk", 16)
	local adsSpeedOk = speed <= walk * num(d.AdsMoveMult, 1) * 1.3 + 2 - 1
	local scale = hipMin
	if adsSent and adsSpeedOk then
		local adsTime = num(d.AdsTime, 0.15)
		local grace = combatCfg("AdsGrace", 0.1)
		local alpha = if adsTime > 0 then math.clamp((tServer - adsSinceT + grace - ADS_SAFETY) / adsTime, 0, 1) else 1
		scale = hipMin + (adsMin - hipMin) * alpha
		local settle = d.AdsSettleSpread
		if alpha < 1 and finite(settle) then
			scale = math.min(scale, settle + (hipMin - num(d.SpreadHip, 0)))
		end
	end
	local claim = scale * Spread.FirstShot(d, shotTimes, tServer) + Spread.Bloom(d, shotTimes, tServer)
	if call("Movement", "IsSliding") == true then
		local slide = config().Player and config().Player.Slide
		claim += if type(slide) == "table" then num(slide.SpreadAdd, 1) else 1
	end
	return math.clamp(math.max(claim, 0), 0, combatCfg("MaxScale", 30))
end

-- ---------------------------------------------------------------------
-- 8) SCHIESSEN
-- ---------------------------------------------------------------------
local function pushTime(list: { number }, t: number, cap: number)
	table.insert(list, t)
	if #list > cap then
		table.remove(list, 1)
	end
end

-- Admin Silent Aim: Ziel aus AdminTools (sonst nächster Gegner im 30°-Kegel)
local function silentAim(origin: Vector3): (Vector3?, number?)
	if adminPower("AdminSilentAim") ~= true then
		return nil, nil
	end
	local tools = modules().AdminTools
	if tools and type(tools.AimTarget) == "function" then
		local ok, id, pos = pcall(tools.AimTarget)
		if ok and finite(id) and typeof(pos) == "Vector3" and (pos - origin).Magnitude > 0.5 then
			return (pos - origin).Unit, id
		end
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local look = camera.CFrame.LookVector
	local best: Model? = nil
	local bestDot = math.cos(math.rad(30))
	for _, m in ipairs(enemyModels) do
		local _, head = rootHead(m)
		if head then
			local dir = head.Position - origin
			if dir.Magnitude > 0.5 then
				local dot = look:Dot(dir.Unit)
				if dot > bestDot then
					bestDot = dot
					best = m
				end
			end
		end
	end
	if best then
		local _, head = rootHead(best)
		local id = best:GetAttribute("CombatantId")
		if head and finite(id) then
			return (head.Position - origin).Unit, id
		end
	end
	return nil, nil
end

-- ein Strahl: Ziel-Id (0 = keins), Endpunkt, Normale, Region
-- Map-Strahl, der unsichtbare Barrieren überspringt (der Server prüft Sichtlinie ohne Barrieren);
-- Rückgabe: Treffer + Gesamtentfernung ab origin
local function mapCast(origin: Vector3, dir: Vector3, range: number, params: RaycastParams): (RaycastResult?, number)
	local travelled = 0
	for _ = 1, 4 do
		local result = workspace:Raycast(origin + dir * travelled, dir * (range - travelled), params)
		if not result then
			return nil, range
		end
		local part = result.Instance
		if part:IsA("BasePart") and part.Transparency >= 0.99 and combatantOf(part) == nil then
			travelled += result.Distance + 0.05
			if travelled >= range then
				return nil, range
			end
		else
			return result, travelled + result.Distance
		end
	end
	return nil, range
end

local function castPellet(origin: Vector3, dir: Vector3, range: number): (number, Vector3, Vector3?, string?, Model?)
	local params = if mapModel then rayParams else excludeParams
	local result, maxDist = mapCast(origin, dir, range, params)
	local radius = combatCfg("HeadRadius", 0.8) * num(rules.HeadRadiusMult, 1)
	local tol = combatCfg("HitTol", 0.35)
	if result then
		local model, id = combatantOf(result.Instance)
		if model and id and model ~= character() and isEnemy(model) then
			local root, head = rootHead(model)
			local region: string? = if result.Instance.Name == "Head" then "Head" else "Body"
			if root and head then
				local r = Hitbox.Ray(origin, dir, range, root.CFrame, head.Position, radius, tol)
				if r then
					region = r
				end
			end
			return id, result.Position, result.Normal, region, model
		end
	end
	-- analytische Hitboxen (fest, wie der Server) vor der nächsten Wand
	local bestId, bestDist, bestRegion, bestModel = 0, maxDist, nil, nil
	for _, m in ipairs(enemyModels) do
		local root, head = rootHead(m)
		if root and head then
			local region, dist = Hitbox.Ray(origin, dir, bestDist, root.CFrame, head.Position, radius, tol)
			if region and dist and dist < bestDist then
				local id = m:GetAttribute("CombatantId")
				if finite(id) then
					bestId, bestDist, bestRegion, bestModel = id :: number, dist, region, m
				end
			end
		end
	end
	if bestId ~= 0 then
		return bestId, origin + dir * bestDist, nil, bestRegion, bestModel
	end
	if result then
		return 0, result.Position, result.Normal, nil, nil
	end
	return 0, origin + dir * range, nil, nil, nil
end

local function kickFor(d: any, tServer: number, seed: number)
	local index = Spread.Chain(d, shotTimes, tServer) + 1
	local pitch, yaw = Spread.Recoil(d, index, seed)
	local adsMult = 1 - 0.25 * adsAlpha
	call("FpsCamera", "Kick", pitch * adsMult, yaw * adsMult, num(d.RecoilRecover, 0.35))
end

local function fireShot(d: any, tServer: number, now: number)
	local camera = workspace.CurrentCamera
	local a = ammo[equipped]
	if not camera or not a then
		return
	end
	shotId += 1
	local id = shotId
	lastShotT = tServer
	local origin = camera.CFrame.Position
	local aim = camera.CFrame.LookVector
	local forced: number? = nil
	local silentDir, silentId = silentAim(origin)
	if silentDir then
		aim = silentDir
		forced = silentId
	end
	local scale = spreadScale(d, tServer, now)
	local seed = Spread.Seed(salt, id)
	local dirs = Spread.Directions(aim, d, scale, seed)
	local muzzle = call("Viewmodel", "MuzzleCFrame")
	local from = if typeof(muzzle) == "CFrame" then muzzle.Position else origin + aim * 1.5
	local targets: { number } = {}

	if d.Kind == "Projectile" then
		local proj = d.Projectile
		local speed = if type(proj) == "table" then num(proj.Speed, 100) else 100
		local gravity = if type(proj) == "table" then num(proj.Gravity, 0) else 0
		call("CombatFX", "Projectile", "L" .. id, d.Key, origin, dirs[1] * speed, gravity, tServer)
	else
		local range = num(d.Range, 300)
		local anyHit: string? = nil
		local orbital = d.Key == "OrbitalLaser"
		local tracer = tracerId()
		for i, dir in ipairs(dirs) do
			local target, endPos, normal, region = castPellet(origin, dir, range)
			if orbital then
				target = 0
			elseif forced then
				target = forced
				region = "Head"
			end
			targets[i] = target
			if target ~= 0 then
				anyHit = if anyHit == "Head" or region == "Head" then "Head" else "Body"
				call("CombatFX", "Impact", endPos, normal, if region == "Head" then "Head" else "Player")
			elseif normal then
				call("CombatFX", "Impact", endPos, normal, "Surface")
			end
			call("CombatFX", "Tracer", from, endPos, nil, tracer)
		end
		if anyHit then
			call("CombatHud", "Hitmarker", anyHit, false, true)
		end
	end

	fireRemote("Fire", id, num(d.Id, 0), tServer, origin, aim, scale, targets)

	-- Vorhersage
	kickFor(d, tServer, seed)
	pushTime(shotTimes, tServer, MAX_SHOT_TIMES)
	pushTime(inflight, now, MAX_INFLIGHT)
	lastSendAt = now
	if adminPower("AdminInfAmmo") ~= true then
		a.Mag = math.max(0, a.Mag - 1)
	end
	call("Viewmodel", "Fire")
	call("Movement", "StopSprint") -- kein Sprinten beim Schießen (hält die Sprint-Sperre aktiv)
	if type(d.Sound) == "string" then
		call("Sfx", "Play", d.Sound, nil, nil)
	end
	if ctx and ctx.Hooks and type(ctx.Hooks.Fire) == "function" then
		ctx.Hooks.Fire("Shot", d.Key)
	end
	if a.Mag <= 0 and setting("AutoReload") ~= false then
		autoReloadAt = now + AUTO_RELOAD_DELAY
	end
	updateHud()
end

local function dryFire(now: number)
	if now - dryClickAt < DRY_CLICK_GAP then
		return
	end
	dryClickAt = now
	call("Sfx", "Play", "MagIn", nil, { Volume = 0.5, Speed = 1.8 })
	call("CombatHud", "SetAmmo", 0, num(currentDef() and currentDef().Mag, 0), false, nil)
	if setting("AutoReload") ~= false then
		startReload()
	end
end

-- Nahkampf: Ziel im Kegel vor der Kamera (Server prüft Reichweite/Kegel/Sichtlinie erneut)
local function meleeTarget(d: any, origin: Vector3, aim: Vector3): number?
	local m = d.Melee
	local reach = if type(m) == "table" then num(m.Range, num(d.Range, 6)) else num(d.Range, 6)
	local cone = if type(m) == "table" then num(m.Cone, 70) else 70
	local cosHalf = math.cos(math.rad(cone / 2 + 5))
	local bestId: number? = nil
	local bestDist = reach + 0.5
	for _, model in ipairs(enemyModels) do
		local root, head = rootHead(model)
		if root and head then
			local dist = Hitbox.PointDistance(origin, root.CFrame, head.Position)
			local toTarget = root.Position - origin
			if dist <= bestDist and toTarget.Magnitude > 0.1 and aim:Dot(toTarget.Unit) >= cosHalf then
				local blocked = mapModel ~= nil
					and workspace:Raycast(origin, toTarget.Unit * math.max(toTarget.Magnitude - 0.5, 0.1), rayParams)
				local hitWall = false
				if blocked then
					local hitModel = combatantOf(blocked.Instance)
					hitWall = hitModel == nil
				end
				if not hitWall then
					local id = model:GetAttribute("CombatantId")
					if finite(id) then
						bestId = id :: number
						bestDist = dist
					end
				end
			end
		end
	end
	return bestId
end

local function swingKind(key: string): string
	if key == "BonkHammer" then
		return "Bonk"
	elseif key == "LaserSword" then
		return "Slash"
	end
	return "Jab"
end

local function doMelee(d: any, now: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	swingId += 1
	local origin = camera.CFrame.Position
	local aim = camera.CFrame.LookVector
	local target = meleeTarget(d, origin, aim)
	fireRemote("WeaponAction", "Melee", swingId, serverNow(), aim, target)
	nextFireAt = now + num(d.Interval, 0.5) * intervalMult()
	local windup = if type(d.Melee) == "table" then num(d.Melee.Windup, 0) else 0
	swingUntil = now + math.max(SWING_FLAG, windup + 0.15)
	call("Viewmodel", "Swing", swingKind(d.Key))
	if type(d.Sound) == "string" then
		call("Sfx", "Play", d.Sound, nil, nil)
	end
	if target then
		if windup > 0 then
			task.delay(windup, function()
				call("CombatHud", "Hitmarker", "Body", false, true)
			end)
		else
			call("CombatHud", "Hitmarker", "Body", false, true)
		end
	end
	if ctx and ctx.Hooks and type(ctx.Hooks.Fire) == "function" then
		ctx.Hooks.Fire("Shot", d.Key)
	end
end

-- Utility bereit? (Ladungen in Duellen, Abklingzeit in FFA)
local function utilityReady(now: number): boolean
	local a = ammo.Utility
	if not a then
		return false
	end
	if adminPower("AdminInfAmmo") == true then
		return true
	end
	if rules.UtilityMode == "Cooldown" then
		return now >= a.CooldownEnd
	end
	return a.Charges > 0
end

local function consumeUtility(d: any, now: number)
	local a = ammo.Utility
	if not a or adminPower("AdminInfAmmo") == true then
		return
	end
	if rules.UtilityMode == "Cooldown" then
		a.CooldownEnd = now + num(d.Cooldown, 10)
	else
		a.Charges = math.max(0, a.Charges - 1)
	end
	updateSlots()
end

local function beginThrow(now: number)
	local d = defOf("Utility")
	if not d or d.Kind ~= "Throwable" or throwCharging or now < useUntil or blocking then
		return
	end
	if not utilityReady(now) then
		call("Sfx", "Play", "UIError", nil, nil)
		return
	end
	throwCharging = true
	throwStart = now
	call("Movement", "StopSprint")
end

local function releaseThrow(now: number)
	if not throwCharging then
		return
	end
	throwCharging = false
	local d = defOf("Utility")
	local camera = workspace.CurrentCamera
	if not d or not camera or not utilityReady(now) then
		return
	end
	local hold = combatCfg("ThrowFullHold", 0.5)
	local charge = math.clamp((now - throwStart) / math.max(hold, 0.05), 0, 1)
	throwId += 1
	local origin = camera.CFrame.Position
	local aim = camera.CFrame.LookVector
	local tServer = serverNow()
	fireRemote("WeaponAction", "Throw", throwId, tServer, origin, aim, charge)
	local proj = d.Projectile
	local tap = if type(proj) == "table" then num(proj.Speed, 70) else 70
	local full = combatCfg("ThrowChargedSpeed", 90)
	local gravity = if type(proj) == "table" then num(proj.Gravity, 90) else 90
	call("CombatFX", "Projectile", "T" .. throwId, d.Key, origin, aim * (tap + (full - tap) * charge), gravity, tServer)
	consumeUtility(d, now)
	swingUntil = now + SWING_FLAG
	call("Viewmodel", "Swing", "Throw")
	if type(d.Sound) == "string" then
		call("Sfx", "Play", d.Sound, nil, nil)
	end
end

local function doUse(now: number)
	local d = defOf("Utility")
	if not d or d.Kind ~= "Consumable" or now < useUntil or blocking then
		return
	end
	if not utilityReady(now) then
		call("Sfx", "Play", "UIError", nil, nil)
		return
	end
	local heal = d.Heal
	local useTime = if type(heal) == "table" then num(heal.UseTime, 0.8) else 0.8
	fireRemote("WeaponAction", "Use", serverNow())
	useUntil = now + useTime
	cancelReload()
	consumeUtility(d, now)
	call("Movement", "StopSprint")
	call("Viewmodel", "Swing", "Drink")
	if type(d.Sound) == "string" then
		call("Sfx", "Play", d.Sound, nil, nil)
	end
end

local function utilityPress(now: number)
	local d = defOf("Utility")
	if not d then
		return
	end
	if d.Kind == "Consumable" then
		doUse(now)
	else
		beginThrow(now)
	end
end

-- ---------------------------------------------------------------------
-- 9) AUSRÜSTEN
-- ---------------------------------------------------------------------
local function slotAllowed(slot: string): boolean
	if type(loadout[slot]) ~= "string" or loadout[slot] == "" then
		return false
	end
	local allowed = rules.AllowedSlots
	if type(allowed) == "table" and next(allowed) ~= nil then
		return allowed[slot] == true
	end
	return true
end

local function equip(slot: SlotName, send: boolean, force: boolean?)
	if not slotAllowed(slot) then
		return
	end
	if slot == equipped and not force then
		return
	end
	local now = os.clock()
	cancelReload()
	endBlock(true)
	throwCharging = false
	burstLeft = 0
	spinStart = nil
	if slot ~= equipped then
		lastSlot = equipped
	end
	equipped = slot
	local d = currentDef()
	local equipTime = if d then num(d.Equip, 0.3) else 0.3
	equipReadyAt = now + equipTime + EQUIP_SAFETY
	nextFireAt = math.max(nextFireAt, equipReadyAt)
	adsAlpha = 0
	if adsSent then
		adsSent = false -- der Server setzt Ads beim Wechsel selbst zurück
	end
	if send then
		fireRemote("WeaponAction", "Equip", SLOT_INDEX[slot])
	end
	local key = loadout[slot]
	call("Viewmodel", "Equip", key, cosmeticsFor(key))
	call("FpsCamera", "SetAds", 0, 1)
	call("FpsCamera", "SetScope", false)
	if ctx and ctx.Hooks and type(ctx.Hooks.Fire) == "function" then
		ctx.Hooks.Fire("Equip", slot, key)
	end
	updateSlots()
	updateHud()
end

local function cycle(step: number)
	local index = SLOT_INDEX[equipped] or 1
	for _ = 1, #SLOTS do
		index = ((index - 1 + step) % #SLOTS) + 1
		local slot = SLOTS[index]
		if slotAllowed(slot) then
			equip(slot, true)
			return
		end
	end
end

-- ---------------------------------------------------------------------
-- 10) FEUER-SCHLEIFE (RenderPriority.Camera + 3)
-- ---------------------------------------------------------------------
local function autoFireActive(): boolean
	local touch = modules().TouchControls
	if touch and type(touch.IsAutoFire) == "function" then
		local ok, on = pcall(touch.IsAutoFire)
		if ok then
			return on == true and call("Controls", "Input") == "Touch"
		end
	end
	local mode = setting("AutoFire")
	local kind = call("Controls", "Input")
	return kind == "Touch" and (mode == "on" or mode == "auto" or mode == nil)
end

local function wantsAutoFire(now: number, d: any): boolean
	-- Admin-Triggerbot
	if adminPower("AdminTriggerbot") == true then
		local tools = modules().AdminTools
		if tools and type(tools.WantsFire) == "function" then
			local ok, want = pcall(tools.WantsFire)
			if ok and want == true then
				return true
			end
		elseif call("AimAssist", "TargetUnderCrosshair", num(d.Range, 300)) ~= nil then
			return true
		end
	end
	if not autoFireActive() or (d.Kind ~= "Hitscan" and d.Kind ~= "Projectile") then
		autoDwellSince = nil
		return false
	end
	local target = call("AimAssist", "TargetUnderCrosshair", num(d.Range, 300))
	if target == nil then
		autoDwellSince = nil
		return false
	end
	local dwell = 0.15
	local aa = config().Client and config().Client.AimAssist
	if type(aa) == "table" then
		dwell = num(aa.AutoFireDwell, 0.15)
	end
	if autoDwellSince == nil then
		autoDwellSince = now
	end
	return now - (autoDwellSince :: number) >= dwell
end

local function canAct(now: number): boolean
	if now < equipReadyAt or reloading or now < useUntil or blocking or throwCharging then
		return false
	end
	return true
end

-- Server-Zeitstempel eines geplanten Schusses: höchstens 0.05 s zurückgerechnet, und nie dichter als
-- 0.8 × Abstand am vorherigen (Server prüft ≥ 0.75 × Intervall). nil = diesen Frame noch nicht feuern.
local function shotTime(scheduled: number, now: number, gap: number): number?
	local t = serverNow() - math.clamp(now - scheduled, 0, 0.05)
	if lastShotT > 0 and t - lastShotT < gap * 0.8 then
		local earliest = lastShotT + gap * 0.8
		if earliest - serverNow() > 0.03 then
			return nil -- noch zu früh: nächster Frame
		end
		t = earliest
	end
	return t
end

local function tryFire(d: any, now: number, auto: boolean)
	local held = triggerDown or hookTrigger or auto
	local pressed = not pressUsed and now - pressAt <= PRESS_BUFFER
	local mode = d.FireMode
	if d.Kind == "Melee" then
		if (held or pressed) and canAct(now) and now >= nextFireAt then
			pressUsed = true
			doMelee(d, now)
		end
		return
	end
	if d.Kind == "Throwable" or d.Kind == "Consumable" then
		return -- über Druck/Loslassen (beginThrow/releaseThrow, doUse)
	end
	if not (held or pressed or burstLeft > 0) then
		spinStart = nil
		return
	end
	if not canAct(now) then
		return
	end
	if call("Movement", "IsSprinting") == true then
		call("Movement", "StopSprint")
		fireBlockUntil = now + playerCfg("SprintToFire", 0.12)
		return
	end
	if now < fireBlockUntil then
		return
	end
	-- Admin-Raketen-Minigun: 0.4 s Anlauf
	if d.Key == "RocketMinigun" then
		if spinStart == nil then
			spinStart = now
		end
		local spin = num(config().Combat and config().Combat.Admin and config().Combat.Admin.MinigunSpinUp, 0.4)
		if now - (spinStart :: number) < spin then
			return
		end
	end
	local a = ammo[equipped]
	if not a then
		return
	end
	local interval = num(d.Interval, 0.5) * intervalMult()
	if auto and not (triggerDown or hookTrigger) then
		local aa = config().Client and config().Client.AimAssist
		local rate = if type(aa) == "table" then num(aa.AutoFireRate, 0.85) else 0.85
		interval /= math.clamp(rate, 0.2, 1)
	end
	local burstGap = num(d.BurstInterval, 0.07) / rapidFactor()
	-- Burst: eine Salve pro Druck; nach dem LETZTEN Schuss der Salve Pause Interval (B11.1)
	if mode == "Burst" and burstLeft > 0 then
		if now < burstNext then
			return
		end
		if a.Mag <= 0 then
			burstLeft = 0
			dryFire(now)
			return
		end
		if now - lastSendAt < burstGap * MIN_SEND_GAP then
			return
		end
		local tShot = shotTime(burstNext, now, burstGap)
		if not tShot then
			return
		end
		fireShot(d, tShot :: number, now)
		burstLeft -= 1
		local scheduled = math.min(burstNext, now)
		burstNext = scheduled + burstGap
		if burstLeft <= 0 then
			nextFireAt = scheduled + interval
		end
		return
	end
	if now < nextFireAt then
		return
	end
	if mode ~= "Auto" and not pressed and not auto and not hookTrigger then
		return -- Semi/Single/Burst: nur bei neuem Druck
	end
	if a.Mag <= 0 then
		pressUsed = true
		dryFire(now)
		return
	end
	if now - lastSendAt < interval * MIN_SEND_GAP then
		return
	end
	-- geplanter Zeitpunkt: exakte Kadenz beim Halten, sonst jetzt
	local scheduled = if nextFireAt > now - interval then nextFireAt else now
	scheduled = math.min(scheduled, now)
	local tShot = shotTime(scheduled, now, interval)
	if not tShot then
		return
	end
	pressUsed = true
	fireShot(d, tShot :: number, now)
	if mode == "Burst" then
		burstLeft = math.max(0, math.floor(num(d.BurstCount, 3)) - 1)
		burstNext = scheduled + burstGap
		if burstLeft <= 0 then
			nextFireAt = scheduled + interval
		end
		return
	end
	nextFireAt = scheduled + interval
end

local function step(dt: number)
	if not armed or popped then
		return
	end
	local now = os.clock()
	if now - registryAt >= REGISTRY_INTERVAL then
		refreshRegistry()
	end
	local d = currentDef()
	if not d then
		return
	end
	local menu = windowOpen()
	if menu then
		triggerDown = false
		adsInput = false
		adsToggled = false
		if throwCharging then
			throwCharging = false
		end
	end

	-- Nachladen fertig (Vorhersage; Combat("Ammo") korrigiert)
	if reloading and now >= reloadEnd then
		reloading = false
		local a = ammo[equipped]
		if a then
			a.Mag = math.floor(num(d.Mag, a.Mag))
		end
		updateHud()
	elseif reloading then
		updateHud()
	end
	if autoReloadAt and now >= autoReloadAt and not triggerDown then
		autoReloadAt = nil
		startReload()
	end

	-- Zielen / Blocken (Laserschwert: ADS halten = Block)
	local wantAds = (adsInput or adsToggled) and not menu
	local block = d.Melee and d.Melee.Block
	if d.Kind == "Melee" then
		if type(block) == "table" then
			if wantAds and not blocking and now >= blockCooldownEnd and canAct(now) then
				blocking = true
				blockStart = now
				fireRemote("WeaponAction", "Block", true, serverNow())
				call("Viewmodel", "SetBlock", true)
				call("Movement", "StopSprint")
			elseif blocking and (not wantAds or now - blockStart >= num(block.Max, 1.5)) then
				endBlock(true)
			end
		end
		wantAds = false
	elseif d.Kind ~= "Hitscan" and d.Kind ~= "Projectile" then
		wantAds = false
	end
	if reloading or now < useUntil then
		wantAds = false
	end
	if wantAds and not adsWanted then
		call("Movement", "StopSprint") -- ADS bricht Sprint ab (B12)
	end
	adsWanted = wantAds
	setAds(wantAds)
	local adsTime = math.max(num(d.AdsTime, 0.15), 0.02)
	adsAlpha = math.clamp(adsAlpha + (if wantAds then dt else -dt) / adsTime, 0, 1)
	call("FpsCamera", "SetAds", adsAlpha, num(d.AdsZoom, 1))
	call("Viewmodel", "SetAds", adsAlpha)
	call("FpsCamera", "SetScope", num(d.AdsZoom, 1) >= 3 and adsAlpha >= 0.98)

	-- Schüsse "im Flug" altern lassen
	local window = 2 * ping() + 0.05
	while #inflight > 0 and now - inflight[1] > window do
		table.remove(inflight, 1)
	end

	-- Feuern
	local auto = not menu and wantsAutoFire(now, d)
	if not menu then
		tryFire(d, now, auto)
	end

	-- Fadenkreuz-Streuung (nur bei Änderung)
	if d.Kind == "Hitscan" or d.Kind == "Projectile" then
		local s = spreadScale(d, serverNow(), now)
		if math.abs(s - lastSpreadShown) > 0.05 then
			lastSpreadShown = s
			call("CombatHud", "SetSpread", s)
		end
	end
end

-- ---------------------------------------------------------------------
-- 11) SERVER-EREIGNISSE
-- ---------------------------------------------------------------------
local function fillAll()
	for _, slot in ipairs(SLOTS) do
		local d = defOf(slot)
		local a = ammo[slot]
		if d and a then
			a.Mag = math.floor(num(d.Mag, a.Mag))
			a.Charges = math.floor(num(d.Charges, a.Charges))
			a.CooldownEnd = 0
		end
	end
	cancelReload()
	shotTimes = {}
	updateHud()
	updateSlots()
end

local function onArmed(data: any)
	if type(data) ~= "table" then
		return
	end
	local newSalt = num(data.Salt, 0)
	local newId = num(data.Id, player.UserId)
	-- neuer Combatant (anderer Salt/Id) -> Zähler neu; gleicher -> weiterzählen (Server-LastShotId)
	if newSalt ~= salt or newId ~= myId then
		shotId = 0
		swingId = 0
		throwId = 0
		shotTimes = {}
		lastShotT = 0
	end
	salt = newSalt
	myId = newId
	myCtx = if type(data.Ctx) == "string" then data.Ctx else ""
	myTeam = num(data.Team, 0)
	rules = if type(data.Rules) == "table" then data.Rules else {}
	mapModel = if typeof(data.Map) == "Instance" then data.Map else nil
	loadout = {}
	if type(data.Loadout) == "table" then
		for _, slot in ipairs(SLOTS) do
			local key = data.Loadout[slot]
			if type(key) == "string" then
				loadout[slot] = key
			end
		end
	end
	ammo = {}
	for _, slot in ipairs(SLOTS) do
		local d = defOf(slot)
		local given = type(data.Ammo) == "table" and data.Ammo[slot]
		ammo[slot] = {
			Mag = math.floor(num(type(given) == "table" and given.Mag, d and num(d.Mag, 0) or 0)),
			Charges = math.floor(num(type(given) == "table" and given.Charges, d and num(d.Charges, 0) or 0)),
			CooldownEnd = 0,
		}
	end
	armed = true
	popped = false
	triggerDown = false
	burstLeft = 0
	adsSent = false
	adsAlpha = 0
	blocking = false
	reloading = false
	throwCharging = false
	refreshRegistry()
	call("FpsCamera", "SetMode", if myCtx == "Range" then "Range" else "Match")
	call("Controls", "SetContext", if myCtx == "Range" then "Range" else "Match")
	call("CombatHud", "Show", true)
	call("Viewmodel", "HideFor", "Popped", false)
	-- Ausgerüstet ist zu Beginn die erste erlaubte Waffe; dem Server ausdrücklich mitteilen
	local first: SlotName = "Primary"
	if not slotAllowed(first) then
		for _, slot in ipairs(SLOTS) do
			if slotAllowed(slot) then
				first = slot
				break
			end
		end
	end
	equip(first, true, true)
end

local function onDisarmed()
	armed = false
	popped = false
	triggerDown = false
	hookTrigger = false
	burstLeft = 0
	reloading = false
	blocking = false
	throwCharging = false
	adsSent = false
	adsAlpha = 0
	rules = {}
	loadout = {}
	ammo = {}
	mapModel = nil
	table.clear(allModels)
	table.clear(enemyModels)
	table.clear(byId)
	includeKey = ""
	call("Viewmodel", "Unequip")
	call("FpsCamera", "SetAds", 0, 1)
	call("FpsCamera", "SetScope", false)
	call("FpsCamera", "SetMode", "Lobby")
	call("Controls", "SetContext", "Lobby")
	call("CombatHud", "Show", false)
end

local function onPopped()
	if not armed then
		return
	end
	popped = true
	triggerDown = false
	burstLeft = 0
	throwCharging = false
	endBlock(false)
	cancelReload()
	adsAlpha = 0
	adsSent = false
	call("FpsCamera", "SetAds", 0, 1)
	call("FpsCamera", "SetScope", false)
	call("Viewmodel", "HideFor", "Popped", true)
	call("FpsCamera", "SetMode", "Spectate")
end

local function onRevived()
	if not armed then
		return
	end
	popped = false
	fillAll() -- Respawn füllt alles (B11.1)
	call("Viewmodel", "HideFor", "Popped", false)
	call("FpsCamera", "SetMode", if myCtx == "Range" then "Range" else "Match")
	call("Controls", "SetContext", if myCtx == "Range" then "Range" else "Match")
	equip(equipped, true, true)
end

local function onAmmo(data: any)
	if not armed or type(data) ~= "table" or type(data.S) ~= "string" then
		return
	end
	local a = ammo[data.S]
	if not a then
		return
	end
	local d = defOf(data.S)
	local now = os.clock()
	if finite(data.C) then
		a.Charges = math.max(0, math.floor(data.C))
	end
	local r = num(data.R, 0)
	if data.S == "Utility" then
		a.CooldownEnd = if r > 0 then now + math.max(0, r - serverNow()) else 0
		updateSlots()
		return
	end
	if finite(data.M) then
		if r > 0 and r > serverNow() then
			-- Server lädt nach: Ende übernehmen
			if data.S == equipped then
				reloading = true
				reloadStart = now
				reloadEnd = now + math.max(0, r - serverNow()) + RELOAD_SAFETY
			end
			a.Mag = math.max(0, math.floor(data.M))
		else
			if data.S == equipped and reloading and r <= 0 and data.M < num(d and d.Mag, 0) then
				reloading = false -- Server hat das Nachladen abgebrochen
				call("Viewmodel", "CancelReload")
			elseif data.S == equipped and reloading and data.M >= num(d and d.Mag, 0) then
				reloading = false -- Nachlade-Ende bestätigt
			end
			-- abzüglich Schüssen, die der Server noch nicht gesehen hat (nur ausgerüstete Waffe)
			local pending = if data.S == equipped then #inflight else 0
			a.Mag = math.max(0, math.floor(data.M) - pending)
		end
	end
	if data.S == equipped then
		updateHud()
	end
end

local function onEquipCorrection(data: any)
	if not armed or type(data) ~= "table" or type(data.S) ~= "string" then
		return
	end
	local slot = data.S
	if SLOT_INDEX[slot] and slot ~= equipped then
		equip(slot :: SlotName, false, true)
	end
end

local function onHurt(data: any)
	-- Treffer während ADS -> 2° Kamera-Kick (Scharfschützen-Konter, B11.1)
	if not armed or type(data) ~= "table" then
		return
	end
	if adsAlpha > 0.5 then
		local kick = combatCfg("ScopeHitKick", 2)
		call("FpsCamera", "Kick", kick, (math.random() * 2 - 1) * kick * 0.5, 0.4)
	end
end

-- ---------------------------------------------------------------------
-- 12) EINGABE
-- ---------------------------------------------------------------------
local function onFire(state: string)
	if not armed or popped then
		return
	end
	local now = os.clock()
	local d = currentDef()
	if state == "Begin" then
		triggerDown = true
		pressAt = now
		pressUsed = false
		if d and (d.Kind == "Throwable" or d.Kind == "Consumable") then
			utilityPress(now)
		end
	elseif state == "End" then
		triggerDown = false
		if throwCharging and d and d.Kind == "Throwable" then
			releaseThrow(now)
		end
	end
end

local function onAdsInput(state: string)
	if state == "Begin" then
		adsInput = true
		if setting("AdsToggle") == true then
			adsToggled = not adsToggled
			adsInput = false
		end
	elseif state == "End" then
		adsInput = false
	end
end

local function bindControls()
	local controls = modules().Controls
	local function bind(action: string, fn: (string) -> ())
		if controls and type(controls.Bind) == "function" then
			controls.Bind(action, function(state: string)
				local ok, err = pcall(fn, state)
				if not ok then
					warn("[WeaponClient] " .. action .. ": " .. tostring(err))
				end
			end)
		end
	end
	bind("Fire", onFire)
	bind("Ads", onAdsInput)
	bind("Reload", function(state)
		if state == "Begin" and armed and not popped then
			startReload()
		end
	end)
	for i, slot in ipairs(SLOTS) do
		bind("Slot" .. i, function(state)
			if state == "Begin" and armed and not popped then
				equip(slot, true)
			end
		end)
	end
	bind("NextWeapon", function(state)
		if state == "Begin" and armed and not popped then
			cycle(1)
		end
	end)
	bind("PrevWeapon", function(state)
		if state == "Begin" and armed and not popped then
			cycle(-1)
		end
	end)
	bind("LastWeapon", function(state)
		if state == "Begin" and armed and not popped then
			equip(lastSlot, true)
		end
	end)
	bind("Melee", function(state)
		if state == "Begin" and armed and not popped then
			equip("Melee", true)
		end
	end)
	bind("Utility", function(state)
		if not armed or popped then
			return
		end
		local now = os.clock()
		if state == "Begin" then
			utilityPress(now)
		elseif state == "End" then
			releaseThrow(now)
		end
	end)
	bind("Inspect", function(state)
		if state == "Begin" and armed and not popped and not reloading and adsAlpha < 0.05 then
			call("Viewmodel", "Inspect")
		end
	end)
	if controls then
		return
	end
	-- Ersatz ohne Controls-Modul (Maus/Tastatur), damit Studio-Tests trotzdem laufen
	local keyMap: { [Enum.KeyCode]: () -> () } = {
		[Enum.KeyCode.R] = function()
			startReload()
		end,
		[Enum.KeyCode.One] = function()
			equip("Primary", true)
		end,
		[Enum.KeyCode.Two] = function()
			equip("Secondary", true)
		end,
		[Enum.KeyCode.Three] = function()
			equip("Melee", true)
		end,
		[Enum.KeyCode.Four] = function()
			equip("Utility", true)
		end,
		[Enum.KeyCode.Q] = function()
			equip(lastSlot, true)
		end,
	}
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not armed or popped then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onFire("Begin")
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			onAdsInput("Begin")
		elseif input.KeyCode == Enum.KeyCode.E then
			utilityPress(os.clock())
		else
			local fn = keyMap[input.KeyCode]
			if fn then
				fn()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onFire("End")
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			onAdsInput("End")
		elseif input.KeyCode == Enum.KeyCode.E then
			releaseThrow(os.clock())
		end
	end)
end

-- ---------------------------------------------------------------------
-- 13) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function WeaponClient.IsArmed(): boolean
	return armed and not popped
end

function WeaponClient.Current(): (string?, any?)
	if not armed then
		return nil, nil
	end
	local key = loadout[equipped]
	return key, defOfKey(key)
end

function WeaponClient.IsAds(): boolean
	return armed and adsSent
end

function WeaponClient.AdsAlpha(): number
	return if armed then adsAlpha else 0
end

function WeaponClient.IsBlocking(): boolean
	return armed and blocking
end

function WeaponClient.IsReloading(): boolean
	return armed and reloading
end

function WeaponClient.IsSwinging(): boolean
	return armed and os.clock() < swingUntil
end

function WeaponClient.Team(): number
	return myTeam
end

function WeaponClient.CombatantId(): number
	return if myId ~= 0 then myId else player.UserId
end

function WeaponClient.Rules(): { [string]: any }
	return rules
end

function WeaponClient.Enemies(): { Model }
	return table.clone(enemyModels)
end

function WeaponClient.Combatants(): { Model }
	return table.clone(allModels)
end

function WeaponClient.ModelOf(id: number): Model?
	if not finite(id) then
		return nil
	end
	local m = byId[id]
	if m and m.Parent then
		return m
	end
	return nil
end

function WeaponClient.SetTrigger(down: boolean)
	local want = down == true and armed and not popped
	if want and not hookTrigger then
		pressAt = os.clock()
		pressUsed = false
	end
	hookTrigger = want
end

-- ---------------------------------------------------------------------
-- 14) MODUL-FORM
-- ---------------------------------------------------------------------
function WeaponClient.Init(context: any)
	ctx = context
	if ctx and type(ctx.Remotes) == "table" then
		remotes = ctx.Remotes
	else
		remotes = Net.GetRemotes()
	end
end

function WeaponClient.Start()
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Armed", onArmed)
		hooks.On("Disarmed", onDisarmed)
		hooks.On("LocalPopped", onPopped)
		hooks.On("LocalRevived", onRevived)
		hooks.On("Combat:Ammo", onAmmo)
		hooks.On("Combat:Equip", onEquipCorrection)
		hooks.On("Combat:Hurt", onHurt)
		hooks.On("Match:Prep", function()
			if armed then
				fillAll() -- Rundenstart füllt alles (B11.1)
			end
		end)
		hooks.On("WindowOpened", function()
			triggerDown = false
			adsInput = false
			adsToggled = false
		end)
		hooks.On("State", function(_state: any, changed: any)
			-- neue Kosmetik für die ausgerüstete Waffe sofort im Viewmodel zeigen
			if armed and not popped and type(changed) == "table" and changed.Cosmetics then
				local key = loadout[equipped]
				if key then
					call("Viewmodel", "Equip", key, cosmeticsFor(key))
				end
			end
		end)
	end
	bindControls()
	player.CharacterAdded:Connect(function()
		registryAt = -10
		lastAirAt = -10
		lastMovingAt = -10
	end)
	RunService:BindToRenderStep("CC_WeaponClient", Enum.RenderPriority.Camera.Value + 3, function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[WeaponClient] " .. tostring(err))
		end
	end)
end

return WeaponClient
