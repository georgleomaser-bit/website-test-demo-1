-- GADGETS: mit Cash im Shop kaufen (Config.Gadgets). Sie gehören einem für immer (data.Gadgets,
-- bleibt bei Rebirth) und liegen nach jedem Spawn als Werkzeug im Rucksack:
--   🌀 Speed Coil – solange in der Hand: +30% Tempo (EconomyService.ApplySpeed fragt SpeedBonus)
--   🪤 Falle      – Klick in der EIGENEN Base: Falle am Boden (max. Config.MaxTrapsPerBase).
--                   Fremde frieren Config.TrapFreezeTime Sekunden ein, getragene Beute ist weg.
--   🔨 Super-Bonk – kein eigenes Werkzeug: Boost für den Schläger (mehr Reichweite + Wucht, schneller;
--                   Schlag-Logik in CarryService)
--   👻 Umhang     – Klick: Config.CloakDuration Sekunden unsichtbar und nicht bonkbar,
--                   danach Config.CloakCooldown Sekunden Abklingzeit (ab dem Sichtbarwerden).
--                   Wer klaut, wird sofort sichtbar (CarryService), mit Beute geht er nicht an.
-- Alles wird hier auf dem Server geprüft und gebremst (Klicks kommen vom Client).
-- Fallen lösen über Touched UND über eine eigene Server-Prüfung aus (Touched meldet der Client –
-- wer das lokal abschaltet, läuft trotzdem nicht einfach drüber).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local GadgetService = {}
local Services

local useLimiter = Util.RateLimiter(4, 1) -- Werkzeug-Klicks pro Sekunde (Falle, Umhang)
local SYNC_INTERVAL = 2 -- so oft wird geprüft, ob jeder seine Werkzeuge hat
local TRAP_PLACE_COOLDOWN = 1 -- Sekunden zwischen zwei Fallen
local TRAP_SIZE = 4.5
local TRAP_HEIGHT = 0.6 -- so hoch, dass Füße beim Drüberlaufen sicher die Falle berühren
local TRAP_EDGE_MARGIN = TRAP_SIZE / 2 + 1 -- Fallen-Mitte so weit innerhalb der Base (nichts ragt raus)
local TRAP_IMMUNE_EXTRA = 5 -- nach dem Auftauen so viele Sekunden immun (keine Endlos-Falle)
local TRAP_CHECK_INTERVAL = 0.2 -- so oft prüft der Server selbst, ob jemand auf einer Falle steht
local TRAP_REACH = TRAP_SIZE / 2 + 1 -- waagrechter Abstand Fallen-Mitte <-> HumanoidRootPart
local TRAP_MAX_HEIGHT = 5 -- so hoch über der Falle zählt der HumanoidRootPart noch als "draufgetreten"

-- Werkzeug-Namen im Rucksack (Super-Bonk hat kein Werkzeug, er verstärkt den Schläger)
local TOOL_NAMES = {
	SpeedCoil = "Speed Coil",
	Trap = "Falle",
	Cloak = "Umhang",
}

-- Fallen pro Besitzer (eine Base pro Spieler): [player] = { Falle, ... }
local trapsByOwner: { [Player]: { BasePart } } = {}
local trapPlacedAt: { [Player]: number } = {}
local trapImmuneUntil: { [Player]: number } = {} -- gerade aus einer Falle aufgetaut -> kurz immun
-- Umhang: [player] = { Character, Changed = { [Instance] = alte Transparenz }, Conn, ... }
type CloakState = {
	Character: Model,
	Changed: { [Instance]: number },
	Conn: RBXScriptConnection,
	Humanoid: Humanoid?,
	DisplayType: Enum.HumanoidDisplayDistanceType?,
}
local cloaks: { [Player]: CloakState } = {}
local cloakReadyAt: { [Player]: number } = {}
local freezeToken = 0
local templates: { [string]: Tool } = {}

