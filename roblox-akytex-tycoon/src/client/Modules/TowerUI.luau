-- =====================================================================
--  AKYTEX TYCOON – Tower-Menü (Client/Modules/TowerUI)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §D WP8 (Tower-Menü: Etage bauen,
--  Abteilungen mit Nachbar-Pfeilen, Personal, Stufen, Effizienz, Deko-Slots, Fassade/Name/Privat, Börsengang-
--  Vorschau-Einstieg, Gewinn-Transfer-Knopf), §B4 (Regeln/Kosten aus Shared/TowerMath = Server-Rechnung),
--  §B5.3 (Effizienz), §B8.2 (Gewinn-Transfer: Verfügbar → CR zum Bau-Kurs der Lizenz), §B9.6 (Vorschau ab Stufe 7),
--  §B4.10 (Besuche, Privat-Etagen), §C7.3 (Fenster "Tower"), §C7.2 (feuert Hooks "Tower:Built"/"Tower:Stage" aus
--  dem State-Diff).
--
--  Alles Wertvolle entscheidet der Server (Requests Tower*); das Menü zeigt nur, was der State sagt, und schickt
--  Absichten. Kosten werden mit denselben Formeln angezeigt (TowerMath + State.Tower.CostFactor/CostEvent).
--
--  Öffentliche API (§C7.5):
--    TowerUI.Open(tab?)       tab ∈ "Overview" | "Floors" | "Staff" | "Facade" | "Visit"
--  Ergänzungen: TowerUI.Close() · TowerUI.SelectFloor(floor) · TowerUI.Init(ctx) · TowerUI.Start()
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerMath = require(Shared:WaitForChild("TowerMath"))

local TowerUI = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local WINDOW_W, WINDOW_H = 780, 600
local TABS = { "Overview", "Floors", "Staff", "Facade", "Visit" }
local REFRESH_GAP = 0.25
local CONFIRM_SECONDS = 3

local ctx: any = nil
local window: any = nil
local tabs: any = nil
local body: Frame? = nil
local tab = "Overview"
local pendingTab: string? = nil
local selectedFloor = 1
local decorPick: { Floor: number, Slot: number }? = nil
local confirmFire: { Key: string, Until: number }? = nil
local builtLang = ""
local lastSig = ""
local refreshQueued = false
local lastRefresh = 0
local lastFloors: number? = nil
local lastStage: number? = nil
local nameDraft: { A: number, N: number }? = nil
local autoPlan: { string }? = nil
local liveLabels: { [string]: TextLabel } = {}
local liveBars: { [string]: any } = {}

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function credits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, lang())
	return if ok then text else tostring(math.floor(n))
end

local function aky(cents: number): string
	local ok, text = pcall(ctx.Format.Aky, cents, lang(), true)
	return if ok then text else tostring(math.floor(cents / 100))
end

local function duration(seconds: number): string
	local ok, text = pcall(ctx.Format.Duration, math.max(0, seconds), lang())
	return if ok then text else tostring(math.floor(seconds))
end

local function mult(x: number): string
	local ok, text = pcall(ctx.Format.Mult, x, lang())
	return if ok then text else string.format("x%.2f", x)
end

local function pick(pair: any): string
	return ctx.Lang.Pick(lang(), pair)
end

local function tower(): { [string]: any }
	local t = ctx.State.Tower
	return if type(t) == "table" then t else {}
end

local function income(): { [string]: any }
	local i = ctx.State.Income
	return if type(i) == "table" then i else {}
end

local function towerCfg(): { [string]: any }
	local cfg = ctx.Config.Tower
	return if type(cfg) == "table" then cfg else {}
end

local function decorCfg(): { [string]: any }
	local cfg = ctx.Config.Decor
	return if type(cfg) == "table" then cfg else {}
end

local function byKey(list: any, key: string): any
	if type(list) ~= "table" then
		return nil
	end
	for _, entry in ipairs(list) do
		if type(entry) == "table" and entry.Key == key then
			return entry
		end
	end
	return nil
end

local function stageName(stage: number): string
	local list = towerCfg().Stages
	local entry = if type(list) == "table" then list[stage] else nil
	return if type(entry) == "table" then pick(entry.Name) else tostring(stage)
end

local function roomName(key: string): string
	local entry = byKey(towerCfg().Rooms, key)
	return if entry then pick(entry.Name) else key
end

local function staffName(key: string): string
	local entry = byKey(towerCfg().Staff, key)
	return if entry then pick(entry.Name) else key
end

local function decorName(key: string): string
	local entry = decorCfg().ByKey and decorCfg().ByKey[key]
	return if type(entry) == "table" then pick(entry.Name) else key
end

local function licenceName(index: number): string
	local progression = ctx.Config.Progression
	local list = if type(progression) == "table" then progression.Licences else nil
	local entry = if type(list) == "table" then list[index] else nil
	if type(entry) == "table" and type(entry.Name) == "table" then
		return pick(entry.Name)
	end
	return T("tui.licenceLevel", index)
end

local function bauKurs(): number
	local prog = ctx.State.Prog
	local licence = if type(prog) == "table" then math.floor(num(prog.Licence, 1)) else 1
	local progression = ctx.Config.Progression
	local list = if type(progression) == "table" then progression.Licences else nil
	if type(list) ~= "table" then
		local trading = ctx.Config.Trading
		list = if type(trading) == "table" then trading.LicenceFallback else nil
	end
	local entry = if type(list) == "table" then list[licence] else nil
	return if type(entry) == "table" then num(entry.BauKurs, 40) else 40
end

local function hasPass(key: string): boolean
	local passes = ctx.State.Passes
	return type(passes) == "table" and passes[key] == true
end

-- Anfrage im Hintergrund (Toast bei Meldung kommt aus ctx.RequestFull)
local function Request(action: string, arg: any?)
	task.spawn(function()
		local okCall, result = pcall(ctx.RequestFull, action, arg)
		local reply = if okCall and type(result) == "table" then result else { Ok = false }
		if reply.Ok then
			call("Sfx", "Play", "UIClick")
		end
		if action == "TowerAutoPlan" and reply.Ok and type(reply.Plan) == "table" then
			autoPlan = reply.Plan
			lastSig = ""
			TowerUI.Refresh()
		end
	end)
