-- =====================================================================
--  AKYTEX TYCOON – Sounds nur aus eingebauten Dateien (Client/Modules/Sfx)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §A4 (Sound-Rollen), §C7.5, §C14.3 (SoundId = 0),
--  docs/ASSETS.md §2 (CC-Rezept-Engine 1:1, neue Rollen).
--
--  Jede Rolle (z. B. "Buy", "MarketBell", "CrashAlarm") ist ein REZEPT aus den 9 nutzbaren eingebauten Roblox-Sounds:
--  Tonhöhe (PlaybackSpeed), Ausschnitt (PlaybackRegion), Effekte (Verzerrung, Equalizer, Echo) und mehrere Schichten
--  nacheinander (Jingles). Trägt der Besitzer in Config.Client.Sounds.<Rolle> eine Audio-ID ein (≠ 0), wird stattdessen
--  diese gespielt (Hybrid, Wunsch 17). Feste Stimmen-Vorräte (Pools.Sounds: halb 2D, halb 3D) im Rundlauf – kein neues
--  Sound-Objekt pro Ton. Lautstärke über SoundGroups (Einstellungen Sfx / Ui / Music). Keine Casino-Klänge, keine
--  Münz-Kaskade pro Trade (§0.2/§0.3): Gewinn = ruhiges Arpeggio, Verlust = ein tiefer Ton.
--
--  Rollen (§A4): UIClick, UIHover, UIError, Buy, Sell, Profit, Loss, CashRegister, TickerTick, MarketBell, CrashAlarm,
--    RallyFanfare, ElevatorDing, Construct, MoneyRain, Engine (Loop) + LevelUp, Achievement, Pickup, Whoosh, Countdown, Notify.
--
--  Öffentliche API (§C7.5):
--    Sfx.Play(role, pos?, opts?)        opts { Volume?, Speed? } – pos = 3D-Sound an dieser Stelle
--    Sfx.Duck(amount, seconds)          Welt-/Effekt-Sounds kurz leiser (Glocke, Ansage)
--    Sfx.SetMusic(kind?)                nil = aus; sonst Musik aus Config.Client.Sounds.Music (ohne ID keine Musik)
--  Zusätzlich: Sfx.Has(role), Sfx.Loop(role, parent?) -> { Sound, SetSpeed(x), SetVolume(v), Stop() } (z. B. Motor),
--    Sfx.ApplySettings(settings), Sfx.Init(ctx), Sfx.Start()
-- =====================================================================

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Sfx = {}

local ctx: any = nil

-- Die eingebauten Dateien (exakte Pfade aus docs/ASSETS.md §2 – nichts anderes benutzen!)
local FILES = {
	Boom = "rbxasset://sounds/impact_explosion_03.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Tick = "rbxasset://sounds/volume_slider.ogg",
	Jump = "rbxasset://sounds/action_jump.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Wind = "rbxasset://sounds/action_falling.ogg",
	Water = "rbxasset://sounds/impact_water.mp3",
}

type Echo = { Delay: number, Feedback: number, Wet: number }
type Layer = {
	File: string,
	Speed: number,
	Vol: number,
	Region: { number }?, -- { Start, Ende } in Sekunden der Original-Datei
	Delay: number?, -- Sekunden nach der ersten Schicht
	Dist: number?, -- DistortionSoundEffect.Level
	EqLow: number?,
	EqMid: number?,
	EqHigh: number?,
	Echo: Echo?,
	Jitter: number?, -- ± Anteil zufällige Tonhöhe (0.04 = ±4 %)
	Range: number?, -- RollOffMaxDistance (3D)
}
type Recipe = { Group: string, Layers: { Layer } }

local ECHO_DING: Echo = { Delay = 0.08, Feedback = 0.2, Wet = -6 }
local ECHO_BELL: Echo = { Delay = 0.22, Feedback = 0.42, Wet = -3 }
local ECHO_JINGLE: Echo = { Delay = 0.12, Feedback = 0.3, Wet = -4 }

