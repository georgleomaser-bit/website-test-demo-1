--[[
	Sounds (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Sounds

	All sound effects in one place. The defaults use sound files that ship
	with every Roblox client (rbxasset://sounds/...), so the game has audio
	without uploading anything. Replace any Id with your own
	"rbxassetid://<number>" from the Creator Store to customise the audio.

	Music: Roblox does not ship background music with the client, so Music.Id
	is empty by default. Paste the asset id of a track you own or that is
	free to use, e.g. "rbxassetid://1234567890". The music volume setting
	works as soon as an id is set.
]]

local Sounds = {
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.45, PitchMin = 0.95, PitchMax = 1.08 },
	Crit = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, PitchMin = 1.1, PitchMax = 1.25 },
	Streak = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, PitchMin = 0.7, PitchMax = 0.75 },
	Golden = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, PitchMin = 1.45, PitchMax = 1.5 },
	Purchase = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, PitchMin = 0.95, PitchMax = 1.0 },
	Error = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, PitchMin = 0.5, PitchMax = 0.55 },
	UIHover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.12, PitchMin = 1.6, PitchMax = 1.7 },
	UIClick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.3, PitchMin = 1.2, PitchMax = 1.3 },
	UIOpen = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.25, PitchMin = 1.2, PitchMax = 1.3 },
	ChestShake = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.35, PitchMin = 0.7, PitchMax = 0.9 },
	ChestBurst = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6, PitchMin = 0.8, PitchMax = 0.85 },
	Reveal = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, PitchMin = 1.0, PitchMax = 1.0 },
	LevelUp = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.65, PitchMin = 0.85, PitchMax = 0.85 },
	Unlock = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, PitchMin = 1.3, PitchMax = 1.3 },
	Orb = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.35, PitchMin = 1.5, PitchMax = 1.6 },
	Announcement = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, PitchMin = 0.6, PitchMax = 0.6 },
	Music = { Id = "", Volume = 0.35 },
}

return Sounds
