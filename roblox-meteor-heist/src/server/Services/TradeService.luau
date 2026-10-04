-- 🤝 HANDEL zwischen Spielern (wie in Steal-Spielen)
--  * Anfrage (Spieler-Liste oder Prompt "Handeln" am Charakter) -> Ziel nimmt an/lehnt ab (20 s)
--  * Beide sehen beide Seiten: Aliens/Eier aus der eigenen Base (max. 6) + Cash
--  * Jede Änderung setzt "Bereit" bei beiden zurück. Beide bereit -> 3 s Countdown -> Tausch
--  * Der Tausch passiert in EINEM Schritt ohne Warten (kein yield): erst alles prüfen, dann
--    verschieben. Angebote werden per Referenz verglichen -> verkauft/geklaut/Rebirth/Reset = Abbruch.
--  * Ein Spieler ist immer nur in EINEM Handel. Verlassen beendet den Handel sofort.
-- Client -> Server: Remotes.Trade (RemoteFunction) mit (Aktion, Wert), Antwort { Ok, Message }
-- Server -> Client: Remotes.TradeEvent (RemoteEvent) mit (Art, Daten):
--   "Request" { From, Name, Timeout }, "RequestGone" { From }, "Update" (Ansicht), "Closed" { Text, Done }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local TradeService = {}
local Services

local MIN_PLAYTIME = 120 -- Sekunden nach dem Beitritt ohne Handel (gegen Alt-Account-Spam)
local REQUEST_TIMEOUT = 20 -- so lange gilt eine Anfrage
local MAX_ITEMS = 6 -- pro Seite
local COUNTDOWN = 3 -- beide bereit -> so viele Sekunden bis zum Tausch
local CHECK_INTERVAL = 1 -- so oft werden laufende Angebote geprüft (verkauft, geklaut, geschlüpft ...)

local actionLimiter = Util.RateLimiter(12, 1) -- alle Aktionen
local requestLimiter = Util.RateLimiter(3, 15) -- Anfragen senden

type Item = { Key: string, Ref: any, Sig: string }
type Offer = { Items: { Item }, Cash: number, Ready: boolean }
type Trade = {
	Id: number,
	A: Player,
	B: Player,
	Offers: { [Player]: Offer },
	Token: number,
	EndsAt: number?,
	Active: boolean,
	InvKey: { [Player]: string },
}
type Request = { Id: number, To: Player, Expires: number }

local joinedAt: { [Player]: number } = {}
local blocked: { [Player]: boolean } = {}
local outgoing: { [Player]: Request } = {} -- eine offene Anfrage pro Absender
local tradeOf: { [Player]: Trade } = {}
local trades: { [Trade]: boolean } = {}
local leaving = setmetatable({} :: { [Player]: boolean }, { __mode = "k" })
local nextId = 0

-- -------------------------------------------------------------------
-- HILFEN
-- -------------------------------------------------------------------
local function notify(player: Player, text: string, kind: string?)
	local economy = Services.EconomyService
	if economy and economy.Notify then
		economy.Notify(player, text, kind)
	end
end

local function fire(player: Player, kind: string, data: any)
	if player.Parent then
		Remotes.TradeEvent:FireClient(player, kind, data)
	end
end

local function dataOf(player: Player): any
	return Services.DataService.Get(player)
end

-- Spieler noch da und Spielstand voll benutzbar (nicht am Speichern beim Verlassen)?
local function isPresent(player: Player): boolean
	if not player.Parent or leaving[player] then
		return false
	end
	local profiles = Services.DataService.Profiles
	local profile = profiles and profiles[player]
	if not profile or not profile.Loaded or profile.Releasing then
		return false
	end
	local economy = Services.EconomyService
	if economy and economy.IsReady and not economy.IsReady(player) then
		return false
	end
	return dataOf(player) ~= nil
end

local function isCarrying(player: Player): boolean
	local carry = Services.CarryService
	return carry ~= nil and carry.IsCarrying ~= nil and carry.IsCarrying(player) == true
