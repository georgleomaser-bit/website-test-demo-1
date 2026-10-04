-- Belohnungen, die zum Wiederkommen locken (v2.1):
--  * 🎁 SPIELZEIT-GESCHENKE: nach 2, 5, 10 ... 60 Minuten Spielzeit ein Geschenk. Die Spielzeit zählt
--    pro UTC-Tag über ALLE Besuche und steht im Spielstand (data.Gifts) – neu beitreten setzt sie
--    nicht zurück (sonst könnte man alle 10 Minuten neu beitreten und dieselben Geschenke abholen).
--  * 🎡 GLÜCKSRAD: Drehs (data.Spins) + alle Config.FreeSpinHours Stunden ein Gratis-Dreh
--  * 📜 TAGESAUFGABEN: pro UTC-Tag 3 Aufgaben (Klauen, Schlüpfen, Laufen ...) -> Cash + 1 Dreh,
--    eine davon darf man einmal am Tag tauschen (z.B. "Bonk 3 Diebe" auf einem leeren Server)
-- Gewürfelt und gutgeschrieben wird NUR hier auf dem Server. Der Client zeigt nur an (State)
-- und schickt Anfragen ("ClaimGift", "Spin", "ClaimQuest", "RerollQuest" über den EconomyService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local RewardService = {}
local Services

local rng = Random.new()

-- -------------------------------------------------------------------
-- EINSTELLUNGEN
-- Geschenke und Glücksrad-Felder stehen in Config (PlaytimeGifts, WheelPrizes, FreeSpinHours):
--   Type "Cash"  -> max(Min, Einkommen pro Sekunde * Seconds)
--   Type "Steps" -> so viele Schritte wie Seconds Sekunden auf dem besten Laufband (mind. Min)
--   Type "Spins" -> Amount Glücksrad-Drehs
--   Type "Egg"   -> zufälliges Ei (Meteor) der Seltenheit Rarity in die Base (Base voll -> Wert als Cash)
-- -------------------------------------------------------------------
local MAX_SPINS = 100000
local SPIN_COOLDOWN = 2 -- Sekunden zwischen zwei Drehs (der Client dreht das Rad in der Zeit)
local SPIN_REVEAL_DELAY = 5 -- große Gewinne erst ansagen, wenn das Rad beim Gewinner stehen geblieben ist
local SPIN_ANNOUNCE_RARITY = "Legendary" -- ab dieser Seltenheit wird ein Ei-Gewinn allen angesagt
local FIRST_NOTIFY_DELAY = 8 -- "Gratis-Dreh bereit" erst nach den Willkommens-Nachrichten
local MAX_TICK = 5 -- Spielzeit: nach einem Server-Hänger höchstens so viele Sekunden auf einmal
local MAX_GIFT_SECONDS = 86400 -- mehr als ein Tag Spielzeit geht an einem Tag nicht

-- Tagesaufgaben: Goals = feste Auswahl, Scale = wächst mit dem Fortschritt des Spielers.
-- Social = braucht andere Spieler (Klauen aus Basen, Bonken) -> höchstens eine davon pro Tag.
local QUEST_POOL = {
	{ Id = "Grab", Kind = "Grab", Text = "🥚 Klau %s Eier aus der Parade", Goals = { 5, 6, 8, 10 } },
	{ Id = "Steal", Kind = "Steal", Text = "😈 Klau %s Aliens/Eier aus Basen", Goals = { 2, 3 }, Social = true },
	{ Id = "Hatch", Kind = "Hatch", Text = "🐣 Lass %s Aliens schlüpfen", Goals = { 5, 6, 8 } },
	{ Id = "Steps", Kind = "Steps", Text = "👟 Lauf %s Schritte", Scale = "Steps" },
	{ Id = "Collect", Kind = "Collect", Text = "💰 Sammle %s ein", Scale = "Collect" },
	{ Id = "Bonk", Kind = "Bonk", Text = "🔨 Bonk %s Diebe", Goals = { 2, 3 }, Social = true },
}
local QUESTS_PER_DAY = 3
local QUEST_STEPS_SECONDS = 240 -- "Lauf X Schritte" = 4 Minuten auf dem besten Laufband
local QUEST_STEPS_MIN = 200
local QUEST_COLLECT_SECONDS = 300 -- "Sammle $X ein" = 5 Minuten Einkommen
local QUEST_COLLECT_MIN = 500
local QUEST_REWARD_SECONDS = 240 -- Belohnung = 4 Minuten Einkommen ...
local QUEST_REWARD_MIN = 2000 -- ... mindestens so viel
local QUEST_REWARD_SPINS = 1

local QUEST_BY_ID = {}
for _, def in ipairs(QUEST_POOL) do
	QUEST_BY_ID[def.Id] = def
end

local TRACK_KINDS = { Grab = true, Steal = true, Hatch = true, Steps = true, Collect = true, Bonk = true }

-- Sitzungs-Daten (nicht gespeichert – die Spielzeit für Geschenke steht in data.Gifts)
local joinedAt: { [Player]: number } = {}
local lastTick: { [Player]: number } = {}
local notifiedGifts: { [Player]: { [number]: boolean } } = {}
local notifiedDay: { [Player]: string } = {}
local freeSpinNotified: { [Player]: boolean } = {}
local lastSpin: { [Player]: number } = {}
-- Zuletzt geschickte Geschenke/Aufgaben (nur bei Änderung neu schicken, spart Netzwerk)
local sentGiftKey: { [Player]: string } = {}
local sentQuestKey: { [Player]: string } = {}

-- -------------------------------------------------------------------
-- HELFER
-- -------------------------------------------------------------------
local function giftList(): { any }
	return Config.PlaytimeGifts or {}
end

local function wheelList(): { any }
	return Config.WheelPrizes or {}
end

local function freeSpinPeriod(): number
	local hours = tonumber(Config.FreeSpinHours) or 4
	if hours ~= hours or hours <= 0 then
		hours = 4
	end
	return hours * 3600
end

local function finite(n: number): number
	if n ~= n or n < 0 then
		return 0
	end
	return math.min(n, 1e30)
end

-- 1234 -> 1200, 56789 -> 57000 (2 gültige Stellen – Ziele sehen so schöner aus)
local function roundNice(n: number): number
	n = finite(n)
	if n < 100 then
		return math.max(1, math.floor(n + 0.5))
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / magnitude + 0.5) * magnitude
end

