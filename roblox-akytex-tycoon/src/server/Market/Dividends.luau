--!strict
-- =====================================================================
--  AKYTEX TYCOON – Dividenden-Regeln (Server/Market/Dividends)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §6.3, §13 Nr. 7, §18.1; DESIGN.md §B6.1.
--  Zahler (DivBps > 0) schütten an ihrem Quartalstag ((Börsentag + Id) % 3 == 0) um :19 aus.
--  Betrag je Aktie = round(mid · DivBps / 10000) (mid OHNE diese Dividende, im Ex-Tick); im selben Tick fällt
--  der Kurs um genau diesen Betrag: E_i += ln(1 − div / mid) -> Dividenden-Mitnahme bringt nichts.
--  Anspruch = Bestand im Ex-Tick. Die Gutschrift ins Depot macht WP4 (Portfolio.Credit, Grund "Dividend",
--  Depot-Schreibtrichter §C11.4 Nr. 3) über MarketService.Dividends(t0, t1) – auch offline nachgerechnet.
--
--  Öffentliche API (rein, ohne Zustand)
--    Dividends.IsPayDay(id, day, everyDays): boolean
--    Dividends.ExTick(id, day, divBps, config): number?      Ex-Tick an diesem Börsentag oder nil
--    Dividends.PerShare(mid, bps): number                     Cent je Aktie (0 … mid − 1)
--    Dividends.LogDrop(mid, cents): number                    ln(1 − cents / mid) (≤ 0)
--    Dividends.Payout(perShare, qty): number                  Cent für einen Bestand (ganzzahlig)
-- =====================================================================

local Dividends = {}

function Dividends.IsPayDay(id: number, day: number, everyDays: number): boolean
	return (day + id) % math.max(1, everyDays) == 0
end

function Dividends.ExTick(id: number, day: number, divBps: number, config: { [string]: any }): number?
	if divBps <= 0 or not Dividends.IsPayDay(id, day, config.Earnings.EveryDays) then
		return nil
	end
	return day * config.DayTicks + config.Dividend.Minute * 60
end

function Dividends.PerShare(mid: number, bps: number): number
	if mid <= 1 or bps <= 0 then
		return 0
	end
	return math.clamp(math.round(mid * bps / 10000), 0, mid - 1)
end

function Dividends.LogDrop(mid: number, cents: number): number
	if mid <= 0 or cents <= 0 then
		return 0
	end
	return math.log(1 - math.min(cents, mid - 1) / mid)
end

function Dividends.Payout(perShare: number, qty: number): number
	if perShare <= 0 or qty <= 0 then
		return 0
	end
	return math.floor(perShare) * math.floor(qty)
end

return Dividends