-- Tonfolge aus volume_slider.ogg (musikalische Verhältnisse: große Terz 1.26, Quinte 1.5, Oktave 2.0)
local function notes(file: string, speeds: { number }, gap: number, vol: number, extra: { [string]: any }?): { Layer }
	local list: { Layer } = {}
	for i, speed in ipairs(speeds) do
		local layer: Layer = { File = file, Speed = speed, Vol = vol, Delay = (i - 1) * gap }
		if extra then
			if extra.EchoLast and i == #speeds then
				layer.Echo = ECHO_JINGLE
			end
			if extra.EchoAll then
				layer.Echo = extra.Echo or ECHO_JINGLE
			end
			if extra.EqHigh then
				layer.EqHigh = extra.EqHigh
			end
			if extra.EqLow then
				layer.EqLow = extra.EqLow
			end
			if extra.Dist then
				layer.Dist = extra.Dist
			end
		end
		table.insert(list, layer)
	end
	return list
end

-- Gruppen: SFX (Welt/Effekte, wird bei Duck leiser), UI (Oberfläche), MUSIC
-- Startwerte nach ASSETS.md §2.2 / DESIGN §A4 (nach Gehör im Studio nachstellen)
local RECIPES: { [string]: Recipe } = {
	-- Oberfläche
	UIClick = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 1.0, Vol = 0.5 } } },
	UIHover = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 1.5, Vol = 0.2 } } },
	UIError = { Group = "UI", Layers = { { File = FILES.Land, Speed = 0.7, Vol = 0.5 } } },
	Notify = { Group = "UI", Layers = notes(FILES.Tick, { 1.5, 2.0 }, 0.07, 0.35) },
	Countdown = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 1.0, Vol = 0.6 } } },
	-- Handel (ruhig, nie Slot-artig): Kauf Tick 1.26 -> 1.5, Verkauf 1.5 -> 1.26
	Buy = { Group = "UI", Layers = notes(FILES.Tick, { 1.26, 1.5 }, 0.07, 0.5) },
	Sell = { Group = "UI", Layers = notes(FILES.Tick, { 1.5, 1.26 }, 0.07, 0.5) },
	Profit = { Group = "UI", Layers = notes(FILES.Tick, { 1.0, 1.26, 1.5 }, 0.11, 0.45, { EchoLast = true }) },
	Loss = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 0.667, Vol = 0.4, EqHigh = -6 } } },
	TickerTick = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 2.2, Vol = 0.15 } } },
	-- Tower / Geld
	CashRegister = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Land, Speed = 3.0, Vol = 0.45, EqHigh = 4 },
			{ File = FILES.Tick, Speed = 2.0, Vol = 0.45, Delay = 0.05, Echo = ECHO_DING },
		},
	},
	Construct = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Land, Speed = 0.8, Vol = 0.6, EqLow = 4, Jitter = 0.05 },
			{ File = FILES.Land, Speed = 1.1, Vol = 0.35, Delay = 0.18, Jitter = 0.05 },
		},
	},
	ElevatorDing = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Tick, Speed = 2.0, Vol = 0.55, Echo = ECHO_DING },
			{ File = FILES.Tick, Speed = 1.5, Vol = 0.45, Delay = 0.16, Echo = ECHO_DING },
		},
	},
	MoneyRain = { Group = "SFX", Layers = { { File = FILES.Tick, Speed = 2.0, Vol = 0.35, Jitter = 0.25 } } },
	Pickup = { Group = "SFX", Layers = notes(FILES.Tick, { 1.5, 2.0 }, 0.05, 0.45) },
	Whoosh = { Group = "SFX", Layers = { { File = FILES.Wind, Speed = 2.0, Vol = 0.35, Region = { 0, 0.45 } } } },
	-- Markt-Momente
	MarketBell = {
		Group = "SFX",
		Layers = notes(FILES.Tick, { 1.0, 1.26, 1.5 }, 0.18, 0.8, { EchoAll = true, Echo = ECHO_BELL, EqLow = 3 }),
	},
	CrashAlarm = {
		Group = "SFX",
		Layers = notes(FILES.Tick, { 0.841, 0.667, 0.841, 0.667 }, 0.32, 0.6, { Dist = 0.45, EqHigh = -3 }),
	},
	RallyFanfare = {
		Group = "SFX",
		Layers = notes(FILES.Tick, { 1.0, 1.26, 1.5, 2.0 }, 0.09, 0.75, { EchoAll = true }),
	},
	-- Meilensteine (nur Stufe, Lizenz, Titel, Börsengang, Liga – §0.3 Punkt 6)
	LevelUp = { Group = "UI", Layers = notes(FILES.Tick, { 1.0, 1.26, 1.5, 2.0 }, 0.09, 0.75, { EchoAll = true }) },
	Achievement = { Group = "UI", Layers = notes(FILES.Tick, { 1.26, 1.5, 2.0 }, 0.08, 0.6, { EchoLast = true }) },
	-- Motor-Loop (nur über Sfx.Loop; Tonhöhe nach Tempo)
	Engine = { Group = "SFX", Layers = { { File = FILES.Wind, Speed = 0.8, Vol = 0.35, EqLow = 3, Range = 120 } } },
}