-- -------------------------------------------------------------------
-- BESITZ
-- -------------------------------------------------------------------
local function gadgetTable(data): { [string]: boolean }
	if type(data.Gadgets) ~= "table" then
		data.Gadgets = {} -- alter Spielstand ohne Gadgets
	end
	return data.Gadgets
end

function GadgetService.Owns(player: Player, id: string): boolean
	local data = Services.DataService.Get(player)
	if not data or type(data.Gadgets) ~= "table" then
		return false
	end
	return data.Gadgets[id] == true
end

-- Alle Gadget-Ids, die der Spieler besitzt (Reihenfolge wie in Config.Gadgets)
function GadgetService.OwnedList(player: Player): { string }
	local list = {}
	for _, gadget in ipairs(Config.Gadgets) do
		if GadgetService.Owns(player, gadget.Id) then
			table.insert(list, gadget.Id)
		end
	end
	return list
end

local function aliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- Gadget-Werkzeug (Attribut "Gadget") im Rucksack oder in der Hand?
local function findGadgetTool(container: Instance?, id: string): Tool?
	if not container then
		return nil
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Gadget") == id then
			return child
		end
	end
	return nil
end

-- -------------------------------------------------------------------
-- 🌀 SPEED COIL
-- -------------------------------------------------------------------
-- Faktor für die Laufgeschwindigkeit: 1.3 solange die Speed Coil in der Hand ist, sonst 1
function GadgetService.SpeedBonus(player: Player): number
	local character = player.Character
	if character and findGadgetTool(character, "SpeedCoil") and GadgetService.Owns(player, "SpeedCoil") then
		return 1 + Config.SpeedCoilBonus
	end
	return 1
end

-- -------------------------------------------------------------------
-- 🪤 FALLE
-- -------------------------------------------------------------------
local function trapList(player: Player): { BasePart }
	local list = trapsByOwner[player]
	if not list then
		list = {}
		trapsByOwner[player] = list
	end
	for i = #list, 1, -1 do
		if not list[i].Parent then
			table.remove(list, i) -- schon ausgelöst oder mit der Base weg
		end
	end
	return list
end

-- Boden unter den Füßen (nur begehbare Teile, Spieler ignorieren)
local function floorBelow(position: Vector3): Vector3?
	local ignore: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local result = workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	return result and result.Position or nil
end

-- Kurzer Eisblock um den Eingefrorenen (nur Optik)
local function iceEffect(root: BasePart, seconds: number)
	local ice = Instance.new("Part")
	ice.Name = "TrapIce"
	ice.Size = Vector3.new(4.5, 6.5, 4.5)
	ice.CFrame = root.CFrame * CFrame.new(0, -0.4, 0)
	ice.Anchored = true
	ice.CanCollide = false
	ice.CanQuery = false
	ice.CanTouch = false
	ice.CastShadow = false
	ice.Material = Enum.Material.Glass
	ice.Color = Color3.fromRGB(160, 225, 255)
	ice.Transparency = 0.45
	ice.Parent = workspace
	Debris:AddItem(ice, seconds)
end

-- Friert einen Spieler ein (HumanoidRootPart verankert) und taut ihn danach wieder auf.
-- Ein Admin-Freeze in der Zwischenzeit löscht das Attribut -> wird dann nicht aufgetaut.
local function freeze(root: BasePart, seconds: number)
	freezeToken += 1
	local token = freezeToken
	root:SetAttribute("TrapFreeze", token)
	root.Anchored = true
	iceEffect(root, seconds)
	task.delay(seconds, function()
		if root.Parent and root:GetAttribute("TrapFreeze") == token then
			root:SetAttribute("TrapFreeze", nil)
			root.Anchored = false
		end
	end)
end

