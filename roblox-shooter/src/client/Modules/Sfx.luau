-- =====================================================================
--  CLUTCH CLASH – Sounds nur aus eingebauten Dateien (Client/Modules/Sfx)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C7.4, B14.1, docs/ASSETS.md §2.2.
--
--  Jede Rolle (z. B. "RifleShot", "Headshot", "Kill") ist ein REZEPT aus den 11 eingebauten
--  Roblox-Sounds: Tonhöhe (PlaybackSpeed), Ausschnitt (PlaybackRegion), Effekte (Verzerrung,
--  Equalizer, Echo) und mehrere Schichten nacheinander (Jingles). Trägt der Besitzer in
--  Config.Client.Sounds.<Rolle> eine Audio-ID ein (≠ 0), wird stattdessen diese gespielt.
--  Feste Stimmen-Vorräte (Pools.Sounds: halb 2D, halb 3D) im Rundlauf – kein neues Sound-Objekt
--  pro Schuss. Lautstärke über SoundGroups (Einstellungen Sfx / Ui / Musik).
--
--  Öffentliche API:
--    Sfx.Play(role, pos?, opts?)        opts { Volume?, Speed? } – pos = 3D-Sound an dieser Stelle
--    Sfx.Has(role): boolean             gibt es ein Rezept/eine ID für die Rolle?
--    Sfx.Duck(amount, seconds)          andere Kampf-Sounds kurz leiser (Treffer-Stopp, Kill-Bestätigung)
--    Sfx.SetMusic(kind?)                "Lobby" | "Match" | nil – nur mit eingetragener Musik-ID
--    Sfx.ApplySettings(settings)        Lautstärken übernehmen (macht der "Settings"-Hook automatisch)
--    Sfx.Init(ctx) / Sfx.Start()
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
	Ouch = "rbxasset://sounds/ouch.ogg",
	Oof = "rbxasset://sounds/oof.ogg",
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
local ECHO_SNIPER: Echo = { Delay = 0.15, Feedback = 0.25, Wet = -8 }
local ECHO_JINGLE: Echo = { Delay = 0.12, Feedback = 0.3, Wet = -4 }

-- Gruppen: SFX (wird beim Treffer-Stopp kurz leiser), HIT (Treffer-Töne – nie geduckt), UI, MUSIC
local function notes(file: string, speeds: { number }, gap: number, vol: number, extra: { [string]: any }?): { Layer }
	local list: { Layer } = {}
	for i, speed in ipairs(speeds) do
		local layer: Layer = { File = file, Speed = speed, Vol = vol, Delay = (i - 1) * gap }
		if extra then
			if extra.EchoLast and i == #speeds then
				layer.Echo = ECHO_JINGLE
			end
			if extra.EchoAll then
				layer.Echo = ECHO_JINGLE
			end
			if extra.EqHigh then
				layer.EqHigh = extra.EqHigh
			end
		end
		table.insert(list, layer)
	end
	return list
end

