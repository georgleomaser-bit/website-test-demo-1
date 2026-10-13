-- =====================================================================
--  AKYTEX TYCOON – Admin-Kräfte auf dem Client (Client/Modules/AdminTools)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §B15.2 (Tab "Kräfte"), §C11.3 (Noclip/Fly exempt),
--  REUSE §1.4 (CC-AdminTools ADAPT: nur lokales Noclip/Tempo/Sprung + ESP über Highlights; Aimbot/Silent Aim/Triggerbot/
--  Taint-Schild sind entfernt). Nur für den Besitzer (Modul lädt nur bei IsAdmin). Alle Kräfte sind Attribute am eigenen
--  Player, die NUR der Server setzt (SetPower) – und der Server ehrt sie nur bei IsAdmin. Hier passiert nur die lokale Seite:
--    * Noclip (AdminNoclip), Tempo (AdminSpeed), Sprung (AdminJump) am eigenen Humanoid (vor der Physik)
--    * ESP (AdminESP): ≤ 20 Highlights über den zentralen Verteiler "Highlights" + Name/Abstand über dem Kopf (4 Hz)
--    * Show-Kamera (Kino für Streams): langsamer Kreisflug um die Plaza, HUD aus, Taste X oder Panel beendet
--  Look: ESP-Schilder BuilderSansBold, Accent-Kontur (AKYTEX), feine 1-px-Kante.
--
--  Öffentliche API:
--    AdminTools.ToggleShowCam()        AdminTools.IsShowCam(): boolean
--    AdminTools.Init(ctx) / AdminTools.Start()
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AdminTools = {}

local player = Players.LocalPlayer
local ctx: any = nil

