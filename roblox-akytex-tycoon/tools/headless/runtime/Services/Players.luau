--!nocheck
-- =====================================================================
--  Headless-Harness · Players, Player, Figuren (R15), Humanoid, Sitze, Animator/AnimationTrack, PlayerMouse
--
--  Harness-API (R.Svc.Players):
--    P.newPlayer(game, info) -> Player (Server-DataModel; info = { userId, name, displayName, locale, accountAge,
--                               membership = "None"|"Premium", groups = { [id] = {Rank, Role} }, friends = {ids} })
--    P.loadCharacter(player)  -> Figur bauen und an der SpawnLocation absetzen (wie Player:LoadCharacter)
--    P.removePlayer(player, reason) -> PlayerRemoving, Figur weg, Player entfernen (Game-Modul schließt den Client)
--    P.users[userId] = { name, displayName }   bekannte Nutzer (GetNameFromUserIdAsync …)
--    P.bans[userId] = { … }                     Bann-Speicher (BanAsync/UnbanAsync/GetBanHistoryAsync)
--    P.onRemove = function(player, reason)      vom Game-Modul gesetzt (Client-Kontext schließen)
--  Figuren: Archivable = false (wie Roblox – :Clone() liefert dann nil), HumanoidRootPart (RootPriority 127),
--  15 R15-Teile mit Motor6D, Humanoid (Health 100, Animator, HumanoidDescription), BodyColors.
--  Humanoid: Health-Klemmung, HealthChanged, Died (einmal, Zustand Dead, BreakJointsOnDeath), Respawn nach
--  Players.RespawnTime (nur Server, CharacterAutoLoads), MoveTo/MoveToFinished (gerade Linie mit WalkSpeed,
--  Timeout 8 s), ChangeState/GetState/StateChanged/SetStateEnabled, TakeDamage (ForceField), Sit/SeatPart/Seated,
--  RootPart, Get/ApplyDescription (Server), AddAccessory/GetAccessories/RemoveAccessories, EquipTool/UnequipTools.
-- =====================================================================
return function(R, Svc)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local raise = Util.raise
	local getmt = getmetatable
	local fmt = string.format
	local mk = DT.make
	local CF = DT.CFrame

	local P = {}
	Svc.Players = P
	P.users = {}
	P.bans = {}
	P.banHistory = {}

	local function ext(M)
		local e = M.ext
		if e == nil then
			e = {}
			M.ext = e
		end
		return e
	end

	local function playersOf(game)
		return Inst.findServiceRaw(game, "Players")
	end
	local function workspaceOf(game)
		return Inst.findServiceRaw(game, "Workspace")
	end

	local function playerList(svcM)
		local out = {}
		for _, c in svcM.children do
			local CM = getmt(c)
			if CM.cls.isA.Player and Inst.visible(c) then
				out[#out + 1] = c
			end
		end
		return out
	end

	local function info(pM)
		return ext(pM).info or {}
	end

	-- =================================================================================================
	--  Players-Service
	-- =================================================================================================
	local PS = {}
	function PS.GetPlayers(self)
		local M = Inst.checkSelf(self, "GetPlayers")
		return playerList(M)
	end
	function PS.GetPlayerByUserId(self, userId)
		local M = Inst.checkSelf(self, "GetPlayerByUserId")
		userId = Util.checkNumber(userId, 1, "GetPlayerByUserId")
		for _, p in playerList(M) do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end
	function PS.GetPlayerFromCharacter(self, character)
		local M = Inst.checkSelf(self, "GetPlayerFromCharacter")
		if character == nil then
			return nil
		end
		if not Inst.is(character) then
			Util.badArg(1, "GetPlayerFromCharacter", "Instance", character)
		end
		for _, p in playerList(M) do
			if getmt(p).props.Character == character then
				return p
			end
		end
		return nil
	end

	local function svcCtx(self)
		return Svc.ctxOf(self)
	end

	local function isoTime(unix)
		return DT.DateTime.fromUnixTimestamp(math.floor(unix)):ToIsoDate()
	end

	function PS.BanAsync(self, config)
		local M = Inst.checkSelf(self, "BanAsync")
		local ctx = svcCtx(self)
		if ctx.isClient then
			raise("BanAsync can only be called from the server")
		end
		if type(config) ~= "table" then
			Util.badArg(1, "BanAsync", "table", config)
		end
		local rp = M.ext and M.ext.rojoProps
		if rp and rp.BanningEnabled == false then
			raise("Players:BanAsync() failed: Banning is not enabled (Players.BanningEnabled)")
		end
		local ids = config.UserIds
		if type(ids) ~= "table" or #ids == 0 then
			raise("Players:BanAsync() failed: UserIds is required and must be a non-empty array")
		end
		if #ids > 50 then
			raise("Players:BanAsync() failed: UserIds exceeds the maximum of 50")
		end
		for _, id in ids do
			if type(id) ~= "number" or id ~= math.floor(id) or id <= 0 then
				raise("Players:BanAsync() failed: UserIds must contain positive integers")
			end
		end
		local dur = config.Duration
		if type(dur) ~= "number" or dur ~= math.floor(dur) or (dur <= 0 and dur ~= -1) then
			raise("Players:BanAsync() failed: Duration must be a positive integer or -1")
		end
		local display = config.DisplayReason
		if type(display) ~= "string" then
			raise("Players:BanAsync() failed: DisplayReason is required and must be a string")
		end
		if utf8.len(display) and utf8.len(display) > 400 then
			raise("Players:BanAsync() failed: DisplayReason exceeds 400 characters")
		end
		local private = config.PrivateReason
		if type(private) ~= "string" then
			raise("Players:BanAsync() failed: PrivateReason is required and must be a string")
		end
		if utf8.len(private) and utf8.len(private) > 1000 then
			raise("Players:BanAsync() failed: PrivateReason exceeds 1000 characters")
		end
		for _, k in { "ApplyToUniverse", "ExcludeAltAccounts", "ApplyDeviceBlock" } do
			if config[k] ~= nil and type(config[k]) ~= "boolean" then
				raise("Players:BanAsync() failed: " .. k .. " must be a boolean")
			end
		end
		Svc.latency(0.2)
		local now = Sched.unix()
		local game = M.parent
		for _, id in ids do
			local entry = {
				Ban = true,
				DisplayReason = display,
				PrivateReason = private,
				Duration = dur,
				StartTime = isoTime(now),
				startUnix = now,
				PlaceId = game and game.PlaceId or 0,
			}
			P.bans[id] = entry
			P.banHistory[id] = P.banHistory[id] or {}
			table.insert(P.banHistory[id], entry)
			-- anwesende Spieler werden sofort entfernt (Kick mit DisplayReason)
			if game then
				for _, p in playerList(getmt(playersOf(game))) do
					if p.UserId == id then
						P.removePlayer(p, "Banned: " .. display)
					end
				end
			end
		end
	end
	function PS.UnbanAsync(self, config)
		Inst.checkSelf(self, "UnbanAsync")
		local ctx = svcCtx(self)
		if ctx.isClient then
			raise("UnbanAsync can only be called from the server")
		end
		if type(config) ~= "table" then
			Util.badArg(1, "UnbanAsync", "table", config)
		end
		local ids = config.UserIds
		if type(ids) ~= "table" or #ids == 0 or #ids > 50 then
			raise("Players:UnbanAsync() failed: UserIds is required (1-50 entries)")
		end
		for _, id in ids do
			if type(id) ~= "number" or id ~= math.floor(id) or id <= 0 then
				raise("Players:UnbanAsync() failed: UserIds must contain positive integers")
			end
		end
		Svc.latency(0.2)
		for _, id in ids do
			if P.bans[id] then
				P.bans[id] = nil
				P.banHistory[id] = P.banHistory[id] or {}
				table.insert(P.banHistory[id], {
					Ban = false,
					DisplayReason = "",
					PrivateReason = "",
					Duration = 0,
					StartTime = isoTime(Sched.unix()),
					PlaceId = 0,
				})
			end
		end
	end
	function PS.GetBanHistoryAsync(self, userId)
		Inst.checkSelf(self, "GetBanHistoryAsync")
		local ctx = svcCtx(self)
		if ctx.isClient then
			raise("GetBanHistoryAsync can only be called from the server")
		end
		userId = Util.checkNumber(userId, 1, "GetBanHistoryAsync")
		Svc.latency(0.1)
		local list = {}
		for _, e in P.banHistory[userId] or {} do
			list[#list + 1] = {
				Ban = e.Ban,
				DisplayReason = e.DisplayReason,
				PrivateReason = e.PrivateReason,
				Duration = e.Duration,
				StartTime = e.StartTime,
				PlaceId = e.PlaceId,
			}
		end
		return Svc.newPages("BanHistoryPages", { list })
	end
	function PS.GetNameFromUserIdAsync(self, userId)
		Inst.checkSelf(self, "GetNameFromUserIdAsync")
		userId = Util.checkNumber(userId, 1, "GetNameFromUserIdAsync")
		Svc.latency(0.1)
		local u = P.users[userId]
		if u then
			return u.name
		end
		if userId <= 0 or userId ~= math.floor(userId) then
			raise("Players:GetNameFromUserIdAsync() failed because HTTP 400 (Bad Request)")
		end
		return "User" .. tostring(userId)
	end
	function PS.GetUserIdFromNameAsync(self, name)
		Inst.checkSelf(self, "GetUserIdFromNameAsync")
		name = Util.checkString(name, 1, "GetUserIdFromNameAsync")
		Svc.latency(0.1)
		for id, u in P.users do
			if string.lower(u.name) == string.lower(name) then
				return id
			end
		end
		local id = string.match(name, "^User(%d+)$")
		if id then
			return tonumber(id)
		end
		raise("Players:GetUserIdFromNameAsync() failed: Unknown user")
	end
	function PS.GetFriendsAsync(self, userId)
		Inst.checkSelf(self, "GetFriendsAsync")
		userId = Util.checkNumber(userId, 1, "GetFriendsAsync")
		Svc.latency(0.1)
		local u = P.users[userId]
		local list = {}
		for _, fid in (u and u.friends) or {} do
			local fu = P.users[fid]
			list[#list + 1] = {
				Id = fid,
				Username = fu and fu.name or ("User" .. fid),
				DisplayName = fu and fu.displayName or ("User" .. fid),
				IsOnline = false,
			}
		end
		return Svc.newPages("FriendPages", { list })
	end
	function PS.GetUserThumbnailAsync(self, userId, thumbType, thumbSize)
		Inst.checkSelf(self, "GetUserThumbnailAsync")
		userId = Util.checkNumber(userId, 1, "GetUserThumbnailAsync")
		local tt = Enum.coerce(thumbType, "ThumbnailType")
		if tt == nil then
			Util.badArg(2, "GetUserThumbnailAsync", "Enum.ThumbnailType", thumbType)
		end
		local ts = Enum.coerce(thumbSize, "ThumbnailSize")
		if ts == nil then
			Util.badArg(3, "GetUserThumbnailAsync", "Enum.ThumbnailSize", thumbSize)
		end
		Svc.latency(0.05)
		local w = string.match(ts.Name, "Size(%d+)x") or "420"
		local kind = tt.Name == "HeadShot" and "AvatarHeadShot" or (tt.Name == "AvatarBust" and "AvatarBust" or "Avatar")
		return fmt("rbxthumb://type=%s&id=%d&w=%s&h=%s", kind, userId, w, w), true
	end
	function PS.GetCharacterAppearanceInfoAsync(self, userId)
		Inst.checkSelf(self, "GetCharacterAppearanceInfoAsync")
		userId = Util.checkNumber(userId, 1, "GetCharacterAppearanceInfoAsync")
		Svc.latency(0.1)
		return {
			assets = {},
			bodyColors = {},
			playerAvatarType = "R15",
			scales = { height = 1, width = 1, head = 1, depth = 1, proportion = 0, bodyType = 0 },
			defaultShirtApplied = false,
			defaultPantsApplied = false,
			emotes = {},
		}
	end

	local function newDescription()
		local d = Inst.create("HumanoidDescription", { Name = "HumanoidDescription" })
		return d
	end
	local buildCharacter -- vorwärts

	function PS.GetHumanoidDescriptionFromUserIdAsync(self, userId)
		Inst.checkSelf(self, "GetHumanoidDescriptionFromUserIdAsync")
		Util.checkNumber(userId, 1, "GetHumanoidDescriptionFromUserIdAsync")
		Svc.latency(0.1)
		return newDescription()
	end
	PS.GetHumanoidDescriptionFromUserId = PS.GetHumanoidDescriptionFromUserIdAsync
	function PS.GetHumanoidDescriptionFromOutfitIdAsync(self, outfitId)
		Inst.checkSelf(self, "GetHumanoidDescriptionFromOutfitIdAsync")
		Util.checkNumber(outfitId, 1, "GetHumanoidDescriptionFromOutfitIdAsync")
		Svc.latency(0.1)
		return newDescription()
	end
	local function serverOnlyModel(self, fname)
		if svcCtx(self).isClient then
			raise(fname .. " can only be called by the backend server")
		end
	end
	function PS.CreateHumanoidModelFromUserIdAsync(self, userId)
		Inst.checkSelf(self, "CreateHumanoidModelFromUserIdAsync")
		Util.checkNumber(userId, 1, "CreateHumanoidModelFromUserIdAsync")
		serverOnlyModel(self, "Players:CreateHumanoidModelFromUserId()")
		Svc.latency(0.2)
		local u = P.users[userId]
		local model = buildCharacter(u and u.name or "Character", u and u.displayName or "")
		getmt(model).props.Archivable = true
		return model
	end
	PS.CreateHumanoidModelFromUserId = PS.CreateHumanoidModelFromUserIdAsync
	function PS.CreateHumanoidModelFromDescriptionAsync(self, desc, rigType)
		Inst.checkSelf(self, "CreateHumanoidModelFromDescriptionAsync")
		Svc.checkInstance(desc, 1, "CreateHumanoidModelFromDescriptionAsync", "HumanoidDescription")
		if Enum.coerce(rigType, "HumanoidRigType") == nil then
			Util.badArg(2, "CreateHumanoidModelFromDescriptionAsync", "Enum.HumanoidRigType", rigType)
		end
		serverOnlyModel(self, "Players:CreateHumanoidModelFromDescription()")
		Svc.latency(0.2)
		local model = buildCharacter("Character", "")
		getmt(model).props.Archivable = true
		return model
	end
	PS.CreateHumanoidModelFromDescription = PS.CreateHumanoidModelFromDescriptionAsync

	Inst.registerService("Players", {
		methods = PS,
		props = {
			LocalPlayer = {
				get = function(u, M)
					local game = M.parent
					local gM = game and getmt(game)
					return gM and gM.ext and gM.ext.localPlayer or nil
				end,
			},
			NumPlayers = {
				get = function(u, M)
					return #playerList(M)
				end,
			},
		},
	})

	-- PlayerAdded / PlayerRemoving über die Eltern-Wechsel der Player-Instanzen (Server UND Client)
	local function playerAncestry(u, M, old, new)
		if old and getmt(old).cls.isA.Players then
			if not (new and getmt(new).cls.isA.Players) then
				if not ext(M).removingFired then
					Inst.fire(old, "PlayerRemoving", u)
				end
			end
		end
		if new and getmt(new).cls.isA.Players then
			ext(M).removingFired = nil
			Inst.fire(new, "PlayerAdded", u)
		end
	end

	-- =================================================================================================
	--  Player
	-- =================================================================================================
	local function checkPlayerSelf(self, m)
		local M = Inst.checkSelf(self, m)
		return M
	end
	local function playerCtx(self)
		return Svc.ctxOf(self)
	end

	local PL = {}
	function PL.Kick(self, message)
		local M = checkPlayerSelf(self, "Kick")
		if message ~= nil then
			message = Util.checkString(message, 1, "Kick")
		end
		local ctx = playerCtx(self)
		if ctx.isClient then
			local game = Svc.ctxOfGame and ctx.game
			if game == nil or getmt(game).ext.localPlayer ~= self then
				raise("Cannot kick a non-local Player from a LocalScript")
			end
			-- Selbst-Kick: Server-Spieler entfernen
			local sp = P.serverPlayerOf and P.serverPlayerOf(self)
			if sp then
				Sched.queue(function()
					P.removePlayer(sp, message or "")
				end)
			end
			return
		end
		Sched.queue(function()
			P.removePlayer(self, message or "")
		end)
	end
	local function loadCharacterChecked(self, fname)
		checkPlayerSelf(self, fname)
		local ctx = playerCtx(self)
		if ctx.isClient then
			raise("LoadCharacter can only be called by the backend server")
		end
		local M = getmt(self)
		if M.parent == nil or not getmt(M.parent).cls.isA.Players then
			raise("LoadCharacter can only be called when Player is in the world")
		end
		P.loadCharacter(self)
	end
	function PL.LoadCharacter(self)
		loadCharacterChecked(self, "LoadCharacter")
	end
	function PL.LoadCharacterAsync(self)
		loadCharacterChecked(self, "LoadCharacterAsync")
		Svc.latency(0)
	end
	function PL.LoadCharacterWithHumanoidDescription(self, desc)
		Svc.checkInstance(desc, 1, "LoadCharacterWithHumanoidDescription", "HumanoidDescription")
		loadCharacterChecked(self, "LoadCharacterWithHumanoidDescription")
	end
	function PL.LoadCharacterWithHumanoidDescriptionAsync(self, desc)
		Svc.checkInstance(desc, 1, "LoadCharacterWithHumanoidDescriptionAsync", "HumanoidDescription")
		loadCharacterChecked(self, "LoadCharacterWithHumanoidDescriptionAsync")
		Svc.latency(0)
	end
	local function groupEntry(self, groupId, fname)
		local M = checkPlayerSelf(self, fname)
		groupId = Util.checkNumber(groupId, 1, fname)
		local inf = info(M)
		return inf.groups and inf.groups[groupId]
	end
	function PL.IsInGroup(self, groupId)
		local g = groupEntry(self, groupId, "IsInGroup")
		Svc.latency(0.05)
		return g ~= nil
	end
	PL.IsInGroupAsync = PL.IsInGroup
	function PL.GetRankInGroup(self, groupId)
		local g = groupEntry(self, groupId, "GetRankInGroup")
		Svc.latency(0.05)
		return g and (g.Rank or 1) or 0
	end
	PL.GetRankInGroupAsync = PL.GetRankInGroup
	function PL.GetRoleInGroup(self, groupId)
		local g = groupEntry(self, groupId, "GetRoleInGroup")
		Svc.latency(0.05)
		return g and (g.Role or "Member") or "Guest"
	end
	PL.GetRoleInGroupAsync = PL.GetRoleInGroup
	function PL.IsFriendsWith(self, userId)
		local M = checkPlayerSelf(self, "IsFriendsWith")
		userId = Util.checkNumber(userId, 1, "IsFriendsWith")
		Svc.latency(0.05)
		local inf = info(M)
		return inf.friends ~= nil and table.find(inf.friends, userId) ~= nil
	end
	PL.IsFriendsWithAsync = PL.IsFriendsWith
	function PL.IsBestFriendsWith(self, userId)
		checkPlayerSelf(self, "IsBestFriendsWith")
		Util.checkNumber(userId, 1, "IsBestFriendsWith")
		Svc.latency(0.05)
		return false
	end
	function PL.GetFriendsOnline(self, maxFriends)
		checkPlayerSelf(self, "GetFriendsOnline")
		if svcCtx(self).isServer then
			raise("GetFriendsOnline can only be called from a LocalScript")
		end
		Svc.latency(0.1)
		return {}
	end
	PL.GetFriendsOnlineAsync = PL.GetFriendsOnline
	function PL.GetJoinData(self)
		checkPlayerSelf(self, "GetJoinData")
		return { LaunchData = "", Members = {}, TeleportData = nil, SourceGameId = nil, SourcePlaceId = nil }
	end
	function PL.GetNetworkPing(self)
		checkPlayerSelf(self, "GetNetworkPing")
		return 0.05
	end
	function PL.DistanceFromCharacter(self, point)
		local M = checkPlayerSelf(self, "DistanceFromCharacter")
		local p = DT.checkV3(point, 1, "DistanceFromCharacter")
		local ch = M.props.Character
		local head = ch and Inst.findChild(ch, "Head")
		if head == nil then
			return 0
		end
		return (head.Position - mk.V3vec(p)).Magnitude
	end
	function PL.HasAppearanceLoaded(self)
		local M = checkPlayerSelf(self, "HasAppearanceLoaded")
		return ext(M).appearanceLoaded == true
	end
	function PL.RequestStreamAroundAsync(self, position, timeout)
		checkPlayerSelf(self, "RequestStreamAroundAsync")
		local p = mk.V3vec(DT.checkV3(position, 1, "RequestStreamAroundAsync"))
		if timeout ~= nil then
			Util.checkNumber(timeout, 2, "RequestStreamAroundAsync")
		end
		local ctx = playerCtx(self)
		local sp = ctx.isClient and (Svc.Net and Svc.Net.serverInstanceOf(self)) or self
		if sp and Svc.Net and Svc.Net.requestStreamAround then
			Svc.Net.requestStreamAround(sp, p)
		end
		Svc.latency(0.1)
	end
	function PL.ClearCharacterAppearance(self)
		checkPlayerSelf(self, "ClearCharacterAppearance")
	end
	function PL.IsVerified(self)
		checkPlayerSelf(self, "IsVerified")
		return false
	end
	function PL.AddReplicationFocus(self, part)
		checkPlayerSelf(self, "AddReplicationFocus")
	end
	function PL.RemoveReplicationFocus(self, part)
		checkPlayerSelf(self, "RemoveReplicationFocus")
	end
	function PL.Move(self, direction, relative)
		local M = checkPlayerSelf(self, "Move")
		DT.checkV3(direction, 1, "Move")
		local ch = M.props.Character
		local hum = ch and Inst.findChild(ch, "Humanoid")
		if hum then
			Inst.rawSet(hum, "MoveDirection", direction)
		end
	end
	function PL.GetFriendsInServerAsync(self)
		checkPlayerSelf(self, "GetFriendsInServerAsync")
		Svc.latency(0.05)
		return {}
	end
	function PL.GetMouse(self)
		local M = checkPlayerSelf(self, "GetMouse")
		local ctx = playerCtx(self)
		local e = ext(M)
		if e.mouse == nil then
			e.mouse = Inst.create("PlayerMouse", { Name = "Instance" })
			getmt(e.mouse).ext = { player = self, ctx = ctx }
		end
		return e.mouse
	end

	local function characterChanged(u, M, prop)
		if prop ~= "Character" then
			return
		end
		local e = ext(M)
		local new = M.props.Character
		local old = e.lastCharacter
		if old == new then
			return
		end
		e.lastCharacter = new
		if old ~= nil and not e.removingSent then
			Inst.fire(u, "CharacterRemoving", old)
		end
		e.removingSent = nil
		if new ~= nil then
			Inst.fire(u, "CharacterAdded", new)
		end
	end

	Inst.define("Player", {
		methods = PL,
		onChanged = characterChanged,
		onAncestry = playerAncestry,
	})

	-- =================================================================================================
	--  Figur (R15)
	-- =================================================================================================
	local RIG = {
		-- name, size, offset relativ zum HumanoidRootPart, Eltern-Teil (Motor6D), Gelenkname
		{ "LowerTorso", { 2, 0.4, 1 }, { 0, -0.8, 0 }, "HumanoidRootPart", "Root" },
		{ "UpperTorso", { 2, 1.6, 1 }, { 0, 0.2, 0 }, "LowerTorso", "Waist" },
		{ "Head", { 1.2, 1.2, 1.2 }, { 0, 1.6, 0 }, "UpperTorso", "Neck" },
		{ "LeftUpperArm", { 1, 1.2, 1 }, { -1.5, 0.4, 0 }, "UpperTorso", "LeftShoulder" },
		{ "LeftLowerArm", { 1, 1, 1 }, { -1.5, -0.7, 0 }, "LeftUpperArm", "LeftElbow" },
		{ "LeftHand", { 1, 0.3, 1 }, { -1.5, -1.35, 0 }, "LeftLowerArm", "LeftWrist" },
		{ "RightUpperArm", { 1, 1.2, 1 }, { 1.5, 0.4, 0 }, "UpperTorso", "RightShoulder" },
		{ "RightLowerArm", { 1, 1, 1 }, { 1.5, -0.7, 0 }, "RightUpperArm", "RightElbow" },
		{ "RightHand", { 1, 0.3, 1 }, { 1.5, -1.35, 0 }, "RightLowerArm", "RightWrist" },
		{ "LeftUpperLeg", { 1, 1.2, 1 }, { -0.5, -1.4, 0 }, "LowerTorso", "LeftHip" },
		{ "LeftLowerLeg", { 1, 0.8, 1 }, { -0.5, -2.4, 0 }, "LeftUpperLeg", "LeftKnee" },
		{ "LeftFoot", { 1, 0.2, 1 }, { -0.5, -2.9, 0 }, "LeftLowerLeg", "LeftAnkle" },
		{ "RightUpperLeg", { 1, 1.2, 1 }, { 0.5, -1.4, 0 }, "LowerTorso", "RightHip" },
		{ "RightLowerLeg", { 1, 0.8, 1 }, { 0.5, -2.4, 0 }, "RightUpperLeg", "RightKnee" },
		{ "RightFoot", { 1, 0.2, 1 }, { 0.5, -2.9, 0 }, "RightLowerLeg", "RightAnkle" },
	}
	P.rigParts = RIG

	function buildCharacter(name, displayName, rootCF)
		rootCF = rootCF or CF.new(0, 50, 0)
		local model = Inst.create("Model", { Name = name })
		getmt(model).props.Archivable = false
		local parts = {}
		local hrp = Inst.create("Part", {
			Name = "HumanoidRootPart",
			Size = mk.V3(2, 2, 1),
			Transparency = 1,
			CanCollide = false,
			RootPriority = 127,
		})
		Inst.Parts.storeCF(hrp, rootCF)
		Inst.setParent(hrp, model)
		parts.HumanoidRootPart = hrp
		local skin = mk.C3(234 / 255, 184 / 255, 146 / 255)
		for _, r in RIG do
			local p = Inst.create(r[1] == "Head" and "Part" or "Part", {
				Name = r[1],
				Size = mk.V3(r[2][1], r[2][2], r[2][3]),
				Color = skin,
			})
			Inst.Parts.storeCF(p, rootCF * CF.new(r[3][1], r[3][2], r[3][3]))
			Inst.setParent(p, model)
			parts[r[1]] = p
		end
		for _, r in RIG do
			local p0, p1 = parts[r[4]], parts[r[1]]
			local j = Inst.create("Motor6D", { Name = r[5] })
			local rel = p0.CFrame:Inverse() * p1.CFrame
			Inst.setProp(j, "C0", rel)
			Inst.setProp(j, "C1", CF.identity)
			Inst.setProp(j, "Part0", p0)
			Inst.setProp(j, "Part1", p1)
			Inst.setParent(j, p1)
		end
		local face = Inst.create("Decal", { Name = "face", Texture = "rbxasset://textures/face.png" })
		Inst.setParent(face, parts.Head)
		local hum = Inst.create("Humanoid", { Name = "Humanoid" })
		Inst.setProp(hum, "RigType", Enum.item("HumanoidRigType", "R15"))
		Inst.setProp(hum, "HipHeight", 2)
		Inst.setProp(hum, "DisplayName", displayName or name)
		Inst.setParent(hum, model)
		local animator = Inst.create("Animator", { Name = "Animator" })
		Inst.setParent(animator, hum)
		local desc = newDescription()
		Inst.setParent(desc, hum)
		local bc = Inst.create("BodyColors", { Name = "Body Colors" })
		Inst.setParent(bc, model)
		Inst.setProp(model, "PrimaryPart", hrp)
		return model
	end
	P.buildCharacter = buildCharacter

	local function spawnCFrame(game, player)
		local ws = workspaceOf(game)
		local rl = getmt(player).props.RespawnLocation
		local spawns = {}
		if rl and not getmt(rl).destroyed and Inst.isAncestor(ws, rl) then
			spawns = { rl }
		else
			for _, d in Inst.descendants(ws) do
				local DM = getmt(d)
				if DM.cls.isA.SpawnLocation and DM.props.Enabled ~= false then
					spawns[#spawns + 1] = d
				end
			end
		end
		if #spawns == 0 then
			return CF.new(0, 50, 0)
		end
		local s = spawns[1]
		if #spawns > 1 then
			s = spawns[R.rng:NextInteger(1, #spawns)]
		end
		local scf = s.CFrame
		local size = s.Size
		local _, ry = scf:ToOrientation()
		return CF.new(scf.Position + mk.V3(0, size.Y / 2 + 3, 0)) * CF.Angles(0, ry, 0)
	end

	function P.loadCharacter(player)
		local M = getmt(player)
		local game = Inst.dataModelOf(player)
		if game == nil then
			return nil
		end
		local e = ext(M)
		local old = M.props.Character
		if old ~= nil then
			e.removingSent = true
			Inst.fire(player, "CharacterRemoving", old)
			Sched.flush()
			e.lastCharacter = nil
			Inst.storeProp(player, "Character", nil)
			if not getmt(old).destroyed then
				Inst.destroy(old)
			end
		end
		e.appearanceLoaded = false
		local inf = info(M)
		local model = buildCharacter(M.name, inf.displayName or M.name, spawnCFrame(game, player))
		local hum = Inst.findChild(model, "Humanoid")
		local sp = Inst.findServiceRaw(game, "StarterPlayer")
		if sp then
			for _, pair in {
				{ "CharacterWalkSpeed", "WalkSpeed" },
				{ "CharacterJumpPower", "JumpPower" },
				{ "CharacterJumpHeight", "JumpHeight" },
				{ "CharacterUseJumpPower", "UseJumpPower" },
				{ "CharacterMaxSlopeAngle", "MaxSlopeAngle" },
			} do
				local ok, v = pcall(Inst.getProp, sp, pair[1])
				if ok and v ~= nil then
					pcall(Inst.setProp, hum, pair[2], v)
				end
			end
			-- StarterCharacterScripts kopieren
			local scs = Inst.findChild(sp, "StarterCharacterScripts")
			if scs then
				for _, c in Inst.children(scs) do
					local cc = Inst.clone(c)
					if cc then
						Inst.setParent(cc, model)
					end
				end
			end
		end
		e.lastCharacter = nil
		Inst.storeProp(player, "Character", model)
		Inst.setParent(model, workspaceOf(game))
		-- StarterGui -> PlayerGui (erste Figur bzw. ResetOnSpawn)
		if P.copyStarterGui then
			P.copyStarterGui(player, e.spawnCount == nil)
		end
		e.spawnCount = (e.spawnCount or 0) + 1
		local myCount = e.spawnCount
		Sched.addTimer(Sched.now + 0.5, function()
			if e.spawnCount == myCount and M.props.Character == model and not getmt(model).destroyed then
				e.appearanceLoaded = true
				Inst.fire(player, "CharacterAppearanceLoaded", model)
			end
		end)
		return model
	end

	function P.removePlayer(player, reason)
		local M = getmt(player)
		if M.destroyed or ext(M).removed then
			return
		end
		local e = ext(M)
		e.removed = true
		local parent = M.parent
		if parent and getmt(parent).cls.isA.Players then
			e.removingFired = true
			Inst.fire(parent, "PlayerRemoving", player)
		end
		local ch = M.props.Character
		if ch then
			e.removingSent = true
			Inst.fire(player, "CharacterRemoving", ch)
		end
		Sched.flush()
		if P.onRemove then
			P.onRemove(player, reason)
		end
		if ch and not getmt(ch).destroyed then
			Inst.destroy(ch)
		end
		if not M.destroyed then
			Inst.destroy(player)
		end
	end

	function P.newPlayer(game, inf)
		local players = playersOf(game)
		local p = Inst.create("Player", { Name = inf.name })
		local M = getmt(p)
		ext(M).info = inf
		M.props.UserId = inf.userId
		M.props.DisplayName = inf.displayName or inf.name
		M.props.AccountAge = inf.accountAge or 365
		M.props.LocaleId = inf.locale or "en-us"
		M.props.MembershipType = Enum.item("MembershipType", inf.membership or "None")
		M.props.CharacterAppearanceId = inf.userId
		local sp = Inst.findServiceRaw(game, "StarterPlayer")
		if sp then
			for _, k in { "CameraMaxZoomDistance", "CameraMinZoomDistance", "CameraMode", "DevEnableMouseLock" } do
				local spName = k == "DevEnableMouseLock" and "EnableMouseLockOption" or k
				local ok, v = pcall(Inst.getProp, sp, spName)
				if ok and v ~= nil then
					pcall(Inst.setProp, p, k, v)
				end
			end
		end
		P.users[inf.userId] = P.users[inf.userId] or { name = inf.name, displayName = inf.displayName or inf.name }
		P.users[inf.userId].friends = inf.friends
		local backpack = Inst.create("Backpack", { Name = "Backpack" })
		Inst.setParent(backpack, p)
		local pg = Inst.create("PlayerGui", { Name = "PlayerGui" })
		Inst.setParent(pg, p)
		local gear = Inst.create("StarterGear", { Name = "StarterGear" })
		Inst.setParent(gear, p)
		Inst.setParent(p, players)
		return p
	end

	-- =================================================================================================
	--  Humanoid
	-- =================================================================================================
	local stateItem = function(name)
		return Enum.item("HumanoidStateType", name)
	end
	local movers = setmetatable({}, { __mode = "k" })

	local function humanoidModel(M)
		local p = M.parent
		if p and getmt(p).cls.isA.Model then
			return p
		end
		return nil
	end
	local function rootPart(M)
		local model = humanoidModel(M)
		if model == nil then
			return nil
		end
		local hrp = Inst.findChild(model, "HumanoidRootPart")
		if hrp and getmt(hrp).cls.isPart then
			return hrp
		end
		local tor = Inst.findChild(model, "Torso")
		if tor and getmt(tor).cls.isPart then
			return tor
		end
		return nil
	end

	local function setState(u, M, newState)
		local e = ext(M)
		local old = e.state or stateItem("Running")
		if old == newState then
			return
		end
		e.state = newState
		Inst.fire(u, "StateChanged", old, newState)
		local n = newState.Name
		if n == "Jumping" then
			Inst.fire(u, "Jumping", true)
		elseif n == "Freefall" then
			Inst.fire(u, "FreeFalling", true)
		elseif n == "Running" then
			Inst.fire(u, "Running", 0)
		end
	end

	local function die(u, M)
		local e = ext(M)
		if e.dead then
			return
		end
		e.dead = true
		setState(u, M, stateItem("Dead"))
		Inst.fire(u, "Died")
		local model = humanoidModel(M)
		local ctx = Svc.ctxOf(u)
		if model and ctx.isServer then
			local bj = M.props.BreakJointsOnDeath
			if bj == nil or bj == true then
				for _, d in Inst.descendants(model) do
					local DM = getmt(d)
					if DM.cls.isA.JointInstance and not DM.destroyed then
						Inst.destroy(d)
					end
				end
			end
			-- Respawn (Server, CharacterAutoLoads)
			local game = Inst.dataModelOf(u)
			local players = game and playersOf(game)
			if players then
				for _, p in playerList(getmt(players)) do
					if getmt(p).props.Character == model then
						local auto = Inst.getProp(players, "CharacterAutoLoads")
						local delay = Inst.getProp(players, "RespawnTime")
						if auto then
							Sched.addTimer(Sched.now + delay, function()
								local PM = getmt(p)
								if not PM.destroyed and PM.props.Character == model and PM.parent then
									P.loadCharacter(p)
								end
							end)
						end
					end
				end
			end
		end
	end

	local H = {}
	local function checkHum(self, m)
		return Inst.checkSelf(self, m)
	end
	function H.ChangeState(self, state)
		local M = checkHum(self, "ChangeState")
		local st = Enum.coerce(state, "HumanoidStateType")
		if st == nil then
			Util.badArg(1, "ChangeState", "Enum.HumanoidStateType", state)
		end
		local disabled = ext(M).disabledStates
		if disabled and disabled[st] then
			return
		end
		if st.Name == "Dead" then
			Inst.setProp(self, "Health", 0)
			return
		end
		setState(self, M, st)
	end
	function H.GetState(self)
		local M = checkHum(self, "GetState")
		return ext(M).state or stateItem("Running")
	end
	function H.SetStateEnabled(self, state, enabled)
		local M = checkHum(self, "SetStateEnabled")
		local st = Enum.coerce(state, "HumanoidStateType")
		if st == nil then
			Util.badArg(1, "SetStateEnabled", "Enum.HumanoidStateType", state)
		end
		enabled = Util.checkBool(enabled, 2, "SetStateEnabled")
		local e = ext(M)
		e.disabledStates = e.disabledStates or {}
		local was = not e.disabledStates[st]
		e.disabledStates[st] = (not enabled) or nil
		if was ~= enabled then
			Inst.fire(self, "StateEnabledChanged", st, enabled)
		end
	end
	function H.GetStateEnabled(self, state)
		local M = checkHum(self, "GetStateEnabled")
		local st = Enum.coerce(state, "HumanoidStateType")
		if st == nil then
			Util.badArg(1, "GetStateEnabled", "Enum.HumanoidStateType", state)
		end
		local d = ext(M).disabledStates
		return not (d and d[st])
	end
	function H.TakeDamage(self, amount)
		local M = checkHum(self, "TakeDamage")
		amount = Util.checkNumber(amount, 1, "TakeDamage")
		local model = humanoidModel(M)
		if model then
			for _, c in Inst.children(model) do
				if getmt(c).cls.isA.ForceField then
					return
				end
			end
		end
		Inst.setProp(self, "Health", self.Health - amount)
	end
	function H.MoveTo(self, location, part)
		local M = checkHum(self, "MoveTo")
		local loc = DT.checkV3(location, 1, "MoveTo")
		if part ~= nil then
			Svc.checkInstance(part, 2, "MoveTo", "BasePart")
		end
		Inst.rawSet(self, "WalkToPoint", mk.V3vec(loc))
		Inst.rawSet(self, "WalkToPart", part)
		local e = ext(M)
		e.move = { target = mk.V3vec(loc), part = part, start = Sched.now, seq = (e.move and e.move.seq or 0) + 1 }
		movers[self] = true
	end
	function H.Move(self, direction, relative)
		local M = checkHum(self, "Move")
		DT.checkV3(direction, 1, "Move")
		Inst.rawSet(self, "MoveDirection", direction)
	end
	function H.GetMoveVelocity(self)
		checkHum(self, "GetMoveVelocity")
		return DT.Vector3.zero
	end
	function H.GetAppliedDescription(self)
		local M = checkHum(self, "GetAppliedDescription")
		for _, c in Inst.children(self) do
			if getmt(c).cls.isA.HumanoidDescription then
				return Inst.clone(c) or newDescription()
			end
		end
		return newDescription()
	end
	local function applyDesc(self, desc, fname)
		local M = checkHum(self, fname)
		Svc.checkInstance(desc, 1, fname, "HumanoidDescription")
		if Svc.ctxOf(self).isClient then
			raise("Humanoid::ApplyDescription() can only be called by the backend server")
		end
		if humanoidModel(M) == nil or not Inst.Parts.inWorkspace(self) then
			raise("Humanoid::ApplyDescription() Humanoid must be parented to the Workspace")
		end
		Svc.latency(0.1)
		for _, c in table.clone(Inst.children(self)) do
			if getmt(c).cls.isA.HumanoidDescription then
				Inst.destroy(c)
			end
		end
		local copy = Inst.clone(desc)
		if copy then
			Inst.setParent(copy, self)
		end
		Inst.fire(self, "ApplyDescriptionFinished", desc)
	end
	function H.ApplyDescription(self, desc)
		applyDesc(self, desc, "ApplyDescription")
	end
	function H.ApplyDescriptionAsync(self, desc)
		applyDesc(self, desc, "ApplyDescriptionAsync")
	end
	function H.ApplyDescriptionReset(self, desc)
		applyDesc(self, desc, "ApplyDescriptionReset")
	end
	function H.ApplyDescriptionResetAsync(self, desc)
		applyDesc(self, desc, "ApplyDescriptionResetAsync")
	end
	function H.AddAccessory(self, acc)
		local M = checkHum(self, "AddAccessory")
		Svc.checkInstance(acc, 1, "AddAccessory", "Accoutrement")
		local model = humanoidModel(M)
		if model then
			Inst.setParent(acc, model)
		end
	end
	function H.GetAccessories(self)
		local M = checkHum(self, "GetAccessories")
		local out = {}
		local model = humanoidModel(M)
		if model then
			for _, c in Inst.children(model) do
				if getmt(c).cls.isA.Accoutrement then
					out[#out + 1] = c
				end
			end
		end
		return out
	end
	function H.RemoveAccessories(self)
		local M = checkHum(self, "RemoveAccessories")
		for _, a in H.GetAccessories(self) do
			Inst.destroy(a)
		end
	end
	function H.EquipTool(self, tool)
		local M = checkHum(self, "EquipTool")
		Svc.checkInstance(tool, 1, "EquipTool", "Tool")
		local model = humanoidModel(M)
		if model then
			Inst.setParent(tool, model)
			Inst.fire(tool, "Equipped", nil)
		end
	end
	function H.UnequipTools(self)
		local M = checkHum(self, "UnequipTools")
		local model = humanoidModel(M)
		if model == nil then
			return
		end
		local game = Inst.dataModelOf(self)
		local players = game and playersOf(game)
		local owner
		if players then
			for _, p in playerList(getmt(players)) do
				if getmt(p).props.Character == model then
					owner = p
				end
			end
		end
		for _, c in table.clone(Inst.children(model)) do
			if getmt(c).cls.isA.Tool then
				local bp = owner and Inst.findChild(owner, "Backpack")
				Inst.setParent(c, bp)
				Inst.fire(c, "Unequipped")
			end
		end
	end
	function H.GetLimb(self, part)
		checkHum(self, "GetLimb")
		Svc.checkInstance(part, 1, "GetLimb", "BasePart")
		return Enum.item("Limb", "Unknown")
	end
	function H.GetBodyPartR15(self, part)
		checkHum(self, "GetBodyPartR15")
		Svc.checkInstance(part, 1, "GetBodyPartR15", "BasePart")
		local ok, it = pcall(Enum.item, "BodyPartR15", part.Name)
		return ok and it or Enum.item("BodyPartR15", "Unknown")
	end
	function H.BuildRigFromAttachments(self)
		checkHum(self, "BuildRigFromAttachments")
	end
	function H.PlayEmote(self, name)
		checkHum(self, "PlayEmote")
		Util.checkString(name, 1, "PlayEmote")
		Svc.latency(0)
		return true
	end
	H.PlayEmoteAsync = H.PlayEmote
	function H.GetPlayingAnimationTracks(self)
		local M = checkHum(self, "GetPlayingAnimationTracks")
		local animator = Inst.findChild(self, "Animator")
		return animator and P.playingTracks(animator) or {}
	end
	function H.LoadAnimation(self, anim)
		local M = checkHum(self, "LoadAnimation")
		local animator = Inst.findChild(self, "Animator")
		if animator == nil then
			animator = Inst.create("Animator", { Name = "Animator" })
			Inst.setParent(animator, self)
		end
		return P.loadAnimation(animator, anim, "LoadAnimation")
	end

	local function humChanged(u, M, prop)
		if prop == "Health" then
			local h = M.props.Health
			Inst.fire(u, "HealthChanged", h)
			if h ~= nil and h <= 0 then
				die(u, M)
			end
		elseif prop == "MaxHealth" then
			local h = M.props.Health or 100
			local mx = M.props.MaxHealth or 100
			if h > mx then
				Inst.storeProp(u, "Health", Util.f32(mx))
			end
		elseif prop == "Sit" then
			if M.props.Sit ~= true then
				local seat = M.props.SeatPart
				if seat ~= nil then
					P.unseat(u, seat)
				end
			end
		elseif prop == "Jump" then
			if M.props.Jump == true then
				local seat = M.props.SeatPart
				if seat ~= nil then
					P.unseat(u, seat)
				end
				setState(u, M, stateItem("Jumping"))
				M.props.Jump = false
				Sched.addTimer(Sched.now + 0.3, function()
					if not ext(M).dead and ext(M).state == stateItem("Jumping") then
						setState(u, M, stateItem("Running"))
					end
				end)
			end
		end
	end

	Inst.define("Humanoid", {
		methods = H,
		init = function(u, M)
			M.props.Health = 100
		end,
		props = {
			Health = {
				set = function(u, M, v)
					local mx = M.props.MaxHealth or 100
					if v ~= v then
						v = 0
					end
					v = Util.f32(math.clamp(v, 0, math.max(mx, 0)))
					Inst.storeProp(u, "Health", v)
				end,
			},
			RootPart = {
				get = function(u, M)
					return rootPart(M)
				end,
			},
			FloorMaterial = {
				get = function(u, M)
					return ext(M).seated and Enum.item("Material", "Air") or Enum.item("Material", "Plastic")
				end,
			},
		},
		onChanged = humChanged,
	})

	-- MoveTo-Simulation (Physik-Phase)
	Sched.addHook("physics", function(dt)
		for hum in movers do
			local M = getmt(hum)
			local e = M.ext
			local mv = e and e.move
			if M.destroyed or mv == nil or e.dead then
				movers[hum] = nil
			else
				local root = rootPart(M)
				if root == nil then
					movers[hum] = nil
				else
					local target = mv.target
					if mv.part and not getmt(mv.part).destroyed then
						target = mv.part.Position
					end
					local pos = root.Position
					local flat = mk.V3(target.X - pos.X, 0, target.Z - pos.Z)
					local dist = flat.Magnitude
					local speed = M.props.WalkSpeed or 16
					local step = speed * dt
					local finished = false
					local reached = false
					if dist <= math.max(step, 0.05) then
						Inst.Parts.setCFrame(root, root.CFrame.Rotation + mk.V3(target.X, pos.Y, target.Z), true)
						finished, reached = true, true
					else
						local dir = flat.Unit
						local np = pos + dir * step
						Inst.Parts.setCFrame(root, CF.lookAt(np, np + dir), true)
						if Sched.now - mv.start >= 8 then
							finished = true
						end
					end
					if finished then
						e.move = nil
						movers[hum] = nil
						Inst.fire(hum, "MoveToFinished", reached)
					end
				end
			end
		end
	end, "Humanoid.MoveTo")

	-- =================================================================================================
	--  Sitze
	-- =================================================================================================
	function P.seat(seat, hum)
		local SM, HM = getmt(seat), getmt(hum)
		local old = SM.props.Occupant
		if old == hum then
			return
		end
		if old ~= nil then
			P.unseat(old, seat)
		end
		local prevSeat = HM.props.SeatPart
		if prevSeat ~= nil then
			P.unseat(hum, prevSeat)
		end
		Inst.storeProp(seat, "Occupant", hum)
		Inst.storeProp(hum, "SeatPart", seat)
		ext(HM).seated = true
		HM.props.Sit = true
		Inst.changed(hum, HM, "Sit")
		local root = rootPart(HM)
		if root then
			local w = Inst.create("Weld", { Name = "SeatWeld" })
			Inst.setProp(w, "C0", CF.new(0, 0.5 + (seat.Size.Y / 2), 0))
			Inst.setProp(w, "C1", CF.new(0, -1.5, 0))
			Inst.setProp(w, "Part0", seat)
			Inst.setProp(w, "Part1", root)
			Inst.setParent(w, seat)
		end
		setState(hum, HM, stateItem("Seated"))
		Inst.fire(hum, "Seated", true, seat)
	end
	function P.unseat(hum, seat)
		local SM, HM = getmt(seat), getmt(hum)
		if SM.props.Occupant == hum then
			Inst.storeProp(seat, "Occupant", nil)
		end
		local w = Inst.findChild(seat, "SeatWeld")
		if w then
			Inst.destroy(w)
		end
		if HM.props.SeatPart == seat then
			Inst.storeProp(hum, "SeatPart", nil)
			ext(HM).seated = false
			if HM.props.Sit == true then
				HM.props.Sit = false
				Inst.changed(hum, HM, "Sit")
			end
			if not ext(HM).dead then
				setState(hum, HM, stateItem("Running"))
			end
			Inst.fire(hum, "Seated", false, nil)
		end
	end
	local function seatSit(self, hum)
		local M = Inst.checkSelf(self, "Sit")
		Svc.checkInstance(hum, 1, "Sit", "Humanoid")
		local SM = getmt(self)
		if SM.props.Disabled == true then
			return
		end
		P.seat(self, hum)
	end
	Inst.define("Seat", { methods = { Sit = seatSit } })
	Inst.define("VehicleSeat", { methods = { Sit = seatSit } })

	-- =================================================================================================
	--  Animator / AnimationTrack
	-- =================================================================================================
	function P.playingTracks(animator)
		local out = {}
		local e = getmt(animator).ext
		for _, t in (e and e.tracks) or {} do
			if getmt(t).ext.playing then
				out[#out + 1] = t
			end
		end
		return out
	end
	function P.loadAnimation(animator, anim, fname)
		local AM = getmt(animator)
		local M = Inst.meta(anim)
		if M == nil or not M.cls.isA.Animation then
			Util.badArg(1, fname, "Animation", anim)
		end
		local track = Inst.create("AnimationTrack", { Name = M.name })
		local TM = getmt(track)
		TM.ext = { animation = anim, playing = false, speed = 1, weight = 1, markers = {} }
		TM.props.Animation = anim
		TM.props.Length = 1
		TM.props.Looped = false
		local e = ext(AM)
		e.tracks = e.tracks or {}
		e.tracks[#e.tracks + 1] = track
		return track
	end
	local tracksPlaying = setmetatable({}, { __mode = "k" })
	local AT = {}
	function AT.Play(self, fadeTime, weight, speed)
		local M = Inst.checkSelf(self, "Play")
		local e = M.ext
		e.speed = speed or e.speed or 1
		e.weight = weight or 1
		if not e.playing then
			e.playing = true
			e.t = 0
			Inst.storeProp(self, "IsPlaying", true)
			tracksPlaying[self] = true
		end
	end
	function AT.Stop(self, fadeTime)
		local M = Inst.checkSelf(self, "Stop")
		local e = M.ext
		if e.playing then
			e.playing = false
			Inst.storeProp(self, "IsPlaying", false)
			tracksPlaying[self] = nil
			Inst.fire(self, "Stopped")
			Sched.addTimer(Sched.now + (fadeTime or 0.1), function()
				Inst.fire(self, "Ended")
			end)
		end
	end
	function AT.AdjustSpeed(self, speed)
		local M = Inst.checkSelf(self, "AdjustSpeed")
		M.ext.speed = Util.optNumber(speed, 1, "AdjustSpeed", 1)
		Inst.storeProp(self, "Speed", M.ext.speed)
	end
	function AT.AdjustWeight(self, weight, fade)
		local M = Inst.checkSelf(self, "AdjustWeight")
		M.ext.weight = Util.optNumber(weight, 1, "AdjustWeight", 1)
	end
	function AT.GetMarkerReachedSignal(self, name)
		local M = Inst.checkSelf(self, "GetMarkerReachedSignal")
		name = Util.checkString(name, 1, "GetMarkerReachedSignal")
		local e = M.ext
		e.markers[name] = e.markers[name] or R.Signal.new("MarkerReached:" .. name, self)
		return e.markers[name]
	end
	function AT.GetTimeOfKeyframe(self, name)
		Inst.checkSelf(self, "GetTimeOfKeyframe")
		Util.checkString(name, 1, "GetTimeOfKeyframe")
		raise("Could not find a keyframe by that name!")
	end
	Inst.define("AnimationTrack", {
		methods = AT,
		props = {
			TimePosition = {
				get = function(u, M)
					return M.ext and M.ext.t or 0
				end,
				set = function(u, M, v)
					M.ext = M.ext or {}
					M.ext.t = v
				end,
			},
		},
	})
	Sched.addHook("preAnimation", function(dt)
		for t in tracksPlaying do
			local M = getmt(t)
			if M.destroyed then
				tracksPlaying[t] = nil
			else
				local e = M.ext
				e.t += dt * (e.speed or 1)
				local len = M.props.Length or 1
				if e.t >= len then
					if M.props.Looped then
						e.t -= len
						Inst.fire(t, "DidLoop")
					else
						e.t = len
						AT.Stop(t, 0)
					end
				end
			end
		end
	end, "AnimationTrack")
	Inst.define("Animator", {
		methods = {
			LoadAnimation = function(self, anim)
				Inst.checkSelf(self, "LoadAnimation")
				return P.loadAnimation(self, anim, "LoadAnimation")
			end,
			GetPlayingAnimationTracks = function(self)
				Inst.checkSelf(self, "GetPlayingAnimationTracks")
				return P.playingTracks(self)
			end,
			ApplyJointVelocities = function(self)
				Inst.checkSelf(self, "ApplyJointVelocities")
			end,
		},
	})

	-- =================================================================================================
	--  PlayerMouse (Client)
	-- =================================================================================================
	local function mouseRay(M)
		local e = M.ext or {}
		local ctx = e.ctx
		local game = ctx and ctx.game
		local ws = game and workspaceOf(game)
		local cam = ws and ws.CurrentCamera
		if cam == nil then
			return CF.identity, mk.V3(0, 0, -1)
		end
		local vp = R.config.viewport or { 1280, 720 }
		local ray = cam:ViewportPointToRay(vp[1] / 2, vp[2] / 2, 0)
		return cam.CFrame, ray.Direction
	end
	Inst.define("PlayerMouse", {
		props = {
			Hit = {
				get = function(u, M)
					local origin, dir = mouseRay(M)
					local p = origin.Position + dir * 1000
					if Svc.World and Svc.World.raycastFor then
						local hit = Svc.World.raycastFor(M.ext and M.ext.ctx, origin.Position, dir * 1000, M.props.TargetFilter)
						if hit then
							p = hit.Position
						end
					end
					return CF.new(p) * origin.Rotation
				end,
			},
			Target = {
				get = function(u, M)
					local origin, dir = mouseRay(M)
					if Svc.World and Svc.World.raycastFor then
						local hit = Svc.World.raycastFor(M.ext and M.ext.ctx, origin.Position, dir * 1000, M.props.TargetFilter)
						if hit then
							return hit.Instance
						end
					end
					return nil
				end,
			},
			Origin = {
				get = function(u, M)
					local origin = mouseRay(M)
					return origin
				end,
			},
			UnitRay = {
				get = function(u, M)
					local origin, dir = mouseRay(M)
					return DT.Ray.new(origin.Position, dir.Unit)
				end,
			},
			X = {
				get = function()
					return math.floor((R.config.viewport or { 1280 })[1] / 2)
				end,
			},
			Y = {
				get = function()
					return math.floor((R.config.viewport or { 1280, 720 })[2] / 2)
				end,
			},
			ViewSizeX = {
				get = function()
					return (R.config.viewport or { 1280 })[1]
				end,
			},
			ViewSizeY = {
				get = function()
					return (R.config.viewport or { 1280, 720 })[2]
				end,
			},
		},
	})
end
