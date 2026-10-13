--!strict
-- =====================================================================
--  AKYTEX TYCOON – Ein Frame für alle (Server/Market/QuoteStream)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §10.2/§10.3, DESIGN.md §C8 (MarketFrame), §C16 (0,44 KB/s).
--  Je Markt-Takt genau EIN FireAllClients(buffer) mit dem neuesten Tick: 9 + 10·n Byte (43 Instrumente = 439 B,
--  mit 4 IPOs 479 B). Absolute Kurse (keine Deltas) -> ein verlorener Frame zerstört nichts.
--  Angst-&-Gier-Index, Heatmap, Ticker-Wände rechnet jeder Client selbst aus dem Frame.
--
--  Öffentliche API (nur WP3)
--    QuoteStream.Build(tick, src): (buffer, number)    src = { Ids, Candle(i), Halted(i), News(i), ExDay(i),
--                                                       WeekHigh(i), Regime, AnyHalt, Admin, Crash, Rally }
--    QuoteStream.Broadcast(remote, tick, src): number   kodiert einmal, feuert einmal; Rückgabe: Byte
--    QuoteStream.LastSize(): number
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuoteCodec = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Market"):WaitForChild("QuoteCodec"))

local QuoteStream = {}

local FRAME = QuoteCodec.FRAME_FLAGS
local ROW = QuoteCodec.ROW_FLAGS

local lastSize = 0

export type Source = {
	Ids: { number },
	Candle: (i: number) -> (number?, number?, number?, number?, number?, number?, number?),
	Halted: (i: number) -> boolean,
	News: (i: number) -> boolean,
	ExDay: (i: number) -> boolean,
	WeekHigh: (i: number) -> number,
	Regime: number,
	AnyHalt: boolean,
	Admin: boolean,
	Crash: boolean,
	Rally: boolean,
}

function QuoteStream.Build(tick: number, src: Source): (buffer, number)
	local rows: { QuoteCodec.QuoteRow } = {}
	for _, i in ipairs(src.Ids) do
		local _, _, _, c, v, hiOff, loOff = src.Candle(i)
		if c and c > 0 then
			local flags = 0
			if src.Halted(i) then
				flags += ROW.Halt
			end
			if src.News(i) then
				flags += ROW.News
			end
			if src.ExDay(i) then
				flags += ROW.ExDay
			end
			local high = src.WeekHigh(i)
			if high > 0 and c >= high then
				flags += ROW.WeekHigh
			end
			table.insert(rows, {
				Id = i,
				Flags = flags,
				Close = c,
				HiOff = hiOff or 0,
				LoOff = loOff or 0,
				Vol = v or 0,
			})
		end
	end
	local frameFlags = 0
	if src.AnyHalt then
		frameFlags += FRAME.Halt
	end
	if src.Admin then
		frameFlags += FRAME.Admin
	end
	if src.Crash then
		frameFlags += FRAME.Crash
	end
	if src.Rally then
		frameFlags += FRAME.Rally
	end
	local buf = QuoteCodec.EncodeFrame(tick, frameFlags, src.Regime, rows)
	return buf, #rows
end

function QuoteStream.Broadcast(remote: RemoteEvent?, tick: number, src: Source): number
	local buf = QuoteStream.Build(tick, src)
	lastSize = buffer.len(buf)
	if remote then
		remote:FireAllClients(buf)
	end
	return lastSize
end

function QuoteStream.LastSize(): number
	return lastSize
end

return QuoteStream
