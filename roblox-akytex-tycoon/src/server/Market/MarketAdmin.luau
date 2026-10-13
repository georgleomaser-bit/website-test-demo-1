--!strict
-- =====================================================================
--  AKYTEX TYCOON – Admin-Markt-Aktionen prüfen & klemmen (Server/Market/MarketAdmin)
--  Besitzer: WP3 (Markt-Engine). Vertrag: DESIGN.md §B15.3 (Admin-Abuse-Katalog), §B10.4 (CancelAutoShow),
--  MARKET.md §17. Aufruf nur über MarketService.Admin (dort: Besitzer-Prüfung, 3-s-Abklingzeit, Textfilter, Bus).
--  Markt-Events wirken IMMER global (GlobalBus), klingen IMMER ab und öffnen ein Admin-Fenster (Liga-Taint).
--
--  Aktionen (action = Types.MarketEvent.Kind) und Argumente (alles geklemmt; Prozent 5…50 werden als 0,05…0,5 gelesen,
--  Abklingen ≤ 60 als Minuten):
--    "Crash" / "Rally"   { Scope = "All"|"Sector"|"Inst", Target?, Strength 0,05…0,5, Ramp 30…300 s, Decay 5…60 min,
--                          Warn = true (nur Crash: 3-min-Warnung) }
--    "Pump" / "Dump"     { Target = Firmen-Id, Strength, Ramp?, Decay? }
--    "News"              { Scope = "Inst"|"Sector", Target, Band 1…4, Dir +1/−1, Text = { de, en } oder Text (≤ 80) }
--    "Halt"              { Scope = "All"|"Inst", Target?, Seconds 10…600 }      "Resume" { Scope?, Target? }
--    "Ipo"               { Target = IPO-Id aus der aktuellen Pipeline }  -> Erstnotiz in 10 min
--    "Vol"               { Strength = ×0,5…×3, Seconds 300…1800 (oder Minutes 5…30) }
--    "Normalize"         {}                     "CancelAutoShow" { Target? = Woche }
--  Alias-Schlüssel: I = Target, Sector = Target (bei Scope Sector), Pct = Strength.
--
--  Öffentliche API (nur WP3)
--    MarketAdmin.Build(action, args, ctx): (BusEvent?, string?)   Fehler = Lang-Schlüssel "mkt.admin.*"
--      ctx = { Now: number, ById: { [id]: Instrument }, Listed: (id) -> boolean (handelt jetzt),
--              Taken: (id) -> boolean (IPO gelistet oder angesetzt), InPipeline: (id) -> boolean,
--              Week: number, By: number, NewId: () -> string }
--    MarketAdmin.PRICE_KINDS   Kinds, die Kurse bewegen (sagen die Samstags-Show ab)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MarketAdmin = {}

type Plain = { [string]: any }

MarketAdmin.PRICE_KINDS = { Crash = true, Rally = true, Pump = true, Dump = true, News = true, Vol = true, Ipo = true }

local SECTORS = { T = true, E = true, M = true, K = true, G = true, F = true }
local MAX_ARG_KEYS = 12

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function numberArg(args: Plain, ...: string): number?
	for index = 1, select("#", ...) do
		local value = args[select(index, ...)]
		if finite(value) then
			return value
		end
	end
	return nil
end

local function strength(args: Plain, lo: number, hi: number, default: number): number
	local v = numberArg(args, "Strength", "Pct") or default
	if v > 1 then
		v /= 100 -- 5 … 50 (Prozent) -> 0,05 … 0,5
	end
	return math.clamp(v, lo, hi)
end

local function seconds(value: number?, lo: number, hi: number, default: number, minutesBelow: number?): number
	local v = value or default
	if minutesBelow and v <= minutesBelow then
		v *= 60
	end
	return math.clamp(math.floor(v), lo, hi)
end

local function isStock(ctx: Plain, id: any): boolean
	if not finite(id) or id % 1 ~= 0 then
		return false
	end
	local inst = ctx.ById[id]
	return type(inst) == "table" and inst.Class ~= "ETF" and inst.Set ~= "Tutorial" and ctx.Listed(id)
end

-- Ziel bestimmen: { Scope, Target } oder nil
local function scopeOf(args: Plain, ctx: Plain, allowAll: boolean): (string?, (number | string)?)
	local scope = args.Scope
	local target = if args.Target ~= nil then args.Target elseif args.I ~= nil then args.I else args.Sector
	if scope == nil then
		if type(target) == "string" then
			scope = "Sector"
		elseif target ~= nil then
			scope = "Inst"
		else
			scope = "All"
		end
	end
	if scope == "All" then
		return if allowAll then "All" else nil, nil
	elseif scope == "Sector" then
		if type(target) == "string" and SECTORS[target] then
			return "Sector", target
		end
		return nil, nil
	elseif scope == "Inst" then
		if isStock(ctx, target) then
			return "Inst", target
		end
		return nil, nil
	end
	return nil, nil
end

