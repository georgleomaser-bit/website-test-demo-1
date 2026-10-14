-- =====================================================================
--  AKYTEX TYCOON – Uhren, Accessoires, Deko-Lager (Server/Services/LifestyleService)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C5.7, §C9 (LifeBuy {Key}, LifeEquip
--  {Slot, Key?}, je 2/s), §C10 (State Life, Storage), §B12.2 (Uhren am Handgelenk für alle sichtbar: an LeftLowerArm
--  bzw. R6 "Left Arm" geschweißt, Massless, ohne Kollision/Abfrage/Berührung), §B12.3 (Accessoires, max. 3),
--  §B4.8 (Deko: Kauf ins Lager, Platzieren/Entfernen gratis über TowerService), §B9.6 (Vorstand „Lifestyle“ −5 %/Stufe
--  auf Uhren-/Deko-Preise), §B1 (Willkommen-zurück-Bericht aus OrderService.CatchUpReport).
--
--  Server ist Autorität: CR bucht nur ShopService.Debit (Senken "Watch", "Accessory", "Decor"). Robux-Firewall:
--  dieser Dienst berührt nie AKY, Depot, Lizenz, XP oder Marktinformation.
--
--  Öffentliche API (§C5.7):
--    LifestyleService.Owns(p, key): boolean          Uhr/Accessoire (gekauft, geschenkt oder freigeschaltet über Pass/
--                                                     Lizenz/Vorstand/Gruppe), Deko (Lager oder platziert), Kosmetik
--                                                     (Fassaden/Neon aus Data.Cosmetics bzw. Data.Purchases.Cosmetics)
--    LifestyleService.GrantWatch(p, key) · GrantAccessory(p, key) · GrantDecor(p, key, n): boolean
--    LifestyleService.TakeDecor(p, key): boolean     1 Stück aus dem Lager (für TowerService.SetDecor, kein Yield)
--    LifestyleService.ReturnDecor(p, key)            1 Stück zurück ins Lager (kein Yield)
--    LifestyleService.Comfort(key): number           Komfort-Punkte 1–5 (0 = unbekannt)
--    LifestyleService.CollectionValue(p): number     Sammlungswert (Vermögen, ganzzahlig, ≤ 9e15)
--  Request-Handler: LifeBuy {Key} (2/s), LifeEquip {Slot = "Watch" | "Acc" | "Jetpack", Key?} (2/s)
--    Neon-Jetpack (Pass, §B12.4): LifeEquip {Slot = "Jetpack", Key = "On"} zündet, ohne Key = aus. Server prüft Pass,
--    Treibstoff (8 s, lädt in 12 s), Sitz, fremden Tower; Anti-Cheat-Erlaubnis nur solange aktiv; Abschaltung spätestens
--    bei leerem Tank. Effekt (Neon-Düsen + Spur) hängt am Charakter -> für alle sichtbar.
--  Ergänzung: LifestyleService.StopJetpack(p)   (VehicleService vor dem Einsteigen)
--  State: Life = { Watches, Accessories, Equipped = { Watch, Acc }, Unlocked, Rotation, RotationEnds, Discount,
--                  Welcome? }   ·   Storage = { Decor = { [key] = n }, Placed = { [key] = n } }
--  Ergänzung: LifestyleService.Rotation(): ({ string }, number)   Boutique-Auslage + Ende (Unix)
--             LifestyleService._Test = { Core }  (reine Lager-/Besitz-Logik für VisualTests)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Lang = require(Shared:WaitForChild("Lang"))
local Format = require(Shared:WaitForChild("Format"))
local LifestyleModels = require(Shared:WaitForChild("LifestyleModels"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local LifestyleService = {}
local Services: any = nil

type Reply = Types.Reply

local PREFIX = "[LifestyleService] "
local MAX_MONEY = 9e15
local MAX_KEY = 40
local WELCOME_TIMEOUT = 180 -- Sekunden: so lange auf OrderService.CatchUpReport warten
local CHAR_WAIT = 8 -- Sekunden auf Arm/Kopf/Torso warten
local ERROR_LOG_EVERY = 10

local LCFG: { [string]: any } = if type(Config.Lifestyle) == "table" then Config.Lifestyle else {}
local DCFG: { [string]: any } = if type(Config.Decor) == "table" then Config.Decor else {}

local function num(v: any, default: number): number
	return if Util.IsFinite(v) then v else default
end

local MAX_ACC = math.clamp(math.floor(num(LCFG.MaxAccessories, 3)), 1, 6)
local STORAGE_MAX = math.clamp(math.floor(num(DCFG.StorageMax, 999)), 1, 100000)
local COMFORT_MAX = math.clamp(math.floor(num(DCFG.ComfortItemMax, 5)), 1, 20)

local function byKey(t: any): { [string]: any }
	return if type(t) == "table" then t else {}
end

local LIFE_BY_KEY = byKey(LCFG.ByKey)
local LIFE_KIND = byKey(LCFG.KindOf)
local DECOR_BY_KEY = byKey(DCFG.ByKey)

-- ---------------------------------------------------------------------
-- 1) ZUSTAND (pro Spieler bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local characterConns: { [Player]: RBXScriptConnection } = {}
local welcomePending: { [Player]: number } = {} -- Spieler -> os.clock() des Beitritts
local welcomeReport: { [Player]: { [string]: any } } = {}
local errorLogAt: { [string]: number } = {}
local rotationKeys: { string } = {}
local rotationWindow = -1
local rotationEnds = 0

local function logError(where: string, err: any)
	local t = os.clock()
	if t - (errorLogAt[where] or -math.huge) >= ERROR_LOG_EVERY then
		errorLogAt[where] = t
		warn(PREFIX .. where .. ": " .. tostring(err))
	end
end

local function has(serviceName: string, fnName: string): boolean
	local s = Services and Services[serviceName]
	return type(s) == "table" and type(s[fnName]) == "function"
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local s = Services and Services[serviceName]
	local fn = if type(s) == "table" then s[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		logError(serviceName .. "." .. fnName, result)
		return false, nil
	end
	return true, result
end

local function dataOf(p: Player): { [string]: any }?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function fail(p: Player, key: string, args: { any }?): Reply
	local lang = langOf(p)
	return { Ok = false, Message = if args then Lang.T(lang, key, table.unpack(args)) else Lang.T(lang, key) }
end

local function markDirty(p: Player, ...: string)
	call("PlayerStateService", "MarkDirty", p, ...)
end

local function validKey(key: any): boolean
	return type(key) == "string" and #key >= 1 and #key <= MAX_KEY and string.match(key, "^[%w_]+$") ~= nil
end

local function exact(arg: any, spec: { [string]: string }, optional: { [string]: boolean }?): boolean
	if type(arg) ~= "table" then
		return false
	end
	local count = 0
	for key, value in pairs(arg) do
		count += 1
		if count > 4 or type(key) ~= "string" or spec[key] == nil or type(value) ~= spec[key] then
			return false
		end
	end
	for key in pairs(spec) do
		if arg[key] == nil and not (optional and optional[key]) then
			return false
		end
	end
	return true
end

-- ---------------------------------------------------------------------
-- 2) KERN (reine Daten-Logik; VisualTests prüft sie mit Attrappen-Daten)
-- ---------------------------------------------------------------------
local Core = {}

-- Liste oder Menge -> Menge { [key] = true }
function Core.Set(t: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(t) ~= "table" then
		return set
	end
	for k, v in pairs(t) do
		if type(k) == "string" and v == true then
			set[k] = true
		elseif type(k) == "number" and type(v) == "string" then
			set[v] = true
		end
	end
	return set
end

-- Spielstand-Teile reparieren (Typen, Grenzen); unbekannte Schlüssel bleiben erhalten (nie Daten löschen)
function Core.Repair(data: { [string]: any })
	if type(data.Life) ~= "table" then
		data.Life = { Watches = {}, Accessories = {}, Equipped = { Watch = "", Acc = {} } }
	end
	local life = data.Life
	life.Watches = Core.Set(life.Watches)
	life.Accessories = Core.Set(life.Accessories)
	if type(life.Equipped) ~= "table" then
		life.Equipped = { Watch = "", Acc = {} }
	end
	local eq = life.Equipped
	if type(eq.Watch) ~= "string" or (eq.Watch ~= "" and not validKey(eq.Watch)) then
		eq.Watch = ""
	end
	local acc: { string } = {}
	if type(eq.Acc) == "table" then
		for _, key in ipairs(eq.Acc) do
			if validKey(key) and not table.find(acc, key) and #acc < MAX_ACC then
				table.insert(acc, key)
			end
		end
	end
	eq.Acc = acc
	if type(data.Storage) ~= "table" then
		data.Storage = { Decor = {} }
	end
	if type(data.Storage.Decor) ~= "table" then
		data.Storage.Decor = {}
	end
	local decor = data.Storage.Decor
	for key, n in pairs(decor) do
		if type(key) ~= "string" or not Util.IsFinite(n) or n <= 0 then
			decor[key] = nil
		else
			decor[key] = math.clamp(math.floor(n), 0, STORAGE_MAX)
			if decor[key] == 0 then
				decor[key] = nil
			end
		end
	end
end

function Core.Count(data: { [string]: any }, key: string): number
	local storage = data.Storage
	local decor = if type(storage) == "table" and type(storage.Decor) == "table" then storage.Decor else nil
	return if decor then math.floor(num(decor[key], 0)) else 0
end

function Core.Take(data: { [string]: any }, key: string): boolean
	Core.Repair(data)
	local decor = data.Storage.Decor
	local n = math.floor(num(decor[key], 0))
	if n <= 0 then
		return false
	end
	decor[key] = if n - 1 > 0 then n - 1 else nil
	return true
end

function Core.Give(data: { [string]: any }, key: string, n: number): boolean
	if not validKey(key) or not Util.IsFinite(n) or n < 1 or n % 1 ~= 0 then
		return false
	end
	Core.Repair(data)
	local decor = data.Storage.Decor
	decor[key] = math.clamp(math.floor(num(decor[key], 0)) + n, 0, STORAGE_MAX)
	return true
end

-- Wie oft steht ein Deko-Teil gerade im Tower?
function Core.Placed(data: { [string]: any }): { [string]: number }
	local placed: { [string]: number } = {}
	local tower = data.Tower
	local floors = if type(tower) == "table" and type(tower.Floors) == "table" then tower.Floors else {}
	for _, floor in ipairs(floors) do
		if type(floor) == "table" and type(floor.D) == "table" then
			for _, key in ipairs(floor.D) do
				if type(key) == "string" and key ~= "" then
					placed[key] = (placed[key] or 0) + 1
				end
			end
		end
	end
	return placed
end

-- Rabatt aus dem Vorstand-Ast „Lifestyle“ (nur Uhren und Deko, §B9.6)
function Core.Discount(perkLevel: number): number
	local perk = byKey(LCFG.Perk)
	local level = math.clamp(math.floor(num(perkLevel, 0)), 0, math.floor(num(perk.Max, 5)))
	return math.clamp(level * num(perk.Pct, 0.05), 0, 0.9)
end

function Core.Price(base: number, discount: number): number
	if not Util.IsFinite(base) or base <= 0 then
		return 0
	end
	return math.max(1, math.min(MAX_MONEY, math.floor(base * (1 - discount) + 0.5)))
end

LifestyleService._Test = { Core = Core }

-- ---------------------------------------------------------------------
-- 3) BESITZ & FREISCHALTUNGEN
-- ---------------------------------------------------------------------
local function licenceOf(p: Player, data: { [string]: any }): number
	local ok, licence = call("ProgressionService", "Licence", p)
	if ok and Util.IsFinite(licence) then
		return licence
	end
	local prog = data.Prog
	return if type(prog) == "table" then math.floor(num(prog.Licence, 1)) else 1
end

local function perkOf(p: Player, data: { [string]: any }, branch: string): number
	local ok, level = call("ProgressionService", "Perk", p, branch)
	if ok and Util.IsFinite(level) then
		return level
	end
	local prog = data.Prog
	local prestige = if type(prog) == "table" then prog.Prestige else nil
	local perks = if type(prestige) == "table" then prestige.Perks else nil
	return if type(perks) == "table" then math.floor(num(perks[branch], 0)) else 0
end

local function hasPass(p: Player, key: string): boolean
	local ok, result = call("MonetizationService", "HasPass", p, key)
	return ok and result == true
end

-- Uhr/Accessoire ohne Kauf freigeschaltet (Pass, Lizenz, Vorstand, Gruppe)?
local function unlocked(p: Player, data: { [string]: any }, entry: any): boolean
	local source = entry.Source
	if source == "Pass" then
		return type(entry.Pass) == "string" and hasPass(p, entry.Pass)
	elseif source == "Licence" then
		return licenceOf(p, data) >= num(entry.Licence, 99)
	elseif source == "Perk" then
		local perk = entry.Perk
		return type(perk) == "table" and perkOf(p, data, tostring(perk.Branch)) >= num(perk.Level, 99)
	elseif source == "Group" then
		return type(data.Social) == "table" and data.Social.Group == true
	end
	return false
end

local function inCosmetics(data: { [string]: any }, key: string): boolean
	for _, list in ipairs({ data.Cosmetics, if type(data.Purchases) == "table" then data.Purchases.Cosmetics else nil }) do
		if type(list) == "table" then
			if list[key] == true then
				return true
			end
			for _, value in ipairs(list) do
				if value == key then
					return true
				end
			end
		end
	end
	return false
end

local function ownsIn(p: Player, data: { [string]: any }, key: string): boolean
	local kind = LIFE_KIND[key]
	if kind == "Watch" or kind == "Accessory" then
		local life = data.Life
		local list = if type(life) == "table" then (if kind == "Watch" then life.Watches else life.Accessories) else nil
		if Core.Set(list)[key] then
			return true
		end
		return unlocked(p, data, LIFE_BY_KEY[key])
	end
	if DECOR_BY_KEY[key] then
		return Core.Count(data, key) > 0 or (Core.Placed(data)[key] or 0) > 0
	end
	return inCosmetics(data, key)
end

function LifestyleService.Owns(p: Player, key: string): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not validKey(key) then
		return false
	end
	local data = dataOf(p)
	return data ~= nil and ownsIn(p, data, key)
end

-- ---------------------------------------------------------------------
-- 4) AM KÖRPER: Uhr am linken Handgelenk, Accessoires an Kopf/Brust/Hand/Wurzel (für alle sichtbar)
-- ---------------------------------------------------------------------
local function clearAttachments(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if
			child:IsA("Model") and (child:GetAttribute("AkyWatch") ~= nil or child:GetAttribute("AkyAccessory") ~= nil)
		then
			child:Destroy()
		end
	end
end

local function weldTo(model: Model, part: BasePart, offset: CFrame, character: Model): boolean
	local primary = model.PrimaryPart
	if not primary then
		model:Destroy()
		return false
	end
	model:PivotTo(part.CFrame * offset)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = primary
	weld.Parent = primary
	model.Parent = character
	return true
end

-- Dial zeigt nach außen (−X des Arms), Uhr-+Y zeigt zur Hand (−Y des Arms)
local function wristOffset(arm: BasePart): CFrame
	local s = arm.Size
	return CFrame.fromMatrix(
		Vector3.new(-s.X / 2 - 0.02, -s.Y / 2 + 0.3, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, -1, 0),
		Vector3.new(1, 0, 0)
	)
end

local function accessoryMount(character: Model, entry: any): (BasePart?, CFrame)
	local kind = if type(entry.Recipe) == "table" then entry.Recipe.Kind else nil
	local attach = entry.Attach
	if attach == "Head" then
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return nil, CFrame.identity
		end
		if kind == "Crown" then
			return head, CFrame.new(0, head.Size.Y / 2 + 0.02, 0)
		end
		return head, CFrame.new(0, head.Size.Y * 0.12, -head.Size.Z / 2 - 0.04)
	elseif attach == "Torso" then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if not torso or not torso:IsA("BasePart") then
			return nil, CFrame.identity
		end
		local s = torso.Size
		local front = -s.Z / 2 - 0.04
		if kind == "Lapel" then
			return torso, CFrame.new(-s.X * 0.28, s.Y * 0.18, front)
		elseif kind == "Badge" then
			return torso, CFrame.new(s.X * 0.28, s.Y * 0.22, front)
		end
		return torso, CFrame.new(0, s.Y * 0.05, front)
	elseif attach == "RightHand" then
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if not hand or not hand:IsA("BasePart") then
			return nil, CFrame.identity
		end
		return hand, CFrame.new(0, -hand.Size.Y / 2 - 0.02, 0)
	elseif attach == "Root" then
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") then
			return nil, CFrame.identity
		end
		local legs = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight else 2
		return root, CFrame.new(0, -(root.Size.Y / 2 + legs) + 0.05, 0)
	end
	return nil, CFrame.identity
end

local function applyAttachments(p: Player)
	local character = p.Character
	local data = dataOf(p)
	if not character or not data or character.Parent == nil then
		return
	end
	local ok, err = pcall(function()
		clearAttachments(character)
		local life = data.Life
		local eq = if type(life) == "table" and type(life.Equipped) == "table" then life.Equipped else {}
		local watchKey = eq.Watch
		if
			type(watchKey) == "string"
			and watchKey ~= ""
			and LIFE_KIND[watchKey] == "Watch"
			and ownsIn(p, data, watchKey)
		then
			local arm = character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("Left Arm")
			if arm and arm:IsA("BasePart") then
				weldTo(LifestyleModels.Watch(watchKey), arm, wristOffset(arm), character)
			end
		end
		if type(eq.Acc) == "table" then
			for i, key in ipairs(eq.Acc) do
				if i > MAX_ACC then
					break
				end
				local entry = LIFE_BY_KEY[key]
				if entry and LIFE_KIND[key] == "Accessory" and ownsIn(p, data, key) then
					local part, offset = accessoryMount(character, entry)
					if part then
						weldTo(LifestyleModels.Accessory(key), part, offset, character)
					end
				end
			end
		end
	end)
	if not ok then
		logError("applyAttachments", err)
	end
end

-- ---------------------------------------------------------------------
-- 4b) NEON-JETPACK (Pass „Jetpack“, §B12.4): Treibstoff serverseitig, Erlaubnis nur während des Flugs
-- ---------------------------------------------------------------------
type Jet = { Active: boolean, Fuel: number, At: number, Token: number, Fx: { Instance } }

local JET: { [string]: any } = byKey(LCFG.Jetpack)
local JET_FUEL = math.clamp(num(JET.Fuel, 8), 1, 60)
local JET_RECHARGE = math.clamp(num(JET.Recharge, 12), 1, 120)
local JET_SLACK = 0.75 -- Sekunden Puffer (Ping) über dem Tank hinaus
local jets: { [Player]: Jet } = {}

local function jetAllowance(): (number, number)
	local security = if type(Config.Security) == "table" then Config.Security else {}
	local allow = byKey((security :: any).Allowances)
	local height = math.clamp(num(JET.MaxHeight, 120), 10, 400)
	local vertical = math.max(num(JET.VerticalMult, 3), num(allow.JetpackVerticalMult, 0), (height + 8) / 7.2)
	local speed = math.max(num(JET.SpeedMult, 1.6), num(allow.JetpackSpeedMult, 1))
	return math.clamp(speed, 1, 5), math.clamp(vertical, 1, 20)
end

local function jetOf(p: Player): Jet
	local jet = jets[p]
	if not jet then
		jet = { Active = false, Fuel = JET_FUEL, At = os.clock(), Token = 0, Fx = {} }
		jets[p] = jet
	end
	return jet
end

-- Tank aktualisieren (verbraucht im Flug, lädt am Boden nach)
local function jetRefresh(jet: Jet, now: number)
	local dt = math.max(0, now - jet.At)
	jet.At = now
	if jet.Active then
		jet.Fuel = math.max(0, jet.Fuel - dt)
	else
		jet.Fuel = math.min(JET_FUEL, jet.Fuel + dt * JET_FUEL / JET_RECHARGE)
	end
end

local function jetClearFx(jet: Jet)
	for _, inst in ipairs(jet.Fx) do
		inst:Destroy()
	end
	table.clear(jet.Fx)
end

-- Neon-Rucksack + Düsen-Funken + Spur am Rücken (repliziert, alle sehen den Flug)
local function jetAddFx(jet: Jet, character: Model)
	jetClearFx(jet)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local back = torso.Size.Z / 2 + 0.35
	local pack = Instance.new("Part")
	pack.Name = "AkyJetpack"
	pack.Size = Vector3.new(1.3, 1.6, 0.6)
	pack.Color = Color3.fromRGB(26, 33, 48)
	pack.Material = Enum.Material.Metal
	pack.Reflectance = 0.2
	pack.Anchored = false
	pack.Massless = true
	pack.CanCollide = false
	pack.CanQuery = false
	pack.CanTouch = false
	pack.CFrame = torso.CFrame * CFrame.new(0, 0, back)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = pack
	weld.Parent = pack
	local nozzle = Instance.new("Attachment")
	nozzle.Name = "Nozzle"
	nozzle.Position = Vector3.new(0, -0.85, 0)
	nozzle.Parent = pack
	local trailTop = Instance.new("Attachment")
	trailTop.Name = "TrailTop"
	trailTop.Position = Vector3.new(0, -0.4, 0.1)
	trailTop.Parent = pack
	local accent = Color3.fromRGB(79, 140, 255)
	local cosmic = Color3.fromRGB(179, 107, 255)
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flame.Color = ColorSequence.new(accent, cosmic)
	flame.LightEmission = 1
	flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
	flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	flame.Lifetime = NumberRange.new(0.2, 0.4)
	flame.Speed = NumberRange.new(12, 18)
	flame.SpreadAngle = Vector2.new(10, 10)
	flame.EmissionDirection = Enum.NormalId.Bottom
	flame.Rate = 45
	flame.Parent = nozzle
	local trail = Instance.new("Trail")
	trail.Name = "NeonTrail"
	trail.Attachment0 = trailTop
	trail.Attachment1 = nozzle
	trail.Lifetime = 0.6
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(accent, cosmic)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = pack
	local glow = Instance.new("PointLight")
	glow.Name = "JetGlow"
	glow.Color = accent
	glow.Range = 10
	glow.Brightness = 1.6
	glow.Shadows = false
	glow.Parent = nozzle
	pack.Parent = character
	table.insert(jet.Fx, pack)
end

local function jetStop(p: Player, reason: string?)
	local jet = jets[p]
	if not jet or not jet.Active then
		return
	end
	jetRefresh(jet, os.clock())
	jet.Active = false
	jet.Token += 1
	jetClearFx(jet)
	local character = p.Character
	if character then
		character:SetAttribute("AkyJetpack", nil)
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- im Auto gilt die Auto-Erlaubnis (VehicleService) – nicht überschreiben
	if p.Parent == Players and not (humanoid and humanoid.SeatPart ~= nil) then
		call("AntiCheatService", "SetAllowance", p, nil) -- senkt die Erlaubnis -> Anti-Cheat gibt Ausroll-/Fall-Gnade
	end
	if reason == "Empty" then
		call("PlayerStateService", "Notify", p, "life.jet.empty", nil, "Info")
	end
end

function LifestyleService.StopJetpack(p: Player)
	if typeof(p) == "Instance" and p:IsA("Player") then
		jetStop(p, nil)
	end
end

local function foreignTower(p: Player, position: Vector3): boolean
	local ok, plot = call("PlotService", "TowerAt", position)
	if not ok or not Util.IsFinite(plot) then
		return false
	end
	local okOwner, owner = call("PlotService", "OwnerOf", plot)
	return okOwner and owner ~= nil and owner ~= p
end

local function jetStart(p: Player): Reply
	local key = JET.Pass or "Jetpack"
	if not hasPass(p, key) then
		return fail(p, "life.jet.noPass")
	end
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return fail(p, "core.invalid")
	end
	if humanoid.SeatPart ~= nil then
		return fail(p, "life.jet.seated")
	end
	if foreignTower(p, root.Position) then
		return fail(p, "life.jet.foreign")
	end
	local jet = jetOf(p)
	local now = os.clock()
	jetRefresh(jet, now)
	if jet.Active then
		return { Ok = true, Fuel = jet.Fuel }
	end
	if jet.Fuel < 1 then
		return fail(p, "life.jet.recharge", { math.ceil((1 - jet.Fuel) * JET_RECHARGE / JET_FUEL) })
	end
	jet.Active = true
	jet.Token += 1
	local token = jet.Token
	local speed, vertical = jetAllowance()
	call("AntiCheatService", "SetAllowance", p, { SpeedMult = speed, VerticalMult = vertical })
	character:SetAttribute("AkyJetpack", true)
	local okFx, errFx = pcall(jetAddFx, jet, character)
	if not okFx then
		logError("jetAddFx", errFx)
	end
	-- spätestens mit leerem Tank aus (Client meldet sich normalerweise vorher)
	task.delay(jet.Fuel + JET_SLACK, function()
		local current = jets[p]
		if current and current.Active and current.Token == token then
			jetStop(p, "Empty")
		end
	end)
	return { Ok = true, Fuel = jet.Fuel }
end

local function onCharacterAdded(p: Player, character: Model)
	local jet = jets[p]
	if jet and jet.Active then
		-- Respawn: Flug endet (Effekt-Teile hingen an der alten Figur)
		jetRefresh(jet, os.clock())
		jet.Active = false
		jet.Token += 1
		jetClearFx(jet)
		call("AntiCheatService", "SetAllowance", p, nil)
	end
	task.spawn(function()
		-- Arm/Kopf/Torso müssen da sein (Avatar lädt asynchron)
		local started = os.clock()
		while os.clock() - started < CHAR_WAIT do
			if p.Parent ~= Players or p.Character ~= character then
				return
			end
			if
				character:FindFirstChild("Head")
				and (character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("Left Arm"))
				and character:FindFirstChild("HumanoidRootPart")
			then
				break
			end
			task.wait(0.25)
		end
		if p.Parent == Players and p.Character == character then
			applyAttachments(p)
		end
	end)
end

-- ---------------------------------------------------------------------
-- 5) BOUTIQUE-ROTATION (ShopService.Rotation, sonst deterministischer Ersatz – auf allen Servern gleich)
-- ---------------------------------------------------------------------
local function rotationParams(): (number, number)
	local shop = if type(Config.Shop) == "table" then Config.Shop else {}
	local fallback = byKey(LCFG.Boutique)
	local hours = math.clamp(num(shop.BoutiqueHours, num(fallback.Hours, 4)), 1, 48)
	local slots = math.clamp(math.floor(num(shop.BoutiqueSlots, num(fallback.Slots, 6))), 1, 24)
	return hours, slots
