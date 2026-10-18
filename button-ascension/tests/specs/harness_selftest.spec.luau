--[[
	Self-tests for the mock engine. If these fail, game tests cannot be trusted.
]]

local Test = require("../harness/Test")
local Instance = require("../harness/Instance")

local describe, it = Test.describe, Test.it

local function addScript(world, className: string, parent, source: string, name: string?)
	local script = Instance.create(world, className, true)
	local st = Instance.state(script)
	st.name = name or className
	st.internal.source = source
	Instance.setParent(st, parent)
	return script
end

-- Runs `source` as a ModuleScript inside `world` and returns its value.
local function runModule(world, source: string, name: string?)
	local module = addScript(world, "ModuleScript", world.services.ReplicatedStorage, source, name or "TestModule")
	return world:require(module)
end

-- A server with no project loaded (scripts are added by the test).
local function emptyServer(ctx, options)
	local opts = options or {}
	opts.loadProject = false
	opts.start = false
	return ctx.harness:createServer(opts)
end

describe("Instances", function()
	it("reports Roblox-style errors for invalid members, types and classes", function(ctx)
		local world = ctx.harness:createWorld({ role = "client" })
		local r = runModule(world, [[
			local frame = Instance.new("Frame")
			frame.Name = "Panel"
			local results = {}
			results.badName = select(2, pcall(function() frame.Sizee = 1 end))
			results.badType = select(2, pcall(function() frame.Size = 5 end))
			results.readOnly = select(2, pcall(function() frame.AbsoluteSize = Vector2.new() end))
			results.badEnum = select(2, pcall(function() frame.SizeConstraint = Enum.Font.Arial end))
			results.badClass = select(2, pcall(function() Instance.new("NotAClass") end))
			results.service = select(2, pcall(function() Instance.new("Players") end))
			results.unimplemented = select(2, pcall(function() frame:GetStyled("x") end))
			results.badRead = select(2, pcall(function() return frame.NotAProperty end))
			results.okEnumString = pcall(function() frame.SizeConstraint = "RelativeXX" end)
			results.typeofFrame = typeof(frame)
			results.typeFrame = type(frame)
			results.numberToString = pcall(function() local l = Instance.new("TextLabel"); l.Text = 5; assert(l.Text == "5") end)
			results.childLookup = pcall(function()
				local child = Instance.new("Folder")
				child.Name = "Inner"
				child.Parent = frame
				assert(frame.Inner == child)
			end)
			results.circular = select(2, pcall(function()
				local a = Instance.new("Folder")
				local b = Instance.new("Folder", a)
				a.Parent = b
			end))
			return results
		]])
		ctx.expect(r.badName).toContain('Sizee is not a valid member of Frame "Panel"')
		ctx.expect(r.badType).toContain("UDim2 expected, got number")
		ctx.expect(r.readOnly).toContain("read only")
		ctx.expect(r.badEnum).toContain("Expected Enum.SizeConstraint")
		ctx.expect(r.badClass).toContain('Unable to create an Instance of type "NotAClass"')
		ctx.expect(r.service).toContain('Unable to create an Instance of type "Players"')
		ctx.expect(r.unimplemented).toContain("Frame:GetStyled() is not implemented")
		ctx.expect(r.badRead).toContain("NotAProperty is not a valid member of Frame")
		ctx.expect(r.okEnumString).toBe(true)
		ctx.expect(r.typeofFrame).toBe("Instance")
		ctx.expect(r.typeFrame).toBe("userdata")
		ctx.expect(r.numberToString).toBe(true)
		ctx.expect(r.childLookup).toBe(true)
		ctx.expect(r.circular).toContain("circular reference")
	end)

	it("returns reflection defaults and computes GUI geometry", function(ctx)
		local world = ctx.harness:createWorld({ role = "client" })
		local r = runModule(world, [[
			local gui = Instance.new("ScreenGui")
			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(0.5, 10, 0, 100)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Parent = gui
			local label = Instance.new("TextLabel")
			return {
				visible = frame.Visible,
				archivable = frame.Archivable,
				bgTransparency = frame.BackgroundTransparency,
				size = frame.AbsoluteSize,
				pos = frame.AbsolutePosition,
				labelText = label.Text,
				textX = label.TextXAlignment,
				humanoidHealth = Instance.new("Humanoid").Health,
				scriptEnabled = Instance.new("Script").Enabled,
			}
		]])
		ctx.expect(r.visible).toBe(true)
		ctx.expect(r.archivable).toBe(true)
		ctx.expect(r.bgTransparency).toBe(0)
		ctx.expect(r.size.X).toBe(650)
		ctx.expect(r.size.Y).toBe(100)
		ctx.expect(r.pos.X).toBe(640 - 325)
		ctx.expect(r.labelText).toBe("Label")
		ctx.expect(r.textX.Name).toBe("Center")
		ctx.expect(r.humanoidHealth).toBe(100)
		ctx.expect(r.scriptEnabled).toBe(true)
	end)

	it("fires Changed, property, attribute, child and Destroying signals", function(ctx)
		local world = ctx.harness:createWorld({ role = "client" })
		local log = runModule(world, [[
			local log = {}
			local part = Instance.new("Part")
			part.Changed:Connect(function(prop) table.insert(log, "changed:" .. prop) end)
			part:GetPropertyChangedSignal("Transparency"):Connect(function() table.insert(log, "transparency") end)
			part:GetAttributeChangedSignal("Level"):Connect(function() table.insert(log, "attr:" .. tostring(part:GetAttribute("Level"))) end)
			part.ChildAdded:Connect(function(c) table.insert(log, "child:" .. c.Name) end)
			part.Destroying:Connect(function() table.insert(log, "destroying") end)
			part.Transparency = 0.5
			part.Transparency = 0.5 -- unchanged, no event
			part:SetAttribute("Level", 3)
			local f = Instance.new("Folder")
			f.Name = "Kid"
			f.Parent = part
			part:Destroy()
			local ok, err = pcall(function() part.Parent = workspace end)
			table.insert(log, if ok then "relocked:no" else "locked")
			local ok2, err2 = pcall(function() part:SetAttribute("Bad", {}) end)
			table.insert(log, if ok2 then "attrtable:ok" else "attrtable:error")
			return log
		]])
		-- Roblox does not guarantee the order of Changed vs GetPropertyChangedSignal.
		if log[1] == "transparency" then
			log[1], log[2] = log[2], log[1]
		end
		ctx.expect(log).toEqual({
			"changed:Transparency",
			"transparency",
			"attr:3",
			"child:Kid",
			"destroying",
			"locked",
			"attrtable:error",
		})
	end)

	it("clones deep trees with attributes and remaps internal references", function(ctx)
		local world = ctx.harness:createWorld({ role = "client" })
		local r = runModule(world, [[
			local model = Instance.new("Model")
			local root = Instance.new("Part", model)
			root.Name = "Root"
			model.PrimaryPart = root
			model:SetAttribute("Tier", 2)
			local copy = model:Clone()
			return {
				childName = copy:FindFirstChild("Root") and copy.Root.Name,
				attr = copy:GetAttribute("Tier"),
				primaryRemapped = copy.PrimaryPart == copy.Root,
				parent = copy.Parent,
			}
		]])
		ctx.expect(r.childName).toBe("Root")
		ctx.expect(r.attr).toBe(2)
		ctx.expect(r.primaryRemapped).toBe(true)
		ctx.expect(r.parent).toBeNil()
	end)

	it("detects cyclic requires", function(ctx)
		local world = ctx.harness:createWorld({ role = "client" })
		local folder = world.services.ReplicatedStorage
		addScript(world, "ModuleScript", folder, [[return { b = require(script.Parent.B) }]], "A")
		addScript(world, "ModuleScript", folder, [[return { a = require(script.Parent.A) }]], "B")
		ctx.allowScriptErrors()
		local ok, err = pcall(function()
			return world:requirePath("ReplicatedStorage.A")
		end)
		ctx.expect(ok).toBe(false)
		ctx.expect(tostring(err)).toContain("required recursively")
	end)
end)

