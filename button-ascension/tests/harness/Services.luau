--[[
	Services.luau

	Behaviour for Roblox services (and the DataModel). Each world creates its
	services lazily through game:GetService(name). Services that exist on
	Roblox but are not modelled here raise
	  "Harness: service 'X' is not implemented in the mock engine"
	and unknown names raise "'X' is not a valid Service name", so gaps are
	visible instead of silently returning nil.
]]

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Instance = require("./Instance")
local Reflection = require("./Reflection")
local Types = require("./Types")
local Classes = require("./Classes")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local Enum = roblox.Enum
local states = Instance.states
local getProperty = Instance.getProperty
local setProperty = Instance.setProperty

local Services = {}

-- Services the harness models. Value = true means "create on demand".
Services.Implemented = {
	Workspace = true,
	Players = true,
	ReplicatedStorage = true,
	ReplicatedFirst = true,
	ServerScriptService = true,
	ServerStorage = true,
	StarterPlayer = true,
	StarterGui = true,
	StarterPack = true,
	Lighting = true,
	SoundService = true,
	RunService = true,
	DataStoreService = true,
	MessagingService = true,
	TextService = true,
	HttpService = true,
	TweenService = true,
	UserInputService = true,
	ContextActionService = true,
	GuiService = true,
	TextChatService = true,
	Stats = true,
	Debris = true,
	CollectionService = true,
	MarketplaceService = true,
	Teams = true,
	PhysicsService = true,
	LocalizationService = true,
	SocialService = true,
	PolicyService = true,
	BadgeService = true,
	GroupService = true,
	TeleportService = true,
	Chat = true,
	TestService = true,
	ProximityPromptService = true,
	HapticService = true,
	VRService = true,
	ContentProvider = true,
	AnalyticsService = true,
}

local function svc(self, name)
	return Instance.stateOf(self, name)
end

-- DataModel ---------------------------------------------------------------------------------------

local function getService(self, name)
	local st = Instance.stateOf(self, "GetService")
	if type(name) ~= "string" then
		error("Argument 1 missing or nil", 2)
	end
	local world = st.world
	local existing = world.services[name]
	if existing then
		return existing
	end
	if not Reflection.classExists(name) or not Reflection.isService(name) then
		error(string.format("'%s' is not a valid Service name", name), 2)
	end
	if not Services.Implemented[name] then
		error(string.format("Harness: service '%s' is not implemented in the mock engine", name), 2)
	end
	return world:_createService(name)
end

Instance.define("DataModel", {
	getters = {
		Workspace = function(st)
			return st.world.services.Workspace
		end,
		workspace = function(st)
			return st.world.services.Workspace
		end,
		lighting = function(st)
			return st.world:service("Lighting")
		end,
	},
	methods = {
		GetService = getService,
		getService = getService,
		service = getService,
		FindService = function(self, name)
			local st = Instance.stateOf(self, "FindService")
			return st.world.services[name]
		end,
		BindToClose = function(self, fn)
			local st = Instance.stateOf(self, "BindToClose")
			if type(fn) ~= "function" then
				error("Argument 1 missing or nil", 2)
			end
			if st.world.role ~= "server" then
				error("BindToClose can only be called on the server", 2)
			end
			table.insert(st.world.closeCallbacks, fn)
		end,
		IsLoaded = function()
			return true
		end,
		GetJobsInfo = function()
			return {}
		end,
		Shutdown = function(self)
			local st = Instance.stateOf(self, "Shutdown")
			st.world.shutdownRequested = true
		end,
	},
})

-- Workspace ------------------------------------------------------------------------------------------

