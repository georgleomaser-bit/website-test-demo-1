-- =====================================================================
--  CLUTCH CLASH – Chat-Anzeige: freundliche Umschreibungen + Namens-Präfixe (Client/Modules/ChatClient)
--  Besitzer: WP8 (Fortschritt/Sozial). Vertrag: DESIGN.md B24 + C7.1.
--
--  TextChatService.OnIncomingMessage (nur Anzeige, nur auf diesem Gerät):
--    • Umschreibungen NUR für Nachrichten ANDERER, nur ganze Nachricht oder ganze Wörter
--      (Groß/Klein egal, Satzzeichen trennen): ez → „gg wp“, ggez → „GG ❤“, noob → „Freund“, p2w → „faires Loadout“,
--      trash → „gutes Spiel“ (Liste: Config.Progression.Chat.Rewrites, Logik: ProgressMath.RewriteChat).
--      Normale deutsche Wörter („schlecht“) werden nie angefasst; eigene Nachrichten bleiben unverändert.
--    • PrefixText: [Besitzer] gold, [VIP] gold, Level-Abzeichen (Farbe nach Level), Titel – aus den
--      Player-Attributen IsAdmin / Vip / Level / Title (gesetzt von WP7/WP9/WP8).
--  Öffentliche API: ChatClient.Init(ctx) · ChatClient.Start() · ChatClient.Rewrite(text): string?  (Debug/Tests)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ProgressMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressMath"))

local ChatClient = {}

local ctx: any = nil
local chatCfg: any = nil
local levelColors: { { Min: number, Color: Color3 } } = {}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(
		math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	)
end

-- Rich-Text-sicher (Titel/Namen kommen aus der Config, trotzdem escapen)
local function escape(text: string): string
	return (
		string.gsub(text, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

local function colored(text: string, color: string): string
	return ('<font color="%s">%s</font>'):format(color, escape(text))
end

local function levelColor(level: number): string
	local color = Color3.new(1, 1, 1)
	for _, entry in ipairs(levelColors) do
		if level >= entry.Min then
			color = entry.Color
		end
	end
	return hex(color)
end

local function titleText(id: string): (string?, Color3?)
	local cosmetics = ctx.Config.Cosmetics
	local def = cosmetics and cosmetics.Titles and cosmetics.Titles[id]
	if type(def) ~= "table" or type(def.Name) ~= "table" then
		return nil, nil
	end
	local color = if typeof(def.Color) == "Color3" then def.Color else nil
	return ctx.Lang.Pick(ctx.Lang_(), def.Name), color
end

-- [Besitzer] [VIP] [Lv 12] [Titel]
local function buildPrefix(sender: Player): string
	local parts: { string } = {}
	if sender:GetAttribute("IsAdmin") == true then
		table.insert(parts, colored("[" .. ctx.T("prog.chat.owner") .. "]", chatCfg.OwnerColor or "#FFC828"))
	end
	if sender:GetAttribute("Vip") == true then
		table.insert(parts, colored("[VIP]", chatCfg.VipColor or "#FFD700"))
	end
	local level = sender:GetAttribute("Level")
	if type(level) == "number" and level >= 1 then
		local lvl = math.floor(level)
		table.insert(parts, colored("[" .. ctx.T("prog.chat.level", lvl) .. "]", levelColor(lvl)))
	end
	local title = sender:GetAttribute("Title")
	if type(title) == "string" and title ~= "" then
		local text, color = titleText(title)
		if text then
			table.insert(
				parts,
				colored("[" .. text .. "]", if color then hex(color) else (chatCfg.TitleColor or "#B9A7F2"))
			)
		end
	end
	return table.concat(parts, " ")
end

function ChatClient.Rewrite(text: string): string?
	if not chatCfg then
		return nil
	end
	return ProgressMath.RewriteChat(text, chatCfg.Rewrites, ctx.Lang_())
end

-- ---------------------------------------------------------------------
-- OnIncomingMessage (wird pro Nachricht ggf. mehrfach gerufen: Senden + Erfolg)
-- ---------------------------------------------------------------------
local function onIncoming(message: TextChatMessage): TextChatMessageProperties?
	local source = message.TextSource
	if not source then
		return nil -- System-/Spielnachrichten bleiben, wie sie sind
	end
	local props = Instance.new("TextChatMessageProperties")
	local sender = Players:GetPlayerByUserId(source.UserId)
	if sender then
		local ok, prefix = pcall(buildPrefix, sender)
		if ok and prefix ~= "" then
			props.PrefixText = prefix .. " " .. message.PrefixText
		end
	end
	-- nur Nachrichten ANDERER, nur fertig gefilterte Texte umschreiben
	if source.UserId ~= ctx.Player.UserId and message.Status == Enum.TextChatMessageStatus.Success then
		local ok, rewritten = pcall(ChatClient.Rewrite, message.Text)
		if ok and type(rewritten) == "string" then
			props.Text = rewritten
		end
	end
	return props
end

-- ---------------------------------------------------------------------
-- INIT / START
-- ---------------------------------------------------------------------
function ChatClient.Init(context: any)
	ctx = context
	local progression = ctx.Config.Progression
	chatCfg = if type(progression) == "table" and type(progression.Chat) == "table"
		then progression.Chat
		else { Rewrites = {} }
	if type(progression) == "table" and type(progression.LevelColors) == "table" then
		for _, entry in ipairs(progression.LevelColors) do
			if type(entry) == "table" and type(entry.Min) == "number" and typeof(entry.Color) == "Color3" then
				table.insert(levelColors, { Min = entry.Min, Color = entry.Color })
			end
		end
		table.sort(levelColors, function(a, b)
			return a.Min < b.Min
		end)
	end
end

function ChatClient.Start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[ChatClient] Altes Chat-System aktiv – Umschreibungen/Präfixe aus")
		return
	end
	TextChatService.OnIncomingMessage = onIncoming
end

return ChatClient