describe("Scheduler", function()
	it("orders task.delay / task.wait / task.defer in virtual time", function(ctx)
		local h = ctx.harness
		local world = h:createWorld({ role = "server" })
		local log = runModule(world, [[
			local log = {}
			task.delay(2, function() table.insert(log, "delay2@" .. math.floor(os.clock())) end)
			task.delay(1, function() table.insert(log, "delay1@" .. math.floor(os.clock())) end)
			task.spawn(function()
				local elapsed = task.wait(3)
				table.insert(log, "wait3:" .. math.floor(elapsed + 0.5))
			end)
			task.defer(function() table.insert(log, "deferred") end)
			table.insert(log, "sync")
			local cancelled = task.delay(1.5, function() table.insert(log, "SHOULD NOT RUN") end)
			task.cancel(cancelled)
			return log
		]])
		ctx.expect(log).toEqual({ "sync" })
		h:advance(4)
		ctx.expect(log).toEqual({ "sync", "deferred", "delay1@1", "delay2@2", "wait3:3" })
	end)

	it("lets tests yield: task.wait inside a test advances virtual time", function(ctx)
		local h = ctx.harness
		h:createWorld({ role = "server" })
		local before = h:now()
		h.scheduler:wait(10)
		ctx.expect(h:now() - before).toBeCloseTo(10, 0.05)
	end)

	it("WaitForChild yields until the child appears or the timeout elapses", function(ctx)
		local h = ctx.harness
		local world = h:createWorld({ role = "server" })
		local results = runModule(world, [[
			local results = {}
			local folder = Instance.new("Folder")
			folder.Parent = workspace
			task.spawn(function()
				local child = folder:WaitForChild("Late")
				results.found = child.Name
				results.at = os.clock()
			end)
			task.spawn(function()
				results.timedOut = folder:WaitForChild("Never", 1) == nil
			end)
			task.delay(2, function()
				local c = Instance.new("Folder")
				c.Name = "Late"
				c.Parent = folder
			end)
			return results
		]])
		h:advance(3)
		ctx.expect(results.found).toBe("Late")
		ctx.expect(results.at).toBeCloseTo(2, 0.05)
		ctx.expect(results.timedOut).toBe(true)
	end)

	it("records uncaught errors from script threads", function(ctx)
		local h = ctx.harness
		local server = emptyServer(ctx)
		addScript(server, "Script", server.services.ServerScriptService, [[
			task.delay(1, function() error("kaboom") end)
		]])
		server:startScripts()
		h:advance(2)
		ctx.allowScriptErrors()
		ctx.expect(#h:errors()).toBe(1)
		ctx.expect(h:errors()[1].message).toContain("kaboom")
	end)

	it("completes tweens and fires Completed", function(ctx)
		local h = ctx.harness
		local world = h:createWorld({ role = "client" })
		local r = runModule(world, [[
			local TweenService = game:GetService("TweenService")
			local frame = Instance.new("Frame")
			local r = {}
			local tween = TweenService:Create(frame, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
			tween.Completed:Connect(function(state) r.state = state.Name end)
			tween:Play()
			r.frame = frame
			r.bad = select(2, pcall(function() TweenService:Create(frame, TweenInfo.new(1), { Nope = 1 }) end))
			return r
		]])
		ctx.expect(r.frame.BackgroundTransparency).toBe(0)
		h:advance(1)
		ctx.expect(r.frame.BackgroundTransparency).toBe(1)
		ctx.expect(r.state).toBe("Completed")
		ctx.expect(r.bad).toContain("cannot be tweened")
	end)
end)

describe("DataStores", function()
	it("cancels UpdateAsync when the transform returns nil", function(ctx)
		local h = ctx.harness
		local server = emptyServer(ctx)
		h.backend:poke("Store", "key", { coins = 5 })
		local result = h:run(function()
			local store = server:service("DataStoreService"):GetDataStore("Store")
			local value = store:UpdateAsync("key", function(old)
				return nil
			end)
			local current = store:GetAsync("key")
			return { value = value, coins = current.coins }
		end)
		ctx.expect(result.value).toBeNil()
		ctx.expect(result.coins).toBe(5)
	end)

	it("injects failures and rejects unstorable values", function(ctx)
		local h = ctx.harness
		local server = emptyServer(ctx)
		local r = h:run(function()
			local store = server:service("DataStoreService"):GetDataStore("Store")
			local out = {}
			h.backend:failNext("UpdateAsync", 2, "502: injected")
			out.first = select(2, pcall(store.UpdateAsync, store, "k", function() return 1 end))
			out.second = select(2, pcall(store.UpdateAsync, store, "k", function() return 2 end))
			out.thirdOk, out.third = pcall(store.UpdateAsync, store, "k", function() return 3 end)
			out.nan = select(2, pcall(store.SetAsync, store, "k", 0 / 0))
			out.instance = select(2, pcall(store.SetAsync, store, "k", { part = Instance.create(server, "Part", true) }))
			out.mixed = select(2, pcall(store.SetAsync, store, "k", { 1, 2, x = 3 }))
			out.yield = select(2, pcall(store.UpdateAsync, store, "k", function() h.scheduler:wait(1) return 4 end))
			h.backend:setUnavailable("StudioAccessToApisNotAllowed: Studio access to APIs is not allowed.")
			out.unavailable = select(2, pcall(store.GetAsync, store, "k"))
			h.backend:setUnavailable(nil)
			out.final = store:GetAsync("k")
			return out
		end)
		ctx.expect(r.first).toContain("502: injected")
		ctx.expect(r.second).toContain("502: injected")
		ctx.expect(r.thirdOk).toBe(true)
		ctx.expect(r.third).toBe(3)
		ctx.expect(r.nan).toContain("NaN")
		ctx.expect(r.instance).toContain("Cannot store Instance")
		ctx.expect(r.mixed).toContain("mixed table")
		ctx.expect(r.yield).toContain("yielded")
		ctx.expect(r.unavailable).toContain("Studio access")
		ctx.expect(r.final).toBe(3)
	end)

	it("shares one backend between two servers and serves ordered stores", function(ctx)
		local h = ctx.harness
		local a = emptyServer(ctx, { jobId = "A" })
		local b = emptyServer(ctx, { jobId = "B" })
		local r = h:run(function()
			a:service("DataStoreService"):GetDataStore("Shared"):SetAsync("x", { from = "A" })
			local seen = b:service("DataStoreService"):GetDataStore("Shared"):GetAsync("x")
			local ordered = a:service("DataStoreService"):GetOrderedDataStore("Board")
			for i, v in ipairs({ 30, 10, 50, 20 }) do
				ordered:SetAsync("u" .. i, v)
			end
			local pages = ordered:GetSortedAsync(false, 2)
			local first = pages:GetCurrentPage()
			pages:AdvanceToNextPageAsync()
			local second = pages:GetCurrentPage()
			return { seen = seen.from, first = { first[1].value, first[2].value }, second = { second[1].value, second[2].value }, finished = pages.IsFinished }
		end)
		ctx.expect(r.seen).toBe("A")
		ctx.expect(r.first).toEqual({ 50, 30 })
		ctx.expect(r.second).toEqual({ 20, 10 })
		ctx.expect(r.finished).toBe(true)
	end)
end)

describe("Network", function()
	it("round-trips remotes with Roblox serialisation rules", function(ctx)
		local h = ctx.harness
		local server = emptyServer(ctx)
		addScript(server, "Script", server.services.ServerScriptService, [[
			local folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = game.ReplicatedStorage
			local fn = Instance.new("RemoteFunction")
			fn.Name = "Echo"
			fn.Parent = folder
			local ev = Instance.new("RemoteEvent")
			ev.Name = "Ping"
			ev.Parent = folder
			fn.OnServerInvoke = function(player, payload)
				if payload == "boom" then error("server says no") end
				return {
					who = player.Name,
					meta = getmetatable(payload) == nil,
					fnDropped = type(payload) == "table" and payload.fn == nil,
					mixedLen = type(payload) == "table" and payload.mixed and #payload.mixed or -1,
					mixedKey = type(payload) == "table" and payload.mixed and payload.mixed.key or "none",
				}
			end
			ev.OnServerEvent:Connect(function(player, n)
				ev:FireClient(player, n + 1)
			end)
		]])
		server:startScripts()
		local player, client = h:addPlayer(server, { userId = 7, name = "Alice" })
		local results = {}
		addScript(client, "LocalScript", client.localPlayer.proxy.PlayerScripts, [[
			local remotes = game.ReplicatedStorage:WaitForChild("Remotes")
			local results = {}
			_G.results = results
			remotes.Ping.OnClientEvent:Connect(function(n) results.pong = n end)
			remotes.Ping:FireServer(41)
			local payload = setmetatable({ fn = function() end, mixed = { 1, 2, key = "lost" } }, { __index = {} })
			results.echo = remotes.Echo:InvokeServer(payload)
			results.errorOk, results.errorMsg = pcall(function() return remotes.Echo:InvokeServer("boom") end)
		]])
		h:advance(1)
		local r = client._G.results
		ctx.expect(r.pong).toBe(42)
		ctx.expect(r.echo.who).toBe("Alice")
		ctx.expect(r.echo.meta).toBe(true)
		ctx.expect(r.echo.fnDropped).toBe(true)
		ctx.expect(r.echo.mixedLen).toBe(2)
		ctx.expect(r.echo.mixedKey).toBe("none") -- string keys of mixed tables are lost
		ctx.expect(r.errorOk).toBe(false)
		ctx.expect(r.errorMsg).toContain("server says no")
	end)

	it("replicates server changes and lets tests act as exploiters", function(ctx)
		local h = ctx.harness
		local server = emptyServer(ctx)
		addScript(server, "Script", server.services.ServerScriptService, [[
			local state = Instance.new("Folder")
			state.Name = "ServerState"
			state.Parent = game.ReplicatedStorage
			local fn = Instance.new("RemoteFunction")
			fn.Name = "Secret"
			fn.Parent = game.ReplicatedStorage
			fn.OnServerInvoke = function(player, arg)
				if arg ~= "letmein" then
					player:Kick("Exploit detected")
					return false
				end
				return true
			end
			game.Players.PlayerRemoving:Connect(function(p) _G.removed = p.Name end)
			task.delay(1, function() state:SetAttribute("Event", "double") end)
		]])
		server:startScripts()
		local player, client = h:addPlayer(server, { userId = 9, name = "Mallory" })
		h:advance(2)
		local clientState = client:find("ReplicatedStorage.ServerState")
		ctx.expect(clientState).toBeTruthy()
		ctx.expect(clientState:GetAttribute("Event")).toBe("double")
		ctx.expect(client:find("Workspace.Mallory")).toBeTruthy() -- character replicated
		local granted = h:exploitInvoke(server, player, "Secret", { forged = true })
		ctx.expect(granted).toBe(false)
		h:advance(0.5)
		ctx.expect(server.kicks[1].message).toBe("Exploit detected")
		ctx.expect(server._G.removed).toBe("Mallory")
		ctx.expect(player.Parent).toBeNil()
		ctx.expect(client.closed).toBe(true)
	end)

	it("only replicates a PlayerGui to its owner and starts LocalScripts placed there", function(ctx)
		local h = ctx.harness
		local server = emptyServer(ctx)
		server:startScripts()
		local alice, aliceClient = h:addPlayer(server, { userId = 1, name = "Alice" })
		local _bob, bobClient = h:addPlayer(server, { userId = 2, name = "Bob" })
		local gui = Instance.create(server, "ScreenGui", false)
		Instance.state(gui).name = "AdminGui"
		addScript(server, "LocalScript", gui, [[ _G.adminLoaded = game.Players.LocalPlayer.Name ]])
		gui.Parent = alice.PlayerGui
		h:advance(0.1)
		ctx.expect(aliceClient._G.adminLoaded).toBe("Alice")
		ctx.expect(bobClient._G.adminLoaded).toBeNil()
		local bobsView = bobClient:find("Players.Alice")
		ctx.expect(bobsView).toBeTruthy()
		ctx.expect(bobsView:FindFirstChild("PlayerGui")).toBeNil()
	end)

	it("delivers MessagingService messages between servers", function(ctx)
		local h = ctx.harness
		local a = emptyServer(ctx, { jobId = "A" })
		local b = emptyServer(ctx, { jobId = "B" })
		addScript(b, "Script", b.services.ServerScriptService, [[
			game:GetService("MessagingService"):SubscribeAsync("announce", function(msg) _G.got = msg.Data.text end)
		]])
		b:startScripts()
		h:run(function()
			a:service("MessagingService"):PublishAsync("announce", { text = "hello" })
		end)
		h:advance(0.5)
		ctx.expect(b._G.got).toBe("hello")
	end)

	it("filters text and runs BindToClose on shutdown", function(ctx)
		local h = ctx.harness
		local server = emptyServer(ctx)
		addScript(server, "Script", server.services.ServerScriptService, [[
			local result = game:GetService("TextService"):FilterStringAsync("what a badword", 1)
			_G.filtered = result:GetNonChatStringForBroadcastAsync()
			game:BindToClose(function()
				task.wait(2)
				_G.closed = true
			end)
		]])
		server:startScripts()
		h:advance(0.5)
		ctx.expect(server._G.filtered).toBe("what a #######")
		local finished = h:shutdown(server)
		ctx.expect(finished).toBe(true)
		ctx.expect(server._G.closed).toBe(true)
		ctx.expect(server.closed).toBe(true)
	end)
end)

return Test.collect()
