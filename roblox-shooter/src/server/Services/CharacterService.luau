-- =====================================================================
--  CLUTCH CLASH – Figuren (Server/Services/CharacterService)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C5.4, B13.3, B14.8, C12.5, C12.6.
--  CharacterAdded-Einrichtung (Kollisionsgruppe LobbyPlayers, Accessoires nicht abfragbar + masselos,
--  Standard-Namensschild aus, BreakJointsOnDeath = false, eigenes Namensschild aus Player-Attributen),
--  CharacterAdded-Router (MatchService), Humanoid.Died-Fallback (= Pop), Pop/Unpop (Vault),
--  Freeze/Teleport (+ AntiCheat-Gnade), 3rd-Person-Waffen (4 Modelle an der rechten Hand), Krone, BaseSpeed.
--  Wir schreiben NIE Humanoid.Health = 0 und rufen NIE LoadCharacter während eines Matches.
--
--  Öffentliche API (C5.4):
--    CharacterService.SetRouter(fn)                       fn(p, char) -> ("Lobby" | "Vault" | "Spawn", CFrame?)
--    CharacterService.Teleport(target, cf)                PivotTo + AntiCheat.NoteTeleport
--    CharacterService.Freeze(c, on)                       HRP verankern (Prep/Admin)
--    CharacterService.Pop(c) / Unpop(c, at)               in den Vault des Kontexts / an den Spawn (+3 Y)
--    CharacterService.SetBaseSpeed(c, speed)              Attribut BaseSpeed (Modell + Spieler; Bots: WalkSpeed)
--    CharacterService.BuildGunVisuals(c) / ShowSlot(c, slot) / ClearGunVisuals(c)
--    CharacterService.SetNameplate(model, info)           Bots/Puppen (Spieler: automatisch aus Attributen)
--    CharacterService.SetHeadProp(model, "Crown" | nil)
--    CharacterService.InVault(p): boolean
--  Ergänzungen (von CombatService benutzt):
--    CharacterService.Arm(c) / Disarm(c)                  Gruppe Combatants/Bots bzw. zurück zu LobbyPlayers
--    CharacterService.SetGroup(model, group)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local CharacterService = {}
local Services: any

type Combatant = Types.Combatant
type SlotName = Types.SlotName
type Route = "Lobby" | "Vault" | "Spawn"
type Visuals = { Folder: Folder, Models: { [string]: Model }, Shown: string? }
type PlateInfo = {
	Name: string,
	Level: number,
	Title: string,
	Team: number?,
	IsBot: boolean,
	Crown: boolean?,
	Bounty: number?,
	Vip: boolean?,
	Supporter: boolean?,
}

local COMBAT: any = Config.Combat
local PLAYER: any = Config.Player
local SLOT_NAMES: { SlotName } = { "Primary", "Secondary", "Melee", "Utility" }
local GUN_SCALE = 0.8 -- 3rd-Person-Skala (B11.8)
local CHAR_WAIT = 10
local PLATE_NAME = "CC_Nameplate"
local GUNS_NAME = "CC_Guns"
local PROP_NAME = "CC_HeadProp"
local PLAYER_PLATE_ATTRS = { "Level", "Title", "Vip", "Supporter", "Bounty", "CrownStreak" }
local GOLD = Color3.fromRGB(255, 200, 40) -- Krone (Welt-Geometrie bleibt bunt)
-- AKYTEX-Farben (docs/STYLE-AKYTEX.md; der Server hat kein UI.Theme -> gleiche Hex-Werte als Konstanten)
local AKY_BG = Color3.fromRGB(11, 15, 23) -- AKYTEX-Farbe Bg #0b0f17
local AKY_BORDER = Color3.fromRGB(31, 41, 55) -- AKYTEX-Farbe Border #1f2937
local AKY_TEXT = Color3.fromRGB(230, 236, 245) -- AKYTEX-Farbe Text #e6ecf5
local AKY_TEXT2 = Color3.fromRGB(170, 180, 195) -- AKYTEX-Farbe Text2 #aab4c3
local AKY_MUTED = "#7d889a" -- AKYTEX-Farbe Muted (RichText für [BOT])
local AKY_ACCENT = Color3.fromRGB(79, 140, 255) -- AKYTEX-Farbe Accent #4f8cff (Team 1 / eigenes Team)
local AKY_DOWN = Color3.fromRGB(239, 68, 68) -- AKYTEX-Farbe Down #ef4444 (Team 2 / Gegner)
local AKY_WARN = Color3.fromRGB(234, 179, 8) -- AKYTEX-Farbe Warn #eab308 (VIP-Gold)
local PLATE_W, PLATE_H = 300, 50 -- BillboardGui (Pixel); die Glas-Tafel passt sich der Textbreite an