end

local function costFactor(kind: string?): number
	local t = tower()
	local factor = num(t.CostFactor, 1)
	local event = t.CostEvent
	if kind and type(event) == "table" then
		factor *= num(event[kind], 1)
	end
	return math.clamp(factor, 0, 1)
end

local function comfortCtx(): any
	local items = decorCfg().ByKey
	return {
		Comfort = function(key: string): number
			local entry = if type(items) == "table" then items[key] else nil
			return if type(entry) == "table" then num(entry.Comfort, 0) else 0
		end,
	}
end

-- ---------------------------------------------------------------------
-- 2) BAUSTEINE
-- ---------------------------------------------------------------------
local function card(parent: Instance, order: number, color: Color3?): Frame
	local frame = UI.Card({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		Parent = frame,
	})
	UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = frame })
	if color then
		UI.Create("Frame", {
			Name = "Accent",
			Position = UDim2.new(0, -14, 0, -10),
			Size = UDim2.new(0, 3, 0, 22),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = frame,
		})
	end
	return frame
end

local function text(parent: Instance, value: string, order: number, opts: { [string]: any }?): TextLabel
	local props: { [string]: any } = {
		Size = UDim2.new(1, 0, 0, 22),
		Text = value,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text2,
		MaxText = 16,
		LayoutOrder = order,
		Parent = parent,
	}
	if opts then
		for k, v in pairs(opts) do
			props[k] = v
		end
	end
	return UI.Label(props)
end

local function heading(parent: Instance, value: string, order: number): TextLabel
	return text(
		parent,
		value,
		order,
		{ Face = "Display", TextColor3 = Theme.Text, MaxText = 18, Size = UDim2.new(1, 0, 0, 26) }
	)
end

local function button(
	parent: Instance,
	label: string,
	variant: string,
	order: number,
	onClick: () -> (),
	width: number?
): any
	return UI.Button({
		Size = UDim2.fromOffset(width or 170, 38),
		Text = label,
		Variant = variant,
		MaxText = 16,
		LayoutOrder = order,
		Corner = 10,
		Parent = parent,
	}, onClick)
end

local function row(parent: Instance, order: number, height: number?): Frame
	return UI.Row(parent, order, height or 40)
end