end

local function slotStolen(plot, key: string): boolean
	local carry = Services.CarryService
	local slot = tonumber(key)
	if not carry or not carry.IsSlotBeingStolen or not plot or not slot then
		return false
	end
	return carry.IsSlotBeingStolen(plot, slot) == true
end

local function ownPlot(player: Player): any
	local plot = Services.PlotService.GetPlot(player)
	if plot and plot.Owner == player then
		return plot
	end
	return nil
end

-- Benutzbare Slots (Gamepass +6 berücksichtigt, nie mehr als die Map hat)
local function slotCount(player: Player): number
	local plots = Services.PlotService
	local count = if plots.SlotCount then plots.SlotCount(player) else Config.BaseSlots
	local max = tonumber(plots.MaxSlots)
	if max then
		count = math.min(count, max)
	end
	return count
end

-- "Fingerabdruck" eines Eintrags: ändert sich beim Schlüpfen / anderer Mutation.
-- (Level/Xp/Schlüpfzeit laufen ständig weiter und zählen nicht.)
local function entrySig(entry: any): string
	return tostring(entry.Id) .. "|" .. tostring(entry.Alien or "") .. "|" .. tostring(entry.Mut)
end

local function playedSeconds(player: Player): number
	return os.clock() - (joinedAt[player] or os.clock())
end

local function waitText(player: Player): string?
	local left = MIN_PLAYTIME - playedSeconds(player)
	if left > 0 then
		return Util.FormatTime(math.ceil(left))
	end
	return nil
end

local function cleanCash(value: any): number?
	local n = tonumber(value)
	if not n or n ~= n or n < 0 or n == math.huge then
		return nil
	end
	return math.floor(n)
end

-- -------------------------------------------------------------------
-- ANSICHT FÜR DEN CLIENT
-- -------------------------------------------------------------------
local function itemInfo(key: string, entry: any): { [string]: any }
	local def = Config.MeteorsById[entry.Id]
	return {
		Key = key,
		Name = Config.EntryName(entry),
		Rarity = def and def.Rarity or "Common",
		Mut = entry.Mut or "Normal",
		Lv = tonumber(entry.Lv) or 1,
		Income = Config.MeteorIncome(entry),
		Egg = entry.Alien == nil,
	}
end

local function sortedKeys(meteors: any): { string }
	local keys = {}
	for key in pairs(meteors) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return keys
end

local function offerView(offer: Offer): { [string]: any }
	local items = {}
	for _, item in ipairs(offer.Items) do
		table.insert(items, itemInfo(item.Key, item.Ref))
	end
	return { Items = items, Cash = offer.Cash, Ready = offer.Ready }
end

local function inventoryView(player: Player, offer: Offer): ({ any }, string)
	local data = dataOf(player)
	local list, parts = {}, {}
	if not data then
		return list, ""
	end
	local offered: { [string]: boolean } = {}
	for _, item in ipairs(offer.Items) do
		offered[item.Key] = true
	end
	for _, key in ipairs(sortedKeys(data.Meteors)) do
		local entry = data.Meteors[key]
		local info = itemInfo(key, entry)
		info.Offered = offered[key] == true
		table.insert(list, info)
		table.insert(parts, key .. "=" .. entrySig(entry) .. (if info.Offered then "*" else ""))
	end
	return list, table.concat(parts, ",")
end

local function otherOf(trade: Trade, player: Player): Player
	return if trade.A == player then trade.B else trade.A
end

local function viewFor(trade: Trade, player: Player): { [string]: any }
	local other = otherOf(trade, player)
	local inventory, key = inventoryView(player, trade.Offers[player])
	trade.InvKey[player] = key
	local data = dataOf(player)
	return {
		Id = trade.Id,
		Other = { UserId = other.UserId, Name = other.DisplayName },
		You = offerView(trade.Offers[player]),
		Them = offerView(trade.Offers[other]),
		Inventory = inventory,
		Cash = data and data.Cash or 0,
		EndsAt = trade.EndsAt,
		MaxItems = MAX_ITEMS,
	}
