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

local SCREENS = { "Shop", "Chests", "Inventory", "Skills", "Collection", "Quests", "Ascend", "Stats", "Store", "Settings" }

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

	it("builds the skill tree up as skills are unlocked", function(ctx)
		local h = ctx.harness
		local server, player, _, gui = boot(ctx)
		local Skills = Game.shared(server, "Config.Skills")
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Skills"))
		h:advance(1)
		local window = windowOf(h, gui, "Skills")
		local function node(id: string)
			return h:findDescendant(window, id, "TextButton")
		end
		-- A fresh player sees the core, its neighbours as "?" teasers, and nothing else.
		ctx.expect(node("core").Visible).toBe(true)
		ctx.expect(node("core").Text).toBe(Skills.ById.core.Icon)
		ctx.expect(node("str_1").Visible).toBe(true)
		ctx.expect(node("str_1").Text).toBe("?")
		ctx.expect(node("str_2").Visible).toBe(false)
		ctx.expect(node("str_cap2").Visible).toBe(false)
		ctx.expect(h:findDescendant(window, "core_str_1", "Frame").Visible).toBe(true)
		ctx.expect(h:findDescendant(window, "str_1_str_2", "Frame").Visible).toBe(false)

		local profile = Game.profile(server, player)
		profile.Data.SkillPoints = 5
		Game.service(server, "SyncService"):MarkDirty(profile, "Progress")
		h:advance(0.5)
		ctx.expect(Game.action(ctx, server, player, "UnlockSkill", { Id = "core" }).ok).toBe(true)
		h:advance(1.5)
		-- Buying the core reveals its neighbours and teases the next ring.
		ctx.expect(node("str_1").Text).toBe(Skills.ById.str_1.Icon)
		ctx.expect(node("str_2").Visible).toBe(true)
		ctx.expect(node("str_2").Text).toBe("?")
		ctx.expect(node("str_5").Visible).toBe(false)
		ctx.expect(h:findDescendant(window, "str_1_str_2", "Frame").Visible).toBe(true)

		-- A respec folds the tree back to the core.
		Game.give(server, player, "Gems", 100)
		h:advance(0.5)
		ctx.expect(Game.action(ctx, server, player, "ResetSkills", {}).ok).toBe(true)
		h:advance(1.5)
		ctx.expect(node("str_1").Text).toBe("?")
		ctx.expect(node("str_2").Visible).toBe(false)
		ctx.expect(h:findDescendant(window, "str_1_str_2", "Frame").Visible).toBe(false)
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
		-- The interface size applies on release / − + presses rather than mid-drag.
		local sizeRow = h:findByText(window, "Interface size", "TextLabel").Parent
		h:click(h:findByText(sizeRow, "+", "TextButton"))
		h:advance(2)
		ctx.expect(Game.data(server, player).Settings.UIScale).toBeGreaterThan(1)
	end)
end)