-- Startwerte aus ASSETS.md §2.2 (nach Gehör im Studio nachstellen)
local RECIPES: { [string]: Recipe } = {
	PistolShot = {
		Group = "SFX",
		Layers = {
			{
				File = FILES.Boom,
				Speed = 2.4,
				Vol = 0.6,
				Region = { 0, 0.3 },
				Dist = 0.5,
				EqLow = -6,
				EqHigh = 4,
				Jitter = 0.04,
			},
			{ File = FILES.Land, Speed = 3.0, Vol = 0.35, Jitter = 0.04 },
		},
	},
	RifleShot = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Boom, Speed = 3.0, Vol = 0.45, Region = { 0, 0.2 }, Dist = 0.6, EqHigh = 6, Jitter = 0.04 },
		},
	},
	SmgShot = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Boom, Speed = 3.3, Vol = 0.4, Region = { 0, 0.16 }, Dist = 0.6, EqHigh = 6, Jitter = 0.04 },
		},
	},
	ShotgunShot = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Boom, Speed = 1.7, Vol = 0.8, Region = { 0, 0.5 }, Dist = 0.75, EqLow = 4, Jitter = 0.04 },
			{ File = FILES.GetUp, Speed = 1.8, Vol = 0.4, Region = { 0, 0.25 }, Delay = 0.32 }, -- Pump
		},
	},
	SniperShot = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Boom, Speed = 1.3, Vol = 0.9, Dist = 0.4, Echo = ECHO_SNIPER, Jitter = 0.03, Range = 600 },
		},
	},
	CannonShot = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Boom, Speed = 1.5, Vol = 0.75, Region = { 0, 0.45 }, Dist = 0.5, EqLow = 6, Jitter = 0.04 },
		},
	},
	RocketLaunch = {
		Group = "SFX",
		Layers = { { File = FILES.Wind, Speed = 2.2, Vol = 0.6, Region = { 0, 0.6 }, EqHigh = 6, Jitter = 0.03 } },
	},
	Explosion = {
		Group = "SFX",
		Layers = { { File = FILES.Boom, Speed = 1.0, Vol = 1.0, Dist = 0.2, Jitter = 0.1, Range = 500 } },
	},
	DryFire = { Group = "SFX", Layers = { { File = FILES.Tick, Speed = 0.8, Vol = 0.5 } } },
	MagOut = { Group = "SFX", Layers = { { File = FILES.Land, Speed = 3.2, Vol = 0.5, EqHigh = 4 } } },
	MagIn = { Group = "SFX", Layers = { { File = FILES.Land, Speed = 2.6, Vol = 0.5, Dist = 0.2 } } },
	Bolt = { Group = "SFX", Layers = { { File = FILES.GetUp, Speed = 2.0, Vol = 0.5, Region = { 0, 0.25 } } } },
	LowAmmo = { Group = "SFX", Layers = notes(FILES.Tick, { 1.2, 1.2 }, 0.07, 0.4) },
	Equip = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Jump, Speed = 2.2, Vol = 0.3 },
			{ File = FILES.Land, Speed = 3.0, Vol = 0.3, Delay = 0.08 },
		},
	},
	MeleeSwing = { Group = "SFX", Layers = { { File = FILES.Jump, Speed = 1.8, Vol = 0.5, Jitter = 0.05 } } },
	MeleeHit = {
		Group = "SFX",
		Layers = {
			{ File = FILES.Land, Speed = 1.4, Vol = 0.6, Dist = 0.3, Jitter = 0.05 },
			{ File = FILES.Tick, Speed = 1.2, Vol = 0.3 },
		},
	},
	Throw = { Group = "SFX", Layers = { { File = FILES.Jump, Speed = 1.5, Vol = 0.45, Jitter = 0.05 } } },
	Heal = { Group = "SFX", Layers = notes(FILES.Tick, { 1.26, 1.5 }, 0.08, 0.4) },
	Water = { Group = "SFX", Layers = { { File = FILES.Water, Speed = 1.3, Vol = 0.5, Jitter = 0.05 } } },
	Slide = { Group = "SFX", Layers = { { File = FILES.Wind, Speed = 1.6, Vol = 0.35, Region = { 0, 0.5 } } } },
	-- Treffer-Feedback (B14.1 + SKILL-WÜNSCHE): knackig, hoch, kurz – eigene Gruppe, wird nie geduckt
	Hitmarker = { Group = "HIT", Layers = { { File = FILES.Tick, Speed = 1.6, Vol = 0.55 } } },
	Headshot = {
		Group = "HIT",
		Layers = {
			{ File = FILES.Tick, Speed = 2.2, Vol = 0.75, Echo = ECHO_DING },
			{ File = FILES.Tick, Speed = 2.8, Vol = 0.75, Echo = ECHO_DING, Delay = 0.05 },
		},
	},
	Kill = { Group = "HIT", Layers = notes(FILES.Tick, { 1.0, 1.26, 1.5 }, 0.06, 0.75) },
	Eliminated = { Group = "HIT", Layers = { { File = FILES.Ouch, Speed = 1.0, Vol = 0.6 } } },
	Hurt = { Group = "SFX", Layers = { { File = FILES.Ouch, Speed = 1.15, Vol = 0.22 } } }, -- leise, nur ≤ 30 HP
	-- Oberfläche
	UIClick = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 1.0, Vol = 0.5 } } },
	UIHover = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 1.5, Vol = 0.2 } } },
	UIError = { Group = "UI", Layers = { { File = FILES.Land, Speed = 0.7, Vol = 0.5 } } },
	Countdown = { Group = "UI", Layers = { { File = FILES.Tick, Speed = 1.0, Vol = 0.7 } } },
	Go = {
		Group = "UI",
		Layers = {
			{ File = FILES.Tick, Speed = 2.0, Vol = 0.7 },
			{ File = FILES.Tick, Speed = 1.5, Vol = 0.5 },
		},
	},
	Win = { Group = "UI", Layers = notes(FILES.Tick, { 1.0, 1.26, 1.5, 2.0 }, 0.09, 0.8, { EchoLast = true }) },
	Lose = { Group = "UI", Layers = notes(FILES.Tick, { 1.0, 0.841, 0.667 }, 0.16, 0.7, { EqHigh = -6 }) },
	LevelUp = { Group = "UI", Layers = notes(FILES.Tick, { 1.0, 1.26, 1.5, 2.0 }, 0.09, 0.8, { EchoAll = true }) },
	Oof = { Group = "UI", Layers = { { File = FILES.Oof, Speed = 1.0, Vol = 0.4 } } },
}

-- Rollen ohne eingebautes Rezept (nur mit eigener ID): Musik
local MUSIC_ROLES = { LobbyMusic = true, MatchMusic = true }
-- Treffer-Töne, die die Einstellung "Treffer-Ton" abschaltet
local HIT_SOUND_ROLES = { Hitmarker = true, Headshot = true }

