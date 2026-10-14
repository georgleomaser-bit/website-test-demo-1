--!nocheck
-- =====================================================================
--  Headless-Harness · Szenario ui-crawl
--
--  Nach dem Boot werden alle für einen Spieler ERREICHBAREN GuiButtons im PlayerGui des Clients nacheinander
--  angeklickt (MouseEnter, InputBegan, MouseButton1Down/Up, MouseButton1Click, Activated – wie Roblox; Activated nur
--  bei Active = true, nichts bei Interactable = false), nach jedem Klick click_wait (0,6) s simuliert und neue
--  Fehler dem Knopf (Pfad + Text) zugeordnet.
--
--  Erreichbar = sichtbar (Visible-Kette, ScreenGui.Enabled, Fläche > 0, im Viewport) UND an mindestens einem
--  Probepunkt das oberste eingabe-schluckende Objekt (GuiButton/TextBox oder Active = true) – Zeichenreihenfolge
--  wie Roblox: DisplayOrder, ZIndexBehavior Sibling (Geschwister nach ZIndex, Kinder über Eltern) bzw. Global.
--  ClipsDescendants/ScrollingFrame schneiden ab; Knöpfe außerhalb des sichtbaren ScrollingFrame-Fensters werden
--  vorher hingescrollt (CanvasPosition, wie ein Spieler mit dem Mausrad).
--
--  Reihenfolge: Breitensuche über neu sichtbare Knöpfe – zuerst die Knöpfe, die nach dem letzten Klick neu
--  erschienen sind (geöffnetes Fenster), darin in Baum-Reihenfolge; Schließen-Knöpfe zuletzt. Stehen keine neuen
--  Knöpfe mehr zur Verfügung: Fenster-Hotkeys aus Config.Client.Keys (über UserInputService/ContextActionService),
--  danach Wiederherstellen der Öffner-Kette für noch nicht besuchte, inzwischen verdeckte Knöpfe.
--  Schutz gegen Endlosschleifen: Besuchsliste (Pfad + Text), höchstens group_cap Klicks je Pfad-Muster (Ziffern
--  egal, Text egal – Listenzeilen), höchstens max_clicks (600) Aktionen.
--  TextBoxen: Fokus (ClearTextOnFocus), Text = Testwert, FocusLost(true) – Werte "10", "0", "-5", "abc", "1e99",
--  "", sehr lang, "nan", "1,5", "  7 ", Emoji; danach "1" stehen lassen.
--  Ergebnis: crawl.txt (alle Aktionen mit Fehlern), Abschnitt im report.txt.
-- =====================================================================
return function(C)
	local R = C.R
	local Sc = C.Sc
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Svc = R.Svc
	local In = Svc.Input
	local getmt = getmetatable
	local fmt = string.format

	local U = {}

	local TEXT_VALUES = { "10", "0", "-5", "abc", "1e99", "", string.rep("W", 2000), "nan", "1,5", "  7 ", "😀", "1" }
	local CLOSER_NAMES = { close = true, closebutton = true, windowmodal = true, back = true, cancel = true, x = true }
	local CLOSER_LABELS = {
		["x"] = true,
		["✕"] = true,
		["×"] = true,
		["✖"] = true,
		["schließen"] = true,
		["close"] = true,
		["zurück"] = true,
		["back"] = true,
		["abbrechen"] = true,
		["cancel"] = true,
	}

	-- ---------------------------------------------------------------------------------------------
	--  Geometrie / Zeichenreihenfolge
	-- ---------------------------------------------------------------------------------------------
	local function clipRect(a0, a1, a2, a3, b0, b1, b2, b3)
		return math.max(a0, b0), math.max(a1, b1), math.min(a2, b2), math.min(a3, b3)
	end

	local function guiChildren(M, out)
		-- Nicht-GUI-Container (Folder …) sind für die Reihenfolge durchsichtig
		for _, c in M.children do
			local CM = getmt(c)
			if CM.cls.isA.GuiObject then
				out[#out + 1] = c
			elseif not CM.cls.isA.LayerCollector and #CM.children > 0 and not CM.cls.isA.GuiBase3d then
				guiChildren(CM, out)
			end
		end
		return out
	end

	local function zOf(u)
		local z = getmt(u).props.ZIndex
		if z == nil then
			z = Inst.getProp(u, "ZIndex")
		end
		return z or 1
	end

	local function clips(u, M)
		if M.cls.isA.ScrollingFrame then
			return true
		end
		local v = M.props.ClipsDescendants
		if v == nil then
			v = Inst.getProp(u, "ClipsDescendants")
		end
		return v == true
	end

	local function sinks(u, M)
		if M.props.Interactable == false then
			return false
		end
		if M.cls.isA.GuiButton or M.cls.isA.TextBox then
			return true
		end
		local a = M.props.Active
		if a == nil then
			a = Inst.getProp(u, "Active")
		end
		return a == true
	end

	--- Alle sichtbaren GUI-Objekte des PlayerGui in Zeichenreihenfolge (unterstes zuerst).
	--- Eintrag: { u, M, x0, y0, x1, y1 (sichtbar, inkl. Scroll-Fenster), hx0..hy1 (ohne Scroll-Fenster), sf = {…},
	---            sink, layer }
	local function buildDrawList(pg)
		local vw, vh = R.config.viewport[1], R.config.viewport[2]
		local layers = {}
		for _, d in Inst.descendants(pg) do
			local M = getmt(d)
			if M.cls.isA.ScreenGui then
				-- keine LayerCollector-Vorfahren zwischen PlayerGui und ScreenGui
				local ok = true
				local p = M.parent
				while p and p ~= pg do
					if getmt(p).cls.isA.LayerCollector then
						ok = false
						break
					end
					p = getmt(p).parent
				end
				if ok and M.props.Enabled ~= false then
					layers[#layers + 1] = { u = d, order = M.props.DisplayOrder or 0, idx = #layers + 1 }
				end
			end
		end
		table.sort(layers, function(a, b)
			if a.order ~= b.order then
				return a.order < b.order
			end
			return a.idx < b.idx
		end)
		local list = {}
		for li, layer in layers do
			local LM = getmt(layer.u)
			local zb = LM.props.ZIndexBehavior
			local sibling = zb ~= nil and zb.Name == "Sibling"
			local entries = {}
			local seq = 0
			local function walk(node, NM, c0, c1, c2, c3, h0, h1, h2, h3, sfChain)
				local kids = guiChildren(NM, {})
				if sibling then
					local idx = {}
					for i, k in kids do
						idx[k] = i
					end
					table.sort(kids, function(a, b)
						local za, zb2 = zOf(a), zOf(b)
						if za ~= zb2 then
							return za < zb2
						end
						return idx[a] < idx[b]
					end)
				end
				for _, k in kids do
					local KM = getmt(k)
					if KM.props.Visible ~= false then
						local x, y, w, h = Inst.Gui.abs(k)
						if w > 0 and h > 0 then
							seq += 1
							local x0, y0, x1, y1 = clipRect(x, y, x + w, y + h, c0, c1, c2, c3)
							local hx0, hy0, hx1, hy1 = clipRect(x, y, x + w, y + h, h0, h1, h2, h3)
							local e = {
								u = k,
								M = KM,
								x0 = x0,
								y0 = y0,
								x1 = x1,
								y1 = y1,
								hx0 = hx0,
								hy0 = hy0,
								hx1 = hx1,
								hy1 = hy1,
								ax = x,
								ay = y,
								aw = w,
								ah = h,
								sf = sfChain,
								sink = sinks(k, KM),
								z = zOf(k),
								seq = seq,
								layer = li,
							}
							entries[#entries + 1] = e
							if clips(k, KM) then
								if KM.cls.isA.ScrollingFrame then
									local chain = table.clone(sfChain)
									chain[#chain + 1] = k
									local n0, n1, n2, n3 = clipRect(c0, c1, c2, c3, x, y, x + w, y + h)
									walk(k, KM, n0, n1, n2, n3, h0, h1, h2, h3, chain)
								else
									local n0, n1, n2, n3 = clipRect(c0, c1, c2, c3, x, y, x + w, y + h)
									local m0, m1, m2, m3 = clipRect(h0, h1, h2, h3, x, y, x + w, y + h)
									walk(k, KM, n0, n1, n2, n3, m0, m1, m2, m3, sfChain)
								end
							else
								walk(k, KM, c0, c1, c2, c3, h0, h1, h2, h3, sfChain)
							end
						else
							-- Größe 0 mit ClipsDescendants = false: Kinder können trotzdem sichtbar sein
							if not clips(k, KM) then
								walk(k, KM, c0, c1, c2, c3, h0, h1, h2, h3, sfChain)
							end
						end
					end
				end
			end
			walk(layer.u, LM, 0, 0, vw, vh, 0, 0, vw, vh, {})
			if not sibling then
				table.sort(entries, function(a, b)
					if a.z ~= b.z then
						return a.z < b.z
					end
					return a.seq < b.seq
				end)
			end
			for _, e in entries do
				list[#list + 1] = e
			end
		end
		return list
	end

	local function topSinkAt(sinkers, px, py)
		for i = #sinkers, 1, -1 do
			local e = sinkers[i]
			if px >= e.x0 and px < e.x1 and py >= e.y0 and py < e.y1 then
				return e
			end
		end
		return nil
	end

	--- Klickpunkt für Eintrag e (oberstes schluckendes Objekt an einem Probepunkt) oder nil, Verdecker
	local function clickPoint(e, sinkers)
		if e.x1 - e.x0 < 1 or e.y1 - e.y0 < 1 then
			return nil, nil
		end
		local w, h = e.x1 - e.x0, e.y1 - e.y0
		local pts = {
			{ e.x0 + w * 0.5, e.y0 + h * 0.5 },
			{ e.x0 + w * 0.25, e.y0 + h * 0.25 },
			{ e.x0 + w * 0.75, e.y0 + h * 0.25 },
			{ e.x0 + w * 0.25, e.y0 + h * 0.75 },
			{ e.x0 + w * 0.75, e.y0 + h * 0.75 },
		}
		local blocker = nil
		for _, p in pts do
			local top = topSinkAt(sinkers, p[1], p[2])
			if top == e then
				return p[1], p[2]
			end
			blocker = blocker or top
		end
		return nil, blocker
	end

	-- ---------------------------------------------------------------------------------------------
	--  Beschriftung, Schlüssel
	-- ---------------------------------------------------------------------------------------------
	local function cleanText(t)
		t = string.gsub(t, "<[^>]->", "")
		t = string.gsub(t, "%s+", " ")
		t = string.gsub(t, "^ ", "")
		t = string.gsub(t, " $", "")
		return Sc.cut(t, 40)
	end
	local function labelOf(u)
		local M = getmt(u)
		local t = M.props.Text
		if type(t) == "string" and string.find(t, "%S") then
			return cleanText(t)
		end
		for _, d in Inst.descendants(u) do
			local DM = getmt(d)
			if DM.cls.isA.TextLabel or DM.cls.isA.TextButton or DM.cls.isA.TextBox then
				local tt = DM.props.Text
				if type(tt) == "string" and string.find(tt, "%S") and DM.props.Visible ~= false then
					return cleanText(tt)
				end
			end
		end
		return ""
	end

	local function relPath(u, pg)
		local full = Inst.fullName(u)
		local pfull = Inst.fullName(pg)
		if string.sub(full, 1, #pfull + 1) == pfull .. "." then
			return string.sub(full, #pfull + 2)
		end
		return full
	end

	local function isCloser(name, label)
		local n = string.lower(name)
		if CLOSER_NAMES[n] or string.find(n, "close", 1, true) or string.find(n, "modal", 1, true) then
			return true
		end
		return CLOSER_LABELS[string.lower(label)] == true
	end

	-- ---------------------------------------------------------------------------------------------
	--  Szenario
	-- ---------------------------------------------------------------------------------------------
	function U.run(bundle, opts, results)
		local rec = results.rec
		if rec == nil then
			C.check(results, "ui-crawl: Client vorhanden", false, "kein Client-Kontext")
			return
		end
		local ctx = rec.ctx
		local lp = rec.localPlayer
		local pg = Inst.findChild(lp, "PlayerGui")
		local maxClicks = tonumber(opts.max_clicks) or 600
		local clickWait = tonumber(opts.click_wait) or 0.6
		local groupCap = tonumber(opts.group_cap) or 2 -- je Pfad-Muster + Text (Ziffern egal): wechselnde Preise/Zähler
		local pathCap = tonumber(opts.path_cap) or 30 -- je Pfad-Muster (Listenzeilen mit verschiedenen Texten)
		local navBudget = math.floor(maxClicks / 4)
		local navUsed = 0
		local pathClicks = {}

		local known = {} -- key -> Eintrag
		local knownList = {}
		local groupClicks = {}
		local textTested = {}
		local occluded = {} -- key -> { label, path, by }
		local log = {}
		local actions = 0
		local gen = 0
		local lastAction = nil
		local hotkeys = {}
		local hotkeyIdx = 0
		local stopReason = nil

		-- Hotkeys aus der Client-Config (wie der Spieler sie drückt)
		local cfg = C.moduleAt(ctx, { "ReplicatedStorage", "Shared", "Config" })
		local keysCfg = cfg and cfg.Client and cfg.Client.Keys
		if type(keysCfg) == "table" then
			local seen = {}
			local names = {}
			for action in keysCfg do
				names[#names + 1] = action
			end
			table.sort(names)
			for _, action in names do
				local list = keysCfg[action]
				if type(list) == "string" then
					list = { list }
				end
				if type(list) == "table" then
					for _, k in list do
						if type(k) == "string" and not seen[k] and R.Enum.tryItem("KeyCode", k) then
							seen[k] = true
							hotkeys[#hotkeys + 1] = { key = k, action = action }
						end
					end
				end
			end
		end

		local function closed()
			return rec.closed or getmt(lp).destroyed
		end

		local function record(kind, label, path, diff, extra)
			log[#log + 1] = { n = actions, t = Sched.now, kind = kind, label = label, path = path, diff = diff, extra = extra }
		end

		-- Scan: erreichbare Knöpfe/TextBoxen; neue Schlüssel registrieren
		local function scan()
			local list = buildDrawList(pg)
			local sinkers = {}
			for _, e in list do
				if e.sink and e.x1 > e.x0 and e.y1 > e.y0 then
					sinkers[#sinkers + 1] = e
				end
			end
			local reach, boxes = {}, {}
			local newCount = 0
			for _, e in list do
				local M = e.M
				local isBtn = M.cls.isA.GuiButton
				local isBox = M.cls.isA.TextBox
				if (isBtn or isBox) and M.props.Interactable ~= false then
					local px, py, blocker = nil, nil, nil
					local scroll = false
					if e.x1 > e.x0 and e.y1 > e.y0 then
						px, py, blocker = clickPoint(e, sinkers)
					elseif #e.sf > 0 and e.hx1 > e.hx0 and e.hy1 > e.hy0 then
						scroll = true -- liegt im Canvas, aber außerhalb des Scroll-Fensters
					end
					local path = relPath(e.u, pg)
					if isBox then
						if px then
							boxes[#boxes + 1] = { u = e.u, path = path, px = px, py = py }
						end
					else
						local label = labelOf(e.u)
						local key = path .. "|" .. label
						if px or scroll then
							local k = known[key]
							if k == nil then
								k = {
									key = key,
									path = path,
									label = label,
									group = string.gsub(path, "%d+", "#") .. "|" .. string.gsub(label, "%d+", "#"),
									pgroup = string.gsub(path, "%d+", "#"),
									opener = lastAction,
									gen = gen + 1,
									seq = #knownList + 1,
									visited = false,
									attempts = 0,
									closer = isCloser(M.name, label),
								}
								known[key] = k
								knownList[#knownList + 1] = k
								newCount += 1
							end
							k.u = e.u
							reach[key] = { k = k, u = e.u, px = px, py = py, scroll = scroll, e = e }
							occluded[key] = nil
						elseif blocker and not known[key] then
							occluded[key] = { label = label, path = path, by = relPath(blocker.u, pg) }
						end
					end
				end
			end
			return reach, boxes, newCount
		end

		-- ScrollingFrames so verschieben, dass u sichtbar ist (wie der Spieler mit dem Mausrad)
		local function scrollInto(u, chain)
			for i = #chain, 1, -1 do
				local sf = chain[i]
				local SM = getmt(sf)
				if not SM.destroyed then
					local sx, sy, sw, sh = Inst.Gui.abs(sf)
					local ux, uy, uw, uh = Inst.Gui.abs(u)
					local cp = Inst.getProp(sf, "CanvasPosition")
					local cvs = Inst.getProp(sf, "AbsoluteCanvasSize")
					local nx, ny = cp.X, cp.Y
					if uy < sy then
						ny -= sy - uy
					elseif uy + uh > sy + sh then
						ny += math.min(uy + uh - (sy + sh), uy - sy)
					end
					if ux < sx then
						nx -= sx - ux
					elseif ux + uw > sx + sw then
						nx += math.min(ux + uw - (sx + sw), ux - sx)
					end
					nx = math.clamp(nx, 0, math.max(0, cvs.X - sw))
					ny = math.clamp(ny, 0, math.max(0, cvs.Y - sh))
					if nx ~= cp.X or ny ~= cp.Y then
						Inst.setProp(sf, "CanvasPosition", DT.Vector2.new(nx, ny))
					end
				end
			end
			Sched.flush()
		end

		local function doClick(r, nav)
			local k = r.k
			local u = r.u
			local px, py = r.px, r.py
			if r.scroll or px == nil then
				scrollInto(u, r.e.sf)
				local list = buildDrawList(pg)
				local sinkers = {}
				local mine = nil
				for _, e in list do
					if e.sink and e.x1 > e.x0 and e.y1 > e.y0 then
						sinkers[#sinkers + 1] = e
					end
					if e.u == u then
						mine = e
					end
				end
				if mine then
					px, py = clickPoint(mine, sinkers)
				end
				if px == nil then
					k.attempts += 1
					if k.attempts >= 2 then
						k.visited = true
						k.result = "nach dem Scrollen nicht klickbar"
					end
					return false
				end
			end
			actions += 1
			k.visited = true
			groupClicks[k.group] = (groupClicks[k.group] or 0) + 1
			pathClicks[k.pgroup] = (pathClicks[k.pgroup] or 0) + 1
			if nav then
				navUsed += 1
			end
			local label = fmt('Klick #%d %s "%s"%s', actions, k.path, k.label, nav and " (Navigation)" or "")
			Report.setTrigger(label)
			local s = C.snap()
			local ok = In.clickGui(ctx, u, px, py)
			Sched.run(clickWait)
			local diff = C.since(s, true)
			lastAction = k.key
			record(nav and "nav" or "click", k.label, k.path, diff, if ok then nil else "Klick abgewiesen (Interactable = false?)")
			Report.setTrigger(nil)
			return true
		end

		local function pressKey(hk)
			actions += 1
			local label = fmt("Taste #%d %s (%s)", actions, hk.key, hk.action)
			Report.setTrigger(label)
			local s = C.snap()
			local st = In.state(ctx)
			if st.focused then
				In.releaseTextBox(ctx, st.focused, false)
			end
			In.key(ctx, hk.key, true)
			Sched.run(0.1)
			In.key(ctx, hk.key, false)
			Sched.run(clickWait)
			local diff = C.since(s, true)
			lastAction = "hotkey:" .. hk.key
			record("key", hk.key .. " (" .. hk.action .. ")", "", diff)
			Report.setTrigger(nil)
		end

		local function testBox(b)
			local u = b.u
			textTested[b.path] = true
			local editable = Inst.getProp(u, "TextEditable")
			if editable == false then
				return
			end
			for _, v in TEXT_VALUES do
				if closed() or getmt(u).destroyed then
					return
				end
				actions += 1
				local shown = #v > 20 and fmt("<%d Zeichen>", #v) or fmt("%q", v)
				local label = fmt("TextBox #%d %s = %s", actions, b.path, shown)
				Report.setTrigger(label)
				local s = C.snap()
				In.focusTextBox(ctx, u)
				Sched.flush()
				if not getmt(u).destroyed then
					Inst.setProp(u, "Text", v)
					Sched.flush()
					In.releaseTextBox(ctx, u, true)
				end
				Sched.run(0.25)
				record("text", shown, b.path, C.since(s, true))
				Report.setTrigger(nil)
			end
		end

		local hotkeysDone = false
		while actions < maxClicks do
			if closed() then
				stopReason = "Client wurde geschlossen/gekickt"
				break
			end
			local reach, boxes, newCount = scan()
			if newCount > 0 then
				gen += 1 -- neu erschienene Knöpfe (Generation gen) werden zuerst besucht
			end
			-- TextBoxen zuerst (Werte stehen danach für Knöpfe im selben Fenster bereit)
			local boxDone = false
			for _, b in boxes do
				if not textTested[b.path] then
					testBox(b)
					boxDone = true
					break
				end
			end
			if not boxDone then
				local cands = {}
				for _, r in reach do
					local k = r.k
					if not k.visited and (groupClicks[k.group] or 0) < groupCap and (pathClicks[k.pgroup] or 0) < pathCap then
						cands[#cands + 1] = r
					end
				end
				if #cands > 0 then
					table.sort(cands, function(a, b)
						local ka, kb = a.k, b.k
						if ka.closer ~= kb.closer then
							return not ka.closer
						end
						if ka.gen ~= kb.gen then
							return ka.gen > kb.gen
						end
						return ka.seq < kb.seq
					end)
					doClick(cands[1], false)
				elseif not hotkeysDone and hotkeyIdx < #hotkeys then
					hotkeyIdx += 1
					pressKey(hotkeys[hotkeyIdx])
					if hotkeyIdx >= #hotkeys then
						hotkeysDone = true
					end
				else
					hotkeysDone = true
					-- Öffner-Kette für unbesuchte, nicht erreichbare Knöpfe
					local target = nil
					if navUsed < navBudget then
						for _, k in knownList do
							if
								not k.visited
								and k.attempts < 2
								and (groupClicks[k.group] or 0) < groupCap
								and (pathClicks[k.pgroup] or 0) < pathCap
								and reach[k.key] == nil
							then
								target = k
								break
							end
						end
					end
					if target == nil then
						stopReason = if navUsed >= navBudget
							then fmt("Navigations-Budget (%d Klicks) aufgebraucht", navBudget)
							else "alle erreichbaren Knöpfe besucht"
						break
					end
					target.attempts += 1
					local step = nil
					local cur = target.opener
					local depth = 0
					while cur and depth < 8 do
						depth += 1
						if string.sub(cur, 1, 7) == "hotkey:" then
							step = cur
							break
						end
						if reach[cur] then
							step = cur
							break
						end
						local ok2 = known[cur]
						cur = ok2 and ok2.opener or nil
					end
					if step == nil then
						target.attempts = 2
						target.result = "Öffner nicht mehr erreichbar"
					elseif string.sub(step, 1, 7) == "hotkey:" then
						local keyName = string.sub(step, 8)
						for _, hk in hotkeys do
							if hk.key == keyName then
								pressKey(hk)
								break
							end
						end
					else
						doClick(reach[step], true)
					end
				end
			end
		end
		if actions >= maxClicks then
			stopReason = fmt("Aktions-Limit %d erreicht", maxClicks)
		end
		In.unhover(ctx)
		Sched.run(1)

		U.state = {
			log = log,
			known = knownList,
			occluded = occluded,
			actions = actions,
			stopReason = stopReason,
			hotkeys = hotkeys,
			textTested = textTested,
		}
		local visited, total = 0, #knownList
		for _, k in knownList do
			if k.visited then
				visited += 1
			end
		end
		local boxes = 0
		for _ in textTested do
			boxes += 1
		end
		C.check(
			results,
			"ui-crawl lief durch",
			not closed(),
			fmt("%d Aktionen, %d/%d Knöpfe besucht, %d TextBoxen, %d Hotkeys – %s", actions, visited, total, boxes, #hotkeys, stopReason or "?")
		)
	end

	function U.finish(results)
		local st = U.state
		if st == nil then
			return
		end
		local ids = C.ids()
		local L, S = {}, {}
		L[#L + 1] = fmt("ui-crawl: %d Aktionen · Ende: %s", st.actions, st.stopReason or "?")
		L[#L + 1] = ""
		local withErr = 0
		local repeatOnly = 0
		for _, a in st.log do
			local tag = a.kind == "click" and "KLICK" or (a.kind == "nav" and "NAV  " or (a.kind == "key" and "TASTE" or "TEXT "))
			local shownLabel = a.label
			if a.kind ~= "text" and a.label ~= "" then
				shownLabel = '"' .. a.label .. '"'
			end
			L[#L + 1] = fmt("[%7.2f] #%-4d %s %s%s%s", a.t, a.n, tag, a.path ~= "" and (a.path .. " ") or "", shownLabel, a.extra and (" – " .. a.extra) or "")
			-- neue Fehler ausführlich, bekannte (schon früher aufgetretene) nur als Kurzliste
			local fresh, again = {}, {}
			for _, d in a.diff do
				if d.new then
					fresh[#fresh + 1] = d
				else
					again[#again + 1] = (ids[d.entry] or (d.kind == "warn" and "W" or "?"))
				end
			end
			for _, line in C.describe(fresh, ids) do
				L[#L + 1] = "           -> " .. line
			end
			if #again > 0 then
				L[#L + 1] = "           -> erneut: " .. table.concat(again, ", ")
			end
			local bugs = C.bugs(fresh)
			if #bugs > 0 then
				withErr += 1
				S[#S + 1] = fmt("  #%d %s %s %s", a.n, tag, a.path, shownLabel)
				for _, line in C.describe(bugs, ids, 140) do
					S[#S + 1] = "      -> " .. line
				end
			elseif #C.bugs(a.diff) > 0 then
				repeatOnly += 1
			end
		end
		L[#L + 1] = ""
		L[#L + 1] = "NIE BESUCHT (war erreichbar):"
		for _, k in st.known do
			if not k.visited then
				local why = k.result
				if why == nil and k.attempts >= 2 then
					why = "nach 2 Navigationsversuchen nicht wieder erreichbar"
				elseif why == nil then
					why = "Gruppen-/Pfad-Limit oder Budget"
				end
				L[#L + 1] = fmt("  %s \"%s\" – %s", k.path, k.label, why)
			end
		end
		L[#L + 1] = ""
		L[#L + 1] = "SICHTBAR, ABER NIE KLICKBAR (verdeckt durch ein darüberliegendes Objekt – Hinweis, Geometrie genähert):"
		local occ = {}
		for _, o in st.occluded do
			occ[#occ + 1] = o
		end
		table.sort(occ, function(a, b)
			return a.path < b.path
		end)
		for _, o in occ do
			L[#L + 1] = fmt("  %s \"%s\"  verdeckt von %s", o.path, o.label, o.by)
		end
		results.files["crawl.txt"] = table.concat(L, "\n")
		if #S == 0 then
			S[1] = "  (keine Aktion hat einen Fehler ausgelöst)"
		end
		S[#S + 1] = fmt("  (+ %d Aktionen, bei denen nur schon bekannte Fehler erneut auftraten – siehe crawl.txt)", repeatOnly)
		C.section(results, fmt("UI-CRAWL: AKTIONEN, DIE EINEN NEUEN FEHLER AUSGELÖST HABEN (%d von %d; vollständige Liste: crawl.txt)", withErr, st.actions), S)
	end

	return U
end