end

local function purchasable(): { string }
	local pool: { string } = {}
	for _, list in ipairs({ LCFG.Watches, LCFG.Accessories, DCFG.Items }) do
		if type(list) == "table" then
			for _, entry in ipairs(list) do
				if type(entry) == "table" and entry.Source == "Shop" and num(entry.Price, 0) > 0 then
					table.insert(pool, entry.Key)
				end
			end
		end
	end
	return pool
end

local function knownKey(key: any): boolean
	return type(key) == "string" and (LIFE_BY_KEY[key] ~= nil or DECOR_BY_KEY[key] ~= nil)
end

local function computeRotation(window: number, slots: number): { string }
	local ok, fromShop = call("ShopService", "Rotation")
	local list: { string } = {}
	if ok and type(fromShop) == "table" then
		for _, key in ipairs(fromShop) do
			if knownKey(key) and not table.find(list, key) and #list < 24 then
				table.insert(list, key)
			end
		end
		if #list > 0 then
			return list
		end
	end
	local pool = purchasable()
	local attempts = 0
	while #list < math.min(slots, #pool) and attempts < slots * 8 do
		attempts += 1
		local index = Util.Hash(("boutique:%d:%d"):format(window, attempts)) % #pool + 1
		local key = pool[index]
		if not table.find(list, key) then
			table.insert(list, key)
		end
	end
	return list
