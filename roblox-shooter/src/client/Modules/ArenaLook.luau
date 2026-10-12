-- =====================================================================
--  CLUTCH CLASH – Welt-Ausblendung & Licht-Stimmungen (Client/Modules/ArenaLook)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B9.4 (nur die eigene Welt zeigen), B8.2 (Stimmungen,
--  nur client-lokal), C7.4 (API).
--
--  Welten:   "Lobby" = workspace.Lobby + workspace.Arenas.Crown (Crown Ring und Range gehören dazu)
--            Slot k  = workspace.Arenas.Slot_k
--  Verstecken = für alle Nachfahren LOKAL: BasePart.LocalTransparencyModifier = 1,
--            SurfaceGui/BillboardGui/ParticleEmitter/Beam/Trail/Light.Enabled = false.
--            Originalwerte je Wurzel in einer starken Tabelle; neue Nachfahren (DescendantAdded) sofort mit,
--            entfernte Nachfahren (DescendantRemoving) bekommen ihren Originalwert zurück.
--  Stimmungen: eigene Instanzen CC_MoodAtmosphere/CC_MoodBloom/CC_MoodColorCorrection; die Lobby-
--            Effekte des Servers werden solange lokal geparkt/abgeschaltet. Snowy = Schnee an der Kamera.
--
--  Öffentliche API (C7.4):
--    ArenaLook.SetWorld(world: "Lobby" | number)   Slot-Nummer (0 = Crown = Lobby)
--    ArenaLook.ApplyMood(moodKey: string)
--    ArenaLook.RestoreLobby()
--  Hooks (C7.2): "Match:Start" {Slot, Mood, Map} · "Match:Closed" · "Armed" {Ctx} · "Disarmed" ·
--    "Effect:LobbyLook" {Mood} (Admin-Lobby-Licht, gilt für alle in der Lobby; zusätzlich workspace-Attribut
--    "LobbyMood" für später Beigetretene und aus dem Match Zurückkehrende)
-- =====================================================================

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local ArenaLook = {}

local ctx: any = nil
local Config: any = nil

local MOOD_PREFIX = "CC_Mood"
local MOOD_NAMES = { "CC_MoodAtmosphere", "CC_MoodBloom", "CC_MoodColorCorrection" }
local SNOW_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SNOW_RATE = 60
local SNOW_HEIGHT = 14

-- Versteckte Wurzeln: je Wurzel die Originalwerte ihrer Nachfahren (STARKE Tabelle – Instanzen als
-- schwache Schlüssel können vom GC entfernt werden, obwohl die Instanz noch lebt; dann blieben Teile nach
-- dem Match unsichtbar). Was die Wurzel verlässt (Map zerstört, Automat umgehängt), bekommt sofort seinen
-- Originalwert zurück und wird vergessen -> kein Leck, nichts bleibt versteckt.
type Hidden = { Saved: { [Instance]: any }, Added: RBXScriptConnection, Removing: RBXScriptConnection }
local hiddenRoots: { [Instance]: Hidden } = {}
local currentWorld: string | number = "Lobby"
local inMatch = false
local watchers: { RBXScriptConnection } = {}
local lobbyMood: string? = nil -- Admin-Event "LobbyLook" (Effect bzw. workspace-Attribut "LobbyMood")

local moodActive = false
local lightingSnapshot: { ClockTime: number, Ambient: Color3, OutdoorAmbient: Color3 }? = nil
local parkFolder = Instance.new("Folder") -- bleibt unparented: hier liegen die Lobby-Atmosphären während einer Stimmung
parkFolder.Name = "CC_MoodParked"
local parked: { Instance } = {}
local disabledEffects: { [Instance]: boolean } = {}
local snowPart: Part? = nil
local snowConn: RBXScriptConnection? = nil

-- ---------------------------------------------------------------------
-- Verstecken / Zeigen
-- ---------------------------------------------------------------------
local function hideOne(saved: { [Instance]: any }, inst: Instance)
	if inst:IsA("BasePart") then
		if saved[inst] == nil then
			saved[inst] = inst.LocalTransparencyModifier
		end
		inst.LocalTransparencyModifier = 1
	elseif
		inst:IsA("SurfaceGui")
		or inst:IsA("BillboardGui")
		or inst:IsA("ParticleEmitter")
		or inst:IsA("Beam")
		or inst:IsA("Trail")
		or inst:IsA("Light")
	then
		local any = inst :: any
		if saved[inst] == nil then
			saved[inst] = any.Enabled
		end
		any.Enabled = false
	end