local function today(): string
	return tostring(os.date("!%Y-%m-%d"))
end

local function notify(player: Player, text: string, kind: string?)
	Services.EconomyService.Notify(player, text, kind)
end

local function markDirty(player: Player)
	Services.EconomyService.MarkDirty(player)
end

-- Sekunden seit dem Beitritt (nur für den ersten Hinweis, NICHT für die Geschenke)
local function sessionSeconds(player: Player): number
	local t = joinedAt[player]
	if not t then
		t = os.clock()
		joinedAt[player] = t
	end
	return os.clock() - t
end

-- 🎁 Spielzeit von heute (UTC) aus dem Spielstand: { Day, Seconds, Claimed = { ["1"] = true } }.
-- Neuer Tag oder kaputte Daten -> wieder bei 0, alle Geschenke neu.
type GiftData = { Day: string, Seconds: number, Claimed: { [string]: boolean } }

local function giftData(data): GiftData
	local gifts = data.Gifts
	local day = today()
	if
		type(gifts) ~= "table"
		or gifts.Day ~= day
		or type(gifts.Claimed) ~= "table"
		or type(gifts.Seconds) ~= "number"
		or gifts.Seconds ~= gifts.Seconds
	then
		gifts = { Day = day, Seconds = 0, Claimed = {} }
		data.Gifts = gifts
	end
	return gifts
end

local function prizeType(prize): string
	return tostring(prize.Type or prize.Kind or "Cash")
end

-- Einkommen + Schritte-Tempo einmal ausrechnen (für mehrere Belohnungstexte auf einmal).
-- state (optional) = schon gebauter State: dann werden Income/StepsMult daraus genommen statt neu gerechnet.
type Rates = { Income: number, StepsPerSecond: number }

local function rates(player: Player, data, state: { [string]: any }?): Rates
	local best = Config.BestTreadmill(data.Steps)
	local rate = best and best.Rate or 1
	local income = state and tonumber(state.Income)
	local stepsMult = state and tonumber(state.StepsMult)
	return {
		Income = finite(income or Services.EconomyService.GetIncome(player)),
		StepsPerSecond = finite(
			rate / Config.TreadmillTick * (stepsMult or Services.EconomyService.GetStepsMult(player))
		),
	}