end

local function refreshRotation(): boolean
	local hours, slots = rotationParams()
	local span = math.floor(hours * 3600)
	local window = os.time() // span
	if window == rotationWindow and #rotationKeys > 0 then
		return false
	end
	rotationWindow = window
	rotationEnds = (window + 1) * span
	rotationKeys = computeRotation(window, slots)
	return true
end

function LifestyleService.Rotation(): ({ string }, number)
	refreshRotation()
	return table.clone(rotationKeys), rotationEnds
end

-- ---------------------------------------------------------------------
-- 6) ÖFFENTLICHE API (§C5.7)
-- ---------------------------------------------------------------------
local function grantLife(p: Player, key: string, kind: string): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not validKey(key) or LIFE_KIND[key] ~= kind then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	Core.Repair(data)
	local life = data.Life
	local eq = life.Equipped
	if kind == "Watch" then
		life.Watches[key] = true
		if eq.Watch == "" then
			eq.Watch = key -- sofort sichtbare Wirkung (§0.8 Punkt 3)
		end
	else
		life.Accessories[key] = true
		if #eq.Acc < MAX_ACC and not table.find(eq.Acc, key) then
			table.insert(eq.Acc, key)
		end
	end
	markDirty(p, "Life")
	task.defer(applyAttachments, p)
	return true
