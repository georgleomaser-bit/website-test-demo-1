--!nocheck
-- =====================================================================
--  Headless-Harness · TextService, TextChatService (+TextChannel/TextSource/TextChatCommand/TextChatMessage), Chat
--
--  TextService: FilterStringAsync (nur Server; TextFilterResult liefert den Text unverändert wie in Studio),
--  GetTextSize/GetTextBoundsAsync (Näherung 0,5 × Schriftgröße je Zeichen, Umbruch auf Breite), GetFamilyInfoAsync.
--  TextChatService (ChatVersion aus dem Projekt): Server legt TextChannels (RBXGeneral, RBXSystem) und
--  TextChatCommands (Standardbefehle) an, dazu ChatWindowConfiguration/ChatInputBarConfiguration/
--  BubbleChatConfiguration/ChannelTabsConfiguration; Spieler bekommen beim Beitritt TextSources (CanSend = true).
--  TextChannel:SendAsync (nur Client) -> SendingMessage, TextChatCommand.Triggered (Server- und Client-Befehle,
--  Befehl verschluckt die Nachricht), ShouldDeliverCallback (Server), OnIncomingMessage (Client, darf NICHT yielden),
--  MessageReceived, Player.Chatted (Server). DisplaySystemMessage (nur Client).
--  Harness: R.Svc.Text.chat(clientCtx, text, channelName?)
-- =====================================================================
return function(R, Svc)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local raise = Util.raise
	local typeof = Util.typeof
	local getmt = getmetatable
	local fmt = string.format
	local mk = DT.make

	local T = {}
	Svc.Text = T

	-- =================================================================================================
	--  TextService
	-- =================================================================================================
	local function textSize(text, size, width)
		local lines = 1
		local longest = 0
		for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
			local w = (utf8.len(line) or #line) * size * 0.5
			if width and width > 0 and w > width then
				lines += math.ceil(w / width) - 1
				w = width
			end
			longest = math.max(longest, w)
		end
		for _ in string.gmatch(text, "\n") do
			lines += 1
		end
		if #text == 0 then
			return mk.V2(0, size)
		end
		return mk.V2(math.ceil(longest), lines * size)
	end
	local TS = {}
	function TS.FilterStringAsync(self, text, fromUserId, context)
		Inst.checkSelf(self, "FilterStringAsync")
		text = Util.checkString(text, 1, "FilterStringAsync")
		fromUserId = Util.checkNumber(fromUserId, 2, "FilterStringAsync")
		if context ~= nil and Enum.coerce(context, "TextFilterContext") == nil then
			Util.badArg(3, "FilterStringAsync", "Enum.TextFilterContext", context)
		end
		if Svc.ctxOf(self).isClient then
			raise("FilterStringAsync can only be called from the server")
		end
		Svc.latency(0.1)
		local r = Inst.create("TextFilterResult", { Name = "TextFilterResult" })
		getmt(r).ext = { text = text, from = fromUserId }
		return r
	end
	function TS.GetTextSize(self, text, fontSize, font, frameSize)
		Inst.checkSelf(self, "GetTextSize")
		text = Util.checkString(text, 1, "GetTextSize")
		fontSize = Util.checkNumber(fontSize, 2, "GetTextSize")
		if Enum.coerce(font, "Font") == nil then
			Util.badArg(3, "GetTextSize", "Enum.Font", font)
		end
		local fs = DT.checkV2 and DT.checkV2(frameSize, 4, "GetTextSize") or frameSize
		return textSize(text, fontSize, fs and fs.X or nil)
	end
	function TS.GetTextBoundsAsync(self, params)
		Inst.checkSelf(self, "GetTextBoundsAsync")
		local PM = Inst.meta(params)
		if PM == nil or not PM.cls.isA.GetTextBoundsParams then
			raise("Unable to cast value to Object")
		end
		Svc.latency(0)
		local text = PM.props.Text or ""
		local size = PM.props.Size or 14
		local width = PM.props.Width or 0
		if PM.props.RichText then
			text = string.gsub(text, "<[^>]*>", "")
		end
		return textSize(text, size, width > 0 and width or nil)
	end
	function TS.GetFamilyInfoAsync(self, assetId)
		Inst.checkSelf(self, "GetFamilyInfoAsync")
		Svc.latency(0.05)
		return { Name = "Font", Faces = { { Name = "Regular", Weight = Enum.item("FontWeight", "Regular"), Style = Enum.item("FontStyle", "Normal"), AssetId = "" } } }
	end
	Inst.registerService("TextService", { methods = TS })

	local function filterResult(self, m)
		local M = Inst.checkSelf(self, m)
		Svc.latency(0.05)
		return M.ext and M.ext.text or ""
	end
	Inst.define("TextFilterResult", {
		methods = {
			GetNonChatStringForBroadcastAsync = function(self)
				return filterResult(self, "GetNonChatStringForBroadcastAsync")
			end,
			GetNonChatStringForUserAsync = function(self, userId)
				Util.checkNumber(userId, 1, "GetNonChatStringForUserAsync")
				return filterResult(self, "GetNonChatStringForUserAsync")
			end,
			GetChatForUserAsync = function(self, userId)
				Util.checkNumber(userId, 1, "GetChatForUserAsync")
				return filterResult(self, "GetChatForUserAsync")
			end,
		},
	})

	-- =================================================================================================
	--  TextChatService
	-- =================================================================================================
	local DEFAULT_COMMANDS = {
		{ "RBXClearCommand", "/clear", "/cls" },
		{ "RBXConsoleCommand", "/console", "" },
		{ "RBXEmoteCommand", "/emote", "/e" },
		{ "RBXHelpCommand", "/help", "/?" },
		{ "RBXMuteCommand", "/mute", "/m" },
		{ "RBXTeamCommand", "/team", "/t" },
		{ "RBXUnmuteCommand", "/unmute", "/um" },
		{ "RBXVersionCommand", "/version", "/v" },
		{ "RBXWhisperCommand", "/whisper", "/w" },
	}
	local function tcsCtx(svc)
		return Svc.ctxOf(svc)
	end
	Inst.registerService("TextChatService", {
		setup = function(svc, M, game)
			local ctx = Svc.ctxOfGame(game)
			if ctx and ctx.isClient then
				return -- kommt per Replikation vom Server
			end
			local function child(cls, name, parent)
				local c = Inst.create(cls, { Name = name })
				Inst.reparentRaw(c, parent)
				return c
			end
			Sched.queue(function()
				-- erst nach dem Laden der Projekt-Eigenschaften (CreateDefault…)
				if Inst.getProp(svc, "ChatVersion").Name ~= "TextChatService" then
					return
				end
				if Inst.findChild(svc, "ChatWindowConfiguration") == nil then
					child("ChatWindowConfiguration", "ChatWindowConfiguration", svc)
					child("ChatInputBarConfiguration", "ChatInputBarConfiguration", svc)
					child("BubbleChatConfiguration", "BubbleChatConfiguration", svc)
					child("ChannelTabsConfiguration", "ChannelTabsConfiguration", svc)
				end
				if Inst.getProp(svc, "CreateDefaultTextChannels") and Inst.findChild(svc, "TextChannels") == nil then
					local folder = child("Folder", "TextChannels", svc)
					child("TextChannel", "RBXGeneral", folder)
					child("TextChannel", "RBXSystem", folder)
				end
				if Inst.getProp(svc, "CreateDefaultCommands") and Inst.findChild(svc, "TextChatCommands") == nil then
					local folder = child("Folder", "TextChatCommands", svc)
					for _, c in DEFAULT_COMMANDS do
						local cmd = child("TextChatCommand", c[1], folder)
						Inst.setProp(cmd, "PrimaryAlias", c[2])
						Inst.setProp(cmd, "SecondaryAlias", c[3])
					end
				end
			end)
		end,
	})

	local function defaultChannels(game)
		local svc = Inst.findServiceRaw(game, "TextChatService")
		local folder = svc and Inst.findChild(svc, "TextChannels")
		if folder == nil then
			return {}
		end
		local out = {}
		for _, c in Inst.children(folder) do
			if getmt(c).cls.isA.TextChannel then
				out[#out + 1] = c
			end
		end
		return out
	end

	local function newSource(channel, userId)
		for _, c in Inst.children(channel) do
			local CM = getmt(c)
			if CM.cls.isA.TextSource and CM.props.UserId == userId then
				return c, false
			end
		end
		local src = Inst.create("TextSource", { Name = tostring(userId) })
		local SM = getmt(src)
		SM.props.UserId = userId
		SM.props.CanSend = true
		Inst.setParent(src, channel)
		return src, true
	end

	--- Server: Spieler den Standard-Kanälen hinzufügen (Game-Modul ruft das beim Beitritt)
	function T.addPlayer(game, player)
		local uid = getmt(player).props.UserId
		for _, ch in defaultChannels(game) do
			newSource(ch, uid)
		end
	end
	function T.removePlayer(game, player)
		local uid = getmt(player).props.UserId
		for _, ch in defaultChannels(game) do
			for _, c in table.clone(Inst.children(ch)) do
				local CM = getmt(c)
				if CM.cls.isA.TextSource and CM.props.UserId == uid then
					Inst.destroy(c)
				end
			end
		end
	end

	local msgSeq = 0
	local function newMessage(text, source, channel, status, metadata)
		msgSeq += 1
		local m = Inst.create("TextChatMessage", { Name = "TextChatMessage" })
		local M = getmt(m)
		M.props.Text = text
		M.props.TextSource = source
		M.props.TextChannel = channel
		M.props.MessageId = fmt("%08x-harness-%d", msgSeq, msgSeq)
		M.props.Metadata = metadata or ""
		M.props.Status = Enum.item("TextChatMessageStatus", status or "Success")
		M.props.Timestamp = DT.DateTime.fromUnixTimestampMillis(Sched.unixMillis())
		M.props.PrefixText = ""
		return m
	end

	-- OnIncomingMessage (Client) – darf nicht yielden; Rückgabe TextChatMessageProperties oder nil
	local function runIncoming(cbOwner, msg)
		local cb = Inst.callback(cbOwner, "OnIncomingMessage")
		if cb == nil then
			return
		end
		local ok, props = Svc.callNoYield(cb, "OnIncomingMessage", msg)
		if ok and props ~= nil then
			local PM = Inst.meta(props)
			if PM == nil or not PM.cls.isA.TextChatMessageProperties then
				Report.error({
					message = "OnIncomingMessage must return a TextChatMessageProperties or nil (got " .. typeof(props) .. ")",
					traceback = "",
					ctx = Sched.ctx(),
					kind = "OnIncomingMessage",
				})
				return
			end
			local MM = getmt(msg)
			if PM.props.PrefixText ~= nil then
				MM.props.PrefixText = PM.props.PrefixText
			end
			if PM.props.Text ~= nil and PM.props.Text ~= "" then
				MM.props.Text = PM.props.Text
			end
		end
	end

	local function deliverToClient(ctx, channelServer, srcServer, text, metadata, system)
		local game = ctx.game
		local svc = Inst.findServiceRaw(game, "TextChatService")
		local channel = Svc.Net and Svc.Net.clientInstanceOf(ctx, channelServer)
		if svc == nil or channel == nil then
			return
		end
		local src = srcServer and Svc.Net.clientInstanceOf(ctx, srcServer) or nil
		local msg = newMessage(text, src, channel, "Success", metadata)
		Sched.spawnHandler(function()
			runIncoming(svc, msg)
			runIncoming(channel, msg)
			Inst.fire(channel, "MessageReceived", msg)
			Inst.fire(svc, "MessageReceived", msg)
		end, ctx, "TextChat:deliver")
	end

	local function matchCommand(game, text)
		local svc = Inst.findServiceRaw(game, "TextChatService")
		if svc == nil then
			return {}
		end
		local first = string.match(text, "^(%S+)")
		if first == nil then
			return {}
		end
		first = string.lower(first)
		local out = {}
		for _, d in Inst.descendants(svc) do
			local DM = getmt(d)
			if DM.cls.isA.TextChatCommand and DM.props.Enabled ~= false then
				local a1 = string.lower(DM.props.PrimaryAlias or "")
				local a2 = string.lower(DM.props.SecondaryAlias or "")
				if (a1 ~= "" and a1 == first) or (a2 ~= "" and a2 == first) then
					out[#out + 1] = d
				end
			end
		end
		return out
	end

	--- Harness/SendAsync: Nachricht eines Clients senden
	function T.send(ctx, channel, text, metadata)
		local game = ctx.game
		local svcC = Inst.findServiceRaw(game, "TextChatService")
		local lp = getmt(game).ext.localPlayer
		local uid = lp and getmt(lp).props.UserId or 0
		local srcC
		for _, c in Inst.children(channel) do
			local CM = getmt(c)
			if CM.cls.isA.TextSource and CM.props.UserId == uid then
				srcC = c
			end
		end
		local msg = newMessage(text, srcC, channel, "Sending", metadata)
		if svcC then
			Inst.fire(svcC, "SendingMessage", msg)
		end
		if srcC == nil or getmt(srcC).props.CanSend == false then
			Inst.rawSet(msg, "Status", Enum.item("TextChatMessageStatus", "Sending"))
			return msg
		end
		-- Server-Seite (1 Schritt Latenz)
		local channelS = Svc.Net and Svc.Net.serverInstanceOf(channel)
		local srcS = Svc.Net and Svc.Net.serverInstanceOf(srcC)
		local server = Svc.games[1]
		-- Client-Befehle
		local sunk = false
		for _, cmd in matchCommand(game, text) do
			sunk = true
			Inst.fire(cmd, "Triggered", srcC, text)
		end
		Sched.addTimer(Sched.now + Sched.dt, function()
			if server == nil or channelS == nil then
				return
			end
			local sgame = server.game
			local splayer = Svc.Net.serverInstanceOf(lp)
			if splayer then
				Inst.fire(splayer, "Chatted", text, nil)
			end
			for _, cmd in matchCommand(sgame, text) do
				sunk = true
				Inst.fire(cmd, "Triggered", srcS, text)
			end
			if sunk then
				return
			end
			local should = Inst.callback(channelS, "ShouldDeliverCallback")
			for _, g in Svc.games do
				local c = g.ctx
				if c.isClient and not c.closed then
					local deliver = true
					if should then
						local tlp = getmt(g.game).ext.localPlayer
						local tsrc
						local tsp = tlp and Svc.Net.serverInstanceOf(tlp)
						if tsp then
							for _, s in Inst.children(channelS) do
								if getmt(s).cls.isA.TextSource and getmt(s).props.UserId == getmt(tsp).props.UserId then
									tsrc = s
								end
							end
						end
						local smsg = newMessage(text, srcS, channelS, "Success", metadata)
						local ok, r = Svc.callNoYield(should, "ShouldDeliverCallback", smsg, tsrc)
						deliver = ok and r ~= false
					end
					if deliver then
						Sched.addTimer(Sched.now + Sched.dt, function()
							if not c.closed then
								deliverToClient(c, channelS, srcS, text, metadata, false)
							end
						end)
					end
				end
			end
		end)
		return msg
	end

	function T.chat(ctx, text, channelName)
		local svc = Inst.findServiceRaw(ctx.game, "TextChatService")
		local folder = svc and Inst.findChild(svc, "TextChannels")
		local ch = folder and Inst.findChild(folder, channelName or "RBXGeneral")
		if ch == nil then
			return nil
		end
		return T.send(ctx, ch, text, nil)
	end

	local TC = {}
	function TC.SendAsync(self, message, metadata)
		Inst.checkSelf(self, "SendAsync")
		message = Util.checkString(message, 1, "SendAsync")
		if metadata ~= nil then
			metadata = Util.checkString(metadata, 2, "SendAsync")
		end
		local ctx = Svc.ctxOf(self)
		if not ctx.isClient then
			raise("SendAsync can only be called from the client")
		end
		Svc.latency(0)
		return T.send(ctx, self, message, metadata)
	end
	function TC.DisplaySystemMessage(self, text, metadata)
		Inst.checkSelf(self, "DisplaySystemMessage")
		text = Util.checkString(text, 1, "DisplaySystemMessage")
		local ctx = Svc.ctxOf(self)
		if not ctx.isClient then
			raise("DisplaySystemMessage can only be called from the client")
		end
		local svc = Inst.findServiceRaw(ctx.game, "TextChatService")
		local msg = newMessage(text, nil, self, "Success", metadata)
		if svc then
			runIncoming(svc, msg)
		end
		runIncoming(self, msg)
		Inst.fire(self, "MessageReceived", msg)
		if svc then
			Inst.fire(svc, "MessageReceived", msg)
		end
		return msg
	end
	function TC.AddUserAsync(self, userId)
		Inst.checkSelf(self, "AddUserAsync")
		userId = Util.checkNumber(userId, 1, "AddUserAsync")
		if Svc.ctxOf(self).isClient then
			raise("AddUserAsync can only be called from the server")
		end
		Svc.latency(0.05)
		return newSource(self, userId)
	end
	function TC.SetDirectChatRequester(self, player)
		Inst.checkSelf(self, "SetDirectChatRequester")
	end
	Inst.define("TextChannel", { methods = TC })

	-- =================================================================================================
	--  Chat (Legacy) – nur das Nötigste
	-- =================================================================================================
	Inst.registerService("Chat", {
		methods = {
			FilterStringForBroadcast = function(self, text, fromPlayer)
				Inst.checkSelf(self, "FilterStringForBroadcast")
				return Util.checkString(text, 1, "FilterStringForBroadcast")
			end,
			FilterStringAsync = function(self, text, from, to)
				Inst.checkSelf(self, "FilterStringAsync")
				Svc.latency(0.05)
				return Util.checkString(text, 1, "FilterStringAsync")
			end,
			CanUserChatAsync = function(self, userId)
				Inst.checkSelf(self, "CanUserChatAsync")
				Svc.latency(0.05)
				return true
			end,
			CanUsersChatAsync = function(self, a, b)
				Inst.checkSelf(self, "CanUsersChatAsync")
				Svc.latency(0.05)
				return true
			end,
			Chat = function(self, partOrCharacter, message, color)
				Inst.checkSelf(self, "Chat")
			end,
		},
	})
end
