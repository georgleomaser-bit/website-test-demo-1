-- =====================================================================
--  CLUTCH CLASH – Spind: Loadouts + Kosmetik pro Waffe (Client/Modules/Locker)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md B19, B22.1 (Loadout+), C7.4, C9.
--  Tab "Loadouts": Vorlagen wählen (3, +2 für Münzen, 8 mit Loadout+), pro Slot eine besessene Waffe
--  wählen, Umbenennen + "Zufall aus Favoriten" (Loadout+). Tab "Kosmetik": Waffe wählen, Drehteller-
--  Vorschau (ViewportFrame), Skin/Wrap/Charm pro Waffe, dazu Finisher (mit Vorschau), Tracer, Titel.
--  Der Server prüft alles noch einmal (Besitz, Meisterschafts-Stufe, Slot) – das UI zeigt nur an.
--
--  Öffentliche API (C7.4):
--    Locker.Open()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Util = require(Shared:WaitForChild("Util"))
local CosmeticModels = require(Shared:WaitForChild("CosmeticModels"))

local Locker = {}
local ctx: any = nil
local UI: any = nil

local COSMETICS: any = Config.Cosmetics
local SLOTS = { "Primary", "Secondary", "Melee", "Utility" }
local SLOT_FIELD: { [string]: string } = { Primary = "P", Secondary = "S", Melee = "M", Utility = "U" }
local TABS = { "Loadouts", "Cosmetics" }
local TAB_KEYS: { [string]: { string } } = {
	Loadouts = { "Loadouts", "Weapons", "Coins", "Passes" },
	Cosmetics = { "Cosmetics", "Weapons", "Passes", "Mastery" },
}
local SPIN_SPEED = 0.8 -- Drehteller: Radiant pro Sekunde
local FALLBACK_LOADOUT =
	{ Primary = "PopRifle", Secondary = "PipPistol", Melee = "BoxingGloves", Utility = "PopGrenade" }

local win: any = nil
local body: Frame? = nil
local tabButtons: { [string]: any } = {}
local currentTab = "Loadouts"
local selectedWeapon = "PopRifle"
local pending = false
local renderQueued = false
local viewport: ViewportFrame? = nil
local previewModel: Model? = nil
local spinConnection: RBXScriptConnection? = nil
local spinAngle = 0
local weaponModels: any = nil
local weaponModelsTried = false

-- =====================================================================
-- 1) HELFER
-- =====================================================================
local function lang(): "de" | "en"
	local ok, value = pcall(function()
		return ctx.Lang_()
	end)
	return if ok and value == "de" then "de" else "en"
end

local function t(key: string, ...: any): string
	return Lang.T(lang(), key, ...)
end

local function state(): { [string]: any }
	return if ctx and type(ctx.State) == "table" then ctx.State else {}
end

local function pick(name: any): string
	return if type(name) == "table" then Lang.Pick(lang(), name) else tostring(name)
end

local function rarityColor(rarity: any): Color3
	local colors = Config.Colors and Config.Colors.Rarity
	return colors and colors[rarity] or Color3.new(1, 1, 1)
end

local function hasPass(key: string): boolean
	local passes = state().Passes
	return type(passes) == "table" and passes[key] == true
end

local function cosmeticsState(): any
	local cos = state().Cosmetics
	if type(cos) ~= "table" then
		return { Owned = {}, Equipped = {}, PerWeapon = {} }
	end
	return {
		Owned = if type(cos.Owned) == "table" then cos.Owned else {},
		Equipped = if type(cos.Equipped) == "table" then cos.Equipped else {},
		PerWeapon = if type(cos.PerWeapon) == "table" then cos.PerWeapon else {},
	}
end

local function weaponList(): { any }
	local list = Config.Weapons and Config.Weapons.List
	local result = {}
	if type(list) == "table" then
		for _, def in ipairs(list) do
			if type(def) == "table" and not def.AdminOnly then
				table.insert(result, def)
			end
		end
	end
	table.sort(result, function(a, b)
		return (a.Id or 0) < (b.Id or 0)
	end)
	return result
end

local function ownsWeapon(def: any): boolean
	if def.Free then
		return true
	end
	local weapons = state().Weapons
	return type(weapons) == "table" and type(weapons.Owned) == "table" and weapons.Owned[def.Key] == true