end

function LifestyleService.GrantWatch(p: Player, key: string): boolean
	return grantLife(p, key, "Watch")
end

function LifestyleService.GrantAccessory(p: Player, key: string): boolean
	return grantLife(p, key, "Accessory")
end

function LifestyleService.GrantDecor(p: Player, key: string, n: number): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not DECOR_BY_KEY[key] then
		return false
	end
	local data = dataOf(p)
	if not data or not Core.Give(data, key, n) then
		return false
	end
	markDirty(p, "Storage")
	return true
end

function LifestyleService.TakeDecor(p: Player, key: string): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not validKey(key) or not DECOR_BY_KEY[key] then
		return false
	end
	local data = dataOf(p)
	if not data or not Core.Take(data, key) then
		return false
	end
	markDirty(p, "Storage")
	return true
end

function LifestyleService.ReturnDecor(p: Player, key: string)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not validKey(key) then
		return
	end
	local data = dataOf(p)
	if data and Core.Give(data, key, 1) then
		markDirty(p, "Storage")
	end
end

function LifestyleService.Comfort(key: string): number
	local entry = if type(key) == "string" then DECOR_BY_KEY[key] else nil
	if not entry then
		return 0
	end
	return math.clamp(math.floor(num(entry.Comfort, 0)), 0, COMFORT_MAX)