local ESP_OWNER = "AdminESP"
local ESP_HZ = 4
local ESP_RANGE = 2500
local ESP_COLOR = Color3.fromRGB(79, 140, 255) -- AKYTEX Accent (#4f8cff)
local TEXT_COLOR = Color3.fromRGB(230, 236, 245) -- AKYTEX Text (#e6ecf5)
local DEFAULT_WALK = 16
local DEFAULT_JUMP = 7.2
local CAM_RADIUS = 280
local CAM_HEIGHT = 130
local CAM_SPEED = 0.045 -- Radiant je Sekunde
local CAM_BOB = 18

type EspSlot = { Gui: BillboardGui, Label: TextLabel, Model: Model?, Handle: any? }

local photoHidden = false
local espSlots: { EspSlot } = {}
local espAcc = 0
local espActive = false
local noclipParts: { [BasePart]: boolean } = {}
local speedOverridden = false
local jumpOverridden = false
local showCam = false
local showAngle = 0
local showTime = 0
local savedCameraType: Enum.CameraType? = nil

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

local function toast(text: string, kind: string)
	if ctx and type(ctx.Toast) == "function" then
		ctx.Toast(text, kind)
	end
end

local function power(name: string): any
	if player:GetAttribute("IsAdmin") ~= true then
		return nil
	end
	return player:GetAttribute(name)
end

local function espMax(): number
	local security = ctx and ctx.Config and ctx.Config.Security
	local powers = security and security.Powers
	local n = powers and tonumber(powers.EspMax)
	return math.clamp(math.floor(n or 20), 1, 20)
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
	gui.Name = "AT_AdminESP"
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffset = Vector3.new(0, 3, 0)
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
	label.TextColor3 = ESP_COLOR:Lerp(TEXT_COLOR, 0.35)
	label.Text = ""
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 17
	sizeLimit.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.45
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
	(slot.Gui :: any).Adornee = nil -- Typdefinition kennt kein optionales Adornee
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
	local list: { { Model: Model, Head: BasePart, Dist: number, Name: string } } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		if p ~= player and character then
			local head = character:FindFirstChild("Head")
			local root = character:FindFirstChild("HumanoidRootPart")
			if head and root and head:IsA("BasePart") and root:IsA("BasePart") then
				local dist = (root.Position - camPos).Magnitude
				if dist <= ESP_RANGE then
					table.insert(list, { Model = character, Head = head, Dist = dist, Name = p.DisplayName })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Dist < b.Dist
	end)
	local maxSlots = espMax()
	local used = math.min(#list, maxSlots)
	local wanted: { [Model]: boolean } = {}
	for i = 1, used do
		wanted[list[i].Model] = true
	end
	for _, slot in ipairs(espSlots) do
		if slot.Model and not wanted[slot.Model] then
			releaseSlot(slot)
		end
	end
	local highlights = module("Highlights")
	for i = 1, used do
		local entry = list[i]
		local slot: EspSlot? = nil
		for _, s in ipairs(espSlots) do
			if s.Model == entry.Model then
				slot = s
				break
			end
		end
		if not slot then
			for index = 1, maxSlots do
				local s = espSlot(index)
				if s.Model == nil then
					slot = s
					break
				end
			end
		end
		if slot then
			if slot.Model ~= entry.Model then
				slot.Model = entry.Model
				slot.Gui.Adornee = entry.Head
				if highlights and type(highlights.Acquire) == "function" then
					local ok, handle = pcall(highlights.Acquire, ESP_OWNER, entry.Model, {
						Outline = ESP_COLOR,
						Fill = ESP_COLOR,
						FillTransparency = 0.8,
						Depth = Enum.HighlightDepthMode.AlwaysOnTop,
					})
					slot.Handle = if ok then handle else nil
				end
			end
			local text = ("%s · %dm"):format(entry.Name, math.floor(entry.Dist))
			if slot.Label.Text ~= text then
				slot.Label.Text = text
			end
			slot.Gui.Enabled = not photoHidden
		end
	end
	espActive = true
end

-- ---------------------------------------------------------------------
-- NOCLIP / TEMPO / SPRUNG (vor der Physik, damit die Steuerung sie nicht überschreibt)
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
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
		speedOverridden = true
	elseif speedOverridden then
		speedOverridden = false
		humanoid.WalkSpeed = DEFAULT_WALK
	end
	local jump = power("AdminJump")
	if type(jump) == "number" then
		humanoid.UseJumpPower = false
		if humanoid.JumpHeight ~= jump then
			humanoid.JumpHeight = jump
		end
		jumpOverridden = true
	elseif jumpOverridden then
		jumpOverridden = false
		humanoid.JumpHeight = DEFAULT_JUMP
	end
end

-- ---------------------------------------------------------------------
-- SHOW-KAMERA (Kino für Streams)
-- ---------------------------------------------------------------------
local function plazaCenter(): Vector3
	local city = ctx and ctx.Config and ctx.Config.City
	local zones = city and city.Zones
	local plaza = zones and zones.Plaza
	if plaza and typeof(plaza.Center) == "Vector3" then
		return plaza.Center
	end
	return Vector3.zero
end

local function setHudHidden(hidden: boolean)
	local hud = module("Hud")
	if hud and type(hud.SetVisible) == "function" then
		pcall(hud.SetVisible, not hidden)
	end
end

local function stopShowCam()
	if not showCam then
		return
	end
	showCam = false
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	savedCameraType = nil
	setHudHidden(false)
	toast(T("admin.showCamOff"), "Info")
end

function AdminTools.IsShowCam(): boolean
	return showCam
end

function AdminTools.ToggleShowCam()
	if showCam then
		stopShowCam()
		return
	end
	if player:GetAttribute("IsAdmin") ~= true then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local windows = ctx and ctx.Windows
	if windows and type(windows.Close) == "function" then
		pcall(windows.Close)
	end
	savedCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local offset = camera.CFrame.Position - plazaCenter()
	showAngle = math.atan2(offset.Z, offset.X)
	showTime = 0
	showCam = true
	setHudHidden(true)
	toast(T("admin.showCamOn"), "Success")
end

local function stepShowCam(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	showTime += dt
	showAngle += CAM_SPEED * dt
	local center = plazaCenter()
	local height = CAM_HEIGHT + math.sin(showTime * 0.12) * CAM_BOB
	local radius = CAM_RADIUS + math.sin(showTime * 0.07) * 40
	local pos = center + Vector3.new(math.cos(showAngle) * radius, height, math.sin(showAngle) * radius)
	local target = CFrame.lookAt(pos, center + Vector3.new(0, 30, 0))
	camera.CFrame = camera.CFrame:Lerp(target, math.clamp(dt * 2, 0, 1))
end

local function preRender(dt: number)
	if showCam then
		stepShowCam(dt)
	end
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
		hooks.On("PhotoMode", function(on: any)
			photoHidden = on == true
			if photoHidden then
				clearEsp()
			end
		end)
	end
	RunService.PreRender:Connect(preRender)
	RunService.PreSimulation:Connect(preSimulation)
	player:GetAttributeChangedSignal("AdminESP"):Connect(function()
		if player:GetAttribute("AdminESP") ~= true then
			clearEsp()
		end
	end)
	player.CharacterAdded:Connect(function()
		table.clear(noclipParts)
		speedOverridden = false
		jumpOverridden = false
		if showCam then
			stopShowCam()
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local character = p.Character
		for _, slot in ipairs(espSlots) do
			if slot.Model ~= nil and slot.Model == character then
				releaseSlot(slot)
			end
		end
	end)
	-- Show-Kamera mit X beenden (Zuschauen benutzt X ebenfalls – nur wenn die Show-Kamera läuft)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if showCam and (input.KeyCode == Enum.KeyCode.X or input.KeyCode == Enum.KeyCode.ButtonB) then
			stopShowCam()
		end
	end)
	-- Handy: HUD ist aus -> lange auf den Bildschirm drücken beendet die Show-Kamera (REUSE §7 #37)
	UserInputService.TouchLongPress:Connect(function(_positions, state)
		if showCam and state == Enum.UserInputState.Begin then
			stopShowCam()
		end
	end)
end

return AdminTools