describe("Devices", function()
	it("uses the compact layout on a phone with touch input", function(ctx)
		local h = ctx.harness
		local _, _, _, gui = boot(ctx, { viewport = roblox.Vector2.new(844, 390), input = { touch = true, keyboard = false, mouse = false } })
		-- The bottom dock fits beside Roblox's jump button (bottom right) and is not taller than the screen.
		local dock = h:findDescendant(gui, "Dock", "Frame")
		local dockScale = dock:FindFirstChildOfClass("UIScale").Scale
		ctx.expect(dock.Size.X.Offset * dockScale).toBeLessThanOrEqual(844 - 120 - 10)
		ctx.expect(dock.Size.Y.Offset * dockScale).toBeLessThanOrEqual(390 - 58)
		-- The PRESS button sits above the jump button on touch screens.
		local press = h:findDescendant(gui, "Center", "Frame")
		ctx.expect(press.Position.Y.Offset).toBeLessThanOrEqual(-140)
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

	it("presses with the E key on a keyboard, so you can press while running", function(ctx)
		local h = ctx.harness
		local server, player, client = boot(ctx)
		-- E is bound to the same action as the controller triggers.
		local bound = false
		for _, input in ipairs(client.actions["ButtonAscension_Press"].inputs) do
			bound = bound or input == roblox.Enum.KeyCode.E
		end
		ctx.expect(bound).toBe(true)
		for _ = 1, 4 do
			h:triggerAction(client, "ButtonAscension_Press", nil, h:inputObject({ KeyCode = roblox.Enum.KeyCode.E, UserInputType = roblox.Enum.UserInputType.Keyboard }))
			h:advance(0.2)
		end
		h:advance(1)
		ctx.expect(Game.data(server, player).Stats.TotalClicks).toBe(4)
	end)
end)

describe("Bottom HUD, obby and tutorial", function()
	it("puts the HUD at the bottom with only the quest card at the side, and keeps the world visible", function(ctx)
		local h = ctx.harness
		local _, _, _, gui = boot(ctx)
		local dock = h:findDescendant(gui, "Dock", "Frame")
		ctx.expect(dock.AnchorPoint.Y).toBe(1)
		ctx.expect(dock.Position.Y.Scale).toBe(1)
		-- Navigation, currencies and chips all live in the dock.
		for _, name in ipairs({ "NavRail", "Row", "Chips" }) do
			ctx.expect(dock:FindFirstChild(name)).toBeTruthy()
		end
		ctx.expect(h:findDescendant(dock, "Sparks", "Frame")).toBeTruthy()
		ctx.expect(dock:FindFirstChild("NavRail"):FindFirstChild("Store")).toBeTruthy()
		local press = h:findDescendant(gui, "Center", "Frame")
		ctx.expect(press.AnchorPoint.Y).toBe(1)
		ctx.expect(press.Position.Y.Scale).toBe(1)
		local right = h:findDescendant(gui, "RightColumn", "Frame")
		ctx.expect(right.Position.Y.Scale).toBeLessThan(0.5)
		ctx.expect(right:FindFirstChild("GoalCard")).toBeTruthy()
		-- No more full-screen darkening behind the HUD.
		ctx.expect(h:findDescendant(gui, "Backdrop", "Frame").BackgroundTransparency).toBe(1)
	end)

	it("moves you to your obby checkpoint and back with the dock buttons", function(ctx)
		local h = ctx.harness
		local server, player, _, gui = boot(ctx)
		local obby = Game.service(server, "ObbyService")
		h:click(h:findDescendant(gui, "ObbyGo", "TextButton"))
		h:advance(1)
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		ctx.expect((root.Position - obby.Start.Position).Magnitude).toBeLessThan(5)
		ctx.expect(h:findDescendant(gui, "ObbyLabel", "TextLabel").Text).toMatch("Obby 0/15")
		h:advance(5)
		h:click(h:findDescendant(gui, "ObbyHome", "TextButton"))
		h:advance(1)
		ctx.expect(root.Position.X).toBeLessThan(20)
	end)

	it("shows the tutorial for new players, follows real progress and can be skipped and replayed", function(ctx)
		local h = ctx.harness
		local server, player, _, gui = boot(ctx)
		local card = h:findDescendant(gui, "TutorialCard", "Frame")
		ctx.expect(card.Visible).toBe(true)
		ctx.expect(h:findDescendant(card, "Counter", "TextLabel").Text).toMatch("STEP 1/7")
		ctx.expect(h:findDescendant(gui, "TutorialArrow", "TextLabel").Visible).toBe(true)
		local cap = h:findDescendant(gui, "Cap", "TextButton")
		for _ = 1, 10 do
			h:click(cap)
			h:advance(0.15)
		end
		h:advance(1.5)
		ctx.expect(h:findDescendant(card, "Counter", "TextLabel").Text).toMatch("STEP 2/7")

		h:click(h:findByText(card, "Skip tutorial", "TextButton"))
		h:advance(1)
		ctx.expect(Game.data(server, player).Tutorial.Done).toBe(true)
		ctx.expect(card.Visible).toBe(false)

		-- Settings → Replay starts it again.
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Settings"))
		h:advance(1)
		h:click(h:findDescendant(windowOf(h, gui, "Settings"), "ReplayTutorial", "TextButton"))
		h:advance(1.5)
		ctx.expect(Game.data(server, player).Tutorial.Done).toBe(false)
		ctx.expect(card.Visible).toBe(true)
		ctx.expect(h:findDescendant(card, "Counter", "TextLabel").Text).toMatch("STEP 1/7")
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