local router: ((Player, Model) -> (Route, CFrame?))? = nil
local inVault: { [Player]: boolean } = {}
local frozen: { [Combatant]: boolean } = {}
local visuals: { [Combatant]: Visuals } = {}
local groupOf: { [Model]: string } = {}
local charConns: { [Player]: { RBXScriptConnection } } = {}
local playerConns: { [Player]: { RBXScriptConnection } } = {}

local weaponModels: any = nil
local cosmeticModels: any = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local service = Services and Services[serviceName]
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

-- Shared-Module anderer Pakete erst bei Bedarf laden (fehlen sie, gibt es eben keine Modelle)
local function loadShared(name: string): any
	local module = Shared:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
		warn("[CharacterService] " .. name .. " konnte nicht geladen werden: " .. tostring(result))
	end
	return nil
end

local function getWeaponModels(): any
	if weaponModels == nil then
		weaponModels = loadShared("WeaponModels") or false
	end
	return weaponModels or nil
end

local function getCosmeticModels(): any
	if cosmeticModels == nil then
		cosmeticModels = loadShared("CosmeticModels") or false
	end
	return cosmeticModels or nil
end

local function noteTeleport(p: Player?, cf: CFrame)
	if p then
		call("AntiCheatService", "NoteTeleport", p, cf)
	end
end

