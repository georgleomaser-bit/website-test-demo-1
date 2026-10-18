--[[
	Network.luau

	Bridges one server world with any number of client worlds:

	  * Replication (server -> clients): ReplicatedStorage, Workspace, Lighting,
	    StarterPlayer, StarterGui, ReplicatedFirst, Teams, SoundService,
	    TextChatService and Players are mirrored into every client. A player's
	    PlayerGui and Backpack only replicate to that player. Property,
	    attribute, tag and parent changes made on the server are pushed to
	    the mirrors immediately (client-side changes never replicate back, as
	    with FilteringEnabled).
	  * Remotes: FireServer / FireClient / FireAllClients are delivered
	    asynchronously (task.defer). InvokeServer yields the caller until the
	    server's OnServerInvoke returns; errors propagate to the caller.
	    Events fired before anyone connects are queued, like on Roblox.
	  * Arguments are copied with Roblox's serialisation rules: metatables are
	    stripped, functions become nil, mixed tables lose their string keys,
	    non-string dictionary keys are converted with tostring, cyclic tables
	    error, and Instances are mapped to the other side's copy (or nil).
]]

local Instance = require("./Instance")
local Reflection = require("./Reflection")
local Types = require("./Types")
local Classes = require("./Classes")

local states = Instance.states

local Network = {}
Network.__index = Network

local REPLICATED_SERVICES = {
	ReplicatedStorage = true,
	Workspace = true,
	Lighting = true,
	StarterPlayer = true,
	StarterGui = true,
	StarterPack = true,
	ReplicatedFirst = true,
	Teams = true,
	SoundService = true,
	TextChatService = true,
	Players = true,
}
Network.ReplicatedServices = REPLICATED_SERVICES

local PRIVATE_PLAYER_CONTAINERS = { PlayerGui = true, Backpack = true }

function Network.new(server)
	local self = setmetatable({}, Network)
	self.server = server
	self.clients = {}
	self.byPlayer = {}
	self.byClientWorld = {}
	self.delivered = 0
	server.network = self
	server.replicator = self
	return self
end

-- Visibility -------------------------------------------------------------------------------------

local function classReplicates(className: string): boolean
	return not Reflection.classTags(className).NotReplicated
end

-- Is server instance `st` visible to client record `rec`?
function Network:_visible(st, rec): boolean
	local node = st
	local privateOwner = nil
	while node.parent and node.parent.className ~= "DataModel" do
		if not classReplicates(node.className) and node.className ~= "PlayerGui" then
			return false
		end
		local parent = node.parent
		if parent.className == "Player" and PRIVATE_PLAYER_CONTAINERS[node.className] then
			privateOwner = parent
		elseif parent.className == "Player" and node.className == "PlayerScripts" then
			return false
		end
		node = parent
	end
	if not node.parent then
		return false -- not inside the DataModel
	end
	if not REPLICATED_SERVICES[node.className] then
		return false
	end
	if node == st then
		return true -- the service itself
	end
	if privateOwner and privateOwner ~= rec.playerSt then
		return false
	end
	return true
end

-- Value mapping ------------------------------------------------------------------------------------

function Network:_mapToClient(value, rec)
	local st = states[value]
	if st then
		local cst = rec.s2c[st]
		return cst and cst.proxy
	end
	return value
end

-- Serialisation (Roblox remote argument rules) -------------------------------------------------------