end

local function restoreOne(saved: { [Instance]: any }, inst: Instance)
	local value = saved[inst]
	if value == nil then
		return
	end
	saved[inst] = nil
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = value
	else
		(inst :: any).Enabled = value
	end
end

local function hideRoot(root: Instance)
	if hiddenRoots[root] then
		return
	end
	local saved: { [Instance]: any } = {}
	for _, inst in ipairs(root:GetDescendants()) do
		hideOne(saved, inst)
	end
	hiddenRoots[root] = {
		Saved = saved,
		Added = root.DescendantAdded:Connect(function(inst: Instance)
			hideOne(saved, inst)
		end),
		Removing = root.DescendantRemoving:Connect(function(inst: Instance)
			restoreOne(saved, inst)
		end),
	}
end

local function forgetRoot(root: Instance, restore: boolean)
	local hidden = hiddenRoots[root]
	if not hidden then
		return
	end
	hiddenRoots[root] = nil
	hidden.Added:Disconnect()
	hidden.Removing:Disconnect()
	if restore then
		for inst in pairs(hidden.Saved) do
			restoreOne(hidden.Saved, inst)
		end
	end
	table.clear(hidden.Saved)
end

local function showRoot(root: Instance)
	forgetRoot(root, true)
end

-- Alle Welt-Wurzeln: { Root, Kind = "Lobby" | "Slot", Slot }
local function worldRoots(): { { Root: Instance, Kind: string, Slot: number } }
	local out = {}
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		table.insert(out, { Root = lobby, Kind = "Lobby", Slot = 0 })
	end
	local arenas = workspace:FindFirstChild("Arenas")
	if arenas then
		for _, child in ipairs(arenas:GetChildren()) do
			if child.Name == "Crown" then
				table.insert(out, { Root = child, Kind = "Lobby", Slot = 0 })
			else
				local slot = tonumber(child:GetAttribute("Slot")) or tonumber(string.match(child.Name, "^Slot_(%d+)$"))
				if slot and slot > 0 then
					table.insert(out, { Root = child, Kind = "Slot", Slot = slot })
				end
			end
		end
	end
	return out
end

local function applyWorld()
	-- zerstörte Wurzeln vergessen
	for root in pairs(hiddenRoots) do
		if root.Parent == nil then
			forgetRoot(root, false)
		end
	end
	for _, entry in ipairs(worldRoots()) do
		local show
		if currentWorld == "Lobby" then
			show = entry.Kind == "Lobby"
		else
			show = entry.Kind == "Slot" and entry.Slot == currentWorld
		end
		if show then
			showRoot(entry.Root)
		else
			hideRoot(entry.Root)
		end
	end
end

function ArenaLook.SetWorld(world: string | number)
	local target: string | number = "Lobby"
	local slot = tonumber(world)
	if slot and slot >= 1 then
		target = math.floor(slot)
	end
	currentWorld = target
	applyWorld()
end

-- ---------------------------------------------------------------------
-- Schnee an der Kamera (Snowy)
-- ---------------------------------------------------------------------
local function reducedFx(): boolean
	local modules = ctx and ctx.Modules
	local settings = modules and modules.Settings
	if settings and type(settings.Get) == "function" then
		local ok, values = pcall(settings.Get)
		if ok and type(values) == "table" then
			return values.ReducedFx == true
		end
	end
	return false
end

local function setSnow(on: boolean)
	if not on then
		if snowConn then
			snowConn:Disconnect()
			snowConn = nil
		end
		if snowPart then
			snowPart:Destroy()
			snowPart = nil
		end
		return
	end
	if snowPart then
		return
	end
	local part = Instance.new("Part")
	part.Name = "CC_MoodSnow"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(80, 1, 80)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Snow"
	emitter.Texture = SNOW_TEXTURE
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new(0.15)
	emitter.Rate = if reducedFx() then SNOW_RATE / 2 else SNOW_RATE
	emitter.Lifetime = NumberRange.new(5, 7)
	emitter.Speed = NumberRange.new(3, 5)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Acceleration = Vector3.new(0.4, -0.8, 0)
	emitter.LightEmission = 0.4
	emitter.LockedToPart = false
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = part
	local camera = workspace.CurrentCamera
	if camera then
		part.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, SNOW_HEIGHT, 0))
	end
	part.Parent = workspace -- vom Client erzeugt -> nur lokal
	snowPart = part
	snowConn = RunService.PreRender:Connect(function()
		local cam = workspace.CurrentCamera
		local p = snowPart
		if cam and p then
			p.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, SNOW_HEIGHT, 0))
		end
	end)