end

local function masteryTier(weaponKey: string): number
	local mastery = state().Mastery
	local entry = type(mastery) == "table" and mastery[weaponKey]
	if type(entry) == "number" then
		return entry
	elseif type(entry) == "table" then
		return tonumber(entry.Tier) or tonumber(entry.T) or 0
	end
	return 0
end

-- Darf (laut State) benutzt werden? Server prüft endgültig.
local function canUse(id: string, weaponKey: string?): (boolean, string?)
	local def = COSMETICS.ById[id]
	if def == nil then
		return false, nil
	end
	if def.Source == "Default" then
		return true, nil
	elseif def.Source == "VIP" then
		return hasPass("VIP"), t("shop.lock.vip")
	elseif def.Source == "Mastery" then
		if def.Kind == "Wrap" then
			local need = tonumber(def.MasteryTier) or 99
			return weaponKey ~= nil and masteryTier(weaponKey) >= need, t("shop.lock.mastery", need)
		elseif def.Kind == "Title" and type(def.Weapon) == "string" then
			return cosmeticsState().Owned[id] == true or masteryTier(def.Weapon) >= 9, t("shop.lock.mastery", 9)
		end
	end
	return cosmeticsState().Owned[id] == true, nil
end

local function changedHas(changed: any, key: string): boolean
	if type(changed) ~= "table" then
		return true
	end
	return changed[key] == true or table.find(changed, key) ~= nil
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function request(action: string, arg: any, onOk: ((any) -> ())?)
	if pending then
		return
	end
	pending = true
	task.spawn(function()
		local ok, reply = pcall(ctx.RequestFull, action, arg, true) -- silent: Meldung zeigen wir selbst
		pending = false
		if not ok or type(reply) ~= "table" then
			ctx.Toast(t("shop.noAnswer"), "Error")
			return
		end
		if type(reply.Message) == "string" and reply.Message ~= "" then
			ctx.Toast(reply.Message, if reply.Ok then "Success" else "Error")
		end
		if reply.Ok and onOk then
			onOk(reply)
		end
	end)
end

local function label(parent: Instance, textValue: string, order: number, color: Color3?)
	return UI.Label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = textValue,
		TextColor3 = color or Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		Outline = 2,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function optionGrid(parent: Instance, order: number): Frame
	return UI.Grid(parent, order, 150, 46)
end

local function option(
	parent: Instance,
	order: number,
	textValue: string,
	color: Color3,
	selected: boolean,
	onClick: () -> ()
)
	UI.Button({
		Size = UDim2.fromOffset(150, 46),
		Text = (if selected then "✔ " else "") .. textValue,
		Color = if selected then UI.Theme.Green else color,
		MaxText = 15,
		LayoutOrder = order,
		Parent = parent,
	}, onClick)
end

-- =====================================================================
-- 2) TAB LOADOUTS
-- =====================================================================
local function loadoutsState(): any
	local lo = state().Loadouts
	if type(lo) ~= "table" then
		return { Active = 1, Slots = 3, Max = 3, Presets = {}, Plus = false }
	end
	return lo
end

local function presetLoadout(preset: any): { [string]: string }
	local result = table.clone(FALLBACK_LOADOUT)
	local defaults = Config.Weapons and Config.Weapons.DefaultLoadout
	if type(defaults) == "table" then
		for _, slot in ipairs(SLOTS) do
			if type(defaults[slot]) == "string" then
				result[slot] = defaults[slot]
			end
		end
	end
	if type(preset) == "table" then
		for _, slot in ipairs(SLOTS) do
			local key = preset[SLOT_FIELD[slot]]
			if type(key) == "string" then
				result[slot] = key
			end
		end
	end
	return result
end