end

local function push(trade: Trade)
	if not trade.Active then
		return
	end
	fire(trade.A, "Update", viewFor(trade, trade.A))
	fire(trade.B, "Update", viewFor(trade, trade.B))
end

-- -------------------------------------------------------------------
-- HANDEL STEUERN
-- -------------------------------------------------------------------
local function resetReady(trade: Trade)
	trade.Offers[trade.A].Ready = false
	trade.Offers[trade.B].Ready = false
	trade.Token += 1 -- laufender Countdown verfällt
	trade.EndsAt = nil
end

local function closeTrade(trade: Trade, textA: string?, textB: string?, done: boolean?)
	if not trade.Active then
		return
	end
	trade.Active = false
	trade.Token += 1
	trades[trade] = nil
	if tradeOf[trade.A] == trade then
		tradeOf[trade.A] = nil
	end
	if tradeOf[trade.B] == trade then
		tradeOf[trade.B] = nil
	end
	fire(trade.A, "Closed", { Text = textA, Done = done == true })
	fire(trade.B, "Closed", { Text = textB, Done = done == true })
end

-- Anfrage zurückziehen (Ziel bekommt "RequestGone")
local function dropRequest(from: Player)
	local request = outgoing[from]
	if request then
		outgoing[from] = nil
		fire(request.To, "RequestGone", { From = from.UserId })
	end
end

-- Kann dieser Spieler gerade handeln? (nil = ja, sonst Grund)
local function cannotTrade(player: Player, you: boolean): string?
	if not isPresent(player) or not ownPlot(player) then
		return if you then "Lädt noch... ⏳" else "Geht gerade nicht."
	end
	local wait = waitText(player)
	if wait then
		return if you then "⏳ Handeln geht in " .. wait else "⏳ " .. player.DisplayName .. " ist noch zu neu."
	end
	if tradeOf[player] then
		return if you then "Du handelst schon!" else player.DisplayName .. " handelt gerade."
	end
	return nil
end

local function startTrade(a: Player, b: Player)
	nextId += 1
	local trade: Trade = {
		Id = nextId,
		A = a,
		B = b,
		Offers = {
			[a] = { Items = {}, Cash = 0, Ready = false },
			[b] = { Items = {}, Cash = 0, Ready = false },
		},
		Token = 0,
		EndsAt = nil,
		Active = true,
		InvKey = {},
	}
	trades[trade] = true
	tradeOf[a] = trade
	tradeOf[b] = trade
	dropRequest(a)
	dropRequest(b)
	push(trade)
end

-- Laufende Angebote prüfen: Verschwundenes raus, Geändertes neu, zu viel Cash kürzen.
-- Gibt true zurück, wenn sich etwas geändert hat (dann sind beide nicht mehr bereit).
local function revalidate(trade: Trade): boolean
	local changed = false
	for _, player in ipairs({ trade.A, trade.B }) do
		local data = dataOf(player)
		local offer = trade.Offers[player]
		for i = #offer.Items, 1, -1 do
			local item = offer.Items[i]
			local current = data and data.Meteors[item.Key]
			if current ~= item.Ref then
				table.remove(offer.Items, i)
				changed = true
			elseif entrySig(current) ~= item.Sig then
				item.Sig = entrySig(current)
				changed = true
			end
		end
		local cash = data and data.Cash or 0
		if offer.Cash > cash then
			offer.Cash = math.max(0, math.floor(cash))
			changed = true
		end
	end
	if changed then
		resetReady(trade)
	end
	return changed
end

