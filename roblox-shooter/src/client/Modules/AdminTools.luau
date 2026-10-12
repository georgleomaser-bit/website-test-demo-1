-- =====================================================================
--  CLUTCH CLASH – Admin-Kräfte auf dem Client (Client/Modules/AdminTools)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md B25.2/B25.3 (Kräfte), B14.4, docs/ADMIN-WUENSCHE.md.
--  Nur für den Besitzer (Modul lädt nur bei IsAdmin). Alle Kräfte sind Attribute am eigenen Player, die NUR der
--  Server setzt (SetPower) – und der Server ehrt sie nur bei IsAdmin. Hier passiert nur die lokale Seite:
--    * ESP / Wallhack (AdminESP): ≤ 20 Highlights über den zentralen Verteiler "Highlights" (AlwaysOnTop) +
--      Name, Leben und Abstand über dem Kopf.
--    * Sichtbarer Aimbot (AdminAimbot): zieht die Kamera sanft auf den Kopf des nächsten sichtbaren Gegners,
--      solange Zielen oder Feuern gehalten wird (über FpsCamera.AddLookDelta, Vorzeichen wird selbst erkannt).
--    * Silent Aim (AdminSilentAim) / Triggerbot (AdminTriggerbot): AdminTools.AimTarget() / AdminTools.WantsFire()
--      für den Feuer-Haken von WeaponClient (WP4); Hook "AdminTrigger"(on) bei jeder Änderung.
--    * Noclip lokal (AdminNoclip), Tempo (AdminSpeed) und Super-Sprung (AdminJump) am eigenen Humanoid.
--    * Rotes Schild "TAINTED / Admin-Show", solange das aktuelle Match getaintet ist (Attribut TaintedMatch) –
--      nur als Ersatz, falls MatchUI fehlt (MatchUI zeigt dafür den roten "ADMIN-SHOW"-Chip in Intro + HUD).
--    (Lobby-Licht-Event "LobbyLook" wendet ArenaLook für alle Spieler an – hier nicht noch einmal.)
--  Look (docs/STYLE-AKYTEX.md): ESP-Schilder BuilderSansBold mit feiner Kontur in Down (Gegner-Markierung).
--
--  Öffentliche API:
--    AdminTools.WantsFire(): boolean                 Triggerbot: Fadenkreuz liegt auf einem Gegner
--    AdminTools.AimTarget(): (number?, Vector3?)     Silent Aim/Aimbot: CombatantId + Kopfposition des Ziels
--    AdminTools.Init(ctx) / AdminTools.Start()
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AdminTools = {}

local player = Players.LocalPlayer
local ctx: any = nil