local function buildLoadouts(root: Frame)
	local lo = loadoutsState()
	local active = tonumber(lo.Active) or 1
	local max = tonumber(lo.Max) or 3
	local presets = if type(lo.Presets) == "table" then lo.Presets else {}
	local plus = lo.Plus == true
	local row = UI.Row(root, 1, 48)
	for i = 1, max do
		local preset = presets[i]
		local name = if type(preset) == "table" and type(preset.Name) == "string"
			then preset.Name
			else ("Loadout " .. i)
		UI.Button({
			Size = UDim2.fromOffset(if max > 5 then 84 else 130, 44),
			Text = name,
			Color = if i == active then UI.Theme.Green else UI.Theme.Blue,
			MaxText = 14,
			LayoutOrder = i,
			Parent = row,
		}, function()
			if i ~= active then
				request("SelectPreset", i)
			end
		end)
	end
	local coinSlotsMax = tonumber(lo.CoinSlotsMax) or 5
	if not plus and (tonumber(lo.Slots) or 3) < coinSlotsMax then
		UI.Button({
			Size = UDim2.fromOffset(170, 44),
			Text = t("shop.presetBuy", Util.FormatNumber(tonumber(lo.SlotCoins) or 5000)),
			Color = UI.Theme.Orange,
			MaxText = 14,
			LayoutOrder = 20,
			Parent = row,
		}, function()
			request("BuyPresetSlot", nil)
		end)
	end
	-- Loadout+: Umbenennen + Zufall aus Favoriten
	local plusRow = UI.Row(root, 2, 46)
	if plus then
		local box = UI.TextBox({
			Size = UDim2.fromOffset(220, 40),
			PlaceholderText = t("shop.renameHint"),
			Text = "",
			LayoutOrder = 1,
			Parent = plusRow,
		})
		UI.Button({
			Size = UDim2.fromOffset(150, 42),
			Text = t("shop.rename"),
			Color = UI.Theme.Purple,
			LayoutOrder = 2,
			Parent = plusRow,
		}, function()
			request("RenamePreset", { Index = active, Name = string.sub(box.Text, 1, 64) })
		end)
		UI.Button({
			Size = UDim2.fromOffset(170, 42),
			Text = t("shop.randomPreset"),
			Color = UI.Theme.Cyan,
			LayoutOrder = 3,
			Parent = plusRow,
		}, function()
			request("RandomLoadout", nil)
		end)
	else
		label(plusRow, t("shop.plusHint"), 1, UI.Theme.SubText)
	end
	local current = presetLoadout(presets[active])
	local weapons = weaponList()
	if #weapons == 0 then
		label(root, t("shop.noWeapons"), 3)
		return
	end
	local order = 3
	for _, slot in ipairs(SLOTS) do
		label(root, t("shop.slot." .. slot), order, UI.Theme.Yellow)
		order += 1
		local g = optionGrid(root, order)
		order += 1
		local index = 0
		for _, def in ipairs(weapons) do
			if def.Slot == slot then
				index += 1
				local owned = ownsWeapon(def)
				local selected = current[slot] == def.Key
				local caption = pick(def.Name)
					.. (if owned then "" else (" 🔒" .. Util.FormatNumber(tonumber(def.Price) or 0)))
				option(g, index, caption, if owned then UI.Theme.Blue else UI.Theme.Gray, selected, function()
					if not owned then
						local shop = ctx.Modules and ctx.Modules.Shop
						if shop and type(shop.Open) == "function" then
							shop.Open("Weapons")
						end
						return
					end
					if selected then
						return
					end
					local loadout = table.clone(current)
					loadout[slot] = def.Key
					request("SetLoadout", { Index = active, Loadout = loadout })
				end)
			end
		end
	end
end

-- =====================================================================
-- 3) TAB KOSMETIK (mit Drehteller-Vorschau)
-- =====================================================================
local function getWeaponModels(): any
	if weaponModelsTried then
		return weaponModels
	end
	weaponModelsTried = true
	local module = Shared:FindFirstChild("WeaponModels")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			weaponModels = result
		end
	end
	return weaponModels
end

