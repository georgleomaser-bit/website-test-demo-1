--[[
	Theme (ModuleScript)
	Location: ReplicatedStorage/UI/Theme
	Depends on: Shared/Config/GameConfig, Shared/Config/Rarities

	Design tokens for the whole interface: colours, typography, radii and
	motion. The player UI and the admin panel share these tokens; the admin
	panel swaps in its own accent palette (Theme.Admin) so it is clearly
	distinct while keeping the same design language.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(9, 9, 17),
	BackgroundAlt = Color3.fromRGB(15, 14, 27),
	Panel = Color3.fromRGB(20, 19, 35),
	PanelLight = Color3.fromRGB(30, 28, 50),
	PanelLighter = Color3.fromRGB(42, 39, 68),
	Stroke = Color3.fromRGB(62, 57, 98),
	StrokeSoft = Color3.fromRGB(42, 39, 66),
	Text = Color3.fromRGB(242, 240, 255),
	TextDim = Color3.fromRGB(176, 171, 208),
	TextMuted = Color3.fromRGB(118, 113, 150),
	Accent = Color3.fromRGB(255, 61, 110),
	AccentSoft = Color3.fromRGB(140, 30, 70),
	Accent2 = Color3.fromRGB(77, 225, 255),
	Accent3 = Color3.fromRGB(176, 92, 255),
	Success = Color3.fromRGB(64, 220, 130),
	Warning = Color3.fromRGB(255, 190, 60),
	Danger = Color3.fromRGB(255, 72, 88),
	Gold = Color3.fromRGB(255, 205, 64),
	Black = Color3.new(0, 0, 0),
	White = Color3.new(1, 1, 1),
	Sparks = GameConfig.Currencies.Sparks.Color,
	Gems = GameConfig.Currencies.Gems.Color,
	Prisms = GameConfig.Currencies.Prisms.Color,
}

-- Admin panel palette: same structure, neon green + magenta on near-black teal.
Theme.Admin = {
	Background = Color3.fromRGB(6, 11, 13),
	Panel = Color3.fromRGB(11, 19, 22),
	PanelLight = Color3.fromRGB(17, 29, 33),
	PanelLighter = Color3.fromRGB(25, 42, 47),
	Stroke = Color3.fromRGB(32, 74, 70),
	Accent = Color3.fromRGB(0, 245, 160),
	Accent2 = Color3.fromRGB(255, 61, 200),
	Text = Color3.fromRGB(226, 255, 245),
	TextDim = Color3.fromRGB(140, 190, 175),
	Danger = Color3.fromRGB(255, 72, 88),
	Warning = Color3.fromRGB(255, 190, 60),
}

Theme.Fonts = {
	Display = Enum.Font.Michroma,
	Heading = Enum.Font.BuilderSansExtraBold,
	Bold = Enum.Font.BuilderSansBold,
	Medium = Enum.Font.BuilderSansMedium,
	Body = Enum.Font.BuilderSans,
	Mono = Enum.Font.RobotoMono,
}

Theme.TextSize = {
	Hero = 40,
	Title = 26,
	Heading = 19,
	Body = 16,
	Small = 14,
	Tiny = 12,
}

Theme.Radius = {
	Small = 8,
	Medium = 12,
	Large = 18,
	Pill = 999,
}

Theme.Motion = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Linear = TweenInfo.new(1, Enum.EasingStyle.Linear),
}

-- Runtime preferences (set from player settings).
Theme.ReducedMotion = false
Theme.UserScale = 1

function Theme.rarityColor(rarityId: string): Color3
	local r = Rarities.ById[rarityId]
	return if r then r.Color else Theme.Colors.TextDim
end

function Theme.rarityGlow(rarityId: string): Color3
	local r = Rarities.ById[rarityId]
	return if r then r.Glow else Theme.Colors.StrokeSoft
end

function Theme.currencyColor(currency: string): Color3
	local c = GameConfig.Currencies[currency]
	return if c then c.Color else Theme.Colors.Text
end

function Theme.currencyIcon(currency: string): string
	local c = GameConfig.Currencies[currency]
	return if c then c.Icon else ""
end

function Theme.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Theme.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function Theme.gradient(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

Theme.SecretGradient = Rarities.SecretGradient

return Theme