-- Falle schnappt zu (über Touched oder die Server-Prüfung). Nur für Fremde, die IN der Base des
-- Besitzers stehen (wer am Eingang vorbeiläuft, wird nicht erwischt) und nicht gerade erst aufgetaut sind.
local function springTrap(owner: Player, trap: BasePart, victim: Player)
	if trap:GetAttribute("Sprung") == true or not trap.Parent or victim == owner then
		return
	end
	if victim:GetAttribute("AdminGod") == true then
		return -- Admin-Gott-Modus: Fallen schnappen nicht zu
	end
	if os.clock() < (trapImmuneUntil[victim] or 0) then
		return
	end
	local _, humanoid, root = aliveCharacter(victim)
	local plot = Services.PlotService.GetPlot(owner)
	if not humanoid or not root or not plot or not Services.PlotService.IsInside(plot, root.Position) then
		return
	end
	trap:SetAttribute("Sprung", true)
	trap:Destroy()
	trapImmuneUntil[victim] = os.clock() + Config.TrapFreezeTime + TRAP_IMMUNE_EXTRA
	if not root.Anchored then
		freeze(root, Config.TrapFreezeTime) -- (schon vom Admin eingefroren -> so lassen)
	end
	if Services.CarryService.IsCarrying(victim) then
		Services.CarryService.Fail(victim, "trap") -- Beute aus der Base fliegt zurück, Eier fallen runter
	end
	Services.EconomyService.Effect(victim, "Shake", 0.8)
	Services.EconomyService.Notify(
		victim,
		"🪤 FALLE! Du bist " .. Config.TrapFreezeTime .. " Sekunden eingefroren!",
		"Error"
	)
	Services.EconomyService.Notify(owner, "🪤 " .. victim.DisplayName .. " ist in deine Falle getappt!", "Success")
end

