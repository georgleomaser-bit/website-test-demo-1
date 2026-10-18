--[[
	Client UI: boots the real ClientMain in a client world and drives the
	interface like a player (mouse/touch clicks, controller actions), checking
	that every screen opens and that UI controls reach the real server.
	Property writes are validated against the Roblox API, so a wrong property
	name or type anywhere in the UI fails these tests.
]]

local roblox = require("@lune/roblox")
local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local SCREENS = { "Shop", "Chests", "Inventory", "Skills", "Collection", "Quests", "Ascend", "Stats", "Settings" }

local function boot(ctx, extra)
	local server = Game.server(ctx)
	local player, client = Game.join(ctx, server, 5001, "Alice", extra)
	ctx.harness:advance(3)
	local gui = client:find("Players.Alice.PlayerGui.ButtonAscensionUI")
	return server, player, client, gui
end

local function windowOf(h, gui, id: string)
	return h:findDescendant(gui, id, "Frame")
end

describe("Interface", function()
	it("boots without errors, hides the loading screen and presses through the big button", function(ctx)
		local h = ctx.harness
		local server, player, client, gui = boot(ctx)
		ctx.expect(gui).toBeTruthy()
		ctx.expect(h:findDescendant(gui, "Loading")).toBeNil()
		local cap = h:findDescendant(gui, "Cap", "TextButton")
		ctx.expect(cap).toBeTruthy()
		for _ = 1, 12 do
			h:click(cap)
			h:advance(0.15)
		end
		h:advance(1)
		local data = Game.data(server, player)
		ctx.expect(data.Stats.TotalClicks).toBe(12)
		local sparksPill = h:findDescendant(gui, "Sparks", "Frame")
		local value = sparksPill:FindFirstChild("Value")
		ctx.expect(value.Text).never.toBe("0")
		ctx.expect(client).toBeTruthy()
	end)

	it("opens and closes every screen from the navigation rail", function(ctx)
		local h = ctx.harness
		local _, _, _, gui = boot(ctx)
		local rail = h:findDescendant(gui, "NavRail", "Frame")
		for _, id in ipairs(SCREENS) do
			local navButton = rail:FindFirstChild(id)
			ctx.expect(navButton).toBeTruthy()
			h:click(navButton)
			h:advance(0.6)
			local window = windowOf(h, gui, id)
			ctx.expect(window.Visible).toBe(true)
			local close = h:findDescendant(window, "Close", "TextButton")
			h:click(close)
			h:advance(0.6)
			ctx.expect(window.Visible).toBe(false)
		end
	end)

	it("buys an upgrade from the shop", function(ctx)
		local h = ctx.harness
		local server, player, _, gui = boot(ctx)
		Game.give(server, player, "Sparks", 100)
		h:advance(1)
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Shop"))
		h:advance(1)
		local card = h:findDescendant(windowOf(h, gui, "Shop"), "click_power", "Frame")
		local buy = h:findByText(card, "⚡", "TextButton")
		ctx.expect(buy).toBeTruthy()
		h:click(buy)
		h:advance(1)
		ctx.expect(Game.data(server, player).Upgrades.click_power).toBe(1)
	end)

	it("opens a crate and plays the reveal", function(ctx)
		local h = ctx.harness
		local server, player, client, gui = boot(ctx)
		Game.give(server, player, "Sparks", 1000)
		h:advance(1)
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Chests"))
		h:advance(1)
		local buy = h:findByText(windowOf(h, gui, "Chests"), "Buy ×1", "TextButton")
		ctx.expect(buy).toBeTruthy()
		h:click(buy)
		h:advance(4)
		local overlay = h:findDescendant(gui, "ChestOpening", "TextButton")
		ctx.expect(overlay).toBeTruthy()
		local owned = 0
		for _, n in pairs(Game.data(server, player).Inventory) do
			owned += n
		end
		ctx.expect(owned).toBeGreaterThanOrEqual(1)
		h:click(h:findByText(overlay, "Continue", "TextButton"))
		h:advance(1)
		ctx.expect(h:findDescendant(gui, "ChestOpening", "TextButton")).toBeNil()
		ctx.expect(client).toBeTruthy()
	end)

	it("equips an item from the inventory", function(ctx)
		local h = ctx.harness
		local server, player, _, gui = boot(ctx)
		local data = Game.data(server, player)
		data.Inventory.paper_clip = 2
		data.Discovered.paper_clip = 1
		Game.service(server, "SyncService"):MarkDirty(Game.profile(server, player), "Inventory", "Discovered")
		h:advance(1)
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Inventory"))
		h:advance(1)
		local window = windowOf(h, gui, "Inventory")
		local card = h:findDescendant(window, "ItemCard", "TextButton")
		h:click(card)
		h:advance(0.5)
		h:click(h:findByText(window, "Equip", "TextButton"))
		h:advance(1)
		ctx.expect(data.Equipped[1]).toBe("paper_clip")
	end)

	it("saves settings changed in the settings screen", function(ctx)
		local h = ctx.harness
		local server, player, _, gui = boot(ctx)
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Settings"))
		h:advance(1)
		local window = windowOf(h, gui, "Settings")
		local label = h:findByText(window, "Reduced motion", "TextLabel")
		local toggle = label.Parent:FindFirstChild("Toggle")
		h:click(toggle)
		h:advance(2)
		ctx.expect(Game.data(server, player).Settings.ReducedMotion).toBe(true)
	end)
end)

describe("Devices", function()
	it("uses the compact layout on a phone with touch input", function(ctx)
		local h = ctx.harness
		local _, _, _, gui = boot(ctx, { viewport = roblox.Vector2.new(844, 390), input = { touch = true, keyboard = false, mouse = false } })
		local right = h:findDescendant(gui, "RightColumn", "Frame")
		ctx.expect(right.Visible).toBe(false)
		local toggle = h:findDescendant(gui, "SideToggle", "TextButton")
		ctx.expect(toggle.Visible).toBe(true)
		h:click(toggle)
		ctx.expect(right.Visible).toBe(true)
		local cap = h:findDescendant(gui, "Cap", "TextButton")
		h:click(cap)
		h:advance(1)
	end)

	it("presses the button with a controller trigger", function(ctx)
		local h = ctx.harness
		local server, player, client = boot(ctx, { input = { gamepad = true } })
		for _ = 1, 3 do
			h:triggerAction(client, "ButtonAscension_Press")
			h:advance(0.2)
		end
		h:advance(1)
		ctx.expect(Game.data(server, player).Stats.TotalClicks).toBe(3)
	end)
end)

describe("Admin panel client", function()
	it("boots for an Owner and runs a command from the command bar", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { isStudio = true })
		local owner, client = Game.join(ctx, server, -1, "Owner")
		local target = Game.join(ctx, server, -4, "Target")
		h:advance(4)
		local panelGui = client:find("Players.Owner.PlayerGui.AdminPanelGui")
		ctx.expect(panelGui).toBeTruthy()
		local boxes = h:queryDescendants(panelGui, function(st)
			return st.className == "TextBox"
		end)
		ctx.expect(#boxes).toBeGreaterThan(0)
		local fired = h:chatCommand(client, "/admin givegems Target 25")
		ctx.expect(fired).toBeGreaterThan(0)
		h:advance(2)
		ctx.expect(Game.data(server, target).Currencies.Gems).toBe(25)
		ctx.expect(owner).toBeTruthy()
	end)
end)

return Test.collect()