-- Ersatz-Modell, falls WeaponModels (WP4) fehlt: Spielzeug-Blaster mit oranger Spitze
local function fallbackModel(): Model
	local model = Instance.new("Model")
	local function add(
		name: string,
		role: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		shape: Enum.PartType?,
		material: Enum.Material?
	)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Shape = shape or Enum.PartType.Block
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanQuery = false
		p.CanTouch = false
		p.CanCollide = false
		p.CastShadow = false
		p:SetAttribute("Role", role)
		p.Parent = model
		return p
	end
	local bodyPart = add("Body", "Body", Vector3.new(0.5, 0.6, 2.2), CFrame.new(), Color3.fromRGB(154, 209, 212))
	add(
		"Barrel",
		"Metal",
		Vector3.new(1.2, 0.25, 0.25),
		CFrame.new(0, 0.1, -1.6) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(200, 205, 215),
		Enum.PartType.Cylinder,
		Enum.Material.Foil
	)
	add(
		"Tip",
		"Tip",
		Vector3.new(0.2, 0.3, 0.3),
		CFrame.new(0, 0.1, -2.25) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(255, 120, 0),
		Enum.PartType.Cylinder,
		Enum.Material.Neon
	)
	add("Mag", "Detail", Vector3.new(0.3, 0.7, 0.4), CFrame.new(0, -0.55, -0.2), Color3.fromRGB(244, 235, 221))
	add(
		"Grip",
		"Grip",
		Vector3.new(0.3, 0.7, 0.4),
		CFrame.new(0, -0.5, 0.6) * CFrame.Angles(math.rad(-15), 0, 0),
		Color3.fromRGB(43, 43, 51)
	)
	add(
		"Stripe",
		"Accent",
		Vector3.new(0.05, 0.1, 1.6),
		CFrame.new(0.27, 0.1, 0),
		Color3.fromRGB(90, 230, 200),
		nil,
		Enum.Material.Neon
	)
	local charm = Instance.new("Attachment")
	charm.Name = "Charm"
	charm.Position = Vector3.new(0.3, -0.1, 0.4)
	charm.Parent = bodyPart
	model.PrimaryPart = bodyPart
	return model
end

local function stopSpin()
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

