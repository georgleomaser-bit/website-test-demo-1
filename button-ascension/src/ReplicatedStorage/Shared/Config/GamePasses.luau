--[[
	GamePasses (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/GamePasses

	Robux game passes: bought once, owned forever. Ownership is checked on the
	SERVER only (GamePassService); the client can just open the Roblox purchase
	prompt. Effects are applied in Shared/Formulas, so the store previews and the
	server always agree.

	================================================================
	HOW TO SET UP A PASS (once per pass)
	================================================================
	1. Publish the game (File → Publish to Roblox).
	2. Open create.roblox.com → Creations → your experience →
	   Monetization → Passes → "Create a Pass".
	3. Upload an image (512 × 512; ready-made ones are in branding/passes/),
	   enter the name and description from the list below and click
	   "Create Pass".
	4. Open the new pass → Sales → turn "Item for Sale" on, set the price
	   (SuggestedPrice below is a good start) and save.
	5. Copy the pass ID (the number in the pass's URL or under "Copy Asset ID")
	   and paste it as GamePassId below, e.g.  GamePassId = 123456789,
	6. Publish again. Passes with GamePassId = 0 are "not set up": they are
	   hidden in live games and do nothing.
	================================================================

	Effects use the same stats as skills (see Shared/Formulas):
	  { Stat = "...", Add = n }   adds to a stat
	  { Stat = "...", Mult = n }  multiplies a stat (stacks multiplicatively)
	Special stats: autoRatePass (auto presses/s on top of the upgrade cap),
	gemsMult (×Gems), extraOpen (more crates per opening).
]]

export type Effect = { Stat: string, Add: number?, Mult: number? }

export type Pass = {
	Key: string,
	Name: string,
	Icon: string,
	Color: Color3,
	Description: string,
	EffectText: string,
	Effects: { Effect },
	SkipCrateAnimation: boolean?,
	Op: boolean?,
	SuggestedPrice: number,
	GamePassId: number,
	Order: number?, -- set from the list position below
}

local GamePasses = {}

GamePasses.List = {
	{
		Key = "auto_clicker",
		Name = "Auto Clicker",
		Icon = "🤖",
		Color = Color3.fromRGB(77, 225, 255),
		Description = "Presses the button for you, even while you do other things.",
		EffectText = "+5 auto presses per second (on top of the upgrade limit)",
		Effects = { { Stat = "autoRatePass", Add = 5 } },
		SuggestedPrice = 99,
		GamePassId = 0,
	},
	{
		Key = "op_auto_clicker",
		Name = "OP Auto Clicker",
		Icon = "🚀",
		Color = Color3.fromRGB(255, 61, 110),
		Description = "A turbo presser. Stacks with Auto Clicker for +20 presses per second.",
		EffectText = "+15 auto presses per second",
		Effects = { { Stat = "autoRatePass", Add = 15 } },
		Op = true,
		SuggestedPrice = 349,
		GamePassId = 0,
	},
	{
		Key = "double_sparks",
		Name = "2× Sparks",
		Icon = "⚡",
		Color = Color3.fromRGB(255, 214, 74),
		Description = "Doubles every Spark you earn: presses, auto presses and passive income.",
		EffectText = "×2 Sparks",
		Effects = { { Stat = "sparksMult", Mult = 2 } },
		SuggestedPrice = 199,
		GamePassId = 0,
	},
	{
		Key = "triple_sparks",
		Name = "3× Sparks",
		Icon = "🌟",
		Color = Color3.fromRGB(255, 160, 40),
		Description = "Triples every Spark you earn. Stacks with 2× Sparks for ×6.",
		EffectText = "×3 Sparks (×6 with 2× Sparks)",
		Effects = { { Stat = "sparksMult", Mult = 3 } },
		Op = true,
		SuggestedPrice = 799,
		GamePassId = 0,
	},
	{
		Key = "double_gems",
		Name = "2× Gems",
		Icon = "💎",
		Color = Color3.fromRGB(77, 225, 255),
		Description = "Doubles Gems from quests, achievements, golden presses, orbs and selling items.",
		EffectText = "×2 Gems",
		Effects = { { Stat = "gemsMult", Mult = 2 } },
		SuggestedPrice = 149,
		GamePassId = 0,
	},
	{
		Key = "lucky",
		Name = "Lucky Pass",
		Icon = "🍀",
		Color = Color3.fromRGB(74, 222, 128),
		Description = "Better crate odds for rarer items.",
		EffectText = "+50% Luck",
		Effects = { { Stat = "luck", Add = 0.5 } },
		SuggestedPrice = 249,
		GamePassId = 0,
	},
	{
		Key = "super_luck",
		Name = "Super Luck",
		Icon = "🎰",
		Color = Color3.fromRGB(176, 92, 255),
		Description = "Massively better crate odds. Stacks with Lucky Pass for +200% Luck.",
		EffectText = "+150% Luck",
		Effects = { { Stat = "luck", Add = 1.5 } },
		Op = true,
		SuggestedPrice = 599,
		GamePassId = 0,
	},
	{
		Key = "fast_crates",
		Name = "Fast Crates",
		Icon = "📦",
		Color = Color3.fromRGB(255, 200, 70),
		Description = "Skips the crate animation and lets you open up to 20 crates at once.",
		EffectText = "Instant openings · open ×20",
		Effects = { { Stat = "extraOpen", Add = 10 } },
		SkipCrateAnimation = true,
		Op = true,
		SuggestedPrice = 499,
		GamePassId = 0,
	},
	{
		Key = "vip",
		Name = "VIP",
		Icon = "👑",
		Color = Color3.fromRGB(255, 196, 60),
		Description = "The VIP bundle: more Sparks, more Gems and faster levels.",
		EffectText = "×1.25 Sparks · ×1.25 Gems · ×1.25 XP",
		Effects = {
			{ Stat = "sparksMult", Mult = 1.25 },
			{ Stat = "gemsMult", Mult = 1.25 },
			{ Stat = "xpMult", Mult = 1.25 },
		},
		SuggestedPrice = 399,
		GamePassId = 0,
	},
} :: { Pass }

GamePasses.ByKey = {} :: { [string]: Pass }
for index, pass in ipairs(GamePasses.List) do
	pass.Order = index
	GamePasses.ByKey[pass.Key] = pass
end

-- A pass is live only once its Roblox pass ID has been pasted in.
function GamePasses.isConfigured(pass: Pass): boolean
	return type(pass.GamePassId) == "number" and pass.GamePassId > 0
end

-- The configured pass with this Roblox ID (IDs are read live, so edits in
-- Studio or tests take effect without re-requiring the module).
function GamePasses.byGamePassId(id: any): Pass?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	for _, pass in ipairs(GamePasses.List) do
		if pass.GamePassId == id then
			return pass
		end
	end
	return nil
end

-- Whether owned-pass data (data.Passes) includes this configured pass.
function GamePasses.owns(passes: any, key: string): boolean
	local pass = GamePasses.ByKey[key]
	return pass ~= nil and type(passes) == "table" and passes[key] == true and GamePasses.isConfigured(pass)
end

return GamePasses
