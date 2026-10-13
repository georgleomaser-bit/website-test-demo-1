--!strict
-- =====================================================================
--  AKYTEX TYCOON – Fill-Audit & Ausreißer (Server/Market/MarketAudit)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §13 Nr. 17, DESIGN.md §C11.2 ("Engine-Fehler"), §B15.2 (Statistik).
--  Jeder Fill wird gegen den deterministischen Kurs nachgerechnet:
--    Sofort-Order (Type "MKT", wenn bekannt): Kauf == Brief(t), Verkauf == Geld(t) – exakt.
--    sonst (Limit/Stopp/Ziel/OCO/Nachzieh-Stopp/Bots): Px liegt in [L − hs, H + hs] der 1s-Kerze von t
--    (jede regelkonforme Ausführung inkl. Kurslücke liegt in diesem Band, MARKET §11.3).
--  Tages-G/V-Ausreißer: z > 6 gegenüber den eigenen letzten Börsentagen (≥ 6 Werte) -> "verdächtig" im
--  Admin-Panel. KEINE automatische Strafe. Alles nur im Speicher, je Spieler bei PlayerRemoving geleert.
--
--  Öffentliche API (nur WP3)
--    MarketAudit.VerifyFill(fill, ctx): boolean    fill = { I, Side, Px, Tick, Q?, Type? }
--                                                  ctx = { CandleAt(i, t) -> (O, H, L, C), Quote(i, t) -> (bid, ask) }
--    MarketAudit.NoteDay(userId, day, ret)         MarketAudit.Clear(userId)
--    MarketAudit.Stats(): { Checked, Failed, Recent = { … }, Suspicious = { … } }
-- =====================================================================

local MarketAudit = {}

local MAX_RECENT = 20
local MAX_SUSPICIOUS = 50
local MAX_DAYS = 30
local MIN_DAYS = 6
local Z_LIMIT = 6
local MIN_STD = 0.005

type Plain = { [string]: any }

local checked = 0
local failed = 0
local recent: { Plain } = {}
local suspicious: { Plain } = {}
local days: { [number]: { number } } = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function push(list: { Plain }, entry: Plain, limit: number)
	table.insert(list, entry)
	while #list > limit do
		table.remove(list, 1)
	end
end

function MarketAudit.VerifyFill(fill: Plain, ctx: Plain): boolean
	if type(fill) ~= "table" then
		return false
	end
	local i, px, t, side = fill.I, fill.Px, fill.Tick, fill.Side
	if not finite(i) or not finite(px) or not finite(t) or (side ~= "B" and side ~= "S") then
		return true -- unvollständige Meldung: nichts zu prüfen (kein Fehlalarm)
	end
	checked += 1
	local ok = true
	local reason = ""
	local okCandle, _open, h, l = pcall(ctx.CandleAt, i, t)
	local okQuote, bid, ask = pcall(ctx.Quote, i, t)
	if not okCandle or not okQuote or not finite(h) or not finite(l) or not finite(bid) or not finite(ask) then
		return true -- Kurs nicht berechenbar (z. B. Instrument noch nicht gelistet): kein Urteil
	end
	local hs = math.max((ask :: number) - (bid :: number), 0)
	if fill.Type == "MKT" then
		local expected = if side == "B" then ask else bid
		if px ~= expected then
			ok = false
			reason = ("MKT %s erwartet %s, bekommen %s"):format(side, tostring(expected), tostring(px))
		end
	else
		local lo = (l :: number) - hs - 1
		local hi = (h :: number) + hs + 1
		if px < lo or px > hi then
			ok = false
			reason = ("Px %s außerhalb [%s, %s]"):format(tostring(px), tostring(lo), tostring(hi))
		end
	end
	if not ok then
		failed += 1
		push(recent, {
			I = i,
			Tick = t,
			Side = side,
			Px = px,
			Q = fill.Q,
			Reason = reason,
			At = os.time(),
		}, MAX_RECENT)
		warn("[MarketAudit] Abweichung: " .. reason .. " (Inst " .. tostring(i) .. ", Tick " .. tostring(t) .. ")")
	end
	return ok
end

function MarketAudit.NoteDay(userId: number, day: number, ret: number)
	if not finite(userId) or not finite(ret) then
		return
	end
	local list = days[userId]
	if list == nil then
		list = {}
		days[userId] = list
	end
	local n = #list
	if n >= MIN_DAYS then
		local sum, sq = 0, 0
		for _, r in ipairs(list) do
			sum += r
			sq += r * r
		end
		local mean = sum / n
		local std = math.max(MIN_STD, math.sqrt(math.max(0, sq / n - mean * mean)))
		local z = (ret - mean) / std
		if z > Z_LIMIT then
			push(suspicious, {
				UserId = userId,
				Day = day,
				Return = ret,
				Z = math.round(z * 10) / 10,
				At = os.time(),
			}, MAX_SUSPICIOUS)
		end
	end
	table.insert(list, ret)
	while #list > MAX_DAYS do
		table.remove(list, 1)
	end
end

function MarketAudit.Clear(userId: number)
	days[userId] = nil
end

function MarketAudit.Stats(): Plain
	local recentCopy: { Plain } = table.clone(recent)
	local suspiciousCopy: { Plain } = table.clone(suspicious)
	return { Checked = checked, Failed = failed, Recent = recentCopy, Suspicious = suspiciousCopy }
end

return MarketAudit