local function textPair(raw: any): { de: string, en: string }?
	local maxChars = ((Config.Market :: any).Admin.NewsMaxChars or 80) :: number
	local function cut(text: any): string?
		if type(text) ~= "string" then
			return nil
		end
		local clean = string.gsub(text, "[%c]", " ")
		clean = string.gsub(clean, "^%s+", "")
		clean = string.gsub(clean, "%s+$", "")
		if clean == "" then
			return nil
		end
		local len = utf8.len(clean)
		if len == nil then
			return nil -- kaputtes UTF-8
		end
		if len > maxChars then
			local stop = utf8.offset(clean, maxChars + 1)
			clean = string.sub(clean, 1, (stop or (#clean + 1)) - 1)
		end
		return clean
	end
	if type(raw) == "string" then
		local text = cut(raw)
		return if text then { de = text, en = text } else nil
	elseif type(raw) == "table" then
		local de, en = cut(raw.de), cut(raw.en)
		if de or en then
			return { de = de or en or "", en = en or de or "" }
		end
	end
	return nil
end

function MarketAdmin.Build(action: string, args: any, ctx: Plain): (Plain?, string?)
	local market: any = Config.Market
	local admin = market.Admin
	local a: Plain = if type(args) == "table" then args else {}
	local keys = 0
	for _ in pairs(a) do
		keys += 1
		if keys > MAX_ARG_KEYS then
			return nil, "mkt.admin.badArgs"
		end
	end
	local now = ctx.Now
	local start = now + admin.Lead
	local ev: Plain = {
		Id = ctx.NewId(),
		Kind = action,
		Scope = "All",
		Target = nil,
		Strength = 0,
		Ramp = admin.Ramp[1],
		Decay = admin.Decay[1],
		StartTick = start,
		Until = start,
		Text = nil,
		By = ctx.By,
		Warn = 0,
	}
	if action == "Crash" or action == "Rally" or action == "Pump" or action == "Dump" then
		local isMove = action == "Pump" or action == "Dump"
		local scope, target = scopeOf(a, ctx, not isMove)
		if scope == nil or (isMove and scope ~= "Inst") then
			return nil, "mkt.admin.badArgs"
		end
		ev.Scope, ev.Target = scope, target
		ev.Strength = strength(a, admin.Strength[1], admin.Strength[2], 0.2)
		ev.Ramp = seconds(numberArg(a, "Ramp"), admin.Ramp[1], admin.Ramp[2], 60)
		ev.Decay = seconds(numberArg(a, "Decay"), admin.Decay[1], admin.Decay[2], 900, 60)
		ev.Warn = if action == "Crash" and a.Warn == true then admin.WarnSeconds else 0
		local span = ev.Warn + ev.Ramp + ev.Decay
		if span > admin.MaxSpan then
			ev.Decay = math.max(admin.Decay[1] // 2, admin.MaxSpan - ev.Warn - ev.Ramp)
		end
		ev.Until = start + ev.Warn + ev.Ramp + ev.Decay
	elseif action == "News" then
		local scope, target = scopeOf(a, ctx, false)
		if scope == nil then
			return nil, "mkt.admin.badArgs"
		end
		local text = textPair(a.Text)
		if text == nil then
			return nil, "mkt.admin.badArgs"
		end
		ev.Scope, ev.Target = scope, target
		ev.Band = math.clamp(math.floor(numberArg(a, "Band") or 2), 1, 4)
		ev.Dir = if (numberArg(a, "Dir") or 1) < 0 then -1 else 1
		ev.Text = text
		ev.Until = start + market.Delay + market.Tau + admin.NewsDecay
	elseif action == "Halt" then
		local scope, target = scopeOf(a, ctx, true)
		if scope == nil or scope == "Sector" then
			return nil, "mkt.admin.badArgs"
		end
		ev.Scope, ev.Target = scope, target
		local secs = numberArg(a, "Seconds")
		local minutes = numberArg(a, "Minutes")
		if secs == nil and minutes then
			secs = minutes * 60
		end
		ev.Until = start + seconds(secs, admin.HaltSeconds[1], admin.HaltSeconds[2], 60)
	elseif action == "Resume" then
		local scope, target = scopeOf(a, ctx, true)
		if scope == nil or scope == "Sector" then
			return nil, "mkt.admin.badArgs"
		end
		ev.Scope, ev.Target = scope, target
		ev.Until = start
	elseif action == "Ipo" then
		local id = if a.Target ~= nil then a.Target else a.I
		if not finite(id) or id % 1 ~= 0 then
			return nil, "mkt.admin.ipoUnknown"
		end
		if not ctx.InPipeline(id) then
			return nil, "mkt.admin.ipoUnknown"
		end
		if ctx.Listed(id) or (type(ctx.Taken) == "function" and ctx.Taken(id)) then
			return nil, "mkt.admin.ipoListed"
		end
		ev.Scope, ev.Target = "Inst", id
		ev.Until = now + market.IpoPipeline.AdminLead
	elseif action == "Vol" then
		local mult = numberArg(a, "Strength", "Mult") or 2
		ev.Strength = math.clamp(mult, admin.Vol[1], admin.Vol[2])
		local secs = numberArg(a, "Seconds")
		local minutes = numberArg(a, "Minutes")
		if secs == nil and minutes then
			secs = minutes * 60
		end
		ev.Until = start + seconds(secs, admin.VolSeconds[1], admin.VolSeconds[2], 600)
	elseif action == "Normalize" then
		ev.Until = start + admin.NormalizeSeconds
	elseif action == "CancelAutoShow" then
		local week = numberArg(a, "Target", "Week") or ctx.Week
		ev.Target = math.floor(week)
		ev.Until = start
	else
		return nil, "mkt.admin.unknown"
	end
	return ev, nil
end

return MarketAdmin