-- -------------------------------------------------------------------
-- DER TAUSCH (atomar: kein yield zwischen Prüfen und Verschieben)
-- -------------------------------------------------------------------
-- Gibt (true) oder (false, Grund, schließen) zurück. schließen = Handel ganz beenden.
function TradeService.Execute(trade: Trade): (boolean, string?, boolean?)
	if not trade.Active then
		return false, "Handel ist vorbei.", true
	end
	local a, b = trade.A, trade.B
	local sides = { a, b }
	local datas: { [Player]: any } = {}
	local plots: { [Player]: any } = {}
	for _, player in ipairs(sides) do
		if not isPresent(player) then
			return false, player.DisplayName .. " ist weg.", true
		end
		local plot = ownPlot(player)
		if not plot then
			return false, player.DisplayName .. " hat keine Base.", true
		end
		if tradeOf[player] ~= trade then
			return false, "Handel ist vorbei.", true
		end
		datas[player] = dataOf(player)
		plots[player] = plot
	end
	if datas[a] == datas[b] then
		return false, "Fehler.", true
	end
	for _, player in ipairs(sides) do
		if isCarrying(player) then
			return false, player.DisplayName .. " trägt gerade Beute."
		end
		local data = datas[player]
		local offer = trade.Offers[player]
		if #offer.Items > MAX_ITEMS then
			return false, "Zu viele Sachen."
		end
		local seen: { [string]: boolean } = {}
		for _, item in ipairs(offer.Items) do
			local current = data.Meteors[item.Key]
			if seen[item.Key] or current == nil or current ~= item.Ref or entrySig(current) ~= item.Sig then
				return false, "Angebot von " .. player.DisplayName .. " hat sich geändert."
			end
			if not Config.MeteorsById[current.Id] then
				return false, "Ungültiges Angebot."
			end
			if slotStolen(plots[player], item.Key) then
				return false, Config.EntryName(current) .. " wird gerade geklaut!"
			end
			seen[item.Key] = true
		end
		local cash = cleanCash(offer.Cash)
		if cash == nil or cash ~= offer.Cash or (tonumber(data.Cash) or 0) < cash then
			return false, player.DisplayName .. " hat nicht genug Cash."
		end
	end
	-- Freie Slots beim Empfänger (eigene abgegebene Slots werden frei)
	local freeSlots: { [Player]: { number } } = {}
	for _, receiver in ipairs(sides) do
		local giver = otherOf(trade, receiver)
		local incoming = #trade.Offers[giver].Items
		local leavingKeys: { [string]: boolean } = {}
		for _, item in ipairs(trade.Offers[receiver].Items) do
			leavingKeys[item.Key] = true
		end
		local free = {}
		local meteors = datas[receiver].Meteors
		for slot = 1, slotCount(receiver) do
			if #free >= incoming then
				break
			end
			local key = tostring(slot)
			if meteors[key] == nil or leavingKeys[key] then
				table.insert(free, slot)
			end
		end
		if #free < incoming then
			return false, "📦 Base von " .. receiver.DisplayName .. " ist zu voll."
		end
		freeSlots[receiver] = free
	end

	-- ALLES OK -> verschieben (ab hier kann nichts mehr scheitern)
	local moved: { [Player]: { Item } } = {}
	local touched: { [Player]: { [number]: boolean } } = { [a] = {}, [b] = {} }
	for _, player in ipairs(sides) do
		moved[player] = trade.Offers[player].Items
		for _, item in ipairs(moved[player]) do
			datas[player].Meteors[item.Key] = nil
			touched[player][tonumber(item.Key) :: number] = true
		end
	end
	for _, receiver in ipairs(sides) do
		local giver = otherOf(trade, receiver)
		for i, item in ipairs(moved[giver]) do
			local slot = freeSlots[receiver][i]
			datas[receiver].Meteors[tostring(slot)] = item.Ref
			touched[receiver][slot] = true
		end
	end
	local cashA, cashB = trade.Offers[a].Cash, trade.Offers[b].Cash
	datas[a].Cash = datas[a].Cash - cashA + cashB
	datas[b].Cash = datas[b].Cash - cashB + cashA
	closeTrade(trade, "🤝 Handel fertig!", "🤝 Handel fertig!", true)

	-- Anzeigen, Index, Speichern (Fehler hier dürfen den Tausch nicht mehr rückgängig machen)
	local economy = Services.EconomyService
	for _, player in ipairs(sides) do
		for slot in pairs(touched[player]) do
			local ok, err = pcall(Services.PlotService.RenderSlot, plots[player], slot)
			if not ok then
				warn("[TradeService] RenderSlot fehlgeschlagen: " .. tostring(err))
			end
		end
		local giver = otherOf(trade, player)
		for _, item in ipairs(moved[giver]) do
			if item.Ref.Alien ~= nil and economy and economy.Discover then
				pcall(economy.Discover, player, item.Ref.Alien)
			end
		end
		if economy then
			if economy.MarkDirty then
				economy.MarkDirty(player)
			end
			if economy.Effect then
				economy.Effect(player, "Confetti", 1)
			end
		end
		task.spawn(function()
			local ok, err = pcall(Services.DataService.Save, player)
			if not ok then
				warn("[TradeService] Speichern fehlgeschlagen: " .. tostring(err))
			end
		end)
	end
	print(
		("[TradeService] Handel #%d: %s (%d) gibt %d Sachen + %s, %s (%d) gibt %d Sachen + %s"):format(
			trade.Id,
			a.Name,
			a.UserId,
			#moved[a],
			Util.FormatCash(cashA),
			b.Name,
			b.UserId,
			#moved[b],
			Util.FormatCash(cashB)
		)
	)
	return true