-- Rollen, die nur als Loop gespielt werden (Play ignoriert sie)
local LOOP_ROLES = { Engine = true }
-- Rollen ohne eingebautes Rezept (nur mit eigener ID): Musik
local MUSIC_ROLES = { Music = true }

local DEDUPE_GAP = 0.025 -- dieselbe Rolle innerhalb so kurzer Zeit nur einmal (zwei Module melden dasselbe)
local DEFAULT_RANGE = 300
local MIN_RANGE = 10
local WARN_GAP = 30
local MAX_LOOPS = 12 -- gleichzeitige Loops (Motoren) – mehr werden abgelehnt

type Voice = {
	Sound: Sound,
	Dist: DistortionSoundEffect,
	Eq: EqualizerSoundEffect,
	Echo: EchoSoundEffect,
	Attachment: Attachment?,
	StartedAt: number,
}

export type LoopHandle = {
	Sound: Sound,
	SetSpeed: (mult: number) -> (),
	SetVolume: (volume: number) -> (),
	Stop: () -> (),
}

local voices2D: { Voice } = {}
local voices3D: { Voice } = {}
local next2D = 1
local next3D = 1
local groups: { [string]: SoundGroup } = {}
local baseVolume: { [string]: number } = { SFX = 1, UI = 0.8, MUSIC = 0.5 }
local duckFactor = 1
local duckToken = 0
local lastPlayed: { [string]: number } = {}
local warnedRole: { [string]: number } = {}
local anchorPart: Part? = nil
local musicSound: Sound? = nil
local musicKind: string? = nil
local loopCount = 0
local random = Random.new()

-- ---------------------------------------------------------------------
-- AUFBAU
-- ---------------------------------------------------------------------
local function makeVoice(parent: Instance, name: string, attachment: Attachment?): Voice
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Volume = 0.5
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = MIN_RANGE
	sound.RollOffMaxDistance = DEFAULT_RANGE
	local dist = Instance.new("DistortionSoundEffect")
	dist.Enabled = false
	dist.Parent = sound
	local eq = Instance.new("EqualizerSoundEffect")
	eq.Enabled = false
	eq.Parent = sound
	local echo = Instance.new("EchoSoundEffect")
	echo.Enabled = false
	echo.Parent = sound
	sound.Parent = parent
	return { Sound = sound, Dist = dist, Eq = eq, Echo = echo, Attachment = attachment, StartedAt = -math.huge }
end

local function makeGroup(name: string): SoundGroup
	local full = "AkytexTycoon" .. name
	local existing = SoundService:FindFirstChild(full)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = full
	group.Volume = 1
	group.Parent = SoundService
	return group
end

local function applyGroupVolumes()
	for name, group in pairs(groups) do
		local volume = baseVolume[name] or 1
		if name == "SFX" or name == "MUSIC" then
			volume *= duckFactor
		end
		group.Volume = math.clamp(volume, 0, 2)
	end
end

