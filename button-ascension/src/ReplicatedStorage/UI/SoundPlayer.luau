--[[
	SoundPlayer (ModuleScript)
	Location: ReplicatedStorage/UI/SoundPlayer
	Depends on: Shared/Config/Sounds

	Client-side sound effects and music. Sounds are pooled (a few instances
	per effect, used round-robin) so rapid clicking never creates garbage.
	Volumes follow the player's SFX / Music settings and are capped at
	MAX_VOLUME. A sound's Custom id (Creator Store audio) replaces its
	built-in Id when it is set.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))

local SoundPlayer = {}

local POOL_SIZE = 4
local MAX_VOLUME = 0.8
local sfxVolume = 0.7
local musicVolume = 0.4
local pools: { [string]: { sounds: { Sound }, index: number } } = {}
local folder: Folder? = nil
local music: Sound? = nil
local rng = Random.new()

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "ButtonAscensionSounds"
	f.Parent = SoundService
	folder = f
	return f
end

local function getPool(name: string)
	local pool = pools[name]
	if pool then
		return pool
	end
	local def = Sounds[name]
	if type(def) ~= "table" then
		return nil
	end
	local id = if type(def.Custom) == "string" and def.Custom ~= "" then def.Custom else def.Id
	if type(id) ~= "string" or id == "" then
		return nil
	end
	pool = { sounds = {}, index = 1 }
	for i = 1, def.Pool or POOL_SIZE do
		local sound = Instance.new("Sound")
		sound.Name = name .. i
		sound.SoundId = id
		sound.Volume = def.Volume * sfxVolume
		sound.Parent = getFolder()
		table.insert(pool.sounds, sound)
	end
	pools[name] = pool
	return pool
end

-- opts: { Pitch = number, Volume = multiplier }
function SoundPlayer.play(name: string, opts: { Pitch: number?, Volume: number? }?)
	if sfxVolume <= 0 then
		return
	end
	local def = Sounds[name]
	local pool = getPool(name)
	if not def or not pool then
		return
	end
	local sound = pool.sounds[pool.index]
	pool.index = (pool.index % #pool.sounds) + 1
	local pitch = if opts and opts.Pitch then opts.Pitch else rng:NextNumber(def.PitchMin or 1, def.PitchMax or 1)
	sound.PlaybackSpeed = pitch
	sound.Volume = math.min(MAX_VOLUME, def.Volume * sfxVolume * (if opts and opts.Volume then opts.Volume else 1))
	sound.TimePosition = 0
	sound:Play()
end

-- Plays `name` once per pitch in `notes`, `gap` seconds apart (arpeggios, fanfares).
function SoundPlayer.sequence(name: string, notes: { number }, gap: number, opts: { Volume: number? }?)
	for i, pitch in ipairs(notes) do
		local volume = if opts and opts.Volume then opts.Volume else 1
		if i == 1 then
			SoundPlayer.play(name, { Pitch = pitch, Volume = volume })
		else
			task.delay((i - 1) * gap, SoundPlayer.play, name, { Pitch = pitch, Volume = volume })
		end
	end
end

function SoundPlayer.setVolumes(sfx: number, musicVol: number)
	sfxVolume = math.clamp(sfx, 0, 1)
	musicVolume = math.clamp(musicVol, 0, 1)
	if music then
		music.Volume = Sounds.Music.Volume * musicVolume
		if musicVolume <= 0 then
			music:Pause()
		elseif not music.IsPlaying then
			music:Resume()
		end
	end
end

-- Starts looping background music if Sounds.Music.Id is configured.
function SoundPlayer.startMusic()
	if music or Sounds.Music.Id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = Sounds.Music.Id
	sound.Looped = true
	sound.Volume = Sounds.Music.Volume * musicVolume
	sound.Parent = getFolder()
	music = sound
	if musicVolume > 0 then
		sound:Play()
	end
end

function SoundPlayer.hasMusic(): boolean
	return Sounds.Music.Id ~= ""
end

return SoundPlayer