end

local function cashAmount(prize, r: Rates): number
	return math.floor(math.max(tonumber(prize.Min) or 0, r.Income * (tonumber(prize.Seconds) or 60)))
end

local function stepsAmount(prize, r: Rates): number
	return math.floor(math.max(tonumber(prize.Min) or 0, r.StepsPerSecond * (tonumber(prize.Seconds) or 60)))
end

local function spinsAmount(prize): number
	return math.clamp(math.floor(tonumber(prize.Amount) or 1), 1, 100)
end

local function spinsWord(n: number): string
	return n .. (n == 1 and " Dreh" or " Drehs")
end

-- Feld-Name fürs Glücksrad, z.B. "🌟 Legendary-Ei"
local function prizeLabel(prize): string
	local name = prize.Name or (prizeType(prize) == "Egg" and (tostring(prize.Rarity) .. "-Ei")) or prizeType(prize)
	return (prize.Icon and (tostring(prize.Icon) .. " ") or "") .. tostring(name)
end

-- Was gibt es? (Anzeige im Client, mit den aktuellen Beträgen)
local function prizeText(prize, r: Rates): string
	local kind = prizeType(prize)
	if kind == "Steps" then
		return tostring(prize.Icon or "👟") .. " " .. Util.FormatNumber(stepsAmount(prize, r)) .. " Schritte"
	elseif kind == "Spins" then
		return tostring(prize.Icon or "🎡") .. " " .. spinsWord(spinsAmount(prize))
	elseif kind == "Egg" then
		return tostring(prize.Icon or "🥚") .. " " .. tostring(prize.Name or (tostring(prize.Rarity) .. "-Ei"))
	end
	return tostring(prize.Icon or "💵") .. " " .. Util.FormatCash(cashAmount(prize, r))
end

-- -------------------------------------------------------------------
-- EIER & PREISE GUTSCHREIBEN
-- -------------------------------------------------------------------
-- Ei (Meteor) einer Seltenheit in die Base. Base voll / keine Base -> Geld statt Ei:
--   Gratis-Belohnung (Geschenk, Glücksrad): der Verkaufswert (Wert * Config.SellRatio) – sonst lohnt
--   es sich, die Base absichtlich voll zu lassen. opts.FullValue (Robux-Käufe): der volle Wert.
-- opts.Fixed = immer der günstigste Meteor der Seltenheit (z.B. Länder ohne Zufalls-Käufe)
-- opts.RandomMutation = Mutation würfeln (Gold, Frost ...), sonst "Normal"
-- Gibt (true, Text) zurück – false nur, wenn es die Seltenheit nicht gibt.
function RewardService.GiveEgg(
	player: Player,
	rarityName: string,
	opts: { Fixed: boolean?, RandomMutation: boolean?, FullValue: boolean? }?
): (boolean, string)
	local Meteor = Services.MeteorService
	local def = nil
	if opts and opts.Fixed then
		local list = Config.MeteorsByRarity[rarityName]
		if not list or #list == 0 then
			list = Config.MeteorsByRarityAll[rarityName]
		end
		def = list and list[1]
	else
		def = Meteor.RandomOfRarity(rarityName, true)
	end
	if not def then
		warn("[RewardService] Keine Meteore der Seltenheit " .. tostring(rarityName))
		return false, "???"
	end
	local mut = "Normal"
	if opts and opts.RandomMutation then
		mut = Meteor.RollMutation(1)
	end
	local entry = { Id = def.Id, Mut = Config.MutationsByName[mut] and mut or "Normal", Lv = 1 }
	local label = (entry.Mut ~= "Normal" and (entry.Mut .. " ") or "") .. def.Name .. " (" .. def.Rarity .. ")"
	if Services.EconomyService.GiveMeteor(player, entry, true) then
		return true, "🥚 " .. label .. " fliegt in deine Base!"
	end
	local ratio = if opts and opts.FullValue then 1 else Config.SellRatio
	local value = math.floor(Config.MeteorValue(entry) * ratio)
	Services.EconomyService.AddCash(player, value)
	return true, "📦 Base voll – du bekommst " .. Util.FormatCash(value) .. " statt " .. label
end

