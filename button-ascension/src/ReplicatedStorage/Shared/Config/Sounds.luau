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

	Crate-opening sounds ("Crate..." below) are built from the three bundled
	files, layered and pitch-shifted into ticks, a boom, rising chimes and
	rarity fanfares. Each has an optional Custom slot: paste a Creator Store
	sound ("rbxassetid://<number>") there to use it instead; leave it "" to
	keep the built-in sound. Every Volume stays at or below 0.7 and the SFX
	volume setting scales all of them.
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
	-- Crate openings: accelerating ticks with rising pitch, a whoosh + boom on the
	-- burst, a chime per revealed card (pitch climbs card by card) and a fanfare
	-- that grows with the best rarity (Epic / Legendary / Mythic & Secret).
	CrateTick = { Id = "rbxasset://sounds/clickfast.wav", Custom = "", Volume = 0.32, PitchMin = 1, PitchMax = 1 },
	CrateWhoosh = { Id = "rbxasset://sounds/swoosh.wav", Custom = "", Volume = 0.45, PitchMin = 0.55, PitchMax = 0.6 },
	CrateBoom = { Id = "rbxasset://sounds/electronicpingshort.wav", Custom = "", Volume = 0.55, PitchMin = 0.42, PitchMax = 0.45 },
	CrateChime = { Id = "rbxasset://sounds/electronicpingshort.wav", Custom = "", Volume = 0.42, PitchMin = 1, PitchMax = 1, Pool = 8 },
	CrateSparkle = { Id = "rbxasset://sounds/electronicpingshort.wav", Custom = "", Volume = 0.3, PitchMin = 2.0, PitchMax = 2.2, Pool = 6 },
	CrateFanfare = { Id = "rbxasset://sounds/electronicpingshort.wav", Custom = "", Volume = 0.5, PitchMin = 1, PitchMax = 1, Pool = 8 },
	CrateJackpot = { Id = "rbxasset://sounds/swoosh.wav", Custom = "", Volume = 0.5, PitchMin = 1.4, PitchMax = 1.5 },
	Music = { Id = "", Volume = 0.35 },
}

--[[
	Fanfare note patterns (playback-speed ratios; 1.26 ≈ major third, 1.5 = fifth,
	2 = octave). Played as quick arpeggios by ChestOpening for the best drop.
]]
Sounds.CrateFanfares = {
	Epic = { Notes = { 1, 1.26, 1.5 }, Gap = 0.08 },
	Legendary = { Notes = { 1, 1.26, 1.5, 2 }, Gap = 0.09, Sparkle = true },
	Mythic = { Notes = { 0.75, 1, 1.26, 1.5, 2, 2.52 }, Gap = 0.08, Sparkle = true, Jackpot = true },
}

return Sounds