-- ---------------------------------------------------------------------
-- 3) ÜBERSICHT
-- ---------------------------------------------------------------------
local function buildOverview(parent: Frame)
	local t = tower()
	local inc = income()
	local floors = math.floor(num(t.Floors, 0))
	local stage = math.floor(num(t.Stage, 1))
	-- Kennzahlen
	local tiles = UI.Grid(parent, 1, 172, 64)
	local s1 = UI.StatTile(tiles, T("tui.stat.stage"), 1)
	s1.Text = ("%d · %s"):format(stage, stageName(stage))
	local s2 = UI.StatTile(tiles, T("tui.stat.floors"), 2)
	s2.Text = ("%d / %d"):format(floors, math.floor(num(towerCfg().Floors, 50)))
	local s3 = UI.StatTile(tiles, T("tui.stat.income"), 3)
	s3.Text = T("tui.perSec", credits(num(inc.PerSec, 0)))
	liveLabels.Income = s3
	local s4 = UI.StatTile(tiles, T("tui.stat.mult"), 4)
	s4.Text = mult(num(inc.Mult, 1))
	-- Bauen
	local build = if type(t.Build) == "table" then t.Build else {}
	local nextInfo = if type(t.Next) == "table" then t.Next else {}
	local buildCard = card(parent, 2, Theme.Accent)
	heading(buildCard, T("tui.build.title"), 1)
	if build.Floor ~= nil then
		local now = workspace:GetServerTimeNow()
		local total = math.max(1, num(build.Total, 1))
		local remaining = math.max(0, num(build.Until, now) - now)
		text(buildCard, T("tui.build.running", build.Floor, duration(remaining)), 2, { TextColor3 = Theme.Text })
		local bar = UI.Bar({ Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3, Parent = buildCard, Color = Theme.Warn })
		UI.SetBar(bar, 1 - remaining / total, duration(remaining))
		liveBars.Build = bar
		if num(build.Helpers, 0) > 0 then
			text(buildCard, T("tui.build.helpers", build.Helpers), 4)
		end
		local tokens = if type(t.Tokens) == "table" then t.Tokens else {}
		local actions = row(buildCard, 5)
		button(actions, T("tui.build.instant", math.floor(num(tokens.Instant, 0))), "Secondary", 1, function()
			Request("TowerInstant", {})
		end, 210)
		button(actions, T("tui.build.express", math.floor(num(tokens.Express, 0))), "Secondary", 2, function()
			Request("TowerExpress", {})
		end, 210)
	elseif nextInfo.Locked then
		local reason = nextInfo.Locked
		local message: string
		if reason == "tower.gateLicence" then
			message = T(
				reason,
				stageName(math.floor(num(nextInfo.Stage, stage))),
				licenceName(math.floor(num(nextInfo.Licence, 1)))
			)
		elseif reason == "tower.gateIpo" then
			message = T(reason, stageName(math.floor(num(nextInfo.Stage, stage))), math.floor(num(nextInfo.Ipo, 1)))
		else
			message = T(tostring(reason))
		end
		text(buildCard, message, 2, { TextColor3 = Theme.Warn })
		button(buildCard, T("tui.build.locked"), "Muted", 3, function()
			ctx.Toast(message, "Info")
		end, 240)
	else
		local floor = math.floor(num(nextInfo.Floor, floors + 1))
		text(buildCard, T("tui.build.next", floor, credits(num(nextInfo.Cost, 0))), 2, { TextColor3 = Theme.Text })
		text(buildCard, T("tui.build.gain", credits(num(nextInfo.Income, 0)), duration(num(nextInfo.Seconds, 0))), 3)
		local nextStage = math.floor(num(nextInfo.Stage, stage))
		if nextStage > stage then
			text(buildCard, T("tui.build.stageUp", stageName(nextStage)), 4, { TextColor3 = Theme.Gold })
		end
		button(buildCard, UI.Upper(T("tui.build")), "Primary", 5, function()
			Request("TowerBuild", {})
		end, 240)
	end
	-- Tresor
	local vaultCard = card(parent, 3, Theme.Gold)
	heading(vaultCard, T("tui.vault.title"), 1)
	local cap = math.max(1, num(t.VaultCap, 1))
	local vault = num(t.Vault, 0)
	local vbar = UI.Bar({
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 2,
		Parent = vaultCard,
		Color = if vault >= cap then Theme.Down else Theme.Gold,
	})
	UI.SetBar(vbar, vault / cap, ("%s / %s"):format(credits(vault), credits(cap)))
	liveBars.Vault = vbar
	local vrow = row(vaultCard, 3)
	button(vrow, T("tui.vault.collect"), "Success", 1, function()
		Request("TowerCollect", {})
	end)
	text(vrow, T("tui.vault.hint"), 2, { Size = UDim2.new(1, -190, 1, 0), MaxText = 14 })
	-- Gewinn-Transfer (AKY -> CR zum Bau-Kurs; nie umgekehrt)
	local depot = ctx.State.Depot
	local transferCard = card(parent, 4, Theme.Up)
	heading(transferCard, T("tui.transfer.title"), 1)
	if type(depot) == "table" then
		local cents = math.floor(num(depot.Withdrawable, 0))
		local rate = bauKurs()
		local gain = math.floor(cents / 100 * rate)
		if depot.TransferReady == true and cents > 0 then
			text(
				transferCard,
				T("trade.transferAvail", aky(cents), credits(gain), credits(rate)),
				2,
				{ TextColor3 = Theme.Text }
			)
			button(transferCard, T("trade.transferButton"), "Success", 3, function()
				Request("TowerTransfer", {})
			end, 240)
		else
			text(transferCard, T("trade.transferLocked"), 2)
			text(transferCard, T("tui.transfer.hint", credits(rate)), 3, { MaxText = 14 })
		end
	else
		text(transferCard, T("tui.loading"), 2)
	end
	-- Effizienz (§B5.3)
	local eff = math.floor(num(t.Eff, 0))
	local effMax = math.floor(num(type(towerCfg().Efficiency) == "table" and towerCfg().Efficiency.Max or nil, 20))
	local effCard = card(parent, 5, Theme.Purple)
	heading(effCard, T("tui.eff.title", eff, effMax), 1)
	if eff < effMax then
		text(effCard, T("tui.eff.next", credits(num(t.EffCost, 0))), 2)
		button(effCard, T("tui.eff.buy"), "Primary", 3, function()
			Request("TowerEfficiency", {})
		end)
	else
		text(effCard, T("tui.eff.max"), 2, { TextColor3 = Theme.Up })
	end
	-- Aktionen
	local actions = card(parent, 6)
	heading(actions, T("tui.more"), 1)
	local grid = UI.Grid(actions, 2, 170, 38)
	button(grid, T("tui.autoPlan"), "Secondary", 1, function()
		Request("TowerAutoPlan", {})
	end)
	button(grid, T("tui.boutique"), "Secondary", 2, function()
		local opened = call("Boutique", "Open", "Decor")
		if not opened and ctx.Windows then
			ctx.Windows.Open("Boutique")
		end
	end)
	button(grid, T("tui.future.button"), "Secondary", 3, function()
		call("WelcomeBack", "ShowFuture")
	end)
	if stage >= 7 then
		button(grid, T("tui.ipoPreview"), "Premium", 4, function()
			local ok = call("Prestige", "OpenPreview")
			if not ok then
				ctx.Toast(T("tui.notReady"), "Info")
			end
		end)
	end
	if autoPlan then
		local planCard = card(parent, 7, Theme.Cyan)
		heading(planCard, T("tui.autoPlanTitle"), 1)
		local list = t.List
		local changes = 0
		for i, key in ipairs(autoPlan) do
			local current = if type(list) == "table" and type(list[i]) == "table" then list[i].R else nil
			if current ~= key and changes < 12 then
				changes += 1
				text(planCard, T("tui.autoPlanRow", i, roomName(tostring(current)), roomName(key)), 1 + changes)
			end
		end
		if changes == 0 then
			text(planCard, T("tower.autoPlanNone"), 2)
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) ETAGEN (Abteilung, Stufe, Personal, Deko, Privat, Nachbar-Pfeile)
-- ---------------------------------------------------------------------
-- Nachbar-Wirkungen auf Etage i (§B4.3): Labor ±1 ×1,15, Café ±2 Personal ×1,2, Server-Räume Personal ×1,1 je Raum
local function neighbourChips(list: { any }, i: number): { { Text: string, Color: Color3 } }
	local chips: { { Text: string, Color: Color3 } } = {}
	local rooms = towerCfg().Rooms
	local function room(index: number): any
		local f = list[index]
		return if type(f) == "table" then byKey(rooms, f.R) else nil
	end
	for _, d in ipairs({ -1, 1 }) do
		local r = room(i + d)
		if r and type(r.NeighbourMult) == "number" then
			chips[#chips + 1] = {
				Text = ("%s %s %s"):format(if d < 0 then "▼" else "▲", roomName(r.Key), mult(r.NeighbourMult)),
				Color = Theme.Cyan,
			}
		end
	end
	local floor = list[i]
	if type(floor) == "table" and type(floor.S) == "table" and #floor.S > 0 then
		for d = -2, 2 do
			local r = room(i + d)
			if d ~= 0 and r and type(r.StaffMult) == "number" then
				chips[#chips + 1] = {
					Text = ("%s %s %s"):format(if d < 0 then "▼" else "▲", T("tui.staffBoost"), mult(r.StaffMult)),
					Color = Theme.Orange,
				}
				break
			end
		end
	end
	return chips
end

local function floorIncome(list: { any }, i: number): number
	local ok, value = pcall(TowerMath.FloorIncomeAt, list :: any, i, comfortCtx())
	return if ok and type(value) == "number" then value else 0
end

local function decorSlotsOf(roomKey: string): number
	local room = byKey(towerCfg().Rooms, roomKey)
	if room and type(room.DecorSlots) == "number" then
		return math.floor(num(decorCfg().PenthouseSlots, room.DecorSlots))
	end
	return math.floor(num(decorCfg().SlotsPerFloor, 3))
