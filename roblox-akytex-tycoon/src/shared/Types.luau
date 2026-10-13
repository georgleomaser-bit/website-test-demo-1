--!strict
-- =====================================================================
--  AKYTEX TYCOON – Gemeinsame Typen (Shared/Types)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C4 (vollständig – alle Pakete annotieren damit).
--  Reines Typ-Modul: gibt eine leere Tabelle zurück, enthält nur "export type".
--  Benutzung:  local Types = require(Shared:WaitForChild("Types"))   ->   Types.Reply, Types.Depot, …
--
--  Abschnitte: Basis · Gewährung (nur Turm-Seite) · Markt · Fortschritt · Turm · Welt/Events
--  Geldbeträge: AKY immer in ganzzahligen Cent, CR ganzzahlig, nie ≥ 9e15 (Config.Server.MaxMoney).
-- =====================================================================

-- ---------------------------------------------------------------------
-- BASIS
-- ---------------------------------------------------------------------
export type Lang = "de" | "en"
export type NotifyKind = "Info" | "Success" | "Error" | "Event" | "Alarm" | "Announce"
export type Reply = { Ok: boolean, Message: string?, [string]: any }
export type PlayerData = { [string]: any } -- Schema §C12
export type LangPair = { de: string, en: string }
export type AssetSlot = { MeshId: number, TextureId: number, Scale: number, Offset: CFrame }

-- ---------------------------------------------------------------------
-- GEWÄHRUNG (nur Turm-Seite! Felder aus Config.Shop.ForbiddenRobuxFields werden bei Robux-Quellen entfernt)
-- ---------------------------------------------------------------------
export type Grant = {
	Credits: number?,
	Cars: { string }?,
	Watches: { string }?,
	Accessories: { string }?,
	Decor: { [string]: number }?,
	Cosmetics: { string }?,
	Titles: { string }?,
	BoostX2: number?,
	BoostX5: number?,
	ExpressTokens: number?,
	InstantTokens: number?,
	SeasonPremium: boolean?,
	SeasonTiers: number?,
	SeasonXp: number?,
}

-- ---------------------------------------------------------------------
-- MARKT
-- ---------------------------------------------------------------------
export type Side = "B" | "S"
export type OrderType = "MKT" | "LMT" | "STP" | "TP" | "OCO" | "TRL"
export type Timeframe = "1s" | "5s" | "1m" | "5m" | "15m" | "1T" | "1W"
export type RiskClass = "Stabil" | "Normal" | "Wild" | "ETF"
export type InstSet = "Azubi" | "Trader" | "Fonds" | "Tutorial"
export type Instrument = {
	Id: number,
	Ticker: string,
	Name: string,
	Story: LangPair,
	Sector: string,
	Class: RiskClass,
	Start: number, -- Cent
	DivBps: number,
	Set: InstSet,
	Logo: { Letter: string, Shape: "Circle" | "Square" | "Hex" | "Diamond" },
	Ipo: boolean?,
}
export type QuoteRow = { Id: number, Flags: number, Close: number, HiOff: number, LoOff: number, Vol: number }
export type Frame = { Version: number, Tick: number, Flags: number, Regime: number, Rows: { QuoteRow } }
export type Candle = { T: number, O: number, H: number, L: number, C: number, V: number } -- Cent, Volumen in 10er-Lots
export type Position = { Q: number, C: number, R: number }
export type Order = {
	Id: number,
	I: number,
	Side: Side,
	Type: OrderType,
	Q: number,
	Lim: number?,
	Stp: number?,
	Tp: number?,
	Trl: number?,
	Peak: number?,
	Oco: number?,
	Res: number,
	Exp: number,
	T0: number,
	Bot: number?,
}
export type Alert = { Id: number, I: number, Px: number, Dir: "Up" | "Down" }
export type BotSlot = { Preset: string, Pct: number, Target: number?, On: boolean, Paused: boolean, DayNav: number }
export type DepotStats = {
	Trades: number,
	Wins: number,
	Losses: number,
	GrossWin: number,
	GrossLoss: number,
	PeakNav: number,
	MaxDD: number,
	BestPct: number,
	ReadWell: number,
}
export type Depot = {
	V: number,
	Cash: number,
	Basis: number,
	Pos: { [string]: Position },
	Short: { [string]: any },
	Orders: { Order },
	Alerts: { Alert },
	Watch: { { number } },
	Fills: { { number } },
	Nav: { { number } },
	Seq: { number },
	NextId: number,
	LastTick: number,
	LastTransferDay: number,
	LastRefillUtcDay: number,
	AutoTransfer: boolean,
	Bots: { BotSlot },
	Stats: DepotStats,
	Tutorial: { T0: number, Q: number, Done: boolean },
}
export type NewsKind =
	"Fact"
	| "Rumor"
	| "Confirm"
	| "Deny"
	| "AsExpected"
	| "Sector"
	| "Macro"
	| "Earnings"
	| "Dividend"
	| "Warn"
	| "Crash"
	| "Rally"
	| "Ipo"
	| "Admin"
	| "Halt"
	| "Resume"