Instance.define("Workspace", {
	methods = {
		GetServerTimeNow = function(self)
			return svc(self, "GetServerTimeNow").world.scheduler:unixTime()
		end,
		GetRealPhysicsFPS = function()
			return 60
		end,
		GetNumAwakeParts = function()
			return 0
		end,
		GetPhysicsThrottling = function()
			return 100
		end,
		Raycast = function()
			return nil
		end,
		Blockcast = function()
			return nil
		end,
		Spherecast = function()
			return nil
		end,
		Shapecast = function()
			return nil
		end,
		GetPartBoundsInBox = function()
			return {}
		end,
		GetPartBoundsInRadius = function()
			return {}
		end,
		GetPartsInPart = function()
			return {}
		end,
		FindPartOnRay = function(_, ray)
			return nil, ray.Origin + ray.Direction, Vector3.yAxis, Enum.Material.Air
		end,
		FindPartOnRayWithIgnoreList = function(_, ray)
			return nil, ray.Origin + ray.Direction, Vector3.yAxis, Enum.Material.Air
		end,
	},
})

-- RunService -----------------------------------------------------------------------------------------

Instance.define("RunService", {
	methods = {
		IsServer = function(self)
			return svc(self, "IsServer").world.role == "server"
		end,
		IsClient = function(self)
			return svc(self, "IsClient").world.role == "client"
		end,
		IsStudio = function(self)
			return svc(self, "IsStudio").world.isStudio
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function(self, name, priority, fn)
			local st = svc(self, "BindToRenderStep")
			if st.world.role ~= "client" then
				error("BindToRenderStep can only be used from a LocalScript", 2)
			end
			if type(name) ~= "string" or type(priority) ~= "number" or type(fn) ~= "function" then
				error("BindToRenderStep expects (string, number, function)", 2)
			end
			st.world.renderBindings[name] = { priority = priority, fn = fn }
		end,
		UnbindFromRenderStep = function(self, name)
			local st = svc(self, "UnbindFromRenderStep")
			st.world.renderBindings[name] = nil
		end,
	},
})

-- Players ------------------------------------------------------------------------------------------------

local function players(st)
	local out = {}
	for _, child in ipairs(st.children) do
		if child.className == "Player" then
			table.insert(out, child.proxy)
		end
	end
	return out
end

Instance.define("Players", {
	methods = {
		GetPlayers = function(self)
			return players(svc(self, "GetPlayers"))
		end,
		getPlayers = function(self)
			return players(svc(self, "getPlayers"))
		end,
		GetPlayerByUserId = function(self, userId)
			local st = svc(self, "GetPlayerByUserId")
			if type(userId) ~= "number" then
				error("Argument 1 missing or nil", 2)
			end
			for _, child in ipairs(st.children) do
				if child.className == "Player" and getProperty(child, "UserId") == userId then
					return child.proxy
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(self, character)
			local st = svc(self, "GetPlayerFromCharacter")
			if character == nil then
				return nil
			end
			for _, child in ipairs(st.children) do
				if child.className == "Player" and child.props.Character == character then
					return child.proxy
				end
			end
			return nil
		end,
		GetNameFromUserIdAsync = function(self, userId)
			local st = svc(self, "GetNameFromUserIdAsync")
			if type(userId) ~= "number" then
				error("Argument 1 missing or nil", 2)
			end
			local backend = st.world.backend
			if backend and backend.unavailable then
				error(backend.unavailable, 2)
			end
			for _, child in ipairs(st.children) do
				if child.className == "Player" and getProperty(child, "UserId") == userId then
					return child.name
				end
			end
			if backend and backend.userNames[userId] then
				return backend.userNames[userId]
			end
			return "User" .. tostring(userId)
		end,
		GetUserIdFromNameAsync = function(self, name)
			local st = svc(self, "GetUserIdFromNameAsync")
			for _, child in ipairs(st.children) do
				if child.className == "Player" and string.lower(child.name) == string.lower(tostring(name)) then
					return getProperty(child, "UserId")
				end
			end
			local backend = st.world.backend
			if backend then
				for id, n in pairs(backend.userNames) do
					if string.lower(n) == string.lower(tostring(name)) then
						return id
					end
				end
			end
			error("Players:GetUserIdFromNameAsync() failed: Unknown user", 2)
		end,
		GetUserThumbnailAsync = function(_, userId)
			return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId or 0), true
		end,
		GetFriendsAsync = function()
			error("Harness: Players:GetFriendsAsync() is not implemented in the mock engine", 2)
		end,
	},
})