end

-- ---------------------------------------------------------------------
-- Stimmungen
-- ---------------------------------------------------------------------
local function ensureEffect(className: string, name: string): Instance
	local inst = Lighting:FindFirstChild(name)
	if inst and inst.ClassName ~= className then
		inst:Destroy()
		inst = nil
	end
	if not inst then
		local created = Instance.new(className)
		created.Name = name
		created.Parent = Lighting
		inst = created
	end
	return inst :: Instance
end

local function moodTable(moodKey: string?): any
	local maps = Config and Config.Maps
	local moods = maps and maps.Moods
	if type(moods) ~= "table" then
		return nil
	end
	local mood = if moodKey then moods[moodKey] else nil
	if type(mood) ~= "table" then
		mood = moods[maps.LobbyMood or "Day"] or moods.Day
	end
	return mood
end

-- Lobby-Effekte des Servers lokal beiseitelegen (eine Atmosphere zur Zeit; Bloom/Farbe aus)
local function parkLobbyEffects()
	for _, child in ipairs(Lighting:GetChildren()) do
		if string.sub(child.Name, 1, #MOOD_PREFIX) ~= MOOD_PREFIX then
			if child:IsA("Atmosphere") then
				table.insert(parked, child)
				child.Parent = parkFolder
			elseif child:IsA("BloomEffect") or child:IsA("ColorCorrectionEffect") then
				if disabledEffects[child] == nil then
					disabledEffects[child] = child.Enabled
				end
				child.Enabled = false
			end
		end
	end
end

function ArenaLook.ApplyMood(moodKey: string)
	local mood = moodTable(moodKey)
	if not mood then
		return
	end
	if not moodActive then
		moodActive = true
		lightingSnapshot = {
			ClockTime = Lighting.ClockTime,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
		}
		parkLobbyEffects()
	end
	Lighting.ClockTime = mood.ClockTime
	Lighting.Ambient = mood.Ambient
	Lighting.OutdoorAmbient = mood.OutdoorAmbient

	local atmoDef = mood.Atmosphere or {}
	local atmo = ensureEffect("Atmosphere", "CC_MoodAtmosphere") :: Atmosphere
	atmo.Density = math.max(0.32, tonumber(atmoDef.Density) or 0.32) -- B9.4: nie unter 0.32
	atmo.Haze = tonumber(atmoDef.Haze) or 1
	atmo.Glare = tonumber(atmoDef.Glare) or 0
	atmo.Offset = tonumber(atmoDef.Offset) or 0.25
	if typeof(atmoDef.Color) == "Color3" then
		atmo.Color = atmoDef.Color
	end
	if typeof(atmoDef.Decay) == "Color3" then
		atmo.Decay = atmoDef.Decay
	end

	local bloomDef = mood.Bloom or {}
	local bloom = ensureEffect("BloomEffect", "CC_MoodBloom") :: BloomEffect
	bloom.Intensity = tonumber(bloomDef.Intensity) or 0.5
	bloom.Size = tonumber(bloomDef.Size) or 24
	bloom.Threshold = tonumber(bloomDef.Threshold) or 1.6
	bloom.Enabled = not reducedFx() -- ReducedFx schaltet Bloom aus (C17)

	local ccDef = mood.ColorCorrection or {}
	local cc = ensureEffect("ColorCorrectionEffect", "CC_MoodColorCorrection") :: ColorCorrectionEffect
	cc.Saturation = tonumber(ccDef.Saturation) or 0
	cc.Contrast = tonumber(ccDef.Contrast) or 0
	cc.Brightness = tonumber(ccDef.Brightness) or 0
	cc.TintColor = if typeof(ccDef.TintColor) == "Color3" then ccDef.TintColor else Color3.new(1, 1, 1)

	setSnow(mood.Snow == true)
end

function ArenaLook.RestoreLobby()
	setSnow(false)
	for _, name in ipairs(MOOD_NAMES) do
		local inst = Lighting:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
	if not moodActive then
		return
	end
	moodActive = false
	local snap = lightingSnapshot
	if snap then
		Lighting.ClockTime = snap.ClockTime
		Lighting.Ambient = snap.Ambient
		Lighting.OutdoorAmbient = snap.OutdoorAmbient
	end
	lightingSnapshot = nil
	for _, inst in ipairs(parked) do
		inst.Parent = Lighting
	end
	table.clear(parked)
	for inst, enabled in pairs(disabledEffects) do
		if inst.Parent then
			(inst :: any).Enabled = enabled
		end
	end
	table.clear(disabledEffects)
end

-- ---------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------
local function moodFor(data: any): string
	local maps = Config and Config.Maps
	local mood = data.Mood
	if type(mood) == "string" and maps and maps.Moods and maps.Moods[mood] then
		return mood
	end
	local def = maps and maps.Maps and type(data.Map) == "string" and maps.Maps[data.Map]
	if def and type(def.ForcedMood) == "string" then
		return def.ForcedMood
	end
	return (maps and maps.LobbyMood) or "Day"
end

-- Lobby-Licht: Server-Look (GraphicsService) oder – nach dem Admin-Event "LobbyLook" – dessen Stimmung
local function applyLobbyLook()
	ArenaLook.RestoreLobby()
	local mood = lobbyMood
	if mood then
		ArenaLook.ApplyMood(mood)
	end
end

local function backToLobby()
	ArenaLook.SetWorld("Lobby")
	applyLobbyLook()
end

-- Effect "LobbyLook" {Mood} (AdminService) bzw. workspace-Attribut "LobbyMood": gilt für alle in der Lobby
-- (Lobby, Range, Crown Ring). Wer gerade in einer Arena ist, bekommt die Stimmung beim Zurückkommen.
local function setLobbyMood(value: any)
	local moods = Config and Config.Maps and Config.Maps.Moods
	local mood: string? = if type(value) == "string"
			and type(moods) == "table"
			and moods[value] ~= nil
		then value
		else nil
	if mood == lobbyMood then
		return
	end
	lobbyMood = mood
	if currentWorld == "Lobby" then
		applyLobbyLook()
	end
end

local function onMatchStart(data: any)
	if type(data) ~= "table" then
		return
	end
	inMatch = true
	local slot = tonumber(data.Slot) or 0
	if slot >= 1 then
		ArenaLook.SetWorld(slot)
		ArenaLook.ApplyMood(moodFor(data))
	else
		backToLobby() -- Slot 0 = Crown Ring = Lobby-Welt mit Lobby-Licht
	end
end

function ArenaLook.Init(c: any)
	ctx = c
	Config = c and c.Config
end

function ArenaLook.Start()
	if #watchers > 0 then
		return -- schon gestartet
	end
	ArenaLook.SetWorld("Lobby")
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Match:Start", onMatchStart)
		hooks.On("Match:Closed", function()
			inMatch = false
			backToLobby()
		end)
		hooks.On("Armed", function(info: any)
			if not inMatch and type(info) == "table" and info.Ctx == "Range" then
				backToLobby()
			end
		end)
		hooks.On("Disarmed", function()
			if not inMatch then
				backToLobby()
			end
		end)
		hooks.On("Effect:LobbyLook", function(_strength: any, data: any)
			setLobbyMood(if type(data) == "table" then data.Mood else nil)
		end)
	else
		warn("[ArenaLook] ctx.Hooks fehlt – Welt-Ausblendung reagiert nicht auf Matches")
	end
	-- Später auftauchende Wurzeln (Lobby/Arenas/Slots) gleich richtig ein-/ausblenden
	table.insert(
		watchers,
		workspace.ChildAdded:Connect(function(child)
			if child.Name == "Lobby" or child.Name == "Arenas" then
				applyWorld()
				if child.Name == "Arenas" then
					table.insert(watchers, child.ChildAdded:Connect(applyWorld))
				end
			end
		end)
	)
	local arenas = workspace:FindFirstChild("Arenas")
	if arenas then
		table.insert(watchers, arenas.ChildAdded:Connect(applyWorld))
	end
	-- Admin-Lobby-Licht auch für später Beigetretene / aus dem Match Zurückkehrende (AdminService setzt das Attribut)
	table.insert(
		watchers,
		workspace:GetAttributeChangedSignal("LobbyMood"):Connect(function()
			setLobbyMood(workspace:GetAttribute("LobbyMood"))
		end)
	)
	setLobbyMood(workspace:GetAttribute("LobbyMood"))
end

return ArenaLook