export type NewsItem = {
	Id: number,
	T: number,
	Kind: NewsKind,
	I: number?,
	Sector: string?,
	Key: string,
	Args: { [string]: any },
	Band: number?,
	Stars: number?,
	Dir: number?,
	Text: LangPair?, -- Text nur bei Admin-Eilmeldung (gefiltert)
}
export type CalendarItem = {
	T: number,
	Kind: "Earnings" | "Macro" | "Dividend" | "Crash" | "Rally" | "Ipo",
	I: number?,
	Key: string,
}
export type MarketEvent = {
	Id: string,
	Kind: "Crash" | "Rally" | "Pump" | "Dump" | "Halt" | "Resume" | "Ipo" | "News" | "Vol" | "Normalize" | "CancelAutoShow",
	Scope: "All" | "Sector" | "Inst",
	Target: (number | string)?,
	Strength: number,
	Ramp: number,
	Decay: number,
	StartTick: number,
	Until: number,
	Text: LangPair?,
	By: number,
}
export type FillInfo = {
	I: number,
	Side: Side,
	Q: number,
	Px: number,
	Fee: number,
	Pnl: number?,
	HeldS: number?,
	PctNav: number,
	Protected: boolean,
	ReadWell: boolean,
	Bot: boolean,
	Tick: number,
}
export type DayResult = { Day: number, Return: number, Trades: number, Qualifying: boolean, Tainted: boolean }
export type LeagueStats = {
	Week: number,
	SkillScore: number,
	AvgDailyBp: number,
	Trades: number,
	Days: number,
	Tainted: boolean,
	Qualified: boolean,
}

-- ---------------------------------------------------------------------
-- FORTSCHRITT
-- ---------------------------------------------------------------------
export type Licence = {
	Key: string,
	Name: LangPair,
	Xp: number,
	Exam: { string },
	Basis: number,
	BauKurs: number,
	TowerBonus: number,
	FeeBps: number,
	MaxWeight: number,
	MaxOrders: number,
	PosFactor: number,
	Layer: "Simple" | "Trader" | "Pro",
	Set: InstSet,
	MaxStage: number,
	MaxIpo: number,
	BotSlots: number,
}
export type TradingPerks = {
	Licence: number,
	Layer: string,
	BotSlots: number,
	BotLevels: { [string]: number },
	Alerts: number,
	Watchlists: number,
	Layouts: number,
	Monitors: number,
	ResearchLead: number,
	MultiChart: boolean,
	Risk: number,
	Indicators: { [string]: boolean },
}

-- ---------------------------------------------------------------------
-- TURM
-- ---------------------------------------------------------------------
export type FloorData = { R: string, L: number, S: { string }, D: { string } }
export type MultPart = {
	Key: string,
	Value: number,
	Group: "Perm" | "Trader" | "Pass" | "Fixed" | "Timed",
	Source: "Earned" | "Skill" | "Bought" | "Event",
	Until: number?,
}
export type IncomeInfo = { PerSec: number, Steady: number, Mult: number, Parts: { MultPart } }

-- ---------------------------------------------------------------------
-- WELT / EVENTS
-- ---------------------------------------------------------------------
export type PickupToken = { Id: number, Kind: string, Pos: Vector3, Until: number }
export type EventState = {
	Kind: string,
	Started: number,
	Until: number,
	Scope: "Local" | "Global",
	Data: { [string]: any }?,
}

return {}