local function buildPreview(cos: { Skin: string, Wrap: string, Charm: string })
	local frame = viewport
	if frame == nil then
		return
	end
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	local model: Model? = nil
	local wm = getWeaponModels()
	if wm and type(wm.Build) == "function" then
		local weaponDef = Config.Weapon(selectedWeapon)
		local modelKey = if weaponDef and type(weaponDef.Model) == "string" then weaponDef.Model else selectedWeapon
		local ok, result =
			pcall(wm.Build, modelKey, { Skin = if cos.Skin ~= "" then cos.Skin else nil, Scale = 1, Viewmodel = false })
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			model = result
		end
	end
	local m = model or fallbackModel()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	CosmeticModels.ApplyWrap(m, cos.Wrap)
	if cos.Charm ~= "" then
		local charm = CosmeticModels.BuildCharm(cos.Charm)
		local attach = m:FindFirstChild("Charm", true)
		local at = if attach and attach:IsA("Attachment")
			then attach.WorldCFrame
			else m:GetPivot() * CFrame.new(0.3, -0.1, 0.4)
		for _, d in ipairs(charm:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		charm:PivotTo(at)
		charm.Parent = m
	end
	m.Parent = frame
	previewModel = m
	local size = m:GetExtentsSize()
	local radius = math.max(size.X, size.Y, size.Z, 1)
	local camera = frame.CurrentCamera
	if camera == nil then
		local created = Instance.new("Camera")
		created.FieldOfView = 40
		created.Parent = frame
		frame.CurrentCamera = created
		camera = created
	end
	local center = m:GetPivot().Position
	local cam = camera :: Camera
	cam.CFrame = CFrame.lookAt(center + Vector3.new(radius * 1.6, radius * 0.5, 0), center)
	local base = m:GetPivot()
	stopSpin()
	spinConnection = RunService.PreRender:Connect(function(dt: number)
		if not (win and win.IsOpen) or previewModel ~= m or m.Parent == nil then
			stopSpin()
			return
		end
		spinAngle = (spinAngle + dt * SPIN_SPEED) % (math.pi * 2)
		m:PivotTo(CFrame.new(base.Position) * CFrame.Angles(0, spinAngle, 0) * base.Rotation)
	end)
end

local function equip(kind: string, id: string, weaponKey: string?)
	request("EquipCosmetic", { Kind = kind, Id = id, Weapon = weaponKey })
end

local function listFor(kind: string, weaponKey: string?): { string }
	local ids: { string } = {}
	for id, def in pairs(COSMETICS.ById) do
		if def.Kind == kind then
			if kind ~= "Skin" or def.Weapon == weaponKey then
				local usable = canUse(id, weaponKey)
				-- Meisterschafts-Wraps zeigen wir auch gesperrt (als Ziel), alles andere nur, wenn besessen
				if usable or (def.Source == "Mastery" and kind == "Wrap") then
					table.insert(ids, id)
				end
			end
		end
	end
	table.sort(ids, function(a, b)
		local ra = COSMETICS.RarityRank[COSMETICS.ById[a].Rarity] or 0
		local rb = COSMETICS.RarityRank[COSMETICS.ById[b].Rarity] or 0
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return ids
end

local function cosmeticSection(
	root: Frame,
	order: number,
	kind: string,
	current: string,
	weaponKey: string?,
	allowNone: boolean
): number
	label(root, t("item.kinds." .. kind), order, UI.Theme.Yellow)
	order += 1
	local g = optionGrid(root, order)
	order += 1
	local index = 0
	if allowNone then
		index += 1
		option(g, index, t("shop.none"), UI.Theme.Gray, current == "", function()
			if current ~= "" then
				equip(kind, "", weaponKey)
			end
		end)
	end
	for _, id in ipairs(listFor(kind, weaponKey)) do
		index += 1
		local def = COSMETICS.ById[id]
		local usable, lockText = canUse(id, weaponKey)
		local caption = pick(def.Name) .. (if usable then "" else " 🔒")
		option(
			g,
			index,
			caption,
			if usable then rarityColor(def.Rarity):Lerp(Color3.new(0, 0, 0), 0.25) else UI.Theme.Gray,
			current == id,
			function()
				if not usable then
					ctx.Toast(lockText or t("shop.notOwnedHint"), "Info")
					return
				end
				if current ~= id then
					equip(kind, id, weaponKey)
				end
			end
		)
		if kind == "Finisher" then
			index += 1
			option(g, index, "▶ " .. t("shop.preview"), UI.Theme.Cyan, false, function()
				local finishers = ctx.Modules and ctx.Modules.Finishers
				if finishers and type(finishers.Preview) == "function" then
					finishers.Preview(id)
				end
			end)
		end
	end
	if index == 0 then
		label(root, t("shop.nothingOwned"), order, UI.Theme.SubText)
		order += 1
	end
	return order
end

local function buildCosmetics(root: Frame)
	local weapons = weaponList()
	local owned: { any } = {}
	for _, def in ipairs(weapons) do
		if ownsWeapon(def) then
			table.insert(owned, def)
		end
	end
	local keys: { string } = {}
	if #owned > 0 then
		for _, def in ipairs(owned) do
			table.insert(keys, def.Key)
		end
	else
		keys = table.clone(COSMETICS.WeaponKeys)
	end
	if not table.find(keys, selectedWeapon) then
		selectedWeapon = keys[1] or "PopRifle"
	end
	label(root, t("shop.pickWeapon"), 1, UI.Theme.Yellow)
	local g = UI.Grid(root, 2, 120, 40)
	for i, key in ipairs(keys) do
		local def = Config.Weapon(key)
		UI.Button({
			Size = UDim2.fromOffset(120, 40),
			Text = if def then pick(def.Name) else key,
			Color = if key == selectedWeapon then UI.Theme.Green else UI.Theme.Blue,
			MaxText = 14,
			LayoutOrder = i,
			Parent = g,
		}, function()
			if selectedWeapon ~= key then
				selectedWeapon = key
				Locker.Refresh()
			end
		end)
	end
	local cos = cosmeticsState()
	local per = cos.PerWeapon[selectedWeapon]
	local current = {
		Skin = if type(per) == "table" and type(per.Skin) == "string" then per.Skin else "",
		Wrap = if type(per) == "table" and type(per.Wrap) == "string" then per.Wrap else "",
		Charm = if type(per) == "table" and type(per.Charm) == "string" then per.Charm else "",
	}
	local previewHolder = UI.Card({ Size = UDim2.new(1, 0, 0, 220), LayoutOrder = 3, Parent = root })
	viewport = UI.Create("ViewportFrame", {
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -0.5),
		Parent = previewHolder,
	})
	local okPreview, errPreview = pcall(buildPreview, current)
	if not okPreview then
		warn("[Locker] Vorschau: " .. tostring(errPreview))
	end
	local order = 4
	order = cosmeticSection(root, order, "Skin", current.Skin, selectedWeapon, true)
	order = cosmeticSection(root, order, "Wrap", current.Wrap, selectedWeapon, true)
	order = cosmeticSection(root, order, "Charm", current.Charm, selectedWeapon, true)
	local equipped = cos.Equipped
	order =
		cosmeticSection(root, order, "Finisher", tostring(equipped.Finisher or COSMETICS.Defaults.Finisher), nil, false)
	order = cosmeticSection(root, order, "Tracer", tostring(equipped.Tracer or COSMETICS.Defaults.Tracer), nil, false)
	cosmeticSection(root, order, "Title", tostring(equipped.Title or ""), nil, true)
end

-- =====================================================================
-- 4) FENSTER
-- =====================================================================
local function render()
	local root = body
	if not root or not win then
		return
	end
	stopSpin()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	viewport = nil
	clear(root)
	for name, button in pairs(tabButtons) do
		button.SetColor(if name == currentTab then UI.Theme.Orange else UI.Theme.Blue)
	end
	local ok, err = pcall(if currentTab == "Loadouts" then buildLoadouts else buildCosmetics, root)
	if not ok then
		warn("[Locker] Tab " .. currentTab .. ": " .. tostring(err))
	end