local DEDUPE_GAP = 0.025 -- dieselbe Rolle innerhalb so kurzer Zeit nur einmal (zwei Module melden denselben Treffer)
local DEFAULT_RANGE = 300
local MIN_RANGE = 10
local WARN_GAP = 30

type Voice = {
	Sound: Sound,
	Dist: DistortionSoundEffect,
	Eq: EqualizerSoundEffect,
	Echo: EchoSoundEffect,
	Attachment: Attachment?,
	StartedAt: number,
}

local voices2D: { Voice } = {}
local voices3D: { Voice } = {}
local next2D = 1
local next3D = 1
local groups: { [string]: SoundGroup } = {}
local baseVolume: { [string]: number } = { SFX = 1, HIT = 1, UI = 0.8, MUSIC = 0.5 }
local duckFactor = 1
local duckToken = 0
local lastPlayed: { [string]: number } = {}
local warnedRole: { [string]: number } = {}
local hitSoundOn = true
local anchorPart: Part? = nil
local musicSound: Sound? = nil
local musicKind: string? = nil
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
	local existing = SoundService:FindFirstChild("ClutchClash" .. name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = "ClutchClash" .. name
	group.Volume = 1
	group.Parent = SoundService
	return group
end

local function applyGroupVolumes()
	for name, group in pairs(groups) do
		local volume = baseVolume[name] or 1
		if name == "SFX" then
			volume *= duckFactor
		end
		group.Volume = math.clamp(volume, 0, 2)
	end
end

local function build()
	groups.SFX = makeGroup("Sfx")
	groups.HIT = makeGroup("Hit")
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
	folder2D.Name = "ClutchClashVoices"
	folder2D.Parent = SoundService
	for i = 1, half do
		table.insert(voices2D, makeVoice(folder2D, "Voice2D_" .. i, nil))
	end

	-- 3D-Stimmen: an Attachments eines unsichtbaren Ankers im Ursprung (WorldPosition = Klangquelle)
	local anchor = Instance.new("Part")
	anchor.Name = "ClutchClashSfxAnchor"
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
	music.Name = "ClutchClashMusic"
	music.Looped = true
	music.Volume = 0.5
	music.SoundGroup = groups.MUSIC
	music.Parent = SoundService
	musicSound = music

	applyGroupVolumes()
end

-- Eingebaute Dateien einmal vorladen (sonst kann der allererste Schuss stumm sein)
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
	if type(role) ~= "string" or MUSIC_ROLES[role] then
		return
	end
	if HIT_SOUND_ROLES[role] and not hitSoundOn then
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
	if pos and typeof(pos) ~= "Vector3" then
		pos = nil
	end
	local volume = 1
	local speed = 1
	if opts then
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

-- Kampf-Sounds kurz leiser (Treffer-Töne bleiben laut) – fühlt sich wie ein kleiner "Treffer-Stopp" an
function Sfx.Duck(amount: number, seconds: number)
	if type(amount) ~= "number" or type(seconds) ~= "number" or amount ~= amount or seconds ~= seconds then
		return
	end
	duckToken += 1
	local token = duckToken
	duckFactor = 1 - math.clamp(amount, 0, 0.9)
	applyGroupVolumes()
	task.delay(math.clamp(seconds, 0.01, 1), function()
		if duckToken == token then
			duckFactor = 1
			applyGroupVolumes()
		end
	end)
end

function Sfx.SetMusic(kind: string?)
	local music = musicSound
	if not music then
		return
	end
	local role = if kind == "Lobby" then "LobbyMusic" elseif kind == "Match" then "MatchMusic" else nil
	local id = if role then customId(role) else 0
	if id == 0 then
		musicKind = nil
		if music.IsPlaying then
			music:Stop()
		end
		return
	end
	if musicKind == kind and music.IsPlaying then
		return
	end
	musicKind = kind
	music.SoundId = "rbxassetid://" .. tostring(id)
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
	local sfx = settingNumber(settings, "Sfx", 1)
	baseVolume.SFX = sfx
	baseVolume.HIT = sfx
	baseVolume.UI = settingNumber(settings, "Ui", 0.8)
	baseVolume.MUSIC = settingNumber(settings, "Music", 0.5)
	hitSoundOn = not (settings and settings.HitSound == false)
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
	end
	ctx.Hooks.On("Settings", function(settings)
		Sfx.ApplySettings(settings)
	end)
	-- Musik je Welt (nur wenn der Besitzer eine Musik-ID eingetragen hat)
	ctx.Hooks.On("World", function(world)
		Sfx.SetMusic(if world == "Lobby" then "Lobby" else "Match")
	end)
end

function Sfx.Start()
	task.spawn(preload)
	Sfx.SetMusic("Lobby")
	if anchorPart and anchorPart.Parent == nil then
		anchorPart.Parent = workspace
	end
end

return Sfx
