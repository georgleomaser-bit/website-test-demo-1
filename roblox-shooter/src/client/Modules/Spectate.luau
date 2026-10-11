-- =====================================================================
--  CLUTCH CLASH – Zuschauen nach dem Pop (Client/Modules/Spectate)
--  Besitzer: WP5 (Match-UI). Vertrag: DESIGN.md C7.4 (Spectate.Start/Stop), B14.5.
--
--  Rundenmodi: 1.5 s Blick auf den Killer (Name + HP), dann Verfolger-Kamera über die Schulter
--    (CameraSubject = Humanoid des Teamkollegen, Zoom 8) auf lebende Teamkollegen; wechseln mit
--    Klick / LB-RB / Pfeile (Controls-Aktionen SpecNext/SpecPrev).
--  1v1: Killer 2 s, dann bleibt die Kamera beim Killer (Rückblick-Panel zeigt MatchUI).
--  FFA: Killer 2.5 s (Rückblick), dann Respawn – kein Teamkollegen-Wechsel.
--  Stoppt bei LocalRevived, Match:Prep, Match:Closed, Disarmed.
--
--  Öffentliche API (C7.4):
--    Spectate.Start(candidates: { Model })   Verfolger-Kamera über diese Figuren (erste lebende zuerst)
--    Spectate.Stop()
--  Zusätzlich: Spectate.Target(): Model?, Spectate.Init(ctx).
--  Modul-Start (C7.1): Main.client ruft Spectate.Start() OHNE Argument -> Hooks anmelden (einmal).
--  Feuert Hooks "Spectate"(model?) (Controls schaltet damit den Eingabe-Kontext).
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent:WaitForChild("UI"))

local Spectate = {}

local player = Players.LocalPlayer
local ctx: any = nil

local KILLER_SECONDS = 1.5
local KILLER_SECONDS_DUEL = 2
local KILLER_SECONDS_FFA = 2.5
local REFRESH = 0.25

local candidates: { Model } = {}
local index = 0
local target: Model? = nil
local active = false
local followMode = false -- true = Teamkollegen-Wechsel aktiv
local token = 0
local armed = false
local alive = true
local inMatch = false
local matchMode: string? = nil
local myTeam = 0
local myId = player.UserId
local unbinds: { () -> () } = {}
local panel: Frame? = nil
local nameLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local accum = 0
local killerId: number? = nil

local function module(name: string): any
	return ctx and ctx.Modules and ctx.Modules[name]
end

local function T(key: string, ...: any): string
	return if ctx then ctx.T(key, ...) else key
end

-- ---------------------------------------------------------------------
-- Figuren finden (Attribute CombatantId/Team/Alive setzt CombatService)
-- ---------------------------------------------------------------------
local function allCombatantModels(): { Model }
	local list: { Model } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char and char:GetAttribute("CombatantId") ~= nil then
			table.insert(list, char)
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("Bot")) do
		if inst:IsA("Model") and inst:GetAttribute("CombatantId") ~= nil then
			table.insert(list, inst)
		end
	end
	return list
end

local function modelById(id: number?): Model?
	if id == nil then
		return nil
	end
	for _, model in ipairs(allCombatantModels()) do
		if tonumber(model:GetAttribute("CombatantId")) == id then
			return model
		end
	end
	return nil
end

local function isAlive(model: Model?): boolean
	if not model or not model.Parent then
		return false
	end
	return model:GetAttribute("Alive") ~= false
end

local function teammates(): { Model }
	local list: { Model } = {}
	for _, model in ipairs(allCombatantModels()) do
		local id = tonumber(model:GetAttribute("CombatantId"))
		if id ~= myId and tonumber(model:GetAttribute("Team")) == myTeam and isAlive(model) then
			table.insert(list, model)
		end
	end
	return list
end

local function displayName(model: Model): string
	local p = Players:GetPlayerFromCharacter(model)
	if p then
		return p.DisplayName
	end
	return model.Name
end

-- ---------------------------------------------------------------------
-- Kamera + Anzeige
-- ---------------------------------------------------------------------
local function setSubject(model: Model?)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	else
		local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if own then
			camera.CameraSubject = own
		end
	end
end

local function updatePanel()
	local label = nameLabel
	local p = panel
	if not label or not p then
		return
	end
	local model = target
	if not active or not model then
		p.Visible = false
		return
	end
	p.Visible = true
	local hp = tonumber(model:GetAttribute("Hp")) or 0
	local name = displayName(model)
	local key = if not followMode then "match.spectate.killer" else "match.spectate.watching"
	local text = T(key, name, math.max(0, math.floor(hp + 0.5)))
	if label.Text ~= text then
		label.Text = text
	end
	if hintLabel then
		hintLabel.Visible = followMode and #candidates > 1
	end
end

local function watch(model: Model?)
	target = model
	setSubject(model)
	if ctx then
		ctx.Hooks.Fire("Spectate", model)
	end
	updatePanel()
end