end

function LifestyleService.CollectionValue(p: Player): number
	local data = dataOf(p)
	if not data then
		return 0
	end
	local total = 0
	for key, entry in pairs(LIFE_BY_KEY) do
		if ownsIn(p, data, key) then
			total += math.max(0, num(entry.Value, num(entry.Price, 0)))
		end
	end
	local placed = Core.Placed(data)
	local storage = if type(data.Storage) == "table" and type(data.Storage.Decor) == "table"
		then data.Storage.Decor
		else {}
	for key, entry in pairs(DECOR_BY_KEY) do
		local count = math.floor(num(storage[key], 0)) + (placed[key] or 0)
		if count > 0 then
			local value = num(entry.Price, 0)
			if value <= 0 then
				value = num(entry.Comfort, 1) * 50000 -- Sammlerwert nicht kaufbarer Teile (Pokale, Saison)
			end
			total += value * count
		end
	end
	return math.clamp(math.floor(total), 0, MAX_MONEY)
end

-- ---------------------------------------------------------------------
-- 7) REQUEST-HANDLER (§C9)
-- ---------------------------------------------------------------------
local function credits(p: Player, n: number): string
	return Format.Credits(n, langOf(p))
end

local function nameOf(p: Player, entry: any): string
	return if type(entry) == "table" and type(entry.Name) == "table" then Lang.Pick(langOf(p), entry.Name) else "?"