-- DataStoreService ----------------------------------------------------------------------------------------

local function backendOf(st)
	local backend = st.world.backend
	if not backend then
		error("Harness: this world has no Backend (DataStores unavailable)", 3)
	end
	return backend
end

Instance.define("DataStoreService", {
	methods = {
		GetDataStore = function(self, name, scope, _options)
			local st = svc(self, "GetDataStore")
			if st.world.role ~= "server" then
				error("DataStoreService can only be used on the server", 2)
			end
			return backendOf(st):getStore("global", name, scope)
		end,
		GetGlobalDataStore = function(self)
			local st = svc(self, "GetGlobalDataStore")
			return backendOf(st):getStore("global", "__global")
		end,
		GetOrderedDataStore = function(self, name, scope)
			local st = svc(self, "GetOrderedDataStore")
			if st.world.role ~= "server" then
				error("DataStoreService can only be used on the server", 2)
			end
			return backendOf(st):getStore("ordered", name, scope)
		end,
		GetRequestBudgetForRequestType = function(self, _requestType)
			local st = svc(self, "GetRequestBudgetForRequestType")
			return backendOf(st).budget
		end,
	},
})

Instance.define("MessagingService", {
	methods = {
		PublishAsync = function(self, topic, message)
			local st = svc(self, "PublishAsync")
			backendOf(st):publish(topic, message)
		end,
		SubscribeAsync = function(self, topic, callback)
			local st = svc(self, "SubscribeAsync")
			if type(callback) ~= "function" then
				error("Argument 2 missing or nil", 2)
			end
			return backendOf(st):subscribe(st.world, topic, callback)
		end,
	},
})

-- TextService --------------------------------------------------------------------------------------------