local function serialize(self, value, direction: string, rec, seen)
	local t = Types.typeof(value)
	if t == "nil" or t == "boolean" or t == "number" or t == "string" then
		return value
	elseif t == "Instance" then
		local st = states[value]
		if not st then
			return nil
		end
		if direction == "toServer" then
			if st.world == self.server then
				return value
			end
			local sst = rec and rec.c2s[st]
			return sst and sst.proxy
		end
		if st.world ~= self.server then
			return nil
		end
		local cst = rec.s2c[st]
		return cst and cst.proxy
	elseif Types.ValueTypes[t] then
		return value
	elseif t == "buffer" then
		local copy = buffer.create(buffer.len(value))
		buffer.copy(copy, 0, value)
		return copy
	elseif t == "table" then
		seen = seen or {}
		if seen[value] then
			error("Harness: tables cannot be cyclic (remote argument)", 0)
		end
		seen[value] = true
		local intMax, intCount, otherCount, stringCount = 0, 0, 0, 0
		for k in pairs(value) do
			if type(k) == "number" and k >= 1 and k % 1 == 0 then
				intCount += 1
				intMax = math.max(intMax, k)
			else
				otherCount += 1
				if type(k) == "string" then
					stringCount += 1
				end
			end
		end
		local out = {}
		if otherCount == 0 or (intCount > 0 and stringCount > 0) then
			-- Array (or mixed table: string-keyed values are lost). Stops at the first nil.
			for i = 1, intMax do
				local v = rawget(value, i)
				if v == nil then
					break
				end
				out[i] = serialize(self, v, direction, rec, seen)
			end
		else
			for k, v in pairs(value) do
				local key = if type(k) == "string" then k else tostring(k)
				out[key] = serialize(self, v, direction, rec, seen)
			end
		end
		seen[value] = nil
		return out
	end
	-- functions, threads, userdata (non-Instance), signals ... become nil
	return nil
end

function Network:serialize(args, direction: string, rec)
	local out = { n = args.n }
	for i = 1, args.n do
		out[i] = serialize(self, args[i], direction, rec, nil)
	end
	return out
end

-- Mirroring --------------------------------------------------------------------------------------------

function Network:_copyProps(rec, st, cst)
	for key, value in pairs(st.props) do
		local target = states[value]
		if target then
			local mapped = rec.s2c[target]
			if mapped then
				cst.props[key] = mapped.proxy
			else
				table.insert(rec.pendingRefs, { cst = cst, key = key, target = target })
			end
		else
			cst.props[key] = value
		end
	end
	for k, v in pairs(st.attributes) do
		cst.attributes[k] = v
	end
	for k, v in pairs(st.tags) do
		cst.tags[k] = v
	end
	if Reflection.isA(st.className, "LuaSourceContainer") then
		cst.internal.source = st.internal.source
		cst.internal.path = st.internal.path
		cst.internal.jsonValue = st.internal.jsonValue
	end
end

function Network:_resolvePendingRefs(rec)
	if #rec.pendingRefs == 0 then
		return
	end
	local remaining = {}
	for _, pending in ipairs(rec.pendingRefs) do
		local mapped = rec.s2c[pending.target]
		if mapped and not pending.cst.destroyed then
			Instance.setProperty(pending.cst, pending.key, mapped.proxy)
		elseif not pending.target.destroyed and not pending.cst.destroyed then
			table.insert(remaining, pending)
		end
	end
	rec.pendingRefs = remaining
end

-- Builds the client copy of server instance `st` (and visible descendants) under client parent `cparent`.
function Network:_mirror(rec, st, cparent)
	local function build(node)
		local proxy = Instance.create(rec.world, node.className, true)
		local cst = states[proxy]
		cst.name = node.name
		rec.s2c[node] = cst
		rec.c2s[cst] = node
		self:_copyProps(rec, node, cst)
		for _, child in ipairs(node.children) do
			if self:_visible(child, rec) then
				local childCopy = build(child)
				table.insert(cst.children, childCopy)
				childCopy.parent = cst
			end
		end
		return cst
	end
	local cst = build(st)
	Instance.setParent(cst, cparent.proxy)
	-- Fire DescendantAdded/ChildAdded-dependent script starts for the whole subtree.
	self:_resolvePendingRefs(rec)
	return cst
end

local function unmap(rec, cst)
	local sst = rec.c2s[cst]
	if sst then
		rec.s2c[sst] = nil
	end
	rec.c2s[cst] = nil
	for _, child in ipairs(cst.children) do
		unmap(rec, child)
	end
end

-- Replicator hooks (called by the server world) ------------------------------------------------------

function Network:onPropertyChanged(world, st, key, value)
	if world ~= self.server then
		return
	end
	for _, rec in ipairs(self.clients) do
		local cst = rec.connected and rec.s2c[st]
		if cst then
			if key == "Name" then
				if cst.name ~= value then
					cst.proxy.Name = value
				end
			else
				local target = states[value]
				local mapped = value
				if target then
					local m = rec.s2c[target]
					if m then
						mapped = m.proxy
					else
						mapped = nil
						table.insert(rec.pendingRefs, { cst = cst, key = key, target = target })
					end
				end
				Instance.setProperty(cst, key, mapped)
				if st.className == "Player" and key == "Character" and mapped ~= nil then
					Instance.fire(cst, "CharacterAdded", mapped)
				end
			end
		end
	end