end

local function handleBuy(p: Player, arg: any): Reply
	if not exact(arg, { Key = "string" }) or not validKey(arg.Key) then
		return fail(p, "core.invalid")
	end
	local key = arg.Key
	local lifeKind = LIFE_KIND[key]
	local entry = LIFE_BY_KEY[key] or DECOR_BY_KEY[key]
	if not entry then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	if entry.Source ~= "Shop" or num(entry.Price, 0) <= 0 then
		return fail(p, "life.notForSale")
	end
	Core.Repair(data)
	if lifeKind and ownsIn(p, data, key) then
		return fail(p, "life.owned")
	end
	if not lifeKind and Core.Count(data, key) >= STORAGE_MAX then
		return fail(p, "life.storageFull", { STORAGE_MAX })
	end
	if not has("ShopService", "Debit") then
		return fail(p, "life.shopMissing")
	end
	-- Vorstand „Lifestyle“: −5 % je Stufe auf Uhren und Deko (nicht auf Accessoires, §B9.6)
	local branch = tostring(byKey(LCFG.Perk).Branch or "Lifestyle")
	local discount = if lifeKind == "Accessory" then 0 else Core.Discount(perkOf(p, data, branch))
	local price = Core.Price(entry.Price, discount)
	local sink = if lifeKind == "Watch" then "Watch" elseif lifeKind == "Accessory" then "Accessory" else "Decor"
	local ok, paid = call("ShopService", "Debit", p, price, sink)
	if not ok or paid ~= true then
		local okBalance, balance = call("ShopService", "Balance", p)
		local missing = if okBalance and Util.IsFinite(balance) then math.max(0, price - balance) else price
		return fail(p, "life.noCredits", { credits(p, missing) })
	end
	local granted = if lifeKind == "Watch"
		then LifestyleService.GrantWatch(p, key)
		elseif lifeKind == "Accessory" then LifestyleService.GrantAccessory(p, key)
		else LifestyleService.GrantDecor(p, key, 1)
	if not granted then
		-- sollte nie passieren (alles oben geprüft) – Betrag zurückbuchen
		call("ShopService", "Credit", p, price, "Refund")
		return fail(p, "core.error")
	end
	call("MetricsService", "Custom", p, "LifeBuy", price, { Key = key, Kind = sink })
	local lang = langOf(p)
	local message = if lifeKind
		then Lang.T(lang, "life.boughtWorn", nameOf(p, entry))
		else Lang.T(lang, "life.boughtDecor", nameOf(p, entry))
	return { Ok = true, Message = message, Key = key, Price = price }