end

-- Countdown abgelaufen -> tauschen oder mit Grund abbrechen
local function finish(trade: Trade, token: number)
	if not trade.Active or trade.Token ~= token then
		return
	end
	local ok, reason, close = TradeService.Execute(trade)
	if ok then
		return
	end
	local text = "❌ " .. tostring(reason)
	if close then
		closeTrade(trade, text, text)
	else
		resetReady(trade)
		notify(trade.A, text, "Error")
		notify(trade.B, text, "Error")
		push(trade)
	end
end

-- -------------------------------------------------------------------
-- AKTIONEN VOM CLIENT
-- -------------------------------------------------------------------
local Actions: { [string]: (Player, any) -> (boolean, string?, any?) } = {}

function Actions.Status(player: Player)
	local trade = tradeOf[player]
	return true,
		nil,
		{
			Blocked = blocked[player] == true,
			Wait = math.max(0, math.ceil(MIN_PLAYTIME - playedSeconds(player))),
			Trade = trade and trade.Active and viewFor(trade, player) or nil,
		}
end

function Actions.Block(player: Player, on: any)
	blocked[player] = on == true
	if on == true then
		-- offene Anfragen an mich ablehnen
		for from, request in pairs(outgoing) do
			if request.To == player then
				dropRequest(from)
			end
		end
	end
	return true, if on == true then "🚫 Anfragen blockiert" else "✅ Anfragen erlaubt"
end

function Actions.Send(player: Player, userId: any)
	local target = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	if not target or target == player then
		return false, "Spieler nicht gefunden."
	end
	if not requestLimiter.Check(player) then
		return false, "Langsam! 🐢"
	end
	local reason = cannotTrade(player, true) or cannotTrade(target, false)
	if reason then
		return false, reason
	end
	if blocked[target] then
		return false, "🚫 " .. target.DisplayName .. " blockt Anfragen."
	end
	-- Hat das Ziel MIR schon eine Anfrage geschickt? -> sofort los
	local back = outgoing[target]
	if back and back.To == player and back.Expires > os.clock() then
		startTrade(target, player)
		return true, nil
	end
	local current = outgoing[player]
	if current and current.To == target and current.Expires > os.clock() then
		return false, "Anfrage läuft schon."
	end
	dropRequest(player)
	nextId += 1
	local request: Request = { Id = nextId, To = target, Expires = os.clock() + REQUEST_TIMEOUT }
	outgoing[player] = request
	fire(target, "Request", { From = player.UserId, Name = player.DisplayName, Timeout = REQUEST_TIMEOUT })
	task.delay(REQUEST_TIMEOUT, function()
		if outgoing[player] == request then
			dropRequest(player)
			notify(player, "⌛ " .. target.DisplayName .. " hat nicht geantwortet.", "Info")
		end
	end)
	return true, "📨 Anfrage an " .. target.DisplayName .. " gesendet!"