local function zeroVelocity(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function setOwner(c: Combatant)
	local root = c.Root
	if root.Anchored or not root.Parent then
		return
	end
	if c.Player then
		pcall(root.SetNetworkOwner, root, c.Player)
	elseif c.Kind == "Bot" then
		pcall(root.SetNetworkOwner, root, nil) -- Bots: Server-Netzwerk-Besitz (C12.5)
	end
end

-- Teil einer Figur, das nie Kugeln/Berührung abfängt (Accessoires, Waffen, Krone)
local function isCosmeticPart(part: BasePart): boolean
	return part:FindFirstAncestorOfClass("Accessory") ~= nil
		or part:FindFirstAncestor(GUNS_NAME) ~= nil
		or part:FindFirstAncestor(PROP_NAME) ~= nil
end

local function prepCosmetic(part: BasePart)
	part.CanQuery = false
	part.CanTouch = false
	part.CanCollide = false
	part.Massless = true
	part.CastShadow = false
end

local function applyPart(model: Model, part: BasePart)
	if part:FindFirstAncestor(GUNS_NAME) or part:FindFirstAncestor(PROP_NAME) then
		prepCosmetic(part)
		part.CollisionGroup = "FX"
		return
	end
	if part:FindFirstAncestorOfClass("Accessory") then
		-- Accessoires blockieren keine Kopftreffer (B13.2)
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end
	local group = groupOf[model]
	if group then
		part.CollisionGroup = group
	end
end

-- ---------------------------------------------------------------------
-- KOLLISIONSGRUPPEN (C12.6)
-- ---------------------------------------------------------------------
function CharacterService.SetGroup(model: Model, group: string)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	groupOf[model] = group
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and not isCosmeticPart(part) then
			part.CollisionGroup = group
		end
	end
end

local function groupFor(c: Combatant): string?
	if c.Kind == "Player" then
		return "Combatants"
	elseif c.Kind == "Bot" then
		return "Bots"
	end
	return nil -- Puppen behalten ihre Gruppe (RangeService)
end

-- ---------------------------------------------------------------------
-- NAMENSSCHILD
-- ---------------------------------------------------------------------
local function plateHost(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return model.PrimaryPart
end

local function titleText(title: string): (string, Color3?)
	if title == "" then
		return "", nil
	end
	local titles: any = Config.Cosmetics and Config.Cosmetics.Titles
	local def = if type(titles) == "table" then titles[title] else nil
	if type(def) == "table" and type(def.Name) == "table" then
		-- Das Schild sehen alle -> neutrale englische Anzeige
		return tostring(def.Name.en or def.Name.de or title), if typeof(def.Color) == "Color3" then def.Color else nil
	end
	return string.sub(title, 1, 24), nil
end

-- AKYTEX-Text: BuilderSans, feste Größe (die Tafel wächst mit), feine Kontur über der 3D-Welt
local function makeLabel(name: string, parent: Instance, order: number, height: number, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.LayoutOrder = order
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, height)
	label.Font = font
	label.TextSize = height - 3
	label.RichText = true
	label.TextColor3 = AKY_TEXT
	label.TextStrokeTransparency = 0.6
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = ""
	label.Parent = parent
	return label
end

-- Dunkle Glas-Tafel (Bg, Transparenz 0.15) mit 1-px-Rahmen in Teamfarbe, Ecke 10, Name + Level/Titel
local function ensurePlate(model: Model): BillboardGui?
	local host = plateHost(model)
	if not host then
		return nil
	end
	local existing = host:FindFirstChild(PLATE_NAME)
	if existing and existing:IsA("BillboardGui") then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = PLATE_NAME
	gui.Size = UDim2.fromOffset(PLATE_W, PLATE_H)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Adornee = host
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.fromScale(0.5, 1)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.Size = UDim2.fromOffset(0, 0)
	panel.BackgroundColor3 = AKY_BG
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Thickness = 1
	edge.Color = AKY_BORDER
	edge.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 0)
	list.Parent = panel
	makeLabel("Name", panel, 1, 21, Enum.Font.BuilderSansBold)
	makeLabel("Sub", panel, 2, 16, Enum.Font.BuilderSans)
	panel.Parent = gui
	gui.Parent = host
	return gui
end

-- RichText ist an (graues [BOT]): Namen/Titel dürfen keine Tags einschleusen
local function escapeRich(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Teil eines Namensschilds (Labels liegen in "Panel")
local function plateChild(gui: Instance, name: string): Instance?
	return gui:FindFirstChild(name, true)
end

local function setPlateVisible(model: Model, visible: boolean)
	local host = plateHost(model)
	local gui = host and host:FindFirstChild(PLATE_NAME)
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = visible
	end
end

-- Rahmenfarbe nach Team (wie die Score-Kästen: Team 1 Accent, Team 2 Down); der Client färbt sie lokal
-- relativ zum Betrachter um (eigenes Team Accent, Gegner Down – Client/Modules/Replication)
local function teamColor(team: number?): Color3
	if team == 1 then
		return AKY_ACCENT
	elseif team == 2 then
		return AKY_DOWN
	end
	return AKY_BORDER
end

function CharacterService.SetNameplate(model: Model, info: PlateInfo)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or type(info) ~= "table" then
		return
	end
	local gui = ensurePlate(model)
	if not gui then
		return
	end
	local nameLabel = plateChild(gui, "Name") :: TextLabel?
	local subLabel = plateChild(gui, "Sub") :: TextLabel?
	local edge = plateChild(gui, "Edge") :: UIStroke?
	if not nameLabel or not subLabel or not nameLabel:IsA("TextLabel") or not subLabel:IsA("TextLabel") then
		return
	end
	local crown = info.Crown == true or model:GetAttribute("HeadProp") == "Crown"
	local prefix = (if info.IsBot then ('<font color="%s">[BOT]</font> '):format(AKY_MUTED) else "")
		.. (if crown then "👑 " else "")
	nameLabel.Text = prefix .. escapeRich(string.sub(tostring(info.Name or "?"), 1, 24))
	-- Name weiß; VIP-Name in Warn-Gold (B22.1 goldenes Namensschild, dezent)
	nameLabel.TextColor3 = if info.Vip and not info.IsBot then AKY_WARN else AKY_TEXT
	if edge and edge:IsA("UIStroke") then
		edge.Color = teamColor(info.Team)
	end
	local parts: { string } = {}
	local level = if Util.IsFinite(info.Level) then math.max(1, math.floor(info.Level)) else 1
	table.insert(parts, "Lv " .. level)
	local title, color = titleText(if type(info.Title) == "string" then info.Title else "")
	if title ~= "" then
		table.insert(parts, title)
	end
	local streak = model:GetAttribute("CrownStreak")
	if crown and Util.IsFinite(streak) and streak > 0 then
		table.insert(parts, "🔥" .. math.floor(streak))
	end
	if Util.IsFinite(info.Bounty) and (info.Bounty :: number) > 0 then
		table.insert(parts, "💰" .. Util.FormatNumber(info.Bounty :: number))
	end
	if info.Supporter then
		table.insert(parts, "♥")
	end
	subLabel.Text = escapeRich(table.concat(parts, " · "))
	subLabel.TextColor3 = color or AKY_TEXT2
end

local function refreshPlayerPlate(p: Player)
	local char = p.Character
	if not char then
		return
	end
	local c: Combatant? = nil
	local okC, found = call("CombatService", "OfPlayer", p)
	if okC then
		c = found
	end
	local streak = p:GetAttribute("CrownStreak")
	if Util.IsFinite(streak) then
		char:SetAttribute("CrownStreak", streak)
	end
	local level = p:GetAttribute("Level")
	local title = p:GetAttribute("Title")
	local bounty = p:GetAttribute("Bounty")
	CharacterService.SetNameplate(char, {
		Name = p.DisplayName,
		Level = if Util.IsFinite(level) then level else 1,
		Title = if type(title) == "string" then title else "",
		Team = if c and c.Model == char then c.Team else nil,
		IsBot = false,
		Bounty = if Util.IsFinite(bounty) then bounty else 0,
		Vip = p:GetAttribute("Vip") == true,
		Supporter = p:GetAttribute("Supporter") == true,
	})
	local host = plateHost(char)
	local gui = host and host:FindFirstChild(PLATE_NAME)
	if gui and gui:IsA("BillboardGui") then
		gui.PlayerToHideFrom = p -- das eigene Schild nicht über dem eigenen Kopf
		local popped = c ~= nil and c.Model == char and not c.Alive
		gui.Enabled = not popped
	end
end

local function refreshPlate(c: Combatant)
	if c.Player then
		refreshPlayerPlate(c.Player)
		return
	end
	-- Bots/Puppen: vorhandenes Schild behalten, nur Teamfarbe (Rahmen) nachziehen
	local host = plateHost(c.Model)
	local gui = host and host:FindFirstChild(PLATE_NAME)
	local edge = gui and plateChild(gui, "Edge")
	if edge and edge:IsA("UIStroke") and c.Kind == "Dummy" then
		edge.Color = teamColor(c.Team)
	end
end

-- ---------------------------------------------------------------------
-- KRONE (B4 Crown, 7 Teile, Foil-Gold)
-- ---------------------------------------------------------------------
local function crownPart(parent: Instance, shape: Enum.PartType, size: Vector3, cf: CFrame, neon: boolean?): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cf
	part.Material = if neon then Enum.Material.Neon else Enum.Material.Foil
	part.Color = if neon then Color3.fromRGB(255, 60, 170) else GOLD
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	prepCosmetic(part)
	part.Anchored = false
	part.Parent = parent
	return part
end

function CharacterService.SetHeadProp(model: Model, kind: "Crown" | nil)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local old = model:FindFirstChild(PROP_NAME)
	if old then
		old:Destroy()
	end
	local head = plateHost(model)
	if kind == "Crown" and head then
		local folder = Instance.new("Folder")
		folder.Name = PROP_NAME
		local top = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.2, 0)
		local band = crownPart(
			folder,
			Enum.PartType.Cylinder,
			Vector3.new(0.35, 1.5, 1.5),
			top * CFrame.Angles(0, 0, math.rad(90))
		)
		for i = 0, 4 do
			local angle = math.rad(i * 72)
			local offset = Vector3.new(math.sin(angle) * 0.62, 0.38, math.cos(angle) * 0.62)
			crownPart(folder, Enum.PartType.Ball, Vector3.new(0.34, 0.34, 0.34), top * CFrame.new(offset))
		end
		crownPart(folder, Enum.PartType.Ball, Vector3.new(0.3, 0.3, 0.3), top * CFrame.new(0, 0.02, -0.72), true)
		for _, part in ipairs(folder:GetChildren()) do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = head
				weld.Part1 = part
				weld.Parent = part
			end
		end
		band.Name = "Band"
		folder.Parent = model
		model:SetAttribute("HeadProp", "Crown")
	else
		model:SetAttribute("HeadProp", nil)
	end
	local p = Players:GetPlayerFromCharacter(model)
	if p then
		refreshPlayerPlate(p)
	end
end

-- ---------------------------------------------------------------------
-- 3RD-PERSON-WAFFEN (B14.8)
-- ---------------------------------------------------------------------
local function rightHand(model: Model): BasePart?
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand
	end
	return nil
end

local function hasJoints(model: Model): boolean
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			return true
		end
	end
	return false
end

local function attachGun(model: Model, hand: BasePart): boolean
	local grip = model:FindFirstChild("Grip", true)
	if not (grip and grip:IsA("Attachment")) then
		return false
	end
	local gripPart = grip.Parent
	if not (gripPart and gripPart:IsA("BasePart")) then
		return false
	end
	local needWelds = not hasJoints(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			prepCosmetic(part)
			part.Anchored = false
			part:SetAttribute("BaseT", part.Transparency)
			if needWelds and part ~= gripPart then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = gripPart
				wc.Part1 = part
				wc.Parent = part
			end
		end
	end
	local handGrip = hand:FindFirstChild("RightGripAttachment")
	local weld = Instance.new("Weld")
	weld.Name = "CC_GripWeld"
	weld.Part0 = hand
	weld.Part1 = gripPart
	weld.C0 = if handGrip and handGrip:IsA("Attachment")
		then handGrip.CFrame
		else CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	weld.C1 = grip.CFrame
	weld.Parent = gripPart
	return true
end

local function attachCharm(gun: Model, charmId: string)
	local cm = getCosmeticModels()
	if not cm or type(cm.BuildCharm) ~= "function" then
		return
	end
	local slot = gun:FindFirstChild("Charm", true)
	if not (slot and slot:IsA("Attachment") and slot.Parent and slot.Parent:IsA("BasePart")) then
		return
	end
	local ok, charm = pcall(cm.BuildCharm, charmId)
	if not ok or typeof(charm) ~= "Instance" or not charm:IsA("Model") then
		return
	end
	charm:ScaleTo(GUN_SCALE)
	charm:PivotTo(slot.WorldCFrame)
	local anchorPart = slot.Parent :: BasePart
	for _, part in ipairs(charm:GetDescendants()) do
		if part:IsA("BasePart") then
			prepCosmetic(part)
			part.Anchored = false
			part:SetAttribute("BaseT", part.Transparency)
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = anchorPart
			wc.Part1 = part
			wc.Parent = part
		end
	end
	charm.Name = "Charm"
	charm.Parent = gun
end

local function setModelVisible(model: Model, visible: boolean)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local base = part:GetAttribute("BaseT")
			part.Transparency = if visible then (if type(base) == "number" then base else 0) else 1
		end
	end
end

function CharacterService.ClearGunVisuals(c: Combatant)
	local v = visuals[c]
	visuals[c] = nil
	if v and v.Folder then
		v.Folder:Destroy()
	end
	if c and c.Model then
		local stray = c.Model:FindFirstChild(GUNS_NAME)
		if stray then
			stray:Destroy()
		end
	end
end

function CharacterService.ShowSlot(c: Combatant, slot: SlotName)
	local v = visuals[c]
	if c and c.Model then
		c.Model:SetAttribute("Equipped", slot)
	end
	if not v then
		return
	end
	local shown: string? = if c.Alive then slot else nil
	v.Shown = shown
	for name, model in pairs(v.Models) do
		setModelVisible(model, name == shown)
	end
end

local function hideGuns(c: Combatant)
	local v = visuals[c]
	if v then
		v.Shown = nil
		for _, model in pairs(v.Models) do
			setModelVisible(model, false)
		end
	end
end

function CharacterService.BuildGunVisuals(c: Combatant)
	if type(c) ~= "table" or not c.Model or not c.Model.Parent then
		return
	end
	CharacterService.ClearGunVisuals(c)
	local wm = getWeaponModels()
	local hand = rightHand(c.Model)
	if not wm or type(wm.Build) ~= "function" or not hand then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = GUNS_NAME
	local v: Visuals = { Folder = folder, Models = {} }
	for _, slot in ipairs(SLOT_NAMES) do
		local key = (c.Loadout :: any)[slot]
		local def = if type(key) == "string" then Config.Weapon(key) else nil
		if not def then
			continue
		end
		local cosmetics: any = {}
		if c.Player then
			local ok, result = call("ShopService", "GetCosmetics", c.Player, key)
			if ok and type(result) == "table" then
				cosmetics = result
			end
		end
		local skin = if type(cosmetics.Skin) == "string" and cosmetics.Skin ~= "" then cosmetics.Skin else nil
		local ok, gun = pcall(wm.Build, def.Model, { Skin = skin, Scale = GUN_SCALE, Viewmodel = false })
		if not ok or typeof(gun) ~= "Instance" or not gun:IsA("Model") then
			continue
		end
		local wrap = cosmetics.Wrap
		local cm = getCosmeticModels()
		if type(wrap) == "string" and wrap ~= "" and cm and type(cm.ApplyWrap) == "function" then
			pcall(cm.ApplyWrap, gun, wrap)
		end
		gun:PivotTo(hand.CFrame)
		if not attachGun(gun, hand) then
			gun:Destroy()
			continue
		end
		local charm = cosmetics.Charm
		if type(charm) == "string" and charm ~= "" then
			attachCharm(gun, charm)
		end
		gun.Name = slot
		gun.Parent = folder
		v.Models[slot] = gun
	end
	for _, model in pairs(v.Models) do
		setModelVisible(model, false)
	end
	folder.Parent = c.Model
	visuals[c] = v
	CharacterService.ShowSlot(c, c.Equipped)
end

-- ---------------------------------------------------------------------
-- BEWAFFNEN / ENTWAFFNEN (von CombatService.Register/Unregister)
-- ---------------------------------------------------------------------
function CharacterService.Arm(c: Combatant)
	if type(c) ~= "table" or not c.Model then
		return
	end
	local group = groupFor(c)
	if group then
		CharacterService.SetGroup(c.Model, group)
	end
	if c.Player then
		inVault[c.Player] = nil
	end
	refreshPlate(c)
end

function CharacterService.Disarm(c: Combatant)
	if type(c) ~= "table" then
		return
	end
	CharacterService.ClearGunVisuals(c)
	frozen[c] = nil
	local p = c.Player
	if not p then
		if c.Model then
			groupOf[c.Model] = nil -- Bot-/Puppen-Modelle räumt ihr Besitzer weg
		end
		return
	end
	local wasInVault = inVault[p] == true
	inVault[p] = nil
	local char = p.Character
	if not char or char ~= c.Model or not char.Parent then
		return
	end
	CharacterService.SetGroup(char, "LobbyPlayers")
	c.Root.Anchored = false
	setOwner(c)
	char:SetAttribute("BaseSpeed", PLAYER.Walk)
	p:SetAttribute("BaseSpeed", PLAYER.Walk)
	if wasInVault then
		-- aus dem Tresor nie in der Arena-Tiefe stehen lassen
		local ok, cf = call("ArenaService", "LobbySpawn")
		if ok and typeof(cf) == "CFrame" then
			CharacterService.Teleport(p, cf)
		end
	end
	refreshPlayerPlate(p)
end

-- ---------------------------------------------------------------------
-- BEWEGEN, VERANKERN, TRESOR
-- ---------------------------------------------------------------------
function CharacterService.Teleport(target: Player | Combatant, cf: CFrame)
	if typeof(cf) ~= "CFrame" then
		return
	end
	local model: Model? = nil
	local p: Player? = nil
	if typeof(target) == "Instance" and (target :: Instance):IsA("Player") then
		p = target :: Player
		model = (target :: Player).Character
	elseif type(target) == "table" then
		local c = target :: Combatant
		model = c.Model
		p = c.Player
	end
	if not model or not model.Parent then
		return
	end
	noteTeleport(p, cf) -- Gnade VOR dem Sprung (der Bewegungs-Check läuft parallel)
	model:PivotTo(cf)
	zeroVelocity(model)
end

function CharacterService.Freeze(c: Combatant, on: boolean)
	if type(c) ~= "table" or not c.Root or not c.Root.Parent then
		return
	end
	if on then
		frozen[c] = true
		c.Root.Anchored = true
		c.Root.AssemblyLinearVelocity = Vector3.zero
	else
		frozen[c] = nil
	end
	-- Gepoppte bleiben im Tresor verankert
	if not on and c.Alive and not (c.Player and inVault[c.Player]) then
		c.Root.Anchored = false
		setOwner(c)
		if c.Player then
			noteTeleport(c.Player, c.Root.CFrame)
		end
	end
end

local function vaultOffset(slot: number): CFrame
	local spacing = tonumber(COMBAT.VaultSpacing) or 3
	local index = math.max(0, math.floor(slot) - 1)
	local col = index % 8
	local row = math.floor(index / 8)
	return CFrame.new((col - 3.5) * spacing, 3, (row - 1.5) * spacing)
end

function CharacterService.Pop(c: Combatant)
	if type(c) ~= "table" or not c.Model then
		return
	end
	hideGuns(c)
	setPlateVisible(c.Model, false)
	if c.Kind == "Dummy" then
		return -- Puppen bleiben stehen (RangeService belebt sie wieder)
	end
	local okCtx, info = call("CombatService", "Context", c.Ctx)
	local arena: any = if okCtx and type(info) == "table" then info.Arena else nil
	CharacterService.SetGroup(c.Model, "Ghost")
	if not c.Root.Parent then
		return
	end
	c.Root.Anchored = true
	if arena and typeof(arena.Vault) == "CFrame" and c.Ctx ~= "Range" then
		local cf = arena.Vault * vaultOffset(c.Slot)
		noteTeleport(c.Player, cf)
		c.Model:PivotTo(cf)
	end
	c.Root.AssemblyLinearVelocity = Vector3.zero
	if c.Player then
		inVault[c.Player] = true
	end
end

function CharacterService.Unpop(c: Combatant, at: CFrame)
	if type(c) ~= "table" or not c.Model or typeof(at) ~= "CFrame" then
		return
	end
	local cf = if c.Kind == "Dummy" then at else at + Vector3.new(0, 3, 0) -- Puppen: genau an ihren Platz
	if c.Player then
		inVault[c.Player] = nil
	end
	if c.Root.Parent then
		noteTeleport(c.Player, cf)
		c.Model:PivotTo(cf)
		zeroVelocity(c.Model)
		local group = groupFor(c)
		if group then
			CharacterService.SetGroup(c.Model, group)
		end
		c.Root.Anchored = frozen[c] == true
		setOwner(c)
	end
	CharacterService.ShowSlot(c, c.Equipped)
	setPlateVisible(c.Model, true)
	refreshPlate(c)
end

function CharacterService.InVault(p: Player): boolean
	return inVault[p] == true
end

function CharacterService.SetBaseSpeed(c: Combatant, speed: number)
	if type(c) ~= "table" then
		return
	end
	local s = if Util.IsFinite(speed) then math.clamp(speed, 0, 150) else PLAYER.Walk
	if c.Model then
		c.Model:SetAttribute("BaseSpeed", s)
	end
	if c.Player then
		c.Player:SetAttribute("BaseSpeed", s)
	elseif c.Humanoid then
		c.Humanoid.WalkSpeed = s
	end
end

function CharacterService.SetRouter(fn: (p: Player, char: Model) -> (Route, CFrame?))
	if type(fn) == "function" then
		router = fn
	end
end

-- ---------------------------------------------------------------------
-- CHARACTERADDED
-- ---------------------------------------------------------------------
local function disconnectAll(list: { RBXScriptConnection }?)
	if list then
		for _, conn in ipairs(list) do
			conn:Disconnect()
		end
		table.clear(list)
	end
end

local function onDied(p: Player, char: Model)
	local ok, c = call("CombatService", "OfPlayer", p)
	if not ok or type(c) ~= "table" or c.Model ~= char or not c.Alive then
		return
	end
	-- Fallback (Exploit-Selbstmord): zählt als Pop, gutgeschrieben dem letzten Schadensverursacher ≤ 8 s
	local pos = if c.Root.Parent then c.Root.Position else Vector3.zero
	call("CombatService", "Eliminate", c, {
		WeaponKey = "Fallback",
		Head = false,
		Kind = "Fallback",
		Pos = pos,
	})
end

local function route(p: Player, char: Model, root: BasePart)
	local dest: Route = "Lobby"
	local cf: CFrame? = nil
	if router then
		local ok, d, target = pcall(router, p, char)
		if ok and (d == "Lobby" or d == "Vault" or d == "Spawn") then
			dest = d
			cf = if typeof(target) == "CFrame" then target else nil
		elseif not ok then
			warn("[CharacterService] Router-Fehler: " .. tostring(d))
		end
	end
	local okC, found = call("CombatService", "OfPlayer", p)
	local c: Combatant? = if okC and type(found) == "table" then found else nil
	if c and dest ~= "Lobby" then
		call("CombatService", "Rebind", c, char)
		CharacterService.Arm(c)
		CharacterService.BuildGunVisuals(c)
		if dest == "Vault" then
			-- Runde läuft: zuschauen (lebt der Combatant noch, zählt das als Fallback-Pop)
			if c.Alive then
				onDied(p, char)
			end
			CharacterService.Pop(c)
		else
			CharacterService.Unpop(c, cf or (root.CFrame - Vector3.new(0, 3, 0)))
		end
		return
	end
	-- Lobby
	CharacterService.SetGroup(char, "LobbyPlayers")
	char:SetAttribute("BaseSpeed", PLAYER.Walk)
	p:SetAttribute("BaseSpeed", PLAYER.Walk)
	if cf then
		CharacterService.Teleport(p, cf)
	end
end

local function onCharacter(p: Player, char: Model)
	local conns = charConns[p]
	if not conns then
		conns = {}
		charConns[p] = conns
	end
	disconnectAll(conns)

	local humanoid = char:WaitForChild("Humanoid", CHAR_WAIT)
	local root = char:WaitForChild("HumanoidRootPart", CHAR_WAIT)
	if not (humanoid and humanoid:IsA("Humanoid")) or not (root and root:IsA("BasePart")) then
		warn("[CharacterService] Figur ohne Humanoid/HRP: " .. p.Name)
		return
	end
	if p.Character ~= char or p.Parent ~= Players then
		return -- inzwischen ersetzt oder gegangen
	end
	char:WaitForChild("Head", CHAR_WAIT)
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = PLAYER.MaxHp
	if humanoid.Health > 0 then
		humanoid.Health = PLAYER.MaxHp
	end

	groupOf[char] = "LobbyPlayers"
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			applyPart(char, d)
		end
	end
	table.insert(
		conns,
		char.DescendantAdded:Connect(function(d: Instance)
			if d:IsA("BasePart") then
				applyPart(char, d)
			end
		end)
	)
	table.insert(
		conns,
		humanoid.Died:Connect(function()
			onDied(p, char)
		end)
	)
	table.insert(
		conns,
		char.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				groupOf[char] = nil
			end
		end)
	)

	route(p, char, root)
	refreshPlayerPlate(p)
end

local function onPlayer(p: Player)
	local conns: { RBXScriptConnection } = {}
	playerConns[p] = conns
	table.insert(
		conns,
		p.CharacterAdded:Connect(function(char: Model)
			onCharacter(p, char)
		end)
	)
	for _, attr in ipairs(PLAYER_PLATE_ATTRS) do
		table.insert(
			conns,
			p:GetAttributeChangedSignal(attr):Connect(function()
				refreshPlayerPlate(p)
			end)
		)
	end
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
end

function CharacterService.Init(services: any)
	Services = services
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p: Player)
		disconnectAll(charConns[p])
		disconnectAll(playerConns[p])
		charConns[p] = nil
		playerConns[p] = nil
		inVault[p] = nil
		if p.Character then
			groupOf[p.Character] = nil
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, p)
	end
end

return CharacterService