end

function Network:onAttributeChanged(world, st, name, value)
	if world ~= self.server then
		return
	end
	for _, rec in ipairs(self.clients) do
		local cst = rec.connected and rec.s2c[st]
		if cst then
			Instance.setAttribute(cst, name, value)
		end
	end
end

function Network:onTagChanged(world, st, tag, added)
	if world ~= self.server then
		return
	end
	for _, rec in ipairs(self.clients) do
		local cst = rec.connected and rec.s2c[st]
		if cst then
			cst.tags[tag] = if added then true else nil
			rec.world:_onTagChanged(cst, tag, added)
		end
	end
end

function Network:onParentChanged(world, st, _oldParent, newParent)
	if world ~= self.server then
		return
	end
	for _, rec in ipairs(self.clients) do
		if rec.connected then
			local cst = rec.s2c[st]
			local visible = newParent ~= nil and self:_visible(st, rec)
			if visible then
				local cparent = rec.s2c[newParent]
				if cparent then
					if cst then
						Instance.setParent(cst, cparent.proxy)
					else
						self:_mirror(rec, st, cparent)
					end
				end
			elseif cst then
				unmap(rec, cst)
				Instance.destroy(cst)
			end
		end
	end
end

-- Delivery -------------------------------------------------------------------------------------------

-- Fires `eventName` on remote state `st`, queueing until a listener connects.
local function deliver(scheduler, st, eventName: string, args)
	local signal = Instance.getSignal(st, eventName)
	if signal:_hasListeners() then
		signal:_fire(table.unpack(args, 1, args.n))
		return
	end
	st.internal.queue = st.internal.queue or {}
	local queue = st.internal.queue
	table.insert(queue, args)
	if #queue > 256 then
		table.remove(queue, 1)
		st.world:log("warn", "Remote event invocation queue exhausted for " .. Instance.fullName(st) .. "; did you forget to implement " .. eventName .. "?")
	end
	signal._onConnect = function()
		scheduler:defer(function()
			local pending = st.internal.queue or {}
			st.internal.queue = nil
			for _, queued in ipairs(pending) do
				signal:_fire(table.unpack(queued, 1, queued.n))
			end
		end)
	end
end

function Network:_recordForClientWorld(world)
	return self.byClientWorld[world]
end

-- Client -> server
function Network:fireServer(clientRemoteSt, args)
	local rec = self.byClientWorld[clientRemoteSt.world]
	if not rec or not rec.connected then
		return
	end
	local serverRemote = rec.c2s[clientRemoteSt]
	if not serverRemote then
		error("Harness: FireServer on a remote that does not exist on the server (created by the client?)", 3)
	end
	local payload = self:serialize(args, "toServer", rec)
	self:_deliverToServer(rec, serverRemote, payload)
end

function Network:_deliverToServer(rec, serverRemote, payload)
	local scheduler = self.server.scheduler
	local server = self.server
	scheduler:defer(function()
		if not rec.connected or server.closed or serverRemote.destroyed then
			return
		end
		self.delivered += 1
		local args = { n = payload.n + 1, rec.playerSt.proxy }
		for i = 1, payload.n do
			args[i + 1] = payload[i]
		end
		deliver(scheduler, serverRemote, "OnServerEvent", args)
	end)
end

-- Server -> client
function Network:fireClient(serverRemoteSt, playerSt, args)
	local rec = self.byPlayer[playerSt]
	if not rec or not rec.connected then
		return
	end
	local cst = rec.s2c[serverRemoteSt]
	if not cst then
		return
	end
	local payload = self:serialize(args, "toClient", rec)
	local scheduler = self.server.scheduler
	scheduler:defer(function()
		if not rec.connected or cst.destroyed then
			return
		end
		self.delivered += 1
		deliver(scheduler, cst, "OnClientEvent", payload)
	end)
end

function Network:fireAllClients(serverRemoteSt, args)
	for _, rec in ipairs(self.clients) do
		if rec.connected then
			self:fireClient(serverRemoteSt, rec.playerSt, args)
		end
	end
end