end

function Actions.Answer(player: Player, arg: any)
	if type(arg) ~= "table" or type(arg.From) ~= "number" then
		return false, "Fehler."
	end
	local from = Players:GetPlayerByUserId(arg.From)
	local request = from and outgoing[from]
	if not from or not request or request.To ~= player or request.Expires <= os.clock() then
		return false, "Anfrage ist abgelaufen."
	end
	if arg.Accept ~= true then
		dropRequest(from)
		notify(from, "❌ " .. player.DisplayName .. " will nicht handeln.", "Error")
		return true, nil
	end
	local reason = cannotTrade(player, true) or cannotTrade(from, false)
	if reason then
		dropRequest(from)
		return false, reason
	end
	startTrade(from, player)
	return true, nil
end

local function myTrade(player: Player): Trade?
	local trade = tradeOf[player]
	if trade and trade.Active then
		return trade
	end
	return nil
end

function Actions.Add(player: Player, key: any)
	local trade = myTrade(player)
	if not trade then
		return false, "Kein Handel."
	end
	key = tostring(key)
	local data = dataOf(player)
	local entry = data and data.Meteors[key]
	local offer = trade.Offers[player]
	if not entry or not Config.MeteorsById[entry.Id] then
		return false, "Gibt es nicht mehr."
	end
	for _, item in ipairs(offer.Items) do
		if item.Key == key then
			return false, "Schon drin."
		end
	end
	if #offer.Items >= MAX_ITEMS then
		return false, "Max. " .. MAX_ITEMS .. " Sachen."
	end
	if slotStolen(ownPlot(player), key) then
		return false, "Wird gerade geklaut!"
	end
	table.insert(offer.Items, { Key = key, Ref = entry, Sig = entrySig(entry) })
	resetReady(trade)
	push(trade)
	return true, nil
end

function Actions.Remove(player: Player, key: any)
	local trade = myTrade(player)
	if not trade then
		return false, "Kein Handel."
	end
	key = tostring(key)
	local offer = trade.Offers[player]
	for i, item in ipairs(offer.Items) do
		if item.Key == key then
			table.remove(offer.Items, i)
			resetReady(trade)
			push(trade)
			return true, nil
		end
	end
	return false, "Nicht im Angebot."
end

function Actions.Cash(player: Player, amount: any)
	local trade = myTrade(player)
	if not trade then
		return false, "Kein Handel."
	end
	local cash = cleanCash(amount)
	local data = dataOf(player)
	if not cash or not data then
		return false, "Ungültiger Betrag."
	end
	if cash > (tonumber(data.Cash) or 0) then
		return false, "Nicht genug Cash."
	end
	local offer = trade.Offers[player]
	if offer.Cash ~= cash then
		offer.Cash = cash
		resetReady(trade)
		push(trade)
	end
	return true, nil
end

function Actions.Ready(player: Player, on: any)
	local trade = myTrade(player)
	if not trade then
		return false, "Kein Handel."
	end
	if on ~= true then
		if trade.Offers[player].Ready then
			resetReady(trade)
			push(trade)
		end
		return true, nil
	end
	if revalidate(trade) then
		push(trade)
		return false, "Angebot hat sich geändert – nochmal prüfen!"
	end
	local offers = trade.Offers
	if
		#offers[trade.A].Items == 0
		and #offers[trade.B].Items == 0
		and offers[trade.A].Cash == 0
		and offers[trade.B].Cash == 0
	then
		return false, "Biete erst etwas an!"
	end
	offers[player].Ready = true
	if offers[trade.A].Ready and offers[trade.B].Ready and not trade.EndsAt then
		trade.Token += 1
		local token = trade.Token
		trade.EndsAt = workspace:GetServerTimeNow() + COUNTDOWN
		task.delay(COUNTDOWN, finish, trade, token)
	end
	push(trade)
	return true, nil