-- Schreibt einen Preis (Geschenk / Glücksrad) gut und gibt den Text zurück.
-- effects = fliegende Zahlen sofort zeigen (beim Glücksrad macht das der Client nach dem Drehen)
local function grantPrize(player: Player, data, prize, effects: boolean): string
	local Economy = Services.EconomyService
	local kind = prizeType(prize)
	local r = rates(player, data)
	if kind == "Steps" then
		local amount = stepsAmount(prize, r)
		Economy.AddSteps(player, amount) -- geschenkt, nicht gelaufen -> zählt nicht für "Lauf X Schritte"
		if effects then
			Economy.Effect(player, "Steps", amount)
		end
		return "+" .. Util.FormatNumber(amount) .. " Schritte 👟"
	elseif kind == "Spins" then
		local amount = spinsAmount(prize)
		RewardService.AddSpins(player, amount)
		return "+" .. spinsWord(amount) .. " 🎡"
	elseif kind == "Egg" then
		local ok, text = RewardService.GiveEgg(player, tostring(prize.Rarity), { RandomMutation = true })
		if ok then
			return text
		end
		-- Seltenheit gibt es nicht (Config geändert) -> kleines Cash-Geschenk statt nichts
	end
	local amount = cashAmount(prize, r)
	Economy.AddCash(player, amount)
	if effects then
		Economy.Effect(player, "Collect", amount)
	end
	return "+" .. Util.FormatCash(amount) .. " 💵"
end

function RewardService.AddSpins(player: Player, n: number): boolean
	local data = Services.DataService.Get(player)
	local amount = math.floor(tonumber(n) or 0)
	if not data or amount ~= amount or amount == 0 then
		return false
	end
	data.Spins = math.clamp((tonumber(data.Spins) or 0) + amount, 0, MAX_SPINS)
	markDirty(player)
	return true
end