end

local function handleEquip(p: Player, arg: any): Reply
	if not exact(arg, { Slot = "string", Key = "string" }, { Key = true }) then
		return fail(p, "core.invalid")
	end
	local slot = arg.Slot
	local key = arg.Key
	if slot == "Jetpack" then
		if key == "On" then
			return jetStart(p)
		elseif key == nil or key == "" then
			jetStop(p, nil)
			return { Ok = true }
		end
		return fail(p, "core.invalid")
	end
	if slot ~= "Watch" and slot ~= "Acc" then
		return fail(p, "core.invalid")
	end
	if key ~= nil and key ~= "" and not validKey(key) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	Core.Repair(data)
	local eq = data.Life.Equipped
	local lang = langOf(p)
	local message: string
	if slot == "Watch" then
		if key == nil or key == "" then
			eq.Watch = ""
			message = Lang.T(lang, "life.watchOff")
		else
			if LIFE_KIND[key] ~= "Watch" then
				return fail(p, "core.invalid")
			end
			if not ownsIn(p, data, key) then
				return fail(p, "life.notOwned")
			end
			eq.Watch = key
			message = Lang.T(lang, "life.watchOn", nameOf(p, LIFE_BY_KEY[key]))
		end
	else
		if key == nil or key == "" then
			table.clear(eq.Acc)
			message = Lang.T(lang, "life.accCleared")
		else
			if LIFE_KIND[key] ~= "Accessory" then
				return fail(p, "core.invalid")
			end
			if not ownsIn(p, data, key) then
				return fail(p, "life.notOwned")
			end
			local index = table.find(eq.Acc, key)
			if index then
				table.remove(eq.Acc, index)
				message = Lang.T(lang, "life.accOff", nameOf(p, LIFE_BY_KEY[key]))
			elseif #eq.Acc >= MAX_ACC then
				return fail(p, "life.accFull", { MAX_ACC })
			else
				table.insert(eq.Acc, key)
				message = Lang.T(lang, "life.accOn", nameOf(p, LIFE_BY_KEY[key]))
			end
		end
	end
	markDirty(p, "Life")
	task.defer(applyAttachments, p)
	return { Ok = true, Message = message }