end

function Locker.Refresh()
	if win and win.IsOpen then
		render()
	end
end

local function ensureWindow()
	if win then
		return
	end
	win = UI.Window(t("shop.locker.title"), 800, 560, UI.Theme.Purple)
	local tabRow = UI.Row(win.Content, 1, 46)
	for i, name in ipairs(TABS) do
		tabButtons[name] = UI.Button({
			Size = UDim2.fromOffset(180, 42),
			Text = t("shop.locker.tab." .. name),
			Color = UI.Theme.Blue,
			MaxText = 16,
			LayoutOrder = i,
			Parent = tabRow,
		}, function()
			if currentTab ~= name then
				currentTab = name
				render()
			end
		end)
	end
	body = UI.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = win.Content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
end

local function openWindow()
	ensureWindow()
	render()
	UI.OpenWindow(win)
end

local function closeWindow()
	stopSpin()
end

function Locker.Open()
	if ctx.Windows.IsOpen("Locker") then
		render()
	else
		ctx.Windows.Open("Locker")
	end
end

local function onState(_state: any, changed: any)
	if not (win and win.IsOpen) then
		return
	end
	local relevant = false
	for _, key in ipairs(TAB_KEYS[currentTab] or {}) do
		if changedHas(changed, key) then
			relevant = true
			break
		end
	end
	if relevant and not renderQueued then
		renderQueued = true
		task.delay(0.15, function()
			renderQueued = false
			Locker.Refresh()
		end)
	end
end

function Locker.Init(c: any)
	ctx = c
	UI = c.UI
end

function Locker.Start()
	ctx.Windows.Register("Locker", openWindow, closeWindow)
	CosmeticModels.StartAnimator() -- animierte Wraps in Vorschau, Viewmodel und 3rd Person
	local modules = ctx.Modules or {}
	local hud = modules.Hud
	if hud and type(hud.AddRightButton) == "function" then
		pcall(hud.AddRightButton, "🎒", "shop.hud.locker", UI.Theme.Purple, 21, function()
			ctx.Windows.Open("Locker")
		end)
	end
	-- Taste L / Gamepad: Loadout-Fenster (auch in der Vorbereitungsphase eines Matches)
	local controls = modules.Controls
	if controls and type(controls.Bind) == "function" then
		pcall(controls.Bind, "Loadout", function(inputState: string)
			if inputState ~= "Begin" then
				return
			end
			if ctx.Windows.IsOpen("Locker") then
				ctx.Windows.Close("Locker")
			else
				currentTab = "Loadouts"
				ctx.Windows.Open("Locker")
			end
		end)
	end
	ctx.Hooks.On("State", onState)
end

return Locker