local function onTrapTouched(owner: Player, trap: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local victim = character and Players:GetPlayerFromCharacter(character)
	if victim and victim.Character == character then
		springTrap(owner, trap, victim)
	end
end

-- Server-Prüfung (alle TRAP_CHECK_INTERVAL Sekunden): steht ein Fremder auf einer Falle?
local function checkTraps()
	for owner, list in pairs(trapsByOwner) do
		for _, trap in ipairs(list) do
			if trap.Parent and trap:GetAttribute("Sprung") ~= true then
				local center = trap.Position
				for _, victim in ipairs(Players:GetPlayers()) do
					local character = victim.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if victim ~= owner and root and root:IsA("BasePart") then
						local offset = root.Position - center
						local flatSq = offset.X * offset.X + offset.Z * offset.Z
						if flatSq <= TRAP_REACH * TRAP_REACH and offset.Y > -1 and offset.Y < TRAP_MAX_HEIGHT then
							springTrap(owner, trap, victim)
							if trap:GetAttribute("Sprung") == true then
								break
							end
						end
					end
				end
			end
		end
	end
end

local function buildTrap(position: Vector3): BasePart
	local trap = Instance.new("Part")
	trap.Name = "Trap"
	trap.Shape = Enum.PartType.Cylinder
	trap.Size = Vector3.new(TRAP_HEIGHT, TRAP_SIZE, TRAP_SIZE)
	trap.CFrame = CFrame.new(position + Vector3.new(0, TRAP_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trap.Anchored = true
	trap.CanCollide = false
	trap.CanQuery = false
	trap.CanTouch = true
	trap.CastShadow = false
	trap.Material = Enum.Material.DiamondPlate
	trap.Color = Color3.fromRGB(70, 70, 80)

	-- Leuchtring + Zähne (nur Optik)
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(TRAP_HEIGHT + 0.05, TRAP_SIZE * 0.7, TRAP_SIZE * 0.7)
	ring.CFrame = trap.CFrame
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 60, 60)
	ring.Parent = trap
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local tooth = Instance.new("Part")
		tooth.Name = "Tooth"
		tooth.Size = Vector3.new(0.3, 0.7, 0.3)
		tooth.CFrame = CFrame.new(
			position
				+ Vector3.new(math.cos(angle) * TRAP_SIZE * 0.42, TRAP_HEIGHT + 0.3, math.sin(angle) * TRAP_SIZE * 0.42)
		)
		tooth.Anchored = true
		tooth.CanCollide = false
		tooth.CanQuery = false
		tooth.CanTouch = false
		tooth.CastShadow = false
		tooth.Material = Enum.Material.Metal
		tooth.Color = Color3.fromRGB(210, 210, 220)
		tooth.Parent = trap
	end
	return trap
end

local function placeTrap(player: Player)
	if not useLimiter.Check(player) or not GadgetService.Owns(player, "Trap") then
		return
	end
	local t = os.clock()
	if t - (trapPlacedAt[player] or -math.huge) < TRAP_PLACE_COOLDOWN then
		return
	end
	local _, _, root = aliveCharacter(player)
	local plot = Services.PlotService.GetPlot(player)
	if not root or not plot then
		return
	end
	if not Services.PlotService.IsInside(plot, root.Position) then
		Services.EconomyService.Notify(player, "🪤 Fallen kannst du nur in deiner eigenen Base aufstellen!", "Error")
		return
	end
	local list = trapList(player)
	if #list >= Config.MaxTrapsPerBase then
		Services.EconomyService.Notify(
			player,
			"🪤 Schon " .. Config.MaxTrapsPerBase .. " Fallen aufgestellt – mehr gehen nicht!",
			"Error"
		)
		return
	end
	local floor = floorBelow(root.Position)
	if not floor or not Services.PlotService.IsInside(plot, floor) then
		return
	end
	-- Die ganze Falle muss in der Base liegen (am Rand würde sie vor den Eingang ragen)
	local localFloor = plot.CFrame:PointToObjectSpace(floor)
	local hx, hz = Services.PlotService.HalfExtents(plot)
	-- (Rand innen: FENCE 1 Stud dick -> mit TRAP_EDGE_MARGIN steht die Falle nie im Rand)
	if math.abs(localFloor.X) > hx - TRAP_EDGE_MARGIN or math.abs(localFloor.Z) > hz - TRAP_EDGE_MARGIN then
		Services.EconomyService.Notify(player, "🪤 Zu nah am Rand – stell die Falle weiter innen auf!", "Error")
		return
	end
	-- Nur direkt auf den Base-Boden (nicht auf Baumstamm, Laterne oder Rand)
	local floorPart = plot.Model.PrimaryPart
	if floorPart then
		local floorTop = floorPart.Position.Y + floorPart.Size.Y / 2
		if math.abs(floor.Y - floorTop) > 0.5 then
			Services.EconomyService.Notify(player, "🪤 Stell die Falle auf den Boden deiner Base!", "Error")
			return
		end
	end
	trapPlacedAt[player] = t
	local folder = plot.Model:FindFirstChild("Traps")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Traps"
		folder.Parent = plot.Model
	end
	local trap = buildTrap(floor)
	trap:SetAttribute("OwnerUserId", player.UserId)
	trap.Touched:Connect(function(hit)
		onTrapTouched(player, trap, hit)
	end)
	trap.Parent = folder
	table.insert(list, trap)
	Services.EconomyService.Notify(
		player,
		"🪤 Falle aufgestellt! (" .. #list .. "/" .. Config.MaxTrapsPerBase .. ")",
		"Success"
	)
end

local function clearTraps(player: Player)
	local list = trapsByOwner[player]
	if list then
		for _, trap in ipairs(list) do
			trap:Destroy()
		end
	end
	trapsByOwner[player] = nil
end

-- -------------------------------------------------------------------
-- 👻 UMHANG
-- -------------------------------------------------------------------
function GadgetService.IsCloaked(player: Player): boolean
	return cloaks[player] ~= nil
end

-- Die getragene Beute bleibt sichtbar (man sieht ein schwebendes Ei – bonken geht trotzdem nicht)
local function isCarriedLoot(inst: Instance): boolean
	return inst:FindFirstAncestor("CarriedMeteor") ~= nil
		or inst:FindFirstAncestor("CarriedAlien") ~= nil
		or inst.Name == "CarriedMeteor"
end

local function hide(state: CloakState, inst: Instance)
	if state.Changed[inst] ~= nil or isCarriedLoot(inst) then
		return
	end
	if inst:IsA("BasePart") or inst:IsA("Decal") then
		local item = inst :: any -- beide haben Transparency
		state.Changed[inst] = item.Transparency
		item.Transparency = 1
	end
end

local function setOverheadTag(character: Model)
	local head = character:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("OverheadTag")
	if head and head:IsA("BasePart") and tag and tag:IsA("BillboardGui") then
		tag.Enabled = head.Transparency < 1
	end
end

-- Umhang beenden (Zeit um, Klauen, Respawn, Admin-Unsichtbar). Die Abklingzeit zählt ab JETZT.
-- silent = keine Nachricht
local function endCloak(player: Player, silent: boolean?)
	local state = cloaks[player]
	if not state then
		return
	end
	cloaks[player] = nil
	cloakReadyAt[player] = os.clock() + Config.CloakCooldown
	state.Conn:Disconnect()
	for inst, transparency in pairs(state.Changed) do
		if inst.Parent then
			(inst :: any).Transparency = transparency
		end
	end
	local humanoid = state.Humanoid
	if humanoid and humanoid.Parent and state.DisplayType then
		humanoid.DisplayDistanceType = state.DisplayType
	end
	setOverheadTag(state.Character)
	if player.Parent then
		player:SetAttribute("CloakedUntil", nil)
	end
	if not silent then
		Services.EconomyService.Notify(
			player,
			"👻 Du bist wieder sichtbar! (Umhang lädt " .. Config.CloakCooldown .. " s)",
			"Info"
		)
	end
end
GadgetService.EndCloak = endCloak

local function activateCloak(player: Player)
	if not useLimiter.Check(player) or not GadgetService.Owns(player, "Cloak") then
		return
	end
	if cloaks[player] then
		return -- schon unsichtbar
	end
	local t = os.clock()
	local readyAt = cloakReadyAt[player] or 0
	if t < readyAt then
		Services.EconomyService.Notify(player, "👻 Umhang lädt noch " .. math.ceil(readyAt - t) .. " s", "Error")
		return
	end
	if Services.CarryService.IsCarrying(player) then
		Services.EconomyService.Notify(player, "👻 Mit Beute geht der Umhang nicht – erst heimbringen!", "Error")
		return
	end
	local character, humanoid = aliveCharacter(player)
	if not character or not humanoid then
		return
	end
	-- (falls endCloak nie kommt, z.B. Fehler: spätestens dann wieder bereit)
	cloakReadyAt[player] = t + Config.CloakDuration + Config.CloakCooldown
	local state: CloakState = {
		Character = character,
		Changed = {},
		Conn = (nil :: any) :: RBXScriptConnection,
		Humanoid = humanoid,
		DisplayType = humanoid.DisplayDistanceType,
	}
	for _, inst in ipairs(character:GetDescendants()) do
		hide(state, inst)
	end
	-- Neu dazukommende Teile (Werkzeug in die Hand genommen ...) auch verstecken
	state.Conn = character.DescendantAdded:Connect(function(inst)
		hide(state, inst)
	end)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	setOverheadTag(character)
	cloaks[player] = state
	player:SetAttribute("CloakedUntil", workspace:GetServerTimeNow() + Config.CloakDuration)
	Services.EconomyService.Notify(
		player,
		"👻 " .. Config.CloakDuration .. " s unsichtbar – niemand kann dich bonken! (Klauen macht sichtbar)",
		"Success"
	)
	task.delay(Config.CloakDuration, function()
		if cloaks[player] == state then
			endCloak(player)
		end
	end)
end

-- -------------------------------------------------------------------
-- WERKZEUGE
-- -------------------------------------------------------------------
local function weld(part0: BasePart, part1: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part1
end

local function toolPart(tool: Tool, name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = tool
	return p
end

local function newTool(id: string, tip: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAMES[id] or id
	tool.ToolTip = tip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Gadget", id)
	return tool
end

local function buildTemplates()
	-- 🌀 Speed Coil: Griff mit leuchtenden Spiralringen
	local coil = newTool("SpeedCoil", "🌀 +30% Tempo, solange du sie hältst")
	local coilHandle =
		toolPart(coil, "Handle", Vector3.new(0.5, 2.2, 0.5), Color3.fromRGB(60, 60, 75), Enum.Material.Metal)
	for i = 1, 4 do
		local ring =
			toolPart(coil, "Ring", Vector3.new(0.25, 1.1, 1.1), Color3.fromRGB(0, 230, 255), Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.CFrame = coilHandle.CFrame * CFrame.new(0, -0.8 + i * 0.4, 0) * CFrame.Angles(0, 0, math.rad(90))
		weld(coilHandle, ring)
	end
	coil.Grip = CFrame.new(0, -0.4, 0)
	templates.SpeedCoil = coil

	-- 🪤 Falle: kleine Falle in der Hand
	local trapTool = newTool("Trap", "🪤 Klick in deiner Base = Falle aufstellen")
	local trapHandle =
		toolPart(trapTool, "Handle", Vector3.new(0.4, 1.6, 1.6), Color3.fromRGB(70, 70, 80), Enum.Material.DiamondPlate)
	trapHandle.Shape = Enum.PartType.Cylinder
	local trapRing =
		toolPart(trapTool, "Ring", Vector3.new(0.45, 1.1, 1.1), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	trapRing.Shape = Enum.PartType.Cylinder
	trapRing.CFrame = trapHandle.CFrame
	weld(trapHandle, trapRing)
	trapTool.Grip = CFrame.new(0, 0, -0.6) * CFrame.Angles(0, 0, math.rad(90))
	templates.Trap = trapTool

	-- 👻 Umhang: lila Stoffbündel
	local cloak = newTool("Cloak", "👻 Klick = unsichtbar (Abklingzeit beachten)")
	local cloakHandle =
		toolPart(cloak, "Handle", Vector3.new(1.2, 1.4, 0.5), Color3.fromRGB(120, 60, 200), Enum.Material.Fabric)
	local cloakGlow =
		toolPart(cloak, "Glow", Vector3.new(1.3, 0.2, 0.6), Color3.fromRGB(200, 150, 255), Enum.Material.Neon)
	cloakGlow.CFrame = cloakHandle.CFrame * CFrame.new(0, 0.6, 0)
	weld(cloakHandle, cloakGlow)
	templates.Cloak = cloak
end

-- Gibt das Werkzeug eines Gadgets (ohne Doppelte). Super-Bonk hat keins (Boost für den Schläger).
local function giveGadgetTool(player: Player, id: string)
	if id == "SuperBonk" then
		Services.CarryService.GiveBat(player) -- (Schläger bleibt derselbe, schlägt jetzt stärker)
		return
	end
	local template = templates[id]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not template or not backpack then
		return
	end
	if findGadgetTool(backpack, id) or findGadgetTool(player.Character, id) then
		return
	end
	local tool = template:Clone()
	if id == "Trap" then
		tool.Activated:Connect(function()
			placeTrap(player)
		end)
	elseif id == "Cloak" then
		tool.Activated:Connect(function()
			activateCloak(player)
		end)
	elseif id == "SpeedCoil" then
		-- In die Hand nehmen / weglegen -> Tempo neu berechnen
		tool.AncestryChanged:Connect(function()
			Services.EconomyService.ApplySpeed(player)
		end)
	end
	tool.Parent = backpack
end

-- Alle besessenen Gadgets als Werkzeug geben, nicht (mehr) besessene wegnehmen (z.B. nach Reset)
function GadgetService.GiveTools(player: Player)
	local character, humanoid = aliveCharacter(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not humanoid or not backpack or not Services.DataService.Get(player) then
		return
	end
	for _, gadget in ipairs(Config.Gadgets) do
		if GadgetService.Owns(player, gadget.Id) then
			giveGadgetTool(player, gadget.Id)
		else
			for _, container in ipairs({ backpack, character }) do
				local tool = findGadgetTool(container, gadget.Id)
				if tool then
					tool:Destroy()
				end
			end
		end
	end
	Services.CarryService.GiveBat(player) -- bester freigeschalteter Schläger (nie doppelt)
end

-- -------------------------------------------------------------------
-- KAUFEN / SCHENKEN
-- -------------------------------------------------------------------
-- Kauf mit Cash (Shop -> Request "BuyGadget"). Gibt (Erfolg, Nachricht) zurück.
function GadgetService.Buy(player: Player, id: any): (boolean, string)
	local gadget = type(id) == "string" and Config.GadgetsById[id] or nil
	if not gadget then
		return false, "Unbekanntes Gadget"
	end
	local data = Services.DataService.Get(player)
	if not data or not Services.EconomyService.IsReady(player) then
		return false, "Lädt noch... ⏳"
	end
	local owned = gadgetTable(data)
	if owned[gadget.Id] then
		return false, "✅ " .. gadget.Name .. " hast du schon!"
	end
	if data.Cash < gadget.Price then
		return false, "💸 Du brauchst " .. Util.FormatCash(gadget.Price) .. " für " .. gadget.Name .. "!"
	end
	data.Cash -= gadget.Price
	owned[gadget.Id] = true
	Services.EconomyService.MarkDirty(player)
	task.spawn(Services.DataService.Save, player) -- teurer Kauf -> gleich sichern
	giveGadgetTool(player, gadget.Id)
	Services.EconomyService.Effect(player, "Confetti", 1)
	if gadget.Id == "SuperBonk" then
		return true, gadget.Name .. " gekauft! Dein Schläger ist jetzt stärker."
	end
	return true, gadget.Icon .. " " .. gadget.Name .. " gekauft! Liegt in deinem Rucksack."
end

-- Geschenk (Admin, Starter-Paket): gehört dem Spieler danach für immer. true = hat geklappt
function GadgetService.Give(player: Player, id: any): boolean
	local gadget = type(id) == "string" and Config.GadgetsById[id] or nil
	local data = Services.DataService.Get(player)
	if not gadget or not data then
		return false
	end
	gadgetTable(data)[gadget.Id] = true
	Services.EconomyService.MarkDirty(player)
	giveGadgetTool(player, gadget.Id)
	return true
end
GadgetService.Grant = GadgetService.Give

-- -------------------------------------------------------------------
function GadgetService.Init(services)
	Services = services
	buildTemplates()
end

function GadgetService.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			endCloak(player, true) -- neuer Charakter ist sowieso sichtbar
			if player:WaitForChild("Backpack", 10) then
				GadgetService.GiveTools(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	-- Spielstand geladen -> gekaufte Gadgets sofort geben (nicht erst nach dem nächsten Spawn)
	Services.DataService.OnProfileLoaded(function(player: Player)
		GadgetService.GiveTools(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		endCloak(player, true)
		clearTraps(player)
		cloakReadyAt[player] = nil
		trapPlacedAt[player] = nil
		trapImmuneUntil[player] = nil
		useLimiter.Clear(player)
	end)

	-- Fallen selbst prüfen (Touched allein reicht nicht – das meldet der Client)
	task.spawn(function()
		while true do
			task.wait(TRAP_CHECK_INTERVAL)
			local ok, err = pcall(checkTraps)
			if not ok then
				warn("[GadgetService] Fallen-Prüfung: " .. tostring(err))
			end
		end
	end)

	-- Sicherheitsnetz: fehlende Werkzeuge nachreichen (z.B. Gadget per Spielstand geschenkt)
	task.spawn(function()
		while true do
			task.wait(SYNC_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(GadgetService.GiveTools, player)
				if not ok then
					warn("[GadgetService] Werkzeuge für " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return GadgetService