end

local function buildFloorDetail(parent: Frame, list: { any }, i: number)
	local t = tower()
	local floor = list[i]
	if type(floor) ~= "table" then
		return
	end
	local stage = math.floor(num(t.Stage, 1))
	local detail = card(parent, 1, Theme.Accent)
	heading(detail, T("tui.floor.title", i, roomName(floor.R), math.floor(num(floor.L, 1))), 1)
	text(detail, T("tui.floor.income", credits(floorIncome(list, i))), 2, { TextColor3 = Theme.Up })
	local chips = neighbourChips(list, i)
	if #chips > 0 then
		local chipRow = row(detail, 3, 26)
		for _, chip in ipairs(chips) do
			UI.Chip(chipRow, chip.Text, chip.Color)
		end
	end
	-- Aktionen: Stufe, Privat, Hinfahren
	local actions = row(detail, 4)
	local level = math.floor(num(floor.L, 1))
	if level < 5 then
		local cost = TowerMath.Discount(TowerMath.LevelCost(i, level), costFactor("RoomLevel"))
		button(actions, T("tui.floor.levelUp", level + 1, credits(cost)), "Primary", 1, function()
			Request("TowerLevel", { Floor = i })
		end, 230)
	else
		button(actions, T("tower.levelMax"), "Muted", 1, function() end, 230)
	end
	local private = type(t.Private) == "table" and table.find(t.Private, i) ~= nil
	button(actions, if private then T("tui.floor.public") else T("tui.floor.private"), "Secondary", 2, function()
		Request("TowerPrivate", { Floor = i, On = not private })
	end, 160)
	button(actions, T("tui.floor.goto"), "Ghost", 3, function()
		call("Elevator", "Go", i)
	end, 150)
	-- Abteilungen
	text(detail, T("tui.floor.rooms", credits(TowerMath.RoomChangeCost(i))), 5, { TextColor3 = Theme.Text })
	local roomGrid = UI.Grid(detail, 6, 136, 52)
	for order, room in ipairs(if type(towerCfg().Rooms) == "table" then towerCfg().Rooms else {}) do
		local locked = stage < num(room.MinStage, 1)
		local topOnly = room.TopOnly == true and i ~= #list
		local current = room.Key == floor.R
		local variant = if current then "Primary" elseif locked or topOnly then "Muted" else "Secondary"
		UI.Button({
			Size = UDim2.fromOffset(136, 52),
			Text = pick(room.Name),
			Sub = if locked
				then T("tui.fromStage", room.MinStage)
				elseif topOnly then T("tui.topOnly")
				else mult(num(room.Factor, 1)),
			Variant = variant,
			MaxText = 14,
			SubMax = 12,
			Corner = 10,
			LayoutOrder = order,
			Parent = roomGrid,
		}, function()
			if current then
				return
			end
			Request("TowerRoom", { Floor = i, Room = room.Key })
		end)
	end
	-- Personal
	local slots = math.floor(num(t.StaffSlots, 2))
	local staffList = if type(floor.S) == "table" then floor.S else {}
	text(detail, T("tui.floor.staff", #staffList, slots), 7, { TextColor3 = Theme.Text })
	local staffBox = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 8,
		Parent = detail,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }) })
	for slotIndex, key in ipairs(staffList) do
		local staffRow = row(staffBox, slotIndex, 38)
		local entry = byKey(towerCfg().Staff, key)
		text(
			staffRow,
			("🤖 %s  +%d %%"):format(staffName(key), math.floor(num(entry and entry.Bonus, 0) * 100 + 0.5)),
			1,
			{
				Size = UDim2.new(1, -170, 1, 0),
				TextColor3 = Theme.Text,
			}
		)
		local confirmKey = ("%d:%d"):format(i, slotIndex)
		local armed = confirmFire ~= nil and confirmFire.Key == confirmKey and os.clock() < confirmFire.Until
		button(
			staffRow,
			if armed then T("tui.fireConfirm") else T("tui.fire"),
			if armed then "Danger" else "Ghost",
			2,
			function()
				if armed then
					confirmFire = nil
					Request("TowerFire", { Floor = i, Slot = slotIndex })
				else
					confirmFire = { Key = confirmKey, Until = os.clock() + CONFIRM_SECONDS }
					lastSig = ""
					TowerUI.Refresh()
				end
			end,
			150
		)
	end
	if #staffList < slots then
		local hireGrid = UI.Grid(detail, 9, 172, 52)
		for order, staff in ipairs(if type(towerCfg().Staff) == "table" then towerCfg().Staff else {}) do
			if not staff.Lobby then
				local locked = stage < num(staff.MinStage, 1)
				local cost = TowerMath.Discount(TowerMath.StaffCost(i, staff.Key), costFactor(nil))
				UI.Button({
					Size = UDim2.fromOffset(172, 52),
					Text = pick(staff.Name),
					Sub = if locked
						then T("tui.fromStage", staff.MinStage)
						else ("+%d %% · %s"):format(math.floor(num(staff.Bonus, 0) * 100 + 0.5), credits(cost)),
					Variant = if locked then "Muted" else "Secondary",
					MaxText = 14,
					SubMax = 12,
					Corner = 10,
					LayoutOrder = order,
					Parent = hireGrid,
				}, function()
					Request("TowerHire", { Floor = i, Staff = staff.Key })
				end)
			end
		end
	elseif
		slots < math.floor(num(towerCfg().StaffSlotsPlus, 3))
		and not hasPass(tostring(towerCfg().StaffPass or "StaffPlus"))
	then
		local hint = row(detail, 9, 38)
		text(hint, T("tui.staffPlus"), 1, { Size = UDim2.new(1, -150, 1, 0), MaxText = 14 })
		button(hint, T("tui.view"), "Premium", 2, function()
			call("Shop", "Open", tostring(towerCfg().StaffPass or "StaffPlus")) -- direkt die Pass-Details
		end, 130)
	end
	-- Deko-Plätze
	local slotsDecor = decorSlotsOf(floor.R)
	local decorList = if type(floor.D) == "table" then floor.D else {}
	text(detail, T("tui.floor.decor", slotsDecor), 10, { TextColor3 = Theme.Text })
	local decorGrid = UI.Grid(detail, 11, 172, 52)
	for slot = 1, slotsDecor do
		local key = decorList[slot]
		local filled = type(key) == "string" and key ~= ""
		UI.Button({
			Size = UDim2.fromOffset(172, 52),
			Text = if filled then decorName(key) else T("tui.decor.empty"),
			Sub = if filled then T("tui.decor.remove") else T("tui.decor.place"),
			Variant = if filled then "Secondary" else "Muted",
			MaxText = 14,
			SubMax = 12,
			Corner = 10,
			LayoutOrder = slot,
			Parent = decorGrid,
		}, function()
			if filled then
				Request("TowerDecor", { Floor = i, Slot = slot })
			else
				decorPick = { Floor = i, Slot = slot }
				lastSig = ""
				TowerUI.Refresh()
			end
		end)
	end
	-- Auswahl aus dem Lager
	local pickInfo = decorPick
	if pickInfo and pickInfo.Floor == i then
		local storage = ctx.State.Storage
		local decor = if type(storage) == "table" and type(storage.Decor) == "table" then storage.Decor else {}
		local keys: { string } = {}
		for key, count in pairs(decor) do
			if type(count) == "number" and count > 0 then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a, b)
			return decorName(a) < decorName(b)
		end)
		local pickCard = card(detail, 12, Theme.Warn)
		heading(pickCard, T("tui.decor.pick", pickInfo.Slot), 1)
		if #keys == 0 then
			text(pickCard, T("tui.decor.none"), 2)
			button(pickCard, T("tui.boutique"), "Primary", 3, function()
				local opened = call("Boutique", "Open", "Decor")
				if not opened and ctx.Windows then
					ctx.Windows.Open("Boutique")
				end
			end)
		else
			local pickGrid = UI.Grid(pickCard, 2, 172, 52)
			for order, key in ipairs(keys) do
				if order > 40 then
					break
				end
				local entry = decorCfg().ByKey and decorCfg().ByKey[key]
				UI.Button({
					Size = UDim2.fromOffset(172, 52),
					Text = decorName(key),
					Sub = T("tui.decor.count", decor[key], if type(entry) == "table" then num(entry.Comfort, 0) else 0),
					Variant = "Secondary",
					MaxText = 14,
					SubMax = 12,
					Corner = 10,
					LayoutOrder = order,
					Parent = pickGrid,
				}, function()
					decorPick = nil
					Request("TowerDecor", { Floor = pickInfo.Floor, Slot = pickInfo.Slot, Key = key })
				end)
			end
		end
	end