local ESP_OWNER = "AdminESP"
local ESP_MAX = 20
local ESP_HZ = 4
local ESP_RANGE = 2000
local ESP_COLOR = Color3.fromRGB(239, 68, 68) -- AKYTEX Down (#ef4444): Gegner-Markierung
local TEXT_COLOR = Color3.fromRGB(230, 236, 245) -- AKYTEX Text (#e6ecf5)
local AIM_CONE = math.rad(25) -- sichtbarer Aimbot: nur Ziele in diesem Kegel um das Fadenkreuz
local AIM_SPEED = 14 -- je größer, desto schneller rastet die Kamera ein
local AIM_RANGE = 500
local SILENT_CONE = math.rad(60)
local TRIGGER_RANGE = 1000
local FLIP_COOLDOWN = 0.5

type Target = { Model: Model, Id: number, Head: BasePart, Root: BasePart }
type EspSlot = { Gui: BillboardGui, Label: TextLabel, Model: Model?, Handle: any? }

local armedInfo: { Ctx: string?, Team: number? }? = nil
local photoHidden = false
local wantsFire = false
local aimTarget: Target? = nil

local espSlots: { EspSlot } = {}
local espAcc = 0
local espActive = false

local noclipParts: { [BasePart]: boolean } = {}
local speedOverridden = false
local jumpOverridden = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local signX, signY = 1, 1
local lastErrX, lastErrY = 0, 0
local lastFlipX, lastFlipY = 0, 0
local applied = false

local taintSign: TextLabel? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function module(name: string): any
	local modules = ctx and ctx.Modules
	return if type(modules) == "table" then modules[name] else nil
end

local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function power(name: string): any
	if player:GetAttribute("IsAdmin") ~= true then
		return nil
	end
	return player:GetAttribute(name)
end

local function fireHook(name: string, ...: any)
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.Fire) == "function" then
		hooks.Fire(name, ...)
	end
end

local function isArmed(): boolean
	local weapon = module("WeaponClient")
	if weapon and type(weapon.IsArmed) == "function" then
		local ok, result = pcall(weapon.IsArmed)
		if ok then
			return result == true
		end
	end
	return armedInfo ~= nil
end

local function aimingHeld(): boolean
	local controls = module("Controls")
	if controls and type(controls.IsDown) == "function" then
		local okAds, ads = pcall(controls.IsDown, "Ads")
		local okFire, fire = pcall(controls.IsDown, "Fire")
		return (okAds and ads == true) or (okFire and fire == true)
	end
	return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
end

-- Alle Modelle, die Combatants sein können (Spieler, Bots, Übungspuppen)
local function candidateModels(): { Model }
	local list: { Model } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, tag in ipairs({ "Bot", "Dummy" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsA("Model") and not table.find(list, inst) then
				table.insert(list, inst)
			end
		end
	end
	return list
end

-- Gegner im eigenen Kontext? (bewaffnet: gleicher Ctx, anderes Team bzw. FFA; Lobby: jeder andere Spieler)
local function isEnemy(model: Model): boolean
	if model == player.Character then
		return false
	end
	if model:GetAttribute("Alive") == false then
		return false
	end
	local info = armedInfo
	if not info or not info.Ctx then
		return Players:GetPlayerFromCharacter(model) ~= nil
	end
	if model:GetAttribute("Ctx") ~= info.Ctx then
		return false
	end
	local team = model:GetAttribute("Team")
	local myTeam = info.Team or 0
	return myTeam == 0 or team == nil or team ~= myTeam
end

local function targetOf(model: Model): Target?
	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart")
	local id = model:GetAttribute("CombatantId")
	if head and root and head:IsA("BasePart") and root:IsA("BasePart") and type(id) == "number" then
		return { Model = model, Id = id, Head = head, Root = root }
	end
	return nil
end

local filterCharacter: Model? = nil
local filterCamera: Camera? = nil

local function refreshRayFilter()
	local camera = workspace.CurrentCamera
	if player.Character == filterCharacter and camera == filterCamera then
		return
	end
	filterCharacter = player.Character
	filterCamera = camera
	local list: { Instance } = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	if camera then
		table.insert(list, camera)
	end
	rayParams.ExcludeInstances = list
end

local function visible(target: Target, from: Vector3): boolean
	local direction = target.Head.Position - from
	if direction.Magnitude > AIM_RANGE * 2 then
		return false
	end
	local result = workspace:Raycast(from, direction, rayParams)
	if not result then
		return true
	end
	return result.Instance:IsDescendantOf(target.Model)
end

-- Gegner mit dem kleinsten Winkel zum Fadenkreuz (optional nur sichtbare)
local function bestTarget(cone: number, needVisible: boolean): Target?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local cf = camera.CFrame
	local best: Target? = nil
	local bestAngle = cone
	for _, model in ipairs(candidateModels()) do
		if isEnemy(model) then
			local target = targetOf(model)
			if target then
				local offset = target.Head.Position - cf.Position
				local dist = offset.Magnitude
				if dist > 0.5 and dist <= AIM_RANGE then
					local angle = math.acos(math.clamp(cf.LookVector:Dot(offset.Unit), -1, 1))
					if angle < bestAngle and (not needVisible or visible(target, cf.Position)) then
						best = target
						bestAngle = angle
					end
				end
			end
		end
	end
	return best
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- ---------------------------------------------------------------------
-- AIMBOT (sichtbar, sanft)
-- ---------------------------------------------------------------------
local function aimStep(dt: number, target: Target)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cf = camera.CFrame
	local dir = (target.Head.Position - cf.Position).Unit
	local look = cf.LookVector
	local errX = wrapAngle(math.atan2(-dir.X, -dir.Z) - math.atan2(-look.X, -look.Z)) -- + = Ziel links
	local errY = math.asin(math.clamp(dir.Y, -1, 1)) - math.asin(math.clamp(look.Y, -1, 1)) -- + = Ziel oben
	local alpha = 1 - math.exp(-AIM_SPEED * math.clamp(dt, 0, 0.1))
	local camera3 = module("FpsCamera")
	if camera3 and type(camera3.AddLookDelta) == "function" then
		-- Vorzeichen selbst erkennen: wurde der Fehler nach dem letzten Schritt deutlich größer -> umdrehen
		local now = os.clock()
		if applied then
			if math.abs(lastErrX) > 0.01 and math.abs(errX) > math.abs(lastErrX) * (1 + alpha * 0.5) then
				if now - lastFlipX > FLIP_COOLDOWN then
					signX = -signX
					lastFlipX = now
				end
			end
			if math.abs(lastErrY) > 0.01 and math.abs(errY) > math.abs(lastErrY) * (1 + alpha * 0.5) then
				if now - lastFlipY > FLIP_COOLDOWN then
					signY = -signY
					lastFlipY = now
				end
			end
		end
		-- Maus-Konvention: positives dx dreht nach rechts, positives dy nach unten
		pcall(camera3.AddLookDelta, -errX * alpha * signX, -errY * alpha * signY)
		applied = true
	else
		camera.CFrame = cf:Lerp(CFrame.lookAt(cf.Position, target.Head.Position), alpha)
		applied = false
	end
	lastErrX, lastErrY = errX, errY
end

-- ---------------------------------------------------------------------
-- TRIGGERBOT
-- ---------------------------------------------------------------------
local function crosshairOnEnemy(): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local cf = camera.CFrame
	local result = workspace:Raycast(cf.Position, cf.LookVector * TRIGGER_RANGE, rayParams)
	if not result then
		return false
	end
	local model = result.Instance:FindFirstAncestorWhichIsA("Model")
	while model and model:GetAttribute("CombatantId") == nil do
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return model ~= nil and isEnemy(model)
end

local function setWantsFire(on: boolean)
	if wantsFire ~= on then
		wantsFire = on
		fireHook("AdminTrigger", on)
	end
end

-- ---------------------------------------------------------------------
-- ESP (≤ 20, über Highlights)
-- ---------------------------------------------------------------------
local function espSlot(index: number): EspSlot
	local slot = espSlots[index]
	if slot then
		return slot
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CC_AdminESP"
	gui.Size = UDim2.fromOffset(180, 34)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = ESP_RANGE
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.BuilderSansBold
	label.TextScaled = true
	label.TextColor3 = ESP_COLOR:Lerp(TEXT_COLOR, 0.25)
	label.Text = ""
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 18
	sizeLimit.Parent = label
	-- feine Kontur über der 3D-Welt (AKYTEX: 1 px, halb durchsichtig) statt dicker schwarzer Kante
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = player:FindFirstChildOfClass("PlayerGui")
	local created: EspSlot = { Gui = gui, Label = label, Model = nil, Handle = nil }
	espSlots[index] = created
	return created
end

local function releaseSlot(slot: EspSlot)
	local highlights = module("Highlights")
	if slot.Handle ~= nil and highlights and type(highlights.Release) == "function" then
		pcall(highlights.Release, slot.Handle)
	end
	slot.Handle = nil
	slot.Model = nil
	slot.Gui.Enabled = false
	slot.Gui.Adornee = nil :: any
end

local function clearEsp()
	for _, slot in ipairs(espSlots) do
		releaseSlot(slot)
	end
	local highlights = module("Highlights")
	if highlights and type(highlights.ReleaseOwner) == "function" then
		pcall(highlights.ReleaseOwner, ESP_OWNER)
	end
	espActive = false
end

local function updateEsp()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local list: { { Target: Target, Dist: number } } = {}
	for _, model in ipairs(candidateModels()) do
		if isEnemy(model) then
			local target = targetOf(model)
			if not target then
				-- Lobby-Spieler ohne Combatant-Id: trotzdem zeigen
				local head = model:FindFirstChild("Head")
				local root = model:FindFirstChild("HumanoidRootPart")
				if head and root and head:IsA("BasePart") and root:IsA("BasePart") then
					target = { Model = model, Id = 0, Head = head, Root = root }
				end
			end
			if target then
				local dist = (target.Root.Position - camPos).Magnitude
				if dist <= ESP_RANGE then
					table.insert(list, { Target = target, Dist = dist })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Dist < b.Dist
	end)
	local highlights = module("Highlights")
	local used = math.min(#list, ESP_MAX)
	-- erst alle Slots freigeben, deren Modell nicht mehr dabei ist
	local wanted: { [Model]: number } = {}
	for i = 1, used do
		wanted[list[i].Target.Model] = i
	end
	for _, slot in ipairs(espSlots) do
		if slot.Model and not wanted[slot.Model] then
			releaseSlot(slot)
		end
	end
	for i = 1, used do
		local entry = list[i]
		local model = entry.Target.Model
		local slot: EspSlot? = nil
		for _, s in ipairs(espSlots) do
			if s.Model == model then
				slot = s
				break
			end
		end
		if not slot then
			for index = 1, ESP_MAX do
				local s = espSlot(index)
				if s.Model == nil then
					slot = s
					break
				end
			end
		end
		if slot then
			if slot.Model ~= model then
				slot.Model = model
				slot.Gui.Adornee = entry.Target.Head
				if highlights and type(highlights.Acquire) == "function" then
					local ok, handle = pcall(highlights.Acquire, ESP_OWNER, model, {
						Outline = ESP_COLOR,
						Fill = ESP_COLOR,
						FillTransparency = 0.75,
						Depth = Enum.HighlightDepthMode.AlwaysOnTop,
					})
					slot.Handle = if ok then handle else nil
				end
			end
			local hp = model:GetAttribute("Hp")
			local name = model.Name
			local owner = Players:GetPlayerFromCharacter(model)
			if owner then
				name = owner.DisplayName
			end
			local text = if type(hp) == "number"
				then ("%s · %d HP · %dm"):format(name, math.floor(hp + 0.5), math.floor(entry.Dist))
				else ("%s · %dm"):format(name, math.floor(entry.Dist))
			if slot.Label.Text ~= text then
				slot.Label.Text = text
			end
			slot.Gui.Enabled = not photoHidden
		end
	end
	espActive = true
end

-- ---------------------------------------------------------------------
-- NOCLIP / TEMPO / SPRUNG (vor der Physik, damit Movement sie nicht überschreibt)
-- ---------------------------------------------------------------------
local function restoreNoclip()
	for part, original in pairs(noclipParts) do
		if part.Parent then
			part.CanCollide = original
		end
	end
	table.clear(noclipParts)
end

local function preSimulation()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	if power("AdminNoclip") == true then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				if noclipParts[d] == nil then
					noclipParts[d] = true
				end
				d.CanCollide = false
			end
		end
	elseif next(noclipParts) ~= nil then
		restoreNoclip()
	end
	local speed = power("AdminSpeed")
	if type(speed) == "number" then
		humanoid.WalkSpeed = speed
		speedOverridden = true
	elseif speedOverridden then
		speedOverridden = false
		local base = character:GetAttribute("BaseSpeed")
		local walk = ctx and ctx.Config and ctx.Config.Player and ctx.Config.Player.Walk or 16
		humanoid.WalkSpeed = if type(base) == "number" then base else walk
	end
	local jump = power("AdminJump")
	if type(jump) == "number" then
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = jump
		jumpOverridden = true
	elseif jumpOverridden then
		jumpOverridden = false
		humanoid.JumpHeight = ctx and ctx.Config and ctx.Config.Player and ctx.Config.Player.JumpHeight or 7.2
	end
end

-- ---------------------------------------------------------------------
-- TAINTED-SCHILD
-- ---------------------------------------------------------------------
local function updateTaintSign()
	-- MatchUI zeigt den roten "ADMIN-SHOW"-Chip selbst (Vertrag Runde 2) -> Schild hier nur als Ersatz
	local show = player:GetAttribute("TaintedMatch") ~= nil and not photoHidden and module("MatchUI") == nil
	if show and not taintSign then
		local parent = ctx and ctx.Gui
		if typeof(parent) ~= "Instance" then
			return
		end
		-- AKYTEX-Chip: voll rund, Down-Fläche halb durchsichtig, 1-px-Rahmen, weiße BuilderSansBold
		local label = Instance.new("TextLabel")
		label.Name = "CC_TaintedSign"
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 96)
		label.Size = UDim2.fromOffset(0, 26)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.BackgroundColor3 = ESP_COLOR
		label.BackgroundTransparency = 0.15
		label.BorderSizePixel = 0
		label.Font = Enum.Font.BuilderSansBold
		label.TextSize = 14
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = T("admin.tainted")
		label.ZIndex = 40
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Color = ESP_COLOR:Lerp(Color3.new(1, 1, 1), 0.35)
		stroke.Transparency = 0.4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = label
		label.Parent = parent
		taintSign = label
	end
	if taintSign then
		taintSign.Visible = show
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function AdminTools.WantsFire(): boolean
	return wantsFire
end

function AdminTools.AimTarget(): (number?, Vector3?)
	local target = aimTarget
	if not target or not target.Head.Parent then
		return nil, nil
	end
	return target.Id, target.Head.Position
end

local function preRender(dt: number)
	refreshRayFilter()
	local armed = isArmed()
	local aimbot = power("AdminAimbot") == true
	local silent = power("AdminSilentAim") == true
	-- Ziel für Aimbot / Silent Aim
	if armed and (aimbot or silent) then
		local target = bestTarget(if silent then SILENT_CONE else AIM_CONE, not silent)
		aimTarget = target
		if aimbot and target and aimingHeld() then
			aimStep(dt, target)
		else
			applied = false
		end
	else
		aimTarget = nil
		applied = false
	end
	-- Triggerbot
	setWantsFire(armed and power("AdminTriggerbot") == true and crosshairOnEnemy())
	-- ESP mit 4 Hz
	espAcc += dt
	if espAcc >= 1 / ESP_HZ then
		espAcc = 0
		if power("AdminESP") == true and not photoHidden then
			updateEsp()
		elseif espActive then
			clearEsp()
		end
	end
end

function AdminTools.Init(context: any)
	ctx = context
end

function AdminTools.Start()
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Armed", function(info: any)
			if type(info) == "table" then
				armedInfo = {
					Ctx = if type(info.Ctx) == "string" then info.Ctx else nil,
					Team = if type(info.Team) == "number" then info.Team else nil,
				}
			end
		end)
		hooks.On("Disarmed", function()
			armedInfo = nil
			setWantsFire(false)
		end)
		hooks.On("PhotoMode", function(on: any)
			photoHidden = on == true
			if photoHidden then
				clearEsp()
			end
			updateTaintSign()
		end)
	end
	RunService.PreRender:Connect(preRender)
	RunService.PreSimulation:Connect(preSimulation)
	player:GetAttributeChangedSignal("TaintedMatch"):Connect(updateTaintSign)
	player:GetAttributeChangedSignal("AdminESP"):Connect(function()
		if player:GetAttribute("AdminESP") ~= true then
			clearEsp()
		end
	end)
	player.CharacterAdded:Connect(function()
		table.clear(noclipParts)
		speedOverridden = false
		jumpOverridden = false
	end)
	updateTaintSign()
end

return AdminTools