local function build()
	groups.SFX = makeGroup("Sfx")
	groups.UI = makeGroup("Ui")
	groups.MUSIC = makeGroup("Music")

	local poolSize = 24
	local config = ctx and ctx.Config
	local pools = config and config.Client and config.Client.Pools
	if pools and type(pools.Sounds) == "number" then
		poolSize = math.clamp(math.floor(pools.Sounds), 4, 64)
	end
	local half = math.max(2, math.floor(poolSize / 2))

	-- 2D-Stimmen: direkt im SoundService (überall gleich laut)
	local folder2D = Instance.new("Folder")
	folder2D.Name = "AkytexTycoonVoices"
	folder2D.Parent = SoundService
	for i = 1, half do
		table.insert(voices2D, makeVoice(folder2D, "Voice2D_" .. i, nil))
	end

	-- 3D-Stimmen: an Attachments eines unsichtbaren, lokalen Ankers (WorldPosition = Klangquelle)
	local anchor = Instance.new("Part")
	anchor.Name = "AkytexTycoonSfxAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new()
	anchor.Parent = workspace
	anchorPart = anchor
	for i = 1, half do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Voice3D_" .. i
		attachment.Parent = anchor
		table.insert(voices3D, makeVoice(attachment, "Sound", attachment))
	end

	local music = Instance.new("Sound")
	music.Name = "AkytexTycoonMusic"
	music.Looped = true
	music.Volume = 0.5
	music.SoundGroup = groups.MUSIC
	music.Parent = SoundService
	musicSound = music

	applyGroupVolumes()
end

-- Eingebaute Dateien einmal vorladen (sonst kann der allererste Klick stumm sein)
local function preload()
	local list: { Instance } = {}
	for _, path in pairs(FILES) do
		local sound = Instance.new("Sound")
		sound.SoundId = path
		table.insert(list, sound)
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	if not ok then
		warn("[Sfx] Vorladen fehlgeschlagen: " .. tostring(err))
	end
	for _, sound in ipairs(list) do
		sound:Destroy()
	end
end

-- ---------------------------------------------------------------------
-- ABSPIELEN
-- ---------------------------------------------------------------------
local function pickVoice(list: { Voice }, is3D: boolean): Voice?
	local count = #list
	if count == 0 then
		return nil
	end
	local start = if is3D then next3D else next2D
	local chosen: Voice? = nil
	local oldest: Voice? = nil
	for offset = 0, count - 1 do
		local index = (start + offset - 1) % count + 1
		local voice = list[index]
		if not voice.Sound.IsPlaying then
			chosen = voice
			if is3D then
				next3D = index % count + 1
			else
				next2D = index % count + 1
			end
			break
		end
		if not oldest or voice.StartedAt < oldest.StartedAt then
			oldest = voice
		end
	end
	return chosen or oldest -- alle belegt: die älteste Stimme wird übernommen
end

local function configure(voice: Voice, layer: Layer, group: SoundGroup?, volume: number, speed: number)
	local sound = voice.Sound
	if sound.SoundId ~= layer.File then
		sound.SoundId = layer.File
	end
	sound.SoundGroup = group
	local jitter = layer.Jitter or 0
	local pitch = layer.Speed * speed
	if jitter > 0 then
		pitch *= 1 + random:NextNumber(-jitter, jitter)
	end
	sound.PlaybackSpeed = math.clamp(pitch, 0.1, 8)
	sound.Volume = math.clamp(layer.Vol * volume, 0, 3)
	local region = layer.Region
	if region then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(region[1], region[2])
	elseif sound.PlaybackRegionsEnabled then
		sound.PlaybackRegionsEnabled = false
	end
	sound.RollOffMaxDistance = layer.Range or DEFAULT_RANGE
	-- Effekte: nur einschalten, was die Schicht braucht (keine neuen Instanzen)
	local dist = layer.Dist
	voice.Dist.Enabled = dist ~= nil
	if dist then
		voice.Dist.Level = dist
	end
	local hasEq = layer.EqLow ~= nil or layer.EqMid ~= nil or layer.EqHigh ~= nil
	voice.Eq.Enabled = hasEq
	if hasEq then
		voice.Eq.LowGain = layer.EqLow or 0
		voice.Eq.MidGain = layer.EqMid or 0
		voice.Eq.HighGain = layer.EqHigh or 0
	end
	local echo = layer.Echo
	voice.Echo.Enabled = echo ~= nil
	if echo then
		voice.Echo.Delay = echo.Delay
		voice.Echo.Feedback = echo.Feedback
		voice.Echo.WetLevel = echo.Wet
		voice.Echo.DryLevel = 0
	end
end