end

local function buildFloors(parent: Frame)
	local t = tower()
	local list = if type(t.List) == "table" then t.List else {}
	if #list == 0 then
		text(parent, T("tui.noFloors"), 1)
		return
	end
	selectedFloor = math.clamp(selectedFloor, 1, #list)
	buildFloorDetail(parent, list, selectedFloor)
	local listCard = card(parent, 2)
	heading(listCard, T("tui.floors.all"), 1)
	local private = if type(t.Private) == "table" then t.Private else {}
	for i = #list, 1, -1 do
		local floor = list[i]
		if type(floor) == "table" then
			local selected = i == selectedFloor
			local rowCard = UI.RowCard(listCard, 1 + (#list - i + 1), 44)
			if selected then
				rowCard.BackgroundColor3 = Theme.Hover
				UI.Create("UIStroke", { Color = Theme.Accent, Thickness = 1, Parent = rowCard })
			end
			local staff = if type(floor.S) == "table" then #floor.S else 0
			local decorCount = 0
			if type(floor.D) == "table" then
				for _, key in ipairs(floor.D) do
					if type(key) == "string" and key ~= "" then
						decorCount += 1
					end
				end
			end
			local lock = if table.find(private, i) then "🔒 " else ""
			UI.Label({
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(0.6, -12, 1, 0),
				Text = ("%s%d · %s · L%d"):format(lock, i, roomName(floor.R), math.floor(num(floor.L, 1))),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxText = 15,
				Parent = rowCard,
			})
			UI.Label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(0.4, -12, 1, 0),
				Text = ("🤖 %d  ✦ %d  %s"):format(
					staff,
					decorCount,
					T("tui.perSec", credits(floorIncome(list, i)))
				),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = Theme.Text2,
				Face = "Mono",
				MaxText = 14,
				Parent = rowCard,
			})
			local hit: TextButton = UI.Create("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = 3,
				Parent = rowCard,
			})
			hit.Activated:Connect(function()
				selectedFloor = i
				decorPick = nil
				lastSig = ""
				TowerUI.Refresh()
				local content = window and window.Content
				if content then
					content.CanvasPosition = Vector2.zero
				end
			end)
		end
	end
end