-- -------------------------------------------------------------------
-- 📜 TAGESAUFGABEN
-- -------------------------------------------------------------------
local function questGoal(def, r: Rates): number
	if def.Scale == "Steps" then
		return math.max(QUEST_STEPS_MIN, roundNice(r.StepsPerSecond * QUEST_STEPS_SECONDS))
	elseif def.Scale == "Collect" then
		return math.max(QUEST_COLLECT_MIN, roundNice(r.Income * QUEST_COLLECT_SECONDS))
	end
	return def.Goals[rng:NextInteger(1, #def.Goals)]
end

local function questText(quest): string
	local def = QUEST_BY_ID[quest.Id]
	if not def then
		return "???"
	end
	local goal = def.Scale == "Collect" and Util.FormatCash(quest.Goal) or Util.FormatNumber(quest.Goal)
	return def.Text:format(goal)
end

local function questRewardCash(r: Rates): number
	return math.floor(math.max(QUEST_REWARD_MIN, r.Income * QUEST_REWARD_SECONDS))
end

local function questsValid(quests, day: string): boolean
	if type(quests) ~= "table" or quests.Day ~= day or type(quests.List) ~= "table" or #quests.List == 0 then
		return false
	end
	for _, quest in ipairs(quests.List) do
		local def = type(quest) == "table" and QUEST_BY_ID[quest.Id]
		if
			not def
			or quest.Kind ~= def.Kind
			or type(quest.Goal) ~= "number"
			or type(quest.Progress) ~= "number"
			or quest.Goal ~= quest.Goal
			or quest.Progress ~= quest.Progress
		then
			return false
		end
	end
	return true
end

-- 3 zufällige Aufgaben (verschiedene Arten, höchstens eine "mit anderen Spielern")
local function rollQuests(player: Player, data)
	local pool = table.clone(QUEST_POOL)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local r = rates(player, data)
	local list = {}
	local hasSocial = false
	for _, def in ipairs(pool) do
		if #list >= QUESTS_PER_DAY then
			break
		end
		if not (def.Social and hasSocial) then
			hasSocial = hasSocial or def.Social == true
			table.insert(list, {
				Id = def.Id,
				Kind = def.Kind,
				Goal = questGoal(def, r),
				Progress = 0,
				Claimed = false,
			})
		end
	end
	data.Quests = { Day = today(), List = list }
end

-- Neuer UTC-Tag (oder kaputte Daten) -> neue Aufgaben. Gibt true zurück, wenn neu gewürfelt wurde.
local function ensureQuests(player: Player, data): boolean
	local day = today()
	local quests = data.Quests
	if questsValid(quests, day) then
		return false
	end
	local hadOld = type(quests) == "table" and type(quests.Day) == "string" and quests.Day ~= ""
	rollQuests(player, data)
	if hadOld then
		notify(player, "📜 Neue Tagesaufgaben sind da!", "Info")
	end
	markDirty(player)
	return true
end

-- Fortschritt zählen: kind = "Grab" | "Steal" | "Hatch" | "Steps" | "Collect" | "Bonk"
function RewardService.Track(player: Player, kind: string, amount: number?)
	if not TRACK_KINDS[kind] then
		return
	end
	local n = tonumber(amount) or 1
	if n ~= n or n <= 0 or n == math.huge then
		return
	end
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	ensureQuests(player, data)
	for _, quest in ipairs(data.Quests.List) do
		if quest.Kind == kind and not quest.Claimed and quest.Progress < quest.Goal then
			quest.Progress = math.min(quest.Goal, quest.Progress + n)
			if quest.Progress >= quest.Goal then
				notify(
					player,
					"📜 Aufgabe geschafft: " .. questText(quest) .. " – hol dir die Belohnung! 🎁",
					"Success"
				)
			end
			markDirty(player)
		end
	end
end

function RewardService.ClaimQuest(player: Player, index: any): (boolean, string)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch... ⏳"
	end
	if ensureQuests(player, data) then
		return false, "📜 Neuer Tag – neue Aufgaben!"
	end
	local i = tonumber(index)
	local quest = i and data.Quests.List[i]
	if type(quest) ~= "table" then
		return false, "Unbekannte Aufgabe"
	end
	if quest.Claimed then
		return false, "✅ Schon abgeholt!"
	end
	if quest.Progress < quest.Goal then
		return false,
			"📜 Noch nicht geschafft ("
				.. Util.FormatNumber(quest.Progress)
				.. "/"
				.. Util.FormatNumber(quest.Goal)
				.. ")"
	end
	quest.Claimed = true
	local cash = questRewardCash(rates(player, data))
	Services.EconomyService.AddCash(player, cash)
	RewardService.AddSpins(player, QUEST_REWARD_SPINS)
	Services.EconomyService.Effect(player, "Collect", cash)
	Services.EconomyService.Effect(player, "Confetti", 1)
	markDirty(player)
	return true, "📜 Belohnung: +" .. Util.FormatCash(cash) .. " und +" .. spinsWord(QUEST_REWARD_SPINS) .. " 🎡!"
end

-- 🔄 Einmal pro Tag eine (noch nicht geschaffte) Aufgabe tauschen – z.B. "Bonk 3 Diebe" auf einem
-- leeren Server. Die neue Aufgabe braucht nie andere Spieler und ist von einer Art, die heute noch fehlt.
function RewardService.RerollQuest(player: Player, index: any): (boolean, string)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch... ⏳"
	end
	if ensureQuests(player, data) then
		return false, "📜 Neuer Tag – neue Aufgaben!"
	end
	local quests = data.Quests
	if quests.Rerolled == true then
		return false, "🔄 Heute schon getauscht – morgen wieder!"
	end
	local i = tonumber(index)
	local quest = i and quests.List[i]
	if type(quest) ~= "table" then
		return false, "Unbekannte Aufgabe"
	end
	if quest.Claimed or quest.Progress >= quest.Goal then
		return false, "✅ Die hast du schon geschafft!"
	end
	local used = {}
	for _, other in ipairs(quests.List) do
		used[other.Id] = true
	end
	local options = {}
	for _, def in ipairs(QUEST_POOL) do
		if not def.Social and not used[def.Id] then
			table.insert(options, def)
		end
	end
	if #options == 0 then
		return false, "🔄 Gerade keine andere Aufgabe frei"
	end
	local def = options[rng:NextInteger(1, #options)]
	local fresh = {
		Id = def.Id,
		Kind = def.Kind,
		Goal = questGoal(def, rates(player, data)),
		Progress = 0,
		Claimed = false,
	}
	quests.List[i] = fresh
	quests.Rerolled = true
	markDirty(player)
	return true, "🔄 Neue Aufgabe: " .. questText(fresh)
end

-- -------------------------------------------------------------------
-- 🎁 SPIELZEIT-GESCHENKE (Spielzeit von heute, siehe giftData)
-- -------------------------------------------------------------------
local function giftReadyIn(gifts: GiftData, gift): number
	return math.max(0, math.ceil((tonumber(gift.Minutes) or 0) * 60 - gifts.Seconds))
end

function RewardService.ClaimGift(player: Player, index: any): (boolean, string)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch... ⏳"
	end
	local i = tonumber(index)
	local gift = i and giftList()[i]
	if type(gift) ~= "table" or not i then
		return false, "Unbekanntes Geschenk"
	end
	local gifts = giftData(data)
	local key = tostring(i)
	if gifts.Claimed[key] then
		return false, "✅ Schon abgeholt!"
	end
	local remaining = giftReadyIn(gifts, gift)
	if remaining > 0 then
		return false, "⏳ Noch " .. Util.FormatTime(remaining) .. " spielen!"
	end
	gifts.Claimed[key] = true
	local text = grantPrize(player, data, gift, true)
	Services.EconomyService.Effect(player, "Confetti", 1)
	markDirty(player)
	return true, "🎁 Geschenk: " .. text
end

-- -------------------------------------------------------------------
-- 🎡 GLÜCKSRAD
-- -------------------------------------------------------------------
-- Sekunden bis zum nächsten Gratis-Dreh (0 = bereit)
function RewardService.FreeSpinIn(data): number
	local elapsed = math.max(0, os.time() - (tonumber(data.LastFreeSpin) or 0))
	return math.max(0, math.ceil(freeSpinPeriod() - elapsed))
end

-- Dreht das Rad: erst den Gratis-Dreh, sonst einen aus data.Spins.
-- Antwort-Extras für den Client: Segment = Feld (Index in Config.WheelPrizes), Prize = Feld-Text
function RewardService.Spin(player: Player): (boolean, string, { [string]: any }?)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch... ⏳", nil
	end
	local t = os.clock()
	if t - (lastSpin[player] or -math.huge) < SPIN_COOLDOWN then
		return false, "🎡 Das Rad dreht sich noch!", nil
	end
	local freeIn = RewardService.FreeSpinIn(data)
	local free = freeIn <= 0
	if not free and (tonumber(data.Spins) or 0) < 1 then
		return false, "🎡 Keine Drehs mehr! Gratis-Dreh in " .. Util.FormatTime(freeIn), nil
	end
	local prizes = wheelList()
	if #prizes == 0 then
		return false, "🎡 Das Glücksrad ist noch nicht eingerichtet", nil
	end
	local index = table.find(prizes, Util.WeightedPick(prizes, nil, rng)) or 1
	local prize = prizes[index]

	lastSpin[player] = t
	if free then
		data.LastFreeSpin = os.time()
		freeSpinNotified[player] = nil
	else
		data.Spins -= 1
	end
	local text = grantPrize(player, data, prize, false)
	markDirty(player)

	-- Großer Ei-Gewinn: allen ansagen, sobald das Rad beim Gewinner stehen geblieben ist
	local rarity = prizeType(prize) == "Egg" and Config.RarityIndex[prize.Rarity] or nil
	if rarity and rarity >= (Config.RarityIndex[SPIN_ANNOUNCE_RARITY] or math.huge) then
		local name = player.DisplayName
		task.delay(SPIN_REVEAL_DELAY, function()
			Services.EconomyService.NotifyAll(
				"🎡 " .. name .. " hat ein " .. tostring(prize.Rarity) .. "-Ei am Glücksrad gewonnen!",
				"Event"
			)
		end)
	end
	return true, "🎡 Gewonnen: " .. text, {
		Segment = index,
		Prize = prizeLabel(prize),
		Free = free,
	}
end

-- -------------------------------------------------------------------
-- DATEN AN DEN CLIENT (EconomyService ruft das bei jedem State auf)
--   Spins, FreeSpinIn, QuestReroll: klein -> immer
--   Gifts (+ GiftsAt), Quests: nur bei Änderung oder wenn full = true (alle ~20 s). Der Client behält
--   sonst die alten. ReadyIn gilt ab GiftsAt (Serverzeit) – so zählt der Client auch mit einem
--   älteren Paket richtig herunter.
-- -------------------------------------------------------------------
function RewardService.FillState(player: Player, data, state, full: boolean?)
	ensureQuests(player, data)
	local r = rates(player, data, state)
	local gifts = giftData(data)

	state.Spins = tonumber(data.Spins) or 0
	state.FreeSpinIn = RewardService.FreeSpinIn(data)
	state.QuestReroll = data.Quests.Rerolled ~= true -- heute noch eine Aufgabe tauschbar?

	local giftRows = {}
	local giftKey = { gifts.Day }
	for i, gift in ipairs(giftList()) do
		local claimed = gifts.Claimed[tostring(i)] == true
		local text = prizeText(gift, r)
		giftRows[i] = {
			Minutes = tonumber(gift.Minutes) or 0,
			Claimed = claimed,
			ReadyIn = giftReadyIn(gifts, gift),
			Text = text,
		}
		table.insert(giftKey, (if claimed then "1" else "0") .. text)
	end
	local giftSignature = table.concat(giftKey, "|")
	if full or sentGiftKey[player] ~= giftSignature then
		sentGiftKey[player] = giftSignature
		state.Gifts = giftRows
		state.GiftsAt = workspace:GetServerTimeNow()
	end

	local quests = {}
	local questKey = { data.Quests.Day }
	local rewardText = "💵 " .. Util.FormatCash(questRewardCash(r)) .. " + 🎡 " .. spinsWord(QUEST_REWARD_SPINS)
	for i, quest in ipairs(data.Quests.List) do
		local text = questText(quest)
		local claimed = quest.Claimed == true
		quests[i] = {
			Text = text,
			Kind = quest.Kind, -- z.B. "Collect" -> der Client zeigt den Fortschritt mit $
			Goal = quest.Goal,
			Progress = quest.Progress,
			Claimed = claimed,
			RewardText = rewardText,
		}
		table.insert(questKey, text .. "#" .. tostring(quest.Progress) .. (if claimed then "1" else "0"))
	end
	table.insert(questKey, rewardText)
	local questSignature = table.concat(questKey, "|")
	if full or sentQuestKey[player] ~= questSignature then
		sentQuestKey[player] = questSignature
		state.Quests = quests
	end
end

-- Jede Sekunde: Spielzeit hochzählen, "Geschenk bereit" / "Gratis-Dreh bereit" melden (je einmal)
local function tickPlayer(player: Player, dt: number)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local gifts = giftData(data)
	gifts.Seconds = math.min(MAX_GIFT_SECONDS, gifts.Seconds + dt)
	if sessionSeconds(player) < FIRST_NOTIFY_DELAY then
		return
	end
	local notified = notifiedGifts[player]
	if not notified or notifiedDay[player] ~= gifts.Day then
		notified = {} -- neuer Tag -> alle Geschenke wieder neu melden
		notifiedGifts[player] = notified
		notifiedDay[player] = gifts.Day
	end
	local ready = 0
	for i, gift in ipairs(giftList()) do
		if not notified[i] and not gifts.Claimed[tostring(i)] and giftReadyIn(gifts, gift) <= 0 then
			notified[i] = true
			ready += 1
		end
	end
	if ready > 0 then
		notify(player, "🎁 Ein Geschenk wartet auf dich! Klick auf 🎁 Geschenke.", "Success")
		markDirty(player)
	end
	if not freeSpinNotified[player] and RewardService.FreeSpinIn(data) <= 0 then
		freeSpinNotified[player] = true
		notify(player, "🎡 Gratis-Dreh bereit! Dreh am Glücksrad!", "Success")
		markDirty(player)
	end
end

function RewardService.Init(services)
	Services = services
end

function RewardService.Start()
	local function onPlayer(player: Player)
		joinedAt[player] = joinedAt[player] or os.clock()
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		joinedAt[player] = nil
		lastTick[player] = nil
		notifiedGifts[player] = nil
		notifiedDay[player] = nil
		freeSpinNotified[player] = nil
		lastSpin[player] = nil
		sentGiftKey[player] = nil
		sentQuestKey[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				if Services.EconomyService.IsReady(player) then
					-- echte vergangene Zeit (task.wait ist nie genau 1 s), nach Hängern gedeckelt
					local clock = os.clock()
					local dt = math.clamp(clock - (lastTick[player] or clock), 0, MAX_TICK)
					lastTick[player] = clock
					local ok, err = pcall(tickPlayer, player, dt)
					if not ok then
						warn("[RewardService] Fehler bei " .. player.Name .. ": " .. tostring(err))
					end
				end
			end
		end
	end)
end

return RewardService