end

function Actions.Cancel(player: Player)
	local trade = myTrade(player)
	if not trade then
		return true, nil
	end
	closeTrade(
		trade,
		if trade.A == player then "Handel abgebrochen." else "❌ " .. player.DisplayName .. " hat abgebrochen.",
		if trade.B == player then "Handel abgebrochen." else "❌ " .. player.DisplayName .. " hat abgebrochen."
	)
	return true, nil
end

function TradeService.Handle(player: Player, action: any, arg: any): { [string]: any }
	if not actionLimiter.Check(player) then
		return { Ok = false, Message = "Langsam! 🐢" }
	end
	local fn = type(action) == "string" and Actions[action] or nil
	if not fn then
		return { Ok = false, Message = "Unbekannt" }
	end
	local ok, message, extra = fn(player, arg)
	local response: { [string]: any } = { Ok = ok, Message = message or "" }
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			response[key] = value
		end
	end
	return response
end

-- -------------------------------------------------------------------
-- VERLASSEN / RESET
-- -------------------------------------------------------------------
-- Handel eines Spielers sofort beenden (Verlassen, Spielstand wird gespeichert)
function TradeService.CancelFor(player: Player, text: string?)
	local trade = tradeOf[player]
	if trade then
		local other = otherOf(trade, player)
		local otherText = text or ("❌ " .. player.DisplayName .. " ist weg.")
		if trade.A == other then
			closeTrade(trade, otherText, nil)
		else
			closeTrade(trade, nil, otherText)
		end
	end
	dropRequest(player)
	for from, request in pairs(outgoing) do
		if request.To == player then
			outgoing[from] = nil
		end
	end
end

local function onLeave(player: Player)
	leaving[player] = true
	TradeService.CancelFor(player)
	joinedAt[player] = nil
	blocked[player] = nil
	actionLimiter.Clear(player)
	requestLimiter.Clear(player)
end

function TradeService.Init(services)
	Services = services
end

function TradeService.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		joinedAt[player] = joinedAt[player] or os.clock()
	end
	Players.PlayerAdded:Connect(function(player)
		joinedAt[player] = os.clock()
	end)
	Players.PlayerRemoving:Connect(onLeave)
	local data = Services.DataService
	if data and data.OnProfileReleasing then
		data.OnProfileReleasing(function(player)
			leaving[player] = true
			TradeService.CancelFor(player)
		end)
	end

	Remotes.Trade.OnServerInvoke = function(player: Player, action: any, arg: any)
		local ok, result = pcall(TradeService.Handle, player, action, arg)
		if ok then
			return result
		end
		warn("[TradeService] Fehler: " .. tostring(result))
		return { Ok = false, Message = "Fehler – nochmal versuchen" }
	end

	-- Laufende Handel prüfen (verkauft, geklaut, geschlüpft, Rebirth, Spieler weg ...)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for trade in pairs(trades) do
				local ok, err = pcall(function()
					for _, player in ipairs({ trade.A, trade.B }) do
						if not isPresent(player) then
							TradeService.CancelFor(player)
							return
						end
					end
					if revalidate(trade) then
						notify(trade.A, "Angebot geändert – nochmal bereit drücken!", "Info")
						notify(trade.B, "Angebot geändert – nochmal bereit drücken!", "Info")
						push(trade)
						return
					end
					-- Base hat sich geändert (geschlüpft, neues Ei ...) -> Liste neu schicken
					for _, player in ipairs({ trade.A, trade.B }) do
						local _, key = inventoryView(player, trade.Offers[player])
						if key ~= trade.InvKey[player] then
							push(trade)
							break
						end
					end
				end)
				if not ok then
					warn("[TradeService] Prüf-Fehler: " .. tostring(err))
				end
			end
		end
	end)
end

-- Für Tests
TradeService._internal = { tradeOf = tradeOf, joinedAt = joinedAt, outgoing = outgoing, blocked = blocked }

return TradeService
