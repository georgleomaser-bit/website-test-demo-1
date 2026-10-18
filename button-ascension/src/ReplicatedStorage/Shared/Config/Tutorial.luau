--[[
	Tutorial (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Tutorial

	The first-time tutorial. Each step completes when the player really does
	the thing; the SERVER decides (ServerScriptService/Services/TutorialService):
	  Kind = "stat"   a saved counter grew by Amount since the step started
	  Kind = "equip"  at least one item is equipped
	  Kind = "seen"   the client reports the player looked at something
	                  (only accepted for the step that is currently active)
	Target names the HUD element the arrow points at (see Hud.target).
]]

local Tutorial = {}

Tutorial.Steps = {
	{
		Id = "press",
		Title = "Press the button",
		Text = "Tap PRESS (or press E / R2) to earn Sparks ⚡. Press it 10 times.",
		Target = "press",
		Kind = "stat",
		Stat = "TotalClicks",
		Amount = 10,
	},
	{
		Id = "upgrade",
		Title = "Buy an upgrade",
		Text = "Open the Shop 🛒 and buy your first upgrade. Upgrades make every press stronger.",
		Target = "nav:Shop",
		Kind = "stat",
		Stat = "UpgradesPurchased",
		Amount = 1,
	},
	{
		Id = "crate",
		Title = "Open a crate",
		Text = "Claim your free crate on the quest card ➡, then open it in the Crates menu 🎁.",
		Target = "nav:Chests",
		Kind = "stat",
		Stat = "ChestsOpened",
		Amount = 1,
	},
	{
		Id = "equip",
		Title = "Equip an item",
		Text = "Open your Items 🎒 and equip what you found. Equipped items give bonuses.",
		Target = "nav:Inventory",
		Kind = "equip",
	},
	{
		Id = "quests",
		Title = "Check your quests",
		Text = "Quests 📜 give free rewards. Open them any time from here.",
		Target = "quests",
		Kind = "seen",
	},
	{
		Id = "obby",
		Title = "Run the Obby",
		Text = "Press ▶ to go to the Obby and reach checkpoint 1. Your auto-presses keep earning while you run!",
		Target = "obby",
		Kind = "stat",
		Stat = "ObbyCheckpoints",
		Amount = 1,
	},
	{
		Id = "auto",
		Title = "Earn while you explore",
		Text = "Buy Auto-Presser upgrades in the Shop: they press for you, even while you run the Obby. You're all set!",
		Target = "nav:Shop",
		Kind = "seen",
		Final = true,
	},
}

Tutorial.ById = {}
for index, step in ipairs(Tutorial.Steps) do
	step.Index = index
	Tutorial.ById[step.Id] = step
end

-- Paid once, the first time the tutorial is finished (not when skipped or replayed).
Tutorial.Reward = { Gems = 50 }

return Tutorial