local function playLayer(layer: Layer, groupName: string, pos: Vector3?, volume: number, speed: number)
	local is3D = pos ~= nil
	local voice = pickVoice(if is3D then voices3D else voices2D, is3D)
	if not voice then
		return
	end
	if voice.Sound.IsPlaying then
		voice.Sound:Stop()
	end
	configure(voice, layer, groups[groupName], volume, speed)
	local attachment = voice.Attachment
	if attachment and pos then
		attachment.WorldPosition = pos
	end
	voice.StartedAt = os.clock()
	voice.Sound.TimePosition = if layer.Region then layer.Region[1] else 0
	voice.Sound:Play()
end

-- Eigene Audio-ID aus der Config (0 = eingebautes Rezept)
local function customId(role: string): number
	local config = ctx and ctx.Config
	local sounds = config and config.Client and config.Client.Sounds
	local id = sounds and sounds[role]
	if type(id) == "number" and id > 0 and id % 1 == 0 then
		return id
	end
	return 0
end

local customRecipes: { [string]: Recipe } = {}
local function recipeFor(role: string): Recipe?
	local id = customId(role)
	if id > 0 then
		local cached = customRecipes[role]
		local path = "rbxassetid://" .. tostring(id)
		if not cached or cached.Layers[1].File ~= path then
			local base = RECIPES[role]
			cached = {
				Group = if base then base.Group elseif MUSIC_ROLES[role] then "MUSIC" else "SFX",
				Layers = { { File = path, Speed = 1, Vol = 0.6, Jitter = if base then base.Layers[1].Jitter else nil } },
			}
			customRecipes[role] = cached
		end
		return cached
	end
	return RECIPES[role]
end

function Sfx.Has(role: string): boolean
	return type(role) == "string" and recipeFor(role) ~= nil
end

function Sfx.Play(role: string, pos: Vector3?, opts: { Volume: number?, Speed: number? }?)
	if type(role) ~= "string" or MUSIC_ROLES[role] or LOOP_ROLES[role] then
		return
	end
	local recipe = recipeFor(role)
	if not recipe then
		local now = os.clock()
		if now - (warnedRole[role] or -math.huge) > WARN_GAP then
			warnedRole[role] = now
			warn("[Sfx] Unbekannte Sound-Rolle: " .. role)
		end
		return
	end
	local now = os.clock()
	local dedupeKey = if pos then role .. "@3d" else role
	if now - (lastPlayed[dedupeKey] or -math.huge) < DEDUPE_GAP then
		return
	end
	lastPlayed[dedupeKey] = now
	if pos ~= nil and typeof(pos) ~= "Vector3" then
		pos = nil
	end
	local volume = 1
	local speed = 1
	if type(opts) == "table" then
		if type(opts.Volume) == "number" and opts.Volume == opts.Volume then
			volume = math.clamp(opts.Volume, 0, 3)
		end
		if type(opts.Speed) == "number" and opts.Speed == opts.Speed then
			speed = math.clamp(opts.Speed, 0.25, 4)
		end
	end
	for _, layer in ipairs(recipe.Layers) do
		local delay = layer.Delay or 0
		if delay > 0 then
			task.delay(delay, playLayer, layer, recipe.Group, pos, volume, speed)
		else
			playLayer(layer, recipe.Group, pos, volume, speed)
		end
	end
end