-- Calls the server's OnServerInvoke from `rec` (yields the calling thread).
function Network:_invoke(rec, serverRemote, payload)
	local scheduler = self.server.scheduler
	local caller = coroutine.running()
	if not coroutine.isyieldable() then
		error("Harness: InvokeServer must be called from a yieldable thread", 3)
	end
	local done, results, failure = false, nil, nil
	local waiting = false
	scheduler:spawnIn(self.server, function()
		local callback = Classes.waitForCallback(serverRemote, "OnServerInvoke")
		local packed = table.pack(pcall(callback, rec.playerSt.proxy, table.unpack(payload, 1, payload.n)))
		if packed[1] then
			local out = { n = packed.n - 1 }
			for i = 2, packed.n do
				out[i - 1] = packed[i]
			end
			results = self:serialize(out, "toClient", rec)
		else
			failure = packed[2]
		end
		done = true
		if waiting then
			scheduler:resume(caller)
		end
	end)
	while not done do
		waiting = true
		scheduler:suspend()
	end
	if failure ~= nil then
		error(failure, 0)
	end
	return table.unpack(results, 1, results.n)
end

function Network:invokeServer(clientRemoteSt, args)
	local rec = self.byClientWorld[clientRemoteSt.world]
	if not rec or not rec.connected then
		error("Harness: client is disconnected", 3)
	end
	local serverRemote = rec.c2s[clientRemoteSt]
	if not serverRemote then
		error("Harness: InvokeServer on a remote that does not exist on the server", 3)
	end
	local payload = self:serialize(args, "toServer", rec)
	return self:_invoke(rec, serverRemote, payload)
end

-- Exploit helpers: talk to server remotes directly, bypassing client code.
local function findServerRemote(server, name: string, className: string?)
	local found = nil
	Instance.eachDescendant(states[server.services.ReplicatedStorage], function(d)
		if not found and d.name == name and (className == nil or d.className == className) then
			found = d
		end
	end)
	return found
end
Network.findServerRemote = findServerRemote

function Network:exploitFire(playerProxy, remoteName: string, ...)
	local rec = self.byPlayer[states[playerProxy]]
	assert(rec, "exploitFire: unknown player")
	local remote = findServerRemote(self.server, remoteName, nil)
	assert(remote, "exploitFire: no remote named " .. remoteName)
	assert(remote.className == "RemoteEvent" or remote.className == "UnreliableRemoteEvent", remoteName .. " is not a RemoteEvent")
	local payload = self:serialize(table.pack(...), "toServer", rec)
	self:_deliverToServer(rec, remote, payload)
end

function Network:exploitInvoke(playerProxy, remoteName: string, ...)
	local rec = self.byPlayer[states[playerProxy]]
	assert(rec, "exploitInvoke: unknown player")
	local remote = findServerRemote(self.server, remoteName, "RemoteFunction")
	assert(remote, "exploitInvoke: no RemoteFunction named " .. remoteName)
	local payload = self:serialize(table.pack(...), "toServer", rec)
	return self:_invoke(rec, remote, payload)
end

-- Joining / leaving -------------------------------------------------------------------------------------

function Network:_mapServices(rec)
	local server = self.server
	local client = rec.world
	rec.s2c[states[server.game]] = states[client.game]
	rec.c2s[states[client.game]] = states[server.game]
	for name, proxy in pairs(server.services) do
		if REPLICATED_SERVICES[name] then
			local sst = states[proxy]
			local cproxy = client:_createService(name)
			local cst = states[cproxy]
			rec.s2c[sst] = cst
			rec.c2s[cst] = sst
		end
	end
	-- StarterPlayer's built-in children exist on both sides.
	local sp = states[server.services.StarterPlayer]
	local csp = states[client.services.StarterPlayer]
	for _, child in ipairs(sp.children) do
		for _, cchild in ipairs(csp.children) do
			if cchild.name == child.name and cchild.className == child.className then
				rec.s2c[child] = cchild
				rec.c2s[cchild] = child
			end
		end
	end
	-- Camera and Terrain are per-world.
	local ws = states[server.services.Workspace]
	local cws = states[client.services.Workspace]
	for _, child in ipairs(ws.children) do
		if child.className == "Terrain" then
			for _, cchild in ipairs(cws.children) do
				if cchild.className == "Terrain" then
					rec.s2c[child] = cchild
					rec.c2s[cchild] = child
				end
			end
		end
	end
end