local function cycle(step: number)
	if not active or not followMode then
		return
	end
	local fresh: { Model } = {}
	for _, model in ipairs(candidates) do
		if isAlive(model) then
			table.insert(fresh, model)
		end
	end
	candidates = fresh
	if #candidates == 0 then
		return
	end
	index = ((index - 1 + step) % #candidates) + 1
	watch(candidates[index])
end

local function clearBinds()
	for _, unbind in ipairs(unbinds) do
		pcall(unbind)
	end
	table.clear(unbinds)
end

local function bindControls()
	clearBinds()
	local controls = module("Controls")
	if not controls or type(controls.Bind) ~= "function" then
		return
	end
	table.insert(
		unbinds,
		controls.Bind("SpecNext", function(state)
			if state == "Begin" then
				cycle(1)
			end
		end, 5)
	)
	table.insert(
		unbinds,
		controls.Bind("SpecPrev", function(state)
			if state == "Begin" then
				cycle(-1)
			end
		end, 5)
	)
end

-- ---------------------------------------------------------------------
-- Öffentliche API
-- ---------------------------------------------------------------------
local moduleStarted = false
local startModule: () -> () = function() end

function Spectate.Start(list: { Model }?)
	if list == nil then
		-- Modul-Start durch Main.client (C7.1)
		if not moduleStarted then
			moduleStarted = true
			startModule()
		end
		return
	end
	token += 1
	candidates = {}
	for _, model in ipairs(list) do
		if typeof(model) == "Instance" and model:IsA("Model") then
			table.insert(candidates, model)
		end
	end
	if #candidates == 0 then
		return
	end
	active = true
	followMode = true
	index = 1
	local camera = module("FpsCamera")
	if camera and type(camera.SetMode) == "function" then
		pcall(camera.SetMode, "Spectate")
	end
	bindControls()
	watch(candidates[1])
end

function Spectate.Stop()
	token += 1
	local was = active
	active = false
	followMode = false
	candidates = {}
	index = 0
	killerId = nil
	clearBinds()
	if was then
		target = nil
		setSubject(nil)
		if ctx then
			ctx.Hooks.Fire("Spectate", nil)
		end
		local camera = module("FpsCamera")
		if camera and type(camera.SetMode) == "function" then
			pcall(camera.SetMode, if armed and alive then "Match" elseif inMatch then "Spectate" else "Lobby")
		end
	end
	updatePanel()
end

function Spectate.Target(): Model?
	return target
end

-- Eigener Pop: Killer zeigen, danach Teamkollegen (Rundenmodi)
local function onLocalPop(kid: number?)
	if not inMatch then
		return
	end
	token += 1
	local myToken = token
	killerId = kid
	local killer = modelById(kid)
	local ffa = matchMode == "FFA"
	local mates = if ffa then {} else teammates()
	local seconds = if ffa then KILLER_SECONDS_FFA elseif #mates == 0 then KILLER_SECONDS_DUEL else KILLER_SECONDS
	if killer then
		active = true
		followMode = false
		local camera = module("FpsCamera")
		if camera and type(camera.SetMode) == "function" then
			pcall(camera.SetMode, "Spectate")
		end
		watch(killer)
	end
	task.delay(seconds, function()
		if myToken ~= token or alive then
			return
		end
		if ffa then
			Spectate.Stop() -- Respawn kommt gleich
			return
		end
		local now = teammates()
		if #now > 0 then
			Spectate.Start(now)
		end
		-- 1v1/keine Teamkollegen: Kamera bleibt beim Killer
	end)
end

local function buildPanel()
	local gui = ctx and ctx.Gui
	if not gui then
		return
	end
	local frame = UI.Create("Frame", {
		Name = "SpectatePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(420, 64),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 22,
		Parent = gui,
	})
	nameLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 36),
		Text = "",
		MaxText = 26,
		Outline = 3,
		ZIndex = 22,
		Parent = frame,
	})
	hintLabel = UI.Label({
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 22),
		Text = T("match.spectate.hint"),
		MaxText = 16,
		Outline = 2,
		TextColor3 = UI.Theme.SubText,
		Visible = false,
		ZIndex = 22,
		Parent = frame,
	})
	panel = frame
end

local function step(dt: number)
	if not active then
		return
	end
	accum += dt
	if accum < REFRESH then
		return
	end
	accum = 0
	-- Ziel gepoppt -> nächster lebender Teamkollege
	if followMode and target and not isAlive(target) then
		local mates = teammates()
		if #mates > 0 then
			candidates = mates
			index = 1
			watch(mates[1])
		end
	elseif not followMode and target == nil and killerId then
		local killer = modelById(killerId)
		if killer then
			watch(killer)
		end
	end
	updatePanel()
end

function Spectate.Init(context: any)
	ctx = context
	buildPanel()
end

startModule = function()
	local hooks = ctx.Hooks
	hooks.On("Match:Start", function(data)
		inMatch = true
		matchMode = type(data) == "table" and data.Mode or nil
		myTeam = type(data) == "table" and tonumber(data.MyTeam) or 0
		myId = type(data) == "table" and tonumber(data.MyId) or player.UserId
	end)
	hooks.On("Match:Elim", function(data)
		if type(data) == "table" and inMatch and tonumber(data.V) == myId then
			alive = false
			onLocalPop(tonumber(data.K))
		end
	end)
	hooks.On("Match:Spectate", function(data)
		-- Server nennt das Ziel (Killer), falls das Elim schon vorbei ist
		if type(data) == "table" and not alive and not active then
			onLocalPop(tonumber(data.TargetId))
		end
	end)
	hooks.On("Match:Prep", function()
		alive = true
		Spectate.Stop()
	end)
	hooks.On("Match:Closed", function()
		inMatch = false
		alive = true
		matchMode = nil
		Spectate.Stop()
	end)
	hooks.On("LocalRevived", function()
		alive = true
		Spectate.Stop()
	end)
	hooks.On("LocalPopped", function()
		alive = false
	end)
	hooks.On("Armed", function()
		armed = true
	end)
	hooks.On("Disarmed", function()
		armed = false
		Spectate.Stop()
	end)
	RunService.Heartbeat:Connect(step)
end

return Spectate
