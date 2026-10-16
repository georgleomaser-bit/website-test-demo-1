--[[
	Sounds abspielen (eingebaute Roblox-Sounds, siehe Config.Sounds).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)

local Sound = {}

local lastPlayed: { [string]: number } = {}
local music: Sound? = nil

function Sound.Play(key: string, volume: number?, pitch: number?, minGap: number?)
	if not State.Setting("Sfx") then
		return
	end
	local id = Config.Sounds[key]
	if not id or id == "" then
		return
	end
	local now = os.clock()
	if minGap and (lastPlayed[key] or 0) + minGap > now then
		return
	end
	lastPlayed[key] = now
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function Sound.UpdateMusic()
	local id = Config.Sounds.Music
	if not id or id == "" then
		return
	end
	if not music then
		local m = Instance.new("Sound")
		m.Name = "Music"
		m.SoundId = id
		m.Looped = true
		m.Volume = 0.25
		m.Parent = SoundService
		music = m
	end
	local s = music :: Sound
	if State.Setting("Music") then
		if not s.IsPlaying then
			s:Play()
		end
	else
		s:Stop()
	end
end

return Sound