function Network:_initialSync(rec)
	for sst, cst in pairs(table.clone(rec.s2c)) do
		if sst.parent and sst.parent.className == "DataModel" and REPLICATED_SERVICES[sst.className] then
			for key, value in pairs(sst.props) do
				if not states[value] then
					cst.props[key] = value
				end
			end
			for k, v in pairs(sst.attributes) do
				cst.attributes[k] = v
			end
		end
	end
	local function syncChildren(sst, cst)
		for _, child in ipairs(sst.children) do
			if self:_visible(child, rec) then
				local existing = rec.s2c[child]
				if existing then
					syncChildren(child, existing)
				else
					self:_mirror(rec, child, cst)
				end
			end
		end
	end
	for name in pairs(REPLICATED_SERVICES) do
		local proxy = self.server.services[name]
		if proxy then
			local sst = states[proxy]
			syncChildren(sst, rec.s2c[sst])
		end
	end
	self:_resolvePendingRefs(rec)
end

-- Adds a client world for server player `playerSt` and starts its scripts.
function Network:connect(playerSt, clientWorld)
	local rec = {
		world = clientWorld,
		playerSt = playerSt,
		s2c = {},
		c2s = {},
		pendingRefs = {},
		connected = true,
	}
	table.insert(self.clients, rec)
	self.byPlayer[playerSt] = rec
	self.byClientWorld[clientWorld] = rec
	clientWorld.network = self

	self:_mapServices(rec)
	self:_initialSync(rec)

	local localPlayer = rec.s2c[playerSt]
	assert(localPlayer, "Harness: local player did not replicate")
	clientWorld.localPlayer = localPlayer
	local cplayers = states[clientWorld.services.Players]
	Instance.setProperty(cplayers, "LocalPlayer", localPlayer.proxy)

	local playerScripts = Instance.create(clientWorld, "PlayerScripts", true)
	states[playerScripts].name = "PlayerScripts"
	Instance.setParent(states[playerScripts], localPlayer.proxy)

	clientWorld.scriptsRunning = true
	clientWorld:startScripts()

	-- StarterPlayerScripts -> PlayerScripts, StarterGui -> PlayerGui (client side).
	local sps = nil
	for _, child in ipairs(states[clientWorld.services.StarterPlayer].children) do
		if child.className == "StarterPlayerScripts" then
			sps = child
		end
	end
	if sps then
		for _, child in ipairs(table.clone(sps.children)) do
			local copy = Instance.clone(child)
			if copy then
				Instance.setParent(copy, playerScripts)
			end
		end
	end
	local playerGui = nil
	for _, child in ipairs(localPlayer.children) do
		if child.className == "PlayerGui" then
			playerGui = child
		end
	end
	if playerGui then
		for _, child in ipairs(table.clone(states[clientWorld.services.StarterGui].children)) do
			local copy = Instance.clone(child)
			if copy then
				Instance.setParent(copy, playerGui.proxy)
			end
		end
	end
	return rec
end

-- Removes a player: PlayerRemoving fires on the server, the client world closes.
function Network:disconnect(playerSt, reason: string?)
	local rec = self.byPlayer[playerSt]
	local server = self.server
	local playersSt = states[server.services.Players]
	if playerSt.parent then
		Instance.fire(playersSt, "PlayerRemoving", playerSt.proxy)
	end
	if rec then
		rec.connected = false
		rec.reason = reason
		rec.world:close()
	end
	local character = playerSt.props.Character
	if character and states[character] then
		Instance.destroy(states[character])
	end
	if playerSt.parent then
		Instance.setParent(playerSt, nil, true)
	end
end

-- Kick from either side; deferred so the calling code finishes first (like Roblox).
function Network:disconnectFromWorld(world, playerSt, message: string)
	local serverPlayer = playerSt
	if world ~= self.server then
		local rec = self.byClientWorld[world]
		serverPlayer = rec and rec.playerSt
	end
	if not serverPlayer then
		return
	end
	if world ~= self.server then
		table.insert(self.server.kicks, {
			userId = Instance.getProperty(serverPlayer, "UserId"),
			name = serverPlayer.name,
			message = message,
			time = self.server.scheduler.now,
			fromClient = true,
		})
	end
	self.server.scheduler:defer(function()
		self:disconnect(serverPlayer, "kicked: " .. tostring(message))
	end)
end

return Network