local function approxTextSize(text: string, size: number, frameWidth: number?)
	local width = (utf8.len(text) or #text) * size * 0.55
	local lines = 1
	if frameWidth and frameWidth > 0 and width > frameWidth then
		lines = math.ceil(width / frameWidth)
		width = frameWidth
	end
	return Vector2.new(width, lines * size)
end

Instance.define("TextService", {
	methods = {
		FilterStringAsync = function(self, text, fromUserId, _context)
			local st = svc(self, "FilterStringAsync")
			if type(text) ~= "string" then
				error("Argument 1 missing or nil", 2)
			end
			if type(fromUserId) ~= "number" then
				error("Argument 2 missing or nil", 2)
			end
			local filtered = backendOf(st):filter(text)
			local result = Instance.create(st.world, "TextFilterResult", true)
			states[result].internal.filtered = filtered
			return result
		end,
		GetTextSize = function(_, text, size, _font, frameSize)
			return approxTextSize(tostring(text), size or 14, frameSize and frameSize.X)
		end,
		GetTextBoundsAsync = function(_, params)
			return approxTextSize(tostring(params.Text or ""), params.Size or 14, params.Width)
		end,
	},
})

-- HttpService --------------------------------------------------------------------------------------------

Instance.define("HttpService", {
	methods = {
		GenerateGUID = function(self, wrap)
			local st = svc(self, "GenerateGUID")
			local rng = st.world.rng
			local hex = "0123456789ABCDEF"
			local parts = {}
			for i = 1, 32 do
				local n = rng:NextInteger(1, 16)
				if i == 13 then
					n = 5 -- version 4
				elseif i == 17 then
					n = 9 + rng:NextInteger(0, 3)
				end
				parts[i] = string.sub(hex, n, n)
			end
			local s = table.concat(parts)
			local guid = string.format("%s-%s-%s-%s-%s", string.sub(s, 1, 8), string.sub(s, 9, 12), string.sub(s, 13, 16), string.sub(s, 17, 20), string.sub(s, 21, 32))
			if wrap == false then
				return guid
			end
			return "{" .. guid .. "}"
		end,
		JSONEncode = function(_, value)
			local ok, result = pcall(serde.encode, "json", value)
			if not ok then
				error("Can't convert to JSON: " .. tostring(result), 2)
			end
			return result
		end,
		JSONDecode = function(_, text)
			local ok, result = pcall(serde.decode, "json", text)
			if not ok then
				error("Can't parse JSON", 2)
			end
			return result
		end,
		UrlEncode = function(_, text)
			return (string.gsub(tostring(text), "[^%w%-_%.~]", function(c)
				return string.format("%%%02X", string.byte(c))
			end))
		end,
		GetAsync = function()
			error("Harness: HttpService requests are disabled in tests", 2)
		end,
		PostAsync = function()
			error("Harness: HttpService requests are disabled in tests", 2)
		end,
		RequestAsync = function()
			error("Harness: HttpService requests are disabled in tests", 2)
		end,
	},
})

-- TweenService -----------------------------------------------------------------------------------------

Instance.define("TweenService", {
	methods = {
		Create = function(self, instance, info, goals)
			local st = svc(self, "Create")
			return Classes.createTween(st.world, instance, info, goals)
		end,
		GetValue = function(_, alpha, style, direction)
			return Classes.easing(style, direction, math.clamp(alpha, 0, 1))
		end,
	},
})

-- Input ----------------------------------------------------------------------------------------------------

Instance.define("UserInputService", {
	methods = {
		GetLastInputType = function(self)
			return svc(self, "GetLastInputType").world.input.lastInputType
		end,
		GetGamepadConnected = function(self, gamepad)
			local input = svc(self, "GetGamepadConnected").world.input
			return input.gamepad and gamepad == Enum.UserInputType.Gamepad1
		end,
		GetConnectedGamepads = function(self)
			local input = svc(self, "GetConnectedGamepads").world.input
			return if input.gamepad then { Enum.UserInputType.Gamepad1 } else {}
		end,
		GetNavigationGamepads = function(self)
			local input = svc(self, "GetNavigationGamepads").world.input
			return if input.gamepad then { Enum.UserInputType.Gamepad1 } else {}
		end,
		GetSupportedGamepadKeyCodes = function()
			return {}
		end,
		GetMouseLocation = function(self)
			local world = svc(self, "GetMouseLocation").world
			return world.viewport / 2
		end,
		GetMouseDelta = function()
			return Vector2.zero
		end,
		GetMouseButtonsPressed = function()
			return {}
		end,
		IsKeyDown = function(self, keyCode)
			local input = svc(self, "IsKeyDown").world.input
			return input.keysDown[keyCode] == true
		end,
		IsMouseButtonPressed = function()
			return false
		end,
		IsGamepadButtonDown = function()
			return false
		end,
		GetKeysPressed = function()
			return {}
		end,
		GetGamepadState = function()
			return {}
		end,
		GetFocusedTextBox = function()
			return nil
		end,
		GetStringForKeyCode = function(_, keyCode)
			return keyCode.Name
		end,
		GetImageForKeyCode = function()
			return ""
		end,
	},
})

Instance.define("ContextActionService", {
	methods = {
		BindAction = function(self, name, fn, createTouchButton, ...)
			local st = svc(self, "BindAction")
			if type(name) ~= "string" or type(fn) ~= "function" then
				error("BindAction expects (string, function, bool, ...inputs)", 2)
			end
			st.world.actions[name] = { fn = fn, touch = createTouchButton, inputs = { ... }, priority = 2000 }
		end,
		BindActionAtPriority = function(self, name, fn, createTouchButton, priority, ...)
			local st = svc(self, "BindActionAtPriority")
			if type(name) ~= "string" or type(fn) ~= "function" then
				error("BindActionAtPriority expects (string, function, bool, number, ...inputs)", 2)
			end
			st.world.actions[name] = { fn = fn, touch = createTouchButton, inputs = { ... }, priority = priority }
		end,
		UnbindAction = function(self, name)
			svc(self, "UnbindAction").world.actions[name] = nil
		end,
		UnbindAllActions = function(self)
			table.clear(svc(self, "UnbindAllActions").world.actions)
		end,
		GetBoundActionInfo = function(self, name)
			local action = svc(self, "GetBoundActionInfo").world.actions[name]
			return if action then { inputTypes = action.inputs, priorityLevel = action.priority, createTouchButton = action.touch } else {}
		end,
		GetAllBoundActionInfo = function(self)
			local out = {}
			for name, action in pairs(svc(self, "GetAllBoundActionInfo").world.actions) do
				out[name] = { inputTypes = action.inputs, priorityLevel = action.priority, createTouchButton = action.touch }
			end
			return out
		end,
		SetTitle = function() end,
		SetDescription = function() end,
		SetImage = function() end,
		SetPosition = function() end,
		GetButton = function()
			return nil
		end,
		BindActivate = function() end,
		UnbindActivate = function() end,
	},
})

Instance.define("GuiService", {
	methods = {
		Select = function(self, selectionParent)
			local st = svc(self, "Select")
			local parent = states[selectionParent]
			if not parent then
				error("Argument 1 missing or nil", 2)
			end
			local found = nil
			Instance.eachDescendant(parent, function(d)
				if not found and Reflection.isA(d.className, "GuiObject") and getProperty(d, "Selectable") and getProperty(d, "Visible") then
					found = d
				end
			end)
			setProperty(st, "SelectedObject", found and found.proxy)
		end,
		GetGuiInset = function()
			return Vector2.new(0, 58), Vector2.new(0, 0)
		end,
		IsTenFootInterface = function()
			return false
		end,
		GetEmotesMenuOpen = function()
			return false
		end,
		SetEmotesMenuOpen = function() end,
		GetInspectMenuEnabled = function()
			return false
		end,
		SetInspectMenuEnabled = function() end,
		InspectPlayerFromUserId = function() end,
		CloseInspectMenu = function() end,
		AddSelectionParent = function() end,
		RemoveSelectionGroup = function() end,
	},
})

Instance.define("StarterGui", {
	methods = {
		SetCoreGuiEnabled = function(self, coreGuiType, enabled)
			local st = svc(self, "SetCoreGuiEnabled")
			st.world.coreGui[coreGuiType] = enabled == true
		end,
		GetCoreGuiEnabled = function(self, coreGuiType)
			local value = svc(self, "GetCoreGuiEnabled").world.coreGui[coreGuiType]
			return if value == nil then true else value
		end,
		SetCore = function(self, name, value)
			local st = svc(self, "SetCore")
			st.world.core[name] = value
		end,
		GetCore = function(self, name)
			local value = svc(self, "GetCore").world.core[name]
			if value == nil then
				error(string.format("GetCore: %s has not been registered by the CoreScripts", tostring(name)), 2)
			end
			return value
		end,
		RegisterSetCore = function() end,
		RegisterGetCore = function() end,
	},
})

Instance.define("SoundService", {
	methods = {
		PlayLocalSound = function(_, sound)
			sound:Play()
		end,
		SetListener = function() end,
		GetListener = function()
			return Enum.ListenerType.Camera, nil
		end,
	},
})

Instance.define("Stats", {
	onCreate = function(st)
		st.props.HeartbeatTimeMs = 16.6
		st.props.HeartbeatTime = 0.0166
		st.props.PhysicsStepTimeMs = 2
		st.props.DataReceiveKbps = 12
		st.props.DataSendKbps = 24
		st.props.FrameTime = 0.0166
	end,
	getters = {
		InstanceCount = function(st)
			return st.world.instanceCount
		end,
	},
	methods = {
		GetTotalMemoryUsageMb = function()
			return 412.5
		end,
		GetMemoryUsageMbForTag = function()
			return 10
		end,
		GetMemoryUsageMbAllCategories = function()
			return {}
		end,
	},
})

Instance.define("Debris", {
	methods = {
		AddItem = function(self, item, lifetime)
			local st = svc(self, "AddItem")
			local target = states[item]
			if not target then
				error("Argument 1 missing or nil", 2)
			end
			st.world.scheduler:after(lifetime or 10, function()
				Instance.destroy(target)
			end, st.world)
		end,
		addItem = function(self, item, lifetime)
			local st = svc(self, "addItem")
			local target = states[item]
			st.world.scheduler:after(lifetime or 10, function()
				Instance.destroy(target)
			end, st.world)
		end,
	},
})

Instance.define("CollectionService", {
	methods = {
		AddTag = function(_, instance, tag)
			instance:AddTag(tag)
		end,
		RemoveTag = function(_, instance, tag)
			instance:RemoveTag(tag)
		end,
		HasTag = function(_, instance, tag)
			return instance:HasTag(tag)
		end,
		GetTags = function(_, instance)
			return instance:GetTags()
		end,
		GetTagged = function(self, tag)
			local st = svc(self, "GetTagged")
			local out = {}
			Instance.eachDescendant(states[st.world.game], function(d)
				if d.tags[tag] then
					table.insert(out, d.proxy)
				end
			end)
			return out
		end,
		GetAllTags = function(self)
			local st = svc(self, "GetAllTags")
			local seen, out = {}, {}
			Instance.eachDescendant(states[st.world.game], function(d)
				for tag in pairs(d.tags) do
					if not seen[tag] then
						seen[tag] = true
						table.insert(out, tag)
					end
				end
			end)
			table.sort(out)
			return out
		end,
		GetInstanceAddedSignal = function(self, tag)
			return svc(self, "GetInstanceAddedSignal").world:tagSignal(tag, true)
		end,
		GetInstanceRemovedSignal = function(self, tag)
			return svc(self, "GetInstanceRemovedSignal").world:tagSignal(tag, false)
		end,
	},
})

Instance.define("MarketplaceService", {
	methods = {
		PromptProductPurchase = function(self, player, productId)
			table.insert(svc(self, "PromptProductPurchase").world.prompts, { kind = "product", player = player, id = productId })
		end,
		PromptGamePassPurchase = function(self, player, passId)
			table.insert(svc(self, "PromptGamePassPurchase").world.prompts, { kind = "gamepass", player = player, id = passId })
		end,
		PromptPurchase = function(self, player, assetId)
			table.insert(svc(self, "PromptPurchase").world.prompts, { kind = "asset", player = player, id = assetId })
		end,
		PromptPremiumPurchase = function(self, player)
			table.insert(svc(self, "PromptPremiumPurchase").world.prompts, { kind = "premium", player = player })
		end,
		UserOwnsGamePassAsync = function()
			return false
		end,
		PlayerOwnsAsset = function()
			return false
		end,
		PlayerOwnsBundle = function()
			return false
		end,
		GetProductInfo = function(_, id)
			return { Name = "Product " .. tostring(id), PriceInRobux = 0, AssetId = id, IsForSale = false }
		end,
	},
})

Instance.define("Teams", {
	methods = {
		GetTeams = function(self)
			local st = svc(self, "GetTeams")
			local out = {}
			for _, child in ipairs(st.children) do
				if child.className == "Team" then
					table.insert(out, child.proxy)
				end
			end
			return out
		end,
	},
})

Instance.define("PhysicsService", {
	methods = {
		RegisterCollisionGroup = function(self, name)
			svc(self, "RegisterCollisionGroup").world.collisionGroups[name] = true
		end,
		UnregisterCollisionGroup = function(self, name)
			svc(self, "UnregisterCollisionGroup").world.collisionGroups[name] = nil
		end,
		IsCollisionGroupRegistered = function(self, name)
			return name == "Default" or svc(self, "IsCollisionGroupRegistered").world.collisionGroups[name] == true
		end,
		CollisionGroupSetCollidable = function() end,
		CollisionGroupsAreCollidable = function()
			return true
		end,
		GetRegisteredCollisionGroups = function(self)
			local out = { { name = "Default", id = 0 } }
			for name in pairs(svc(self, "GetRegisteredCollisionGroups").world.collisionGroups) do
				table.insert(out, { name = name, id = #out })
			end
			return out
		end,
		GetMaxCollisionGroups = function()
			return 32
		end,
	},
})

Instance.define("LocalizationService", {
	methods = {
		GetCountryRegionForPlayerAsync = function()
			return "US"
		end,
	},
})

Instance.define("SocialService", {
	methods = {
		CanSendGameInviteAsync = function()
			return false
		end,
		PromptGameInvite = function() end,
		CanSendCallInviteAsync = function()
			return false
		end,
	},
})

Instance.define("PolicyService", {
	methods = {
		GetPolicyInfoForPlayerAsync = function()
			return {
				AreAdsAllowed = false,
				ArePaidRandomItemsRestricted = false,
				AllowedExternalLinkReferences = {},
				IsEligibleToPurchaseSubscription = true,
				IsPaidItemTradingAllowed = true,
				IsSubjectToChinaPolicies = false,
			}
		end,
	},
})

Instance.define("BadgeService", {
	methods = {
		AwardBadge = function()
			return true
		end,
		UserHasBadgeAsync = function()
			return false
		end,
		GetBadgeInfoAsync = function(_, id)
			return { Name = "Badge " .. tostring(id), IsEnabled = true }
		end,
	},
})

Instance.define("GroupService", {
	methods = {
		GetGroupInfoAsync = function(_, id)
			return { Id = id, Name = "Group " .. tostring(id), Owner = { Id = 1, Name = "Owner" }, Roles = {} }
		end,
		GetGroupsAsync = function()
			return {}
		end,
	},
})

Instance.define("TeleportService", {
	methods = {
		Teleport = function(self, placeId, player)
			table.insert(svc(self, "Teleport").world.teleports, { placeId = placeId, player = player })
		end,
		TeleportAsync = function(self, placeId, playersList)
			table.insert(svc(self, "TeleportAsync").world.teleports, { placeId = placeId, players = playersList })
		end,
		GetLocalPlayerTeleportData = function()
			return nil
		end,
	},
})

Instance.define("TextChatService", {
	methods = {
		CanUserChatAsync = function()
			return true
		end,
		CanUsersChatAsync = function()
			return true
		end,
		CanUsersDirectChatAsync = function(_, _userId, userIds)
			return userIds or {}
		end,
		DisplayBubble = function() end,
	},
})

Instance.define("Lighting", {
	methods = {
		GetMinutesAfterMidnight = function(self)
			return getProperty(svc(self, "GetMinutesAfterMidnight"), "ClockTime") * 60
		end,
		SetMinutesAfterMidnight = function(self, minutes)
			setProperty(svc(self, "SetMinutesAfterMidnight"), "ClockTime", (minutes / 60) % 24)
		end,
		GetSunDirection = function()
			return Vector3.new(0, 1, 0)
		end,
		GetMoonDirection = function()
			return Vector3.new(0, -1, 0)
		end,
	},
})

Instance.define("ReplicatedFirst", {
	methods = {
		RemoveDefaultLoadingScreen = function() end,
		IsFinishedReplicating = function()
			return true
		end,
		SetDefaultLoadingGuiRemoved = function() end,
	},
})

Instance.define("ContentProvider", {
	methods = {
		PreloadAsync = function(_, _list, callback)
			if type(callback) == "function" then
				for _, item in ipairs(_list or {}) do
					callback(if type(item) == "string" then item else "", Enum.AssetFetchStatus.Success)
				end
			end
		end,
	},
})

Instance.define("TestService", {
	methods = {
		Message = function(self, text)
			svc(self, "Message").world:log("print", tostring(text))
		end,
		Warn = function(self, condition, text)
			if not condition then
				svc(self, "Warn").world:log("warn", tostring(text))
			end
		end,
		Check = function() end,
		Checkpoint = function() end,
		Done = function() end,
		Error = function(self, text)
			svc(self, "Error").world:log("warn", tostring(text))
		end,
		Fail = function(self, text)
			svc(self, "Fail").world:log("warn", tostring(text))
		end,
	},
})

Instance.define("AnalyticsService", {
	methods = {
		LogCustomEvent = function() end,
		LogEconomyEvent = function() end,
		LogProgressionEvent = function() end,
		LogOnboardingFunnelStepEvent = function() end,
		LogFunnelStepEvent = function() end,
	},
})

Services.typeofService = function(value)
	return Types.typeof(value)
end

return Services