-- ---------------------------------------------------------------------
-- 5) PERSONAL (Lobby-Roboter, Übersicht, Personal+)
-- ---------------------------------------------------------------------
local function buildStaff(parent: Frame)
	local t = tower()
	local stage = math.floor(num(t.Stage, 1))
	local lobby = card(parent, 1, Theme.Warn)
	heading(lobby, T("tui.lobby.title"), 1)
	for order, key in ipairs({ "Janitor", "Security" }) do
		local entry = byKey(towerCfg().Staff, key)
		if entry then
			local hired = t[key] == true
			local r = row(lobby, 1 + order, 46)
			text(r, ("%s – %s"):format(pick(entry.Name), pick(entry.Desc)), 1, {
				Size = UDim2.new(1, -190, 1, 0),
				TextColor3 = Theme.Text,
				MaxText = 14,
				TextWrapped = true,
			})
			if hired then
				local confirmKey = "0:" .. order
				local armed = confirmFire ~= nil and confirmFire.Key == confirmKey and os.clock() < confirmFire.Until
				button(
					r,
					if armed then T("tui.fireConfirm") else T("tui.fire"),
					if armed then "Danger" else "Ghost",
					2,
					function()
						if armed then
							confirmFire = nil
							Request("TowerFire", { Floor = 0, Slot = order })
						else
							confirmFire = { Key = confirmKey, Until = os.clock() + CONFIRM_SECONDS }
							lastSig = ""
							TowerUI.Refresh()
						end
					end,
					170
				)
			elseif stage < num(entry.MinStage, 1) then
				button(r, T("tui.fromStage", entry.MinStage), "Muted", 2, function() end, 170)
			else
				local cost = TowerMath.Discount(TowerMath.StaffCost(0, key), costFactor(nil))
				button(
					r,
					if cost > 0 then T("tui.hireFor", credits(cost)) else T("tui.hireFree"),
					"Primary",
					2,
					function()
						Request("TowerHire", { Floor = 0, Staff = key })
					end,
					170
				)
			end
		end
	end
	-- Übersicht je Personal-Art
	local counts: { [string]: number } = {}
	local list = if type(t.List) == "table" then t.List else {}
	for _, floor in ipairs(list) do
		if type(floor) == "table" and type(floor.S) == "table" then
			for _, key in ipairs(floor.S) do
				counts[key] = (counts[key] or 0) + 1
			end
		end
	end
	local summary = card(parent, 2, Theme.Accent)
	heading(summary, T("tui.staff.summary"), 1)
	for order, staff in ipairs(if type(towerCfg().Staff) == "table" then towerCfg().Staff else {}) do
		if not staff.Lobby then
			text(
				summary,
				("%s: %d  ·  +%d %%"):format(
					pick(staff.Name),
					counts[staff.Key] or 0,
					math.floor(num(staff.Bonus, 0) * 100 + 0.5)
				),
				1 + order,
				{
					TextColor3 = if (counts[staff.Key] or 0) > 0 then Theme.Text else Theme.Muted,
				}
			)
		end
	end
	text(summary, T("tui.staff.hint"), 20, { MaxText = 14 })
	if math.floor(num(t.StaffSlots, 2)) < math.floor(num(towerCfg().StaffSlotsPlus, 3)) then
		local hint = row(summary, 21, 38)
		text(hint, T("tui.staffPlus"), 1, { Size = UDim2.new(1, -150, 1, 0), MaxText = 14 })
		button(hint, T("tui.view"), "Premium", 2, function()
			call("Shop", "Open", tostring(towerCfg().StaffPass or "StaffPlus")) -- direkt die Pass-Details
		end, 130)
	end
end

-- ---------------------------------------------------------------------
-- 6) FASSADE, NEON, KRONE, NAME, LAYOUT
-- ---------------------------------------------------------------------
local function buildFacade(parent: Frame)
	local t = tower()
	local skins = card(parent, 1, Theme.Accent)
	heading(skins, T("tui.facade.skins"), 1)
	local skinGrid = UI.Grid(skins, 2, 172, 52)
	for order, skin in ipairs(if type(towerCfg().Skins) == "table" then towerCfg().Skins else {}) do
		local current = t.Skin == skin.Key
		local hint = if skin.Unlock == "Pass"
			then (if hasPass(tostring(skin.Pass)) then T("tui.owned") else T("tui.facade.pass"))
			elseif skin.Unlock == "Default" then T("tui.owned")
			else T("tui.skinHint." .. skin.Key)
		UI.Button({
			Size = UDim2.fromOffset(172, 52),
			Text = pick(skin.Name),
			Sub = if current then T("tui.active") else hint,
			Variant = if current then "Primary" else "Secondary",
			MaxText = 14,
			SubMax = 11,
			Corner = 10,
			LayoutOrder = order,
			Parent = skinGrid,
		}, function()
			if current then
				return
			end
			if skin.Unlock == "Pass" and not hasPass(tostring(skin.Pass)) then
				call("Shop", "Open", if type(skin.Pass) == "string" then skin.Pass else "Passes")
				return
			end
			Request("TowerSkin", { Skin = skin.Key })
		end)
	end
	-- Neon-Farben
	local neonCard = card(parent, 2, Theme.Cyan)
	heading(neonCard, T("tui.facade.neon"), 1)
	local neonGrid = UI.Grid(neonCard, 2, 120, 40)
	for order, neon in ipairs(if type(towerCfg().Neon) == "table" then towerCfg().Neon else {}) do
		local current = t.Neon == neon.Key
		local ok, color = pcall(Color3.fromHex, neon.Hex)
		local btn = UI.Button({
			Size = UDim2.fromOffset(120, 40),
			Text = pick(neon.Name),
			Color = if ok then color else Theme.Accent,
			Variant = if current then nil else "Custom",
			MaxText = 13,
			Corner = 10,
			LayoutOrder = order,
			Parent = neonGrid,
		}, function()
			if not current then
				Request("TowerNeon", { Color = neon.Key })
			end
		end)
		if current then
			UI.Create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = btn.Frame })
		end
	end
	-- Börsengang-Krone
	local crownCard = card(parent, 3, Theme.Gold)
	heading(crownCard, T("tui.facade.crown"), 1)
	local crownEntry = byKey(towerCfg().Crowns, tostring(t.Crown or ""))
	text(
		crownCard,
		if crownEntry then pick(crownEntry.Name) else T("tui.facade.noCrown"),
		2,
		{ TextColor3 = Theme.Text }
	)
	-- Tower-Name aus Wortbausteinen (§B4.9, kein Freitext)
	local names = towerCfg().Names
	if type(names) == "table" and type(names.Adj) == "table" and type(names.Noun) == "table" then
		local nameCard = card(parent, 4, Theme.Purple)
		heading(nameCard, T("tui.facade.name"), 1)
		local current = if type(t.Name) == "table" then t.Name else { A = 1, N = 1 }
		local draft = nameDraft or { A = math.floor(num(current.A, 1)), N = math.floor(num(current.N, 1)) }
		nameDraft = draft
		local adjOptions: { string } = {}
		for _, pair in ipairs(names.Adj) do
			table.insert(adjOptions, pick(pair))
		end
		local nounOptions: { string } = {}
		for _, pair in ipairs(names.Noun) do
			table.insert(nounOptions, pick(pair))
		end
		local preview = text(
			nameCard,
			"",
			2,
			{ Face = "Display", TextColor3 = Theme.Accent, MaxText = 18, Size = UDim2.new(1, 0, 0, 28) }
		)
		local function updatePreview()
			local fn = towerCfg().NameText
			if type(fn) == "function" then
				local ok, value = pcall(fn, draft.A, draft.N, lang())
				preview.Text = if ok then value else ""
			end
		end
		updatePreview()
		local cyclerRow = row(nameCard, 3, 40)
		local adj = UI.Cycler(cyclerRow, T("tui.facade.adj"), adjOptions, UDim2.fromOffset(250, 38))
		adj.Set(adjOptions[draft.A])
		adj.OnChange = function(value: string?)
			draft.A = (value and table.find(adjOptions, value)) or 1
			updatePreview()
		end
		local noun = UI.Cycler(cyclerRow, T("tui.facade.noun"), nounOptions, UDim2.fromOffset(250, 38))
		noun.Set(nounOptions[draft.N])
		noun.OnChange = function(value: string?)
			draft.N = (value and table.find(nounOptions, value)) or 1
			updatePreview()
		end
		button(nameCard, T("tui.facade.apply"), "Primary", 4, function()
			Request("TowerName", { A = draft.A, N = draft.N })
		end)
	end
	-- Layout merken (Börsengang) + Privat-Info
	local layoutCard = card(parent, 5)
	heading(layoutCard, T("tui.facade.layout"), 1)
	local keep = t.KeepLayout ~= false
	local r = row(layoutCard, 2, 40)
	text(r, T("tui.facade.layoutHint"), 1, { Size = UDim2.new(1, -150, 1, 0), MaxText = 14 })
	button(r, if keep then T("tui.on") else T("tui.off"), if keep then "Success" else "Secondary", 2, function()
		Request("TowerLayout", { On = not keep })
	end, 130)
	local privateCount = if type(t.Private) == "table" then #t.Private else 0
	text(layoutCard, T("tui.facade.private", privateCount, math.floor(num(towerCfg().PrivateMax, 5))), 3)