-- Dauer-Ton (z. B. Motor): eigener Sound am parent (BasePart/Attachment = 3D, sonst 2D). Stop() räumt auf.
function Sfx.Loop(role: string, parent: Instance?): LoopHandle?
	if type(role) ~= "string" then
		return nil
	end
	local recipe = recipeFor(role)
	if not recipe or loopCount >= MAX_LOOPS then
		return nil
	end
	local layer = recipe.Layers[1]
	local host: Instance = SoundService
	if typeof(parent) == "Instance" and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		host = parent
	end
	local sound = Instance.new("Sound")
	sound.Name = "AT_Loop_" .. role
	sound.SoundId = layer.File
	sound.Looped = true
	sound.SoundGroup = groups[recipe.Group]
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = MIN_RANGE
	sound.RollOffMaxDistance = layer.Range or DEFAULT_RANGE
	sound.PlaybackSpeed = layer.Speed
	sound.Volume = layer.Vol
	if layer.EqLow or layer.EqMid or layer.EqHigh then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = layer.EqLow or 0
		eq.MidGain = layer.EqMid or 0
		eq.HighGain = layer.EqHigh or 0
		eq.Parent = sound
	end
	sound.Parent = host
	sound:Play()
	loopCount += 1
	local stopped = false
	local baseSpeed = layer.Speed
	local baseVol = layer.Vol
	local function stop()
		if stopped then
			return
		end
		stopped = true
		loopCount = math.max(0, loopCount - 1)
		sound:Stop()
		sound:Destroy()
	end
	-- Träger verschwindet (Auto weg, gestreamt): Loop mit aufräumen
	sound.Destroying:Once(function()
		if not stopped then
			stopped = true
			loopCount = math.max(0, loopCount - 1)
		end
	end)
	return {
		Sound = sound,
		SetSpeed = function(mult: number)
			if not stopped and type(mult) == "number" and mult == mult then
				sound.PlaybackSpeed = math.clamp(baseSpeed * mult, 0.1, 4)
			end
		end,
		SetVolume = function(volume: number)
			if not stopped and type(volume) == "number" and volume == volume then
				sound.Volume = math.clamp(baseVol * volume, 0, 3)
			end
		end,
		Stop = stop,
	}
end

-- Welt-/Effekt-Sounds und Musik kurz leiser (Oberfläche bleibt) – z. B. während der Glocke oder einer Ansage
function Sfx.Duck(amount: number, seconds: number)
	if type(amount) ~= "number" or type(seconds) ~= "number" or amount ~= amount or seconds ~= seconds then
		return
	end
	duckToken += 1
	local token = duckToken
	duckFactor = 1 - math.clamp(amount, 0, 0.9)
	applyGroupVolumes()
	task.delay(math.clamp(seconds, 0.01, 10), function()
		if duckToken == token then
			duckFactor = 1
			applyGroupVolumes()
		end
	end)
end

-- Musik: nur mit eingetragener ID (Config.Client.Sounds.Music bzw. Music<kind>); nil = aus
function Sfx.SetMusic(kind: string?)
	local music = musicSound
	if not music then
		return
	end
	local id = 0
	if type(kind) == "string" and kind ~= "" then
		id = customId("Music" .. kind)
		if id == 0 then
			id = customId("Music")
		end
	end
	if id == 0 then
		musicKind = nil
		if music.IsPlaying then
			music:Stop()
		end
		return
	end
	local path = "rbxassetid://" .. tostring(id)
	if musicKind == kind and music.IsPlaying and music.SoundId == path then
		return
	end
	musicKind = kind
	music.SoundId = path
	music.TimePosition = 0
	music:Play()
end

local function settingNumber(settings: any, key: string, fallback: number): number
	local value = settings and settings[key]
	if type(value) == "number" and value == value then
		return math.clamp(value, 0, 1)
	end
	return fallback
end

function Sfx.ApplySettings(settings: { [string]: any }?)
	baseVolume.SFX = settingNumber(settings, "Sfx", 1)
	baseVolume.UI = settingNumber(settings, "Ui", 0.8)
	baseVolume.MUSIC = settingNumber(settings, "Music", 0.5)
	applyGroupVolumes()
end

function Sfx.Init(context: any)
	ctx = context
	build()
	local settingsModule = ctx.Modules and ctx.Modules.Settings
	if settingsModule and type(settingsModule.Get) == "function" then
		local ok, settings = pcall(settingsModule.Get)
		if ok then
			Sfx.ApplySettings(settings)
		end
	else
		local config = ctx.Config
		Sfx.ApplySettings(config and config.Client and config.Client.DefaultSettings or nil)
	end
	ctx.Hooks.On("Settings", function(settings)
		Sfx.ApplySettings(settings)
	end)
	-- Ansagen und Glocke: Welt kurz leiser
	ctx.Hooks.On("Effect:Announce", function()
		Sfx.Duck(0.5, 1.5)
	end)
end

function Sfx.Start()
	task.spawn(preload)
	Sfx.SetMusic("World")
	if anchorPart and anchorPart.Parent == nil then
		anchorPart.Parent = workspace
	end
end

return Sfx
