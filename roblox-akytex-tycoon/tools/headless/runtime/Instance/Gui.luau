--!nocheck
-- =====================================================================
--  Headless-Harness · GUI-Geometrie (grob, aber konsistent)
--
--  AbsoluteSize/AbsolutePosition/AbsoluteRotation werden aus der UDim2-Kette berechnet:
--   ScreenGui = Viewport (R.config.viewport, Standard 1280×720) minus oberer Inset (58 px), außer
--   IgnoreGuiInset = true oder ScreenInsets = None. SurfaceGui: CanvasSize bzw. Teilfläche × PixelsPerStud;
--   BillboardGui: Size-Offset (+ Scale × 50 px/Stud). Nicht-GUI-Container (Folder) dazwischen sind transparent.
--   Eltern-UIPadding verkleinert die Inhaltsfläche; UIListLayout/UIGridLayout positionieren Geschwister;
--   UIAspectRatioConstraint/UISizeConstraint werden angewendet; SizeConstraint RelativeXX/YY beachtet.
--  TextBounds ≈ Zeichenzahl × TextSize × 0,5 (Umbruch bei TextWrapped, TextScaled passt TextSize an), TextFits.
--  UIListLayout/UIGridLayout.AbsoluteContentSize, ScrollingFrame.AbsoluteCanvasSize/AbsoluteWindowSize.
--  Changed-Signale für Absolute* feuern einmal pro Frame, wenn sich der Wert geändert hat (nur für Instanzen mit
--  verbundenen Signalen). Cache je Instanz, invalidiert über einen globalen Geometrie-Zähler.
--  Harness: Inst.Gui.abs(gui) -> x, y, w, h; Inst.Gui.isRendered(gui) (sichtbar, aktiviert, im Viewport).
-- =====================================================================
return function(R, Inst)
	local Util = R.Util
	local DT = R.DT
	local Sched = R.Sched
	local Signal = R.Signal
	local getmt = getmetatable
	local mk = DT.make

	local G = {}
	Inst.Gui = G

	local version = 0
	local function bump()
		version += 1
	end
	G.bump = bump

	local function cfg()
		local vp = R.config.viewport or { 1280, 720 }
		return vp[1], vp[2], R.config.topInset or 58
	end

	local function prop(u, M, name)
		local v = M.props[name]
		if v == nil then
			v = Inst.defaultValue(u, name)
		end
		return v
	end

	local function guiParent(M)
		local p = M.parent
		while p do
			local PM = getmt(p)
			if PM.cls.isA.GuiBase2d then
				return p, PM
			end
			-- Nicht-GUI-Container sind transparent, aber Teile/Instanzen außerhalb beenden die Kette
			if PM.cls.isA.BasePart or PM.cls.isA.PlayerGui or PM.cls.isA.StarterGui or PM.cls.isA.CoreGui then
				return nil, nil
			end
			p = PM.parent
		end
		return nil, nil
	end

	local compute -- (u, M) -> x, y, w, h, rot

	local function udim2(v)
		return DT.u2Parts(v)
	end

	-- UIScale-Faktor eines Objekts (erstes UIScale-Kind)
	local function uiScaleOf(M)
		for _, c in M.children do
			local CM = getmt(c)
			if CM.cls.name == "UIScale" then
				local k = CM.props.Scale
				if k == nil then
					return 1
				end
				return k
			end
		end
		return 1
	end
	G.uiScaleOf = function(u)
		return uiScaleOf(getmt(u))
	end

	-- Inhaltsfläche eines Containers (berücksichtigt UIPadding, ScrollingFrame-Canvas und UIScale).
	-- Rückgabe x, y, w, h, cs (cs = Faktor für Offsets der Kinder = Produkt aller UIScale darüber)
	local function contentRect(p, PM)
		local x, y, w, h, _, cs = compute(p, PM)
		cs = cs or 1
		if PM.cls.isA.LayerCollector then
			-- UIScale an einer ScreenGui/SurfaceGui skaliert den ganzen Inhalt um die linke obere Ecke
			w, h = w * cs, h * cs
		end
		if PM.cls.isA.ScrollingFrame then
			local cvs = prop(p, PM, "CanvasSize")
			local xs, xo, ys, yo = udim2(cvs)
			local cw, ch = math.max(w, xs * w + xo * cs), math.max(h, ys * h + yo * cs)
			local cp = prop(p, PM, "CanvasPosition")
			x, y, w, h = x - cp.X * cs, y - cp.Y * cs, cw, ch
		end
		for _, c in PM.children do
			local CM = getmt(c)
			if CM.cls.name == "UIPadding" then
				local function u(name, base)
					local sc, o = DT.udParts(prop(c, CM, name))
					return sc * base + o * cs
				end
				local l, r, t, b = u("PaddingLeft", w), u("PaddingRight", w), u("PaddingTop", h), u("PaddingBottom", h)
				x, y, w, h = x + l, y + t, math.max(0, w - l - r), math.max(0, h - t - b)
				break
			end
		end
		return x, y, w, h, cs
	end

	local function constrain(u, M, w, h)
		for _, c in M.children do
			local CM = getmt(c)
			local cn = CM.cls.name
			if cn == "UIAspectRatioConstraint" then
				local ratio = prop(c, CM, "AspectRatio")
				if ratio > 0 then
					local dom = prop(c, CM, "DominantAxis").Name
					local atype = prop(c, CM, "AspectType").Name
					if atype == "ScaleWithParentSize" then
						-- passt in die verfügbare Fläche
						if w / h > ratio then
							w = h * ratio
						else
							h = w / ratio
						end
					elseif dom == "Width" then
						h = w / ratio
					else
						w = h * ratio
					end
				end
			elseif cn == "UISizeConstraint" then
				local mn, mx = prop(c, CM, "MinSize"), prop(c, CM, "MaxSize")
				w = math.clamp(w, mn.X, math.max(mn.X, mx.X))
				h = math.clamp(h, mn.Y, math.max(mn.Y, mx.Y))
			end
		end
		return w, h
	end

	-- Größe vor der eigenen UIScale (pcs = Offset-Faktor des Elternteils)
	local function baseSize(u, M, pw, ph, pcs)
		pcs = pcs or 1
		local xs, xo, ys, yo = udim2(prop(u, M, "Size"))
		local sc = prop(u, M, "SizeConstraint").Name
		local bw, bh = pw, ph
		if sc == "RelativeXX" then
			bh = pw
		elseif sc == "RelativeYY" then
			bw = ph
		end
		local w, h = bw * xs + xo * pcs, bh * ys + yo * pcs
		return constrain(u, M, w, h)
	end
	-- Größe inklusive eigener UIScale (für Layouts)
	local function ownSize(u, M, pw, ph, pcs)
		local w, h = baseSize(u, M, pw, ph, pcs)
		local k = uiScaleOf(M)
		return w * k, h * k
	end

	local function isVisibleGui(c, CM)
		if not CM.cls.isA.GuiObject then
			return false
		end
		local v = CM.props.Visible
		return v == nil or v == true
	end

	-- Position eines Kindes in einem UIListLayout/UIGridLayout (nil, wenn keins vorhanden)
	local function layoutPosition(u, M, p, PM, px, py, pw, ph, w, h, pcs)
		pcs = pcs or 1
		local layout
		for _, c in PM.children do
			local cn = getmt(c).cls.name
			if cn == "UIListLayout" or cn == "UIGridLayout" then
				layout = c
				break
			end
		end
		if layout == nil then
			return nil
		end
		local LM = getmt(layout)
		local sortOrder = prop(layout, LM, "SortOrder").Name
		local sibs = {}
		for i, c in PM.children do
			local CM = getmt(c)
			if isVisibleGui(c, CM) then
				sibs[#sibs + 1] = { c, CM, i }
			end
		end
		table.sort(sibs, function(a, b)
			if sortOrder == "LayoutOrder" then
				local la, lb = prop(a[1], a[2], "LayoutOrder"), prop(b[1], b[2], "LayoutOrder")
				if la ~= lb then
					return la < lb
				end
			elseif sortOrder == "Name" then
				if a[2].name ~= b[2].name then
					return a[2].name < b[2].name
				end
			end
			return a[3] < b[3]
		end)
		local fill = prop(layout, LM, "FillDirection").Name
		if LM.cls.name == "UIListLayout" then
			local ps, po = DT.udParts(prop(layout, LM, "Padding"))
			local pad = (fill == "Vertical" and ph or pw) * ps + po * pcs
			local cursor = 0
			local total = 0
			local mine = nil
			for _, s in sibs do
				local sw, sh
				if s[1] == u then
					sw, sh = w, h
				else
					sw, sh = ownSize(s[1], s[2], pw, ph, pcs)
				end
				if s[1] == u then
					mine = cursor
				end
				local len = fill == "Vertical" and sh or sw
				cursor += len + pad
				total = cursor - pad
			end
			if mine == nil then
				return nil
			end
			local ha = prop(layout, LM, "HorizontalAlignment").Name
			local va = prop(layout, LM, "VerticalAlignment").Name
			local x, y
			if fill == "Vertical" then
				y = py + mine
				if va == "Center" then
					y += (ph - total) / 2
				elseif va == "Bottom" then
					y += ph - total
				end
				x = px
				if ha == "Center" then
					x = px + (pw - w) / 2
				elseif ha == "Right" then
					x = px + pw - w
				end
			else
				x = px + mine
				if ha == "Center" then
					x += (pw - total) / 2
				elseif ha == "Right" then
					x += pw - total
				end
				y = py
				if va == "Center" then
					y = py + (ph - h) / 2
				elseif va == "Bottom" then
					y = py + ph - h
				end
			end
			return x, y
		else
			-- UIGridLayout: Zellen zeilenweise (Horizontal) bzw. spaltenweise (Vertical)
			local cxs, cxo, cys, cyo = udim2(prop(layout, LM, "CellSize"))
			local pxs, pxo, pys, pyo = udim2(prop(layout, LM, "CellPadding"))
			local cw, ch = pw * cxs + cxo * pcs, ph * cys + cyo * pcs
			local padx, pady = pw * pxs + pxo * pcs, ph * pys + pyo * pcs
			local maxCells = prop(layout, LM, "FillDirectionMaxCells")
			local perLine
			if fill == "Horizontal" then
				perLine = math.max(1, math.floor((pw + padx) / math.max(cw + padx, 1)))
			else
				perLine = math.max(1, math.floor((ph + pady) / math.max(ch + pady, 1)))
			end
			if maxCells and maxCells > 0 then
				perLine = math.min(perLine, maxCells)
			end
			for idx, s in sibs do
				if s[1] == u then
					local i = idx - 1
					local line, pos = i // perLine, i % perLine
					if fill == "Horizontal" then
						return px + pos * (cw + padx), py + line * (ch + pady)
					else
						return px + line * (cw + padx), py + pos * (ch + pady)
					end
				end
			end
			return nil
		end
	end

	local function gridCellSize(u, M, PM, pw, ph, pcs)
		pcs = pcs or 1
		for _, c in PM.children do
			local CM = getmt(c)
			if CM.cls.name == "UIGridLayout" then
				local cxs, cxo, cys, cyo = udim2(prop(c, CM, "CellSize"))
				return pw * cxs + cxo * pcs, ph * cys + cyo * pcs
			end
		end
		return nil
	end

	function compute(u, M)
		local cache = M.guiCache
		if cache and cache.v == version then
			return cache.x, cache.y, cache.w, cache.h, cache.r, cache.cs
		end
		local x, y, w, h, r = 0, 0, 0, 0, 0
		local cs = 1
		local cls = M.cls
		if cls.isA.ScreenGui then
			local vw, vh, inset = cfg()
			local ignore = prop(u, M, "IgnoreGuiInset")
			local insets = M.props.ScreenInsets
			if ignore or (insets and insets.Name == "None") then
				x, y, w, h = 0, 0, vw, vh
			else
				x, y, w, h = 0, inset, vw, vh - inset
			end
			cs = uiScaleOf(M)
		elseif cls.isA.SurfaceGui then
			local mode = prop(u, M, "SizingMode").Name
			if mode == "PixelsPerStud" then
				local pps = prop(u, M, "PixelsPerStud")
				local adornee = M.props.Adornee or M.parent
				local AM = adornee and Inst.meta(adornee)
				if AM and AM.cls.isPart then
					local sx, sy, sz = DT.v3xyz(prop(adornee, AM, "Size"))
					local face = prop(u, M, "Face").Name
					local fw, fh = sx, sy
					if face == "Top" or face == "Bottom" then
						fw, fh = sx, sz
					elseif face == "Left" or face == "Right" then
						fw, fh = sz, sy
					end
					w, h = fw * pps, fh * pps
				else
					w, h = 800, 600
				end
			else
				local cvs = prop(u, M, "CanvasSize")
				w, h = cvs.X, cvs.Y
			end
			cs = uiScaleOf(M)
		elseif cls.isA.BillboardGui then
			local xs, xo, ys, yo = udim2(prop(u, M, "Size"))
			w, h = xo + xs * 50, yo + ys * 50
			cs = uiScaleOf(M)
		elseif cls.isA.GuiObject then
			local p, PM = guiParent(M)
			local px, py, pw, ph, pr, pcs = 0, 0, 0, 0, 0, 1
			if p then
				px, py, pw, ph, pcs = contentRect(p, PM)
				local _, _, _, _, prr = compute(p, PM)
				pr = prr or 0
			end
			local k = uiScaleOf(M)
			local gw, gh = nil, nil
			if p then
				gw, gh = gridCellSize(u, M, PM, pw, ph, pcs)
			end
			local bw, bh
			if gw then
				bw, bh = gw, gh
			else
				bw, bh = baseSize(u, M, pw, ph, pcs)
			end
			w, h = bw * k, bh * k
			local lx, ly = nil, nil
			if p then
				lx, ly = layoutPosition(u, M, p, PM, px, py, pw, ph, w, h, pcs)
			end
			if lx then
				x, y = lx, ly
			else
				local xs, xo, ys, yo = udim2(prop(u, M, "Position"))
				local ap = prop(u, M, "AnchorPoint")
				-- Ankerpunkt ohne eigene Skalierung, dann um ihn herum skalieren (wie Roblox' UIScale)
				local ax = px + pw * xs + xo * pcs
				local ay = py + ph * ys + yo * pcs
				x = ax - ap.X * w
				y = ay - ap.Y * h
			end
			r = pr + (prop(u, M, "Rotation") or 0)
			cs = pcs * k
		else
			-- andere GuiBase2d (z. B. LayerCollector-Varianten): wie Viewport
			local vw, vh = cfg()
			w, h = vw, vh
		end
		M.guiCache = { v = version, x = x, y = y, w = w, h = h, r = r, cs = cs }
		return x, y, w, h, r, cs
	end

	function G.abs(u)
		return compute(u, getmt(u))
	end

	-- -------------------------------------------------------------------------------------------------
	--  Text
	-- -------------------------------------------------------------------------------------------------
	local function plainText(u, M)
		local t = prop(u, M, "Text") or ""
		if M.props.RichText then
			t = string.gsub(t, "<[^>]*>", "")
		end
		return t
	end
	local function textBounds(u, M)
		local text = plainText(u, M)
		local _, _, w, h, _, tcs = compute(u, M)
		local size = prop(u, M, "TextSize") * (tcs or 1)
		local lineH = prop(u, M, "LineHeight") or 1
		local n = utf8.len(text) or #text
		local charW = 0.5
		if prop(u, M, "TextScaled") then
			-- größte Schrift (≤ 100), mit der der Text passt
			size = 100
			while size > 1 do
				local tw = n * size * charW
				local lines = 1
				if prop(u, M, "TextWrapped") and w > 0 then
					lines = math.max(1, math.ceil(tw / w))
					tw = math.min(tw, w)
				end
				if tw <= w + 0.5 and lines * size * lineH <= h + 0.5 then
					break
				end
				size -= 1
			end
		end
		local lines = 1
		for _ in string.gmatch(text, "\n") do
			lines += 1
		end
		local longest = 0
		for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
			longest = math.max(longest, (utf8.len(line) or #line) * size * charW)
		end
		local tw = longest
		if prop(u, M, "TextWrapped") and w > 0 and tw > w then
			lines += math.ceil(tw / w) - 1
			tw = w
		end
		if n == 0 then
			return 0, 0, size
		end
		return tw, lines * size * lineH, size
	end
	G.textBounds = function(u)
		return textBounds(u, getmt(u))
	end

	-- -------------------------------------------------------------------------------------------------
	--  Sichtbarkeit für UI-Crawls
	-- -------------------------------------------------------------------------------------------------
	function G.isRendered(u)
		local M = getmt(u)
		if M.destroyed then
			return false
		end
		local cur, CM = u, M
		local layer, rooted = nil, false
		while cur do
			local cls = CM.cls
			if cls.isA.GuiObject then
				local v = CM.props.Visible
				if v == false then
					return false
				end
			elseif cls.isA.LayerCollector then
				local e = CM.props.Enabled
				if e == false then
					return false
				end
				layer = layer or cur
			elseif cls.isA.PlayerGui or cls.isA.CoreGui then
				rooted = true
				break
			elseif cls.isA.Workspace then
				-- 3D-GUIs (SurfaceGui/BillboardGui) werden in Workspace gezeichnet, ScreenGuis dort nicht
				rooted = layer ~= nil and not getmt(layer).cls.isA.ScreenGui
				break
			end
			cur = CM.parent
			CM = cur and getmt(cur)
		end
		if layer == nil or not rooted then
			return false
		end
		local x, y, w, h = compute(u, M)
		if w <= 0 or h <= 0 then
			return false
		end
		local LM = getmt(layer)
		if LM.cls.isA.ScreenGui then
			local vw, vh = cfg()
			if x + w <= 0 or y + h <= 0 or x >= vw or y >= vh then
				return false
			end
		end
		return true
	end

	-- -------------------------------------------------------------------------------------------------
	--  Klassen-Verhalten
	-- -------------------------------------------------------------------------------------------------
	local geometryProps = {
		Size = true,
		Position = true,
		AnchorPoint = true,
		Parent = true,
		Visible = true,
		SizeConstraint = true,
		Rotation = true,
		LayoutOrder = true,
		Name = true,
		CanvasSize = true,
		CanvasPosition = true,
		IgnoreGuiInset = true,
		ScreenInsets = true,
		Enabled = true,
		Text = true,
		TextSize = true,
		TextWrapped = true,
		TextScaled = true,
		Padding = true,
		FillDirection = true,
		HorizontalAlignment = true,
		VerticalAlignment = true,
		SortOrder = true,
		CellSize = true,
		CellPadding = true,
		PaddingLeft = true,
		PaddingRight = true,
		PaddingTop = true,
		PaddingBottom = true,
		AspectRatio = true,
		MinSize = true,
		MaxSize = true,
		CanvasSize2 = true,
		SizingMode = true,
		PixelsPerStud = true,
		Face = true,
		AutomaticSize = true,
		RichText = true,
		Scale = true,
	}
	local function geomChanged(u, M, propName)
		if geometryProps[propName] then
			bump()
		end
	end

	-- Instanzen mit verbundenen Absolute*-Signalen (schwach)
	local watched = setmetatable({}, { __mode = "k" })
	local function watch(sig)
		local owner = getmt(sig).owner
		if owner then
			watched[owner] = true
		end
	end
	local lastSeen = -1
	Sched.addHook("late", function()
		if lastSeen == version then
			return
		end
		lastSeen = version
		for u in watched do
			local M = getmt(u)
			if not M.destroyed then
				local x, y, w, h, r = compute(u, M)
				local last = M.guiLast
				if last == nil then
					M.guiLast = { x = x, y = y, w = w, h = h, r = r }
				else
					if last.w ~= w or last.h ~= h then
						Inst.changed(u, M, "AbsoluteSize")
					end
					if last.x ~= x or last.y ~= y then
						Inst.changed(u, M, "AbsolutePosition")
					end
					if last.r ~= r then
						Inst.changed(u, M, "AbsoluteRotation")
					end
					last.x, last.y, last.w, last.h, last.r = x, y, w, h, r
				end
			end
		end
	end, "GuiGeometry")

	local watchOpts = { onConnect = watch }
	Inst.define("GuiBase2d", {
		props = {
			AbsoluteSize = {
				get = function(u, M)
					local _, _, w, h = compute(u, M)
					return mk.V2(w, h)
				end,
			},
			AbsolutePosition = {
				get = function(u, M)
					local x, y = compute(u, M)
					return mk.V2(x, y)
				end,
			},
			AbsoluteRotation = {
				get = function(u, M)
					local _, _, _, _, r = compute(u, M)
					return r or 0
				end,
			},
		},
		onChanged = geomChanged,
		onAncestry = function()
			bump()
		end,
		signalOpts = { Changed = watchOpts },
		propSignalOpts = { AbsoluteSize = watchOpts, AbsolutePosition = watchOpts, AbsoluteRotation = watchOpts },
	})
	-- Layout-/Constraint-Objekte beeinflussen die Geometrie der Geschwister
	for _, cname in { "UIComponent" } do
		Inst.define(cname, {
			onChanged = geomChanged,
			onAncestry = function()
				bump()
			end,
		})
	end

	local textProps = {
		TextBounds = {
			get = function(u, M)
				local w, h = textBounds(u, M)
				return mk.V2(w, h)
			end,
		},
		TextFits = {
			get = function(u, M)
				local w, h = textBounds(u, M)
				local _, _, aw, ah = compute(u, M)
				return w <= aw + 0.5 and h <= ah + 0.5
			end,
		},
	}
	for _, cname in { "TextLabel", "TextButton", "TextBox" } do
		Inst.define(cname, { props = textProps })
	end

	local function contentSize(u, M)
		local p = M.parent
		local PM = p and getmt(p)
		if PM == nil or not PM.cls.isA.GuiBase2d then
			return 0, 0
		end
		local _, _, pw, ph, pcs = contentRect(p, PM)
		local fill = prop(u, M, "FillDirection").Name
		local total, maxOther = 0, 0
		local count = 0
		if M.cls.name == "UIListLayout" then
			local ps, po = DT.udParts(prop(u, M, "Padding"))
			local pad = (fill == "Vertical" and ph or pw) * ps + po * pcs
			for _, c in PM.children do
				local CM = getmt(c)
				if isVisibleGui(c, CM) then
					local w, h = ownSize(c, CM, pw, ph, pcs)
					count += 1
					if fill == "Vertical" then
						total += h
						maxOther = math.max(maxOther, w)
					else
						total += w
						maxOther = math.max(maxOther, h)
					end
				end
			end
			if count > 1 then
				total += pad * (count - 1)
			end
			if fill == "Vertical" then
				return maxOther, total
			end
			return total, maxOther
		end
		-- UIGridLayout
		local cxs, cxo, cys, cyo = udim2(prop(u, M, "CellSize"))
		local pxs, pxo, pys, pyo = udim2(prop(u, M, "CellPadding"))
		local cw, ch = pw * cxs + cxo * pcs, ph * cys + cyo * pcs
		local padx, pady = pw * pxs + pxo * pcs, ph * pys + pyo * pcs
		for _, c in PM.children do
			if isVisibleGui(c, getmt(c)) then
				count += 1
			end
		end
		if count == 0 then
			return 0, 0
		end
		if fill == "Horizontal" then
			local per = math.max(1, math.floor((pw + padx) / math.max(cw + padx, 1)))
			local rows = math.ceil(count / per)
			return math.min(count, per) * (cw + padx) - padx, rows * (ch + pady) - pady
		end
		local per = math.max(1, math.floor((ph + pady) / math.max(ch + pady, 1)))
		local cols = math.ceil(count / per)
		return cols * (cw + padx) - padx, math.min(count, per) * (ch + pady) - pady
	end
	for _, cname in { "UIListLayout", "UIGridLayout" } do
		Inst.define(cname, {
			props = {
				AbsoluteContentSize = {
					get = function(u, M)
						local w, h = contentSize(u, M)
						return mk.V2(w, h)
					end,
				},
			},
		})
	end
	if
		R.api.classes.UIGridLayout
		and R.api.classes.UIGridLayout.p
		and R.api.classes.UIGridLayout.p.AbsoluteCellSize
	then
		Inst.define("UIGridLayout", {
			props = {
				AbsoluteCellSize = {
					get = function(u, M)
						local p = M.parent
						local PM = p and getmt(p)
						if not PM or not PM.cls.isA.GuiBase2d then
							return mk.V2(0, 0)
						end
						local _, _, pw, ph = contentRect(p, PM)
						local cxs, cxo, cys, cyo = udim2(prop(u, M, "CellSize"))
						return mk.V2(pw * cxs + cxo, ph * cys + cyo)
					end,
				},
			},
		})
	end

	Inst.define("ScrollingFrame", {
		props = {
			AbsoluteCanvasSize = {
				get = function(u, M)
					local _, _, w, h = compute(u, M)
					local xs, xo, ys, yo = udim2(prop(u, M, "CanvasSize"))
					local cw, ch = xs * w + xo, ys * h + yo
					local auto = prop(u, M, "AutomaticCanvasSize").Name
					if auto ~= "None" then
						for _, c in M.children do
							local cn = getmt(c).cls.name
							if cn == "UIListLayout" or cn == "UIGridLayout" then
								local lw, lh = contentSize(c, getmt(c))
								if auto == "X" or auto == "XY" then
									cw = math.max(cw, lw)
								end
								if auto == "Y" or auto == "XY" then
									ch = math.max(ch, lh)
								end
							end
						end
					end
					return mk.V2(math.max(cw, w), math.max(ch, h))
				end,
			},
			AbsoluteWindowSize = {
				get = function(u, M)
					local _, _, w, h = compute(u, M)
					return mk.V2(w, h)
				end,
			},
		},
	})

	-- TextBox-Fokus (UI-Crawl ruft CaptureFocus/ReleaseFocus)
	Inst.define("TextBox", {
		methods = {
			CaptureFocus = function(self)
				local M = Inst.checkSelf(self, "CaptureFocus")
				M.ext = M.ext or {}
				if not M.ext.focused then
					M.ext.focused = true
					Inst.fire(self, "Focused")
				end
			end,
			ReleaseFocus = function(self, submitted)
				local M = Inst.checkSelf(self, "ReleaseFocus")
				if M.ext and M.ext.focused then
					M.ext.focused = false
					Inst.fire(self, "FocusLost", submitted == true, nil)
				end
			end,
			IsFocused = function(self)
				local M = Inst.checkSelf(self, "IsFocused")
				return M.ext ~= nil and M.ext.focused == true
			end,
		},
	})
end