end

-- ---------------------------------------------------------------------
-- 8) STATE (§C10)
-- ---------------------------------------------------------------------
local function sortedKeys(set: { [string]: boolean }): { string }
	local list: { string } = {}
	for key in pairs(set) do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

local function lifeState(p: Player): { [string]: any }
	refreshRotation()
	local data = dataOf(p)
	local base: { [string]: any } = {
		Watches = {},
		Accessories = {},
		Equipped = { Watch = "", Acc = {} },
		Unlocked = {},
		Rotation = table.clone(rotationKeys),
		RotationEnds = rotationEnds,
		Discount = 0,
	}
	if not data then
		return base
	end
	Core.Repair(data)
	local life = data.Life
	base.Watches = sortedKeys(life.Watches)
	base.Accessories = sortedKeys(life.Accessories)
	base.Equipped = { Watch = life.Equipped.Watch, Acc = table.clone(life.Equipped.Acc) }
	local unlockedList: { string } = {}
	for key, entry in pairs(LIFE_BY_KEY) do
		if unlocked(p, data, entry) then
			table.insert(unlockedList, key)
		end
	end
	table.sort(unlockedList)
	base.Unlocked = unlockedList
	base.Discount = Core.Discount(perkOf(p, data, tostring(byKey(LCFG.Perk).Branch or "Lifestyle")))
	local report = welcomeReport[p]
	if report then
		base.Welcome = report
	end
	return base
end

local function storageState(p: Player): { [string]: any }
	local data = dataOf(p)
	if not data then
		return { Decor = {}, Placed = {} }
	end
	Core.Repair(data)
	return { Decor = table.clone(data.Storage.Decor), Placed = Core.Placed(data) }
end

-- ---------------------------------------------------------------------
-- 9) TAKTE & LEBENSZYKLUS
-- ---------------------------------------------------------------------
-- Willkommen-Bericht: OrderService.CatchUpReport, sobald der Offline-Abgleich fertig ist (§B1)
local function sanitizeReport(raw: any): { [string]: any }
	local out: { [string]: any } = {
		Fills = math.clamp(math.floor(num(raw.Fills, 0)), 0, 100000),
		Dividends = math.clamp(math.floor(num(raw.Dividends, 0)), 0, MAX_MONEY),
		Alerts = math.clamp(math.floor(num(raw.Alerts, 0)), 0, 1000),
		Bots = {},
	}
	if type(raw.Bots) == "table" then
		for i, bot in ipairs(raw.Bots) do
			if i > 8 then
				break
			end
			if type(bot) == "table" and type(bot.Preset) == "string" and #bot.Preset <= 24 then
				table.insert(out.Bots, { Preset = bot.Preset, Pct = math.clamp(num(bot.Pct, 0), -10, 10) })
			end
		end
	end
	return out
end

local function welcomeJob(_dt: number)
	local t = os.clock()
	for p, since in pairs(welcomePending) do
		if p.Parent ~= Players or t - since > WELCOME_TIMEOUT then
			welcomePending[p] = nil
			continue
		end
		local ok, report = call("OrderService", "CatchUpReport", p)
		if ok and type(report) == "table" then
			welcomeReport[p] = sanitizeReport(report)
			welcomePending[p] = nil
			markDirty(p, "Life")
		elseif not has("OrderService", "CatchUpReport") then
			welcomePending[p] = nil
		end
	end
end

local function rotationJob(_dt: number)
	if refreshRotation() then
		for _, p in ipairs(Players:GetPlayers()) do
			markDirty(p, "Life")
		end
	end
end

local function onProfileLoaded(p: Player, data: { [string]: any })
	if p.Parent ~= Players or type(data) ~= "table" then
		return
	end
	Core.Repair(data)
	markDirty(p, "Life", "Storage")
	if p.Character then
		task.defer(applyAttachments, p)
	end
end

local function onPlayerAdded(p: Player)
	welcomePending[p] = os.clock()
	if characterConns[p] == nil then
		characterConns[p] = p.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(p, character)
		end)
	end
	if p.Character then
		onCharacterAdded(p, p.Character)
	end
end

local function onPlayerRemoving(p: Player)
	local conn = characterConns[p]
	if conn then
		conn:Disconnect()
	end
	characterConns[p] = nil
	welcomePending[p] = nil
	welcomeReport[p] = nil
	local jet = jets[p]
	if jet then
		jet.Token += 1
		jetClearFx(jet)
	end
	jets[p] = nil
end

function LifestyleService.Init(services: any)
	Services = services
	refreshRotation()
	local pss = Services.PlayerStateService
	if type(pss) ~= "table" then
		warn(PREFIX .. "PlayerStateService fehlt – keine Anfragen/State")
		return
	end
	pss.Provide("Life", lifeState)
	pss.Provide("Storage", storageState)
	pss.Handle("LifeBuy", handleBuy, { Rate = 2, Per = 1 })
	pss.Handle("LifeEquip", handleEquip, { Rate = 2, Per = 1 })
end

function LifestyleService.Start()
	call("DataService", "OnProfileLoaded", onProfileLoaded)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Scheduler.Every("LifeWelcome", 1, welcomeJob)
	Scheduler.Every("BoutiqueRotation", 1, rotationJob)
end

return LifestyleService