end

-- ---------------------------------------------------------------------
-- 7) BESUCHE (Liste nach Höhe, §B4.10)
-- ---------------------------------------------------------------------
local function buildVisit(parent: Frame)
	local listCard = card(parent, 1, Theme.Accent)
	heading(listCard, T("tui.visit.title"), 1)
	local ok, plotList = call("TowerView", "Plots")
	local entries: { { [string]: any } } = {}
	if ok and type(plotList) == "table" then
		for _, plot in ipairs(plotList) do
			local okInfo, info = call("TowerView", "PlotInfo", plot)
			if okInfo and type(info) == "table" and num(info.Owner, 0) > 0 then
				table.insert(entries, info)
			end
		end
	end
	table.sort(entries, function(a, b)
		return num(a.Floors, 0) > num(b.Floors, 0)
	end)
	if #entries == 0 then
		text(listCard, T("tui.visit.none"), 2)
	end
	for order, info in ipairs(entries) do
		local mine = info.Owner == player.UserId
		local r = UI.RowCard(listCard, 1 + order, 50)
		UI.Label({
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -200, 0, 22),
			Text = ("%s%s"):format(tostring(info.OwnerName or "?"), if mine then T("tui.visit.you") else ""),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 16,
			Parent = r,
		})
		UI.Label({
			Position = UDim2.fromOffset(12, 26),
			Size = UDim2.new(1, -200, 0, 18),
			Text = ("%s · %s · %s"):format(
				tostring(info.TowerName or ""),
				T("tui.floorsShort", num(info.Floors, 0)),
				stageName(math.floor(num(info.Stage, 1)))
			),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Text2,
			MaxText = 13,
			Parent = r,
		})
		local actions = UI.RowActions(r, 170)
		button(
			actions,
			if mine then T("tui.visit.home") else T("tui.visit.go"),
			if mine then "Secondary" else "Primary",
			1,
			function()
				if mine then
					Request("TowerHome", {})
				else
					Request("TowerVisit", { UserId = info.Owner })
				end
				if ctx.Windows then
					ctx.Windows.Close("Tower")
				end
			end,
			160
		)
	end
end

-- ---------------------------------------------------------------------
-- 8) FENSTER, REFRESH, HOOKS
-- ---------------------------------------------------------------------
local function signature(): string
	local t = tower()
	local parts: { string } = { tab, tostring(selectedFloor), lang() }
	for _, key in ipairs({
		"Floors",
		"Stage",
		"Eff",
		"EffCost",
		"Skin",
		"Neon",
		"Crown",
		"StaffSlots",
		"Janitor",
		"Security",
		"KeepLayout",
	}) do
		table.insert(parts, tostring(t[key]))
	end
	local build = t.Build
	table.insert(
		parts,
		if type(build) == "table"
			then tostring(build.Floor) .. "/" .. tostring(build.Until) .. "/" .. tostring(build.Helpers)
			else "-"
	)
	local nextInfo = t.Next
	table.insert(parts, if type(nextInfo) == "table" then tostring(nextInfo.Cost) .. tostring(nextInfo.Locked) else "-")
	local tokens = t.Tokens
	table.insert(
		parts,
		if type(tokens) == "table" then tostring(tokens.Instant) .. "/" .. tostring(tokens.Express) else "-"
	)
	local list = t.List
	if type(list) == "table" then
		for _, floor in ipairs(list) do
			if type(floor) == "table" then
				table.insert(
					parts,
					("%s%s%s%s"):format(
						tostring(floor.R),
						tostring(floor.L),
						table.concat(floor.S or {}, ","),
						table.concat(floor.D or {}, ",")
					)
				)
			end
		end
	end
	if type(t.Private) == "table" then
		table.insert(parts, table.concat(t.Private, ","))
	end
	if type(t.Name) == "table" then
		table.insert(parts, tostring(t.Name.A) .. ":" .. tostring(t.Name.N))
	end
	local depot = ctx.State.Depot
	if type(depot) == "table" then
		table.insert(parts, tostring(depot.Withdrawable) .. tostring(depot.TransferReady))
	end
	local storage = ctx.State.Storage
	if tab == "Floors" and type(storage) == "table" and type(storage.Decor) == "table" then
		for key, n in pairs(storage.Decor) do
			table.insert(parts, tostring(key) .. "=" .. tostring(n))
		end
	end
	if confirmFire then
		table.insert(parts, confirmFire.Key)
	end
	if decorPick then
		table.insert(parts, decorPick.Floor .. ":" .. decorPick.Slot)
	end
	if tab == "Visit" then
		local ok, plotList = call("TowerView", "Plots")
		if ok and type(plotList) == "table" then
			for _, plot in ipairs(plotList) do
				local okInfo, info = call("TowerView", "PlotInfo", plot)
				if okInfo and type(info) == "table" then
					table.insert(parts, tostring(info.Owner) .. ":" .. tostring(info.Floors))
				end
			end
		end
	end
	return table.concat(parts, "|")
end

-- Live-Werte ohne Neuaufbau (Einkommen, Tresor, Baufortschritt)
local function updateLive()
	local t = tower()
	local inc = income()
	local incomeLabel = liveLabels.Income
	if incomeLabel and incomeLabel.Parent then
		incomeLabel.Text = T("tui.perSec", credits(num(inc.PerSec, 0)))
	end
	local vaultBar = liveBars.Vault
	if vaultBar and vaultBar.Frame.Parent then
		local cap = math.max(1, num(t.VaultCap, 1))
		local vault = num(t.Vault, 0)
		UI.SetBar(vaultBar, vault / cap, ("%s / %s"):format(credits(vault), credits(cap)))
	end
	local buildBar = liveBars.Build
	local build = t.Build
	if buildBar and buildBar.Frame.Parent and type(build) == "table" and build.Floor ~= nil then
		local now = workspace:GetServerTimeNow()
		local total = math.max(1, num(build.Total, 1))
		local remaining = math.max(0, num(build.Until, now) - now)
		UI.SetBar(buildBar, 1 - remaining / total, duration(remaining))
	end
end

local function rebuild()
	local holder = body
	if not holder then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(liveLabels)
	table.clear(liveBars)
	local ok, err = pcall(function()
		if tab == "Overview" then
			buildOverview(holder)
		elseif tab == "Floors" then
			buildFloors(holder)
		elseif tab == "Staff" then
			buildStaff(holder)
		elseif tab == "Facade" then
			buildFacade(holder)
		else
			buildVisit(holder)
		end
	end)
	if not ok then
		warn("[TowerUI] " .. tab .. ": " .. tostring(err))
	end
end

function TowerUI.Refresh()
	if not window or not window.IsOpen then
		return
	end
	local sig = signature()
	if sig ~= lastSig then
		lastSig = sig
		rebuild()
	end
	updateLive()
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	local wait = math.max(0, REFRESH_GAP - (os.clock() - lastRefresh))
	task.delay(wait, function()
		refreshQueued = false
		lastRefresh = os.clock()
		TowerUI.Refresh()
	end)
end

local function makeTabs()
	if not window then
		return
	end
	if tabs then
		tabs.Frame:Destroy()
	end
	local options = {}
	for _, key in ipairs(TABS) do
		table.insert(options, { Key = key, Text = T("tui.tab." .. string.lower(key)) })
	end
	tabs = UI.Segmented(window.Content, options, function(key: string)
		tab = key
		decorPick = nil
		lastSig = ""
		TowerUI.Refresh()
	end)
	tabs.Frame.LayoutOrder = 1
	builtLang = lang()
end

local function buildWindow()
	if window then
		return
	end
	window = UI.Window(T("tui.title"), WINDOW_W, WINDOW_H, Theme.Accent)
	body = UI.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = window.Content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }) })
	makeTabs()
end

local function openWindow()
	buildWindow()
	if window and builtLang ~= lang() then
		window.TitleLabel.Text = UI.Upper(T("tui.title"))
		makeTabs()
	end
	if pendingTab then
		tab = pendingTab
		pendingTab = nil
	end
	if tabs then
		tabs.Set(tab, true)
	end
	UI.OpenWindow(window)
	lastSig = ""
	TowerUI.Refresh()
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
	autoPlan = nil
	decorPick = nil
	nameDraft = nil
end

function TowerUI.Open(which: string?)
	if type(which) == "string" and table.find(TABS, which) then
		pendingTab = which
	end
	if ctx.Windows then
		ctx.Windows.Open("Tower")
	end
end

function TowerUI.Close()
	if ctx.Windows then
		ctx.Windows.Close("Tower")
	end
end

function TowerUI.SelectFloor(floor: number)
	if type(floor) == "number" and floor >= 1 then
		selectedFloor = math.floor(floor)
		TowerUI.Open("Floors")
	end
end

-- Hooks "Tower:Built" / "Tower:Stage" aus dem State-Diff (§C7.2)
local function onState(state: { [string]: any }, changed: { [any]: any })
	if
		not changed.Tower
		and not changed.Income
		and not changed.Depot
		and not changed.Storage
		and not changed.Passes
	then
		return
	end
	local t = state.Tower
	if type(t) == "table" then
		local floors = math.floor(num(t.Floors, 0))
		local stage = math.floor(num(t.Stage, 1))
		if lastFloors ~= nil and floors > lastFloors then
			ctx.Hooks.Fire("Tower:Built", floors)
		end
		if lastStage ~= nil and stage > lastStage then
			ctx.Hooks.Fire("Tower:Stage", stage)
		end
		lastFloors = floors
		lastStage = stage
	end
	queueRefresh()
end

-- Live-Werte (Baufortschritt, Tresor) – TowerView.Frame ruft das 1×/s (kein eigener Loop)
function TowerUI.Tick()
	if window and window.IsOpen then
		updateLive()
	end
end

function TowerUI.Init(context: any)
	ctx = context
	ctx.Windows.Register("Tower", openWindow, closeWindow)
	ctx.Hooks.On("State", onState)
	ctx.Hooks.On("Settings", function()
		if window and builtLang ~= lang() then
			window.TitleLabel.Text = UI.Upper(T("tui.title"))
			makeTabs()
			if tabs then
				tabs.Set(tab, true)
			end
			lastSig = ""
			TowerUI.Refresh()
		end
	end)
end

function TowerUI.Start() end

return TowerUI
