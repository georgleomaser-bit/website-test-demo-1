--!nocheck
-- =====================================================================
--  Headless-Harness · Eingabe: UserInputService, ContextActionService, GuiService, StarterGui (SetCore*),
--  HapticService, VRService, GamepadService, InputObject
--
--  Client-Gerät (wie ein Desktop-PC): KeyboardEnabled/MouseEnabled = true, TouchEnabled/GamepadEnabled/VR = false,
--  PreferredInput KeyboardAndMouse, Maus in der Bildschirmmitte. Auf dem Server sind die Geräte-Flags false.
--  UserInputService:GetPlatform ist laut API nicht skriptbar (Fehler wie Roblox).
--
--  Harness-API (R.Svc.Input):
--    In.key(ctx, keyName, down)            Taste drücken/loslassen -> CAS-Bindungen (Priorität, Sink/Pass) +
--                                          UIS.InputBegan/InputEnded (gameProcessedEvent = false)
--    In.mouseButton(ctx, n, down, x, y)    Maustaste (MouseButton1/2) an Position
--    In.focusTextBox(ctx, tb) / In.releaseTextBox(ctx, tb, enterPressed)
--    In.windowFocus(ctx, focused)
-- =====================================================================
return function(R, Svc)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local raise = Util.raise
	local typeof = Util.typeof
	local getmt = getmetatable
	local fmt = string.format
	local mk = DT.make

	local In = {}
	Svc.Input = In

	local function ctxOfSvc(self)
		return Svc.ctxOf(self)
	end
	local function state(ctx)
		local s = ctx.data.input
		if s == nil then
			local vp = R.config.viewport or { 1280, 720 }
			s = {
				pressed = {}, -- KeyCode-Item -> InputObject
				mouseButtons = {},
				mouse = mk.V2(vp[1] / 2, vp[2] / 2),
				lastType = Enum.item("UserInputType", "MouseMovement"),
				focused = nil,
				actions = {},
				seq = 0,
			}
			ctx.data.input = s
		end
		return s
	end
	In.state = state

	local function newInput(keyCode, inputType, st, pos)
		local io = Inst.create("InputObject", { Name = "InputObject" })
		local M = getmt(io)
		M.props.KeyCode = keyCode or Enum.item("KeyCode", "None")
		M.props.UserInputType = inputType
		M.props.UserInputState = st
		M.props.Position = pos or DT.Vector3.zero
		M.props.Delta = DT.Vector3.zero
		return io
	end

	local function uisOf(ctx)
		return ctx.game and Inst.findServiceRaw(ctx.game, "UserInputService")
	end
	local function casOf(ctx)
		return ctx.game and Inst.findServiceRaw(ctx.game, "ContextActionService")
	end

	-- =================================================================================================
	--  UserInputService
	-- =================================================================================================
	local function devFlag(value)
		return function(u)
			local ctx = Svc.ctxOf(u)
			return ctx.isClient and value or false
		end
	end
	local UIS = {}
	local function uisCtx(self, m)
		Inst.checkSelf(self, m)
		return ctxOfSvc(self)
	end
	function UIS.GetMouseLocation(self)
		local ctx = uisCtx(self, "GetMouseLocation")
		return state(ctx).mouse
	end
	function UIS.GetMouseDelta(self)
		uisCtx(self, "GetMouseDelta")
		return mk.V2(0, 0)
	end
	function UIS.GetKeysPressed(self)
		local ctx = uisCtx(self, "GetKeysPressed")
		local out = {}
		for _, io in state(ctx).pressed do
			out[#out + 1] = io
		end
		return out
	end
	function UIS.IsKeyDown(self, keyCode)
		local ctx = uisCtx(self, "IsKeyDown")
		local kc = Enum.coerce(keyCode, "KeyCode")
		if kc == nil then
			Util.badArg(1, "IsKeyDown", "Enum.KeyCode", keyCode)
		end
		return state(ctx).pressed[kc] ~= nil
	end
	function UIS.IsMouseButtonPressed(self, inputType)
		local ctx = uisCtx(self, "IsMouseButtonPressed")
		local t = Enum.coerce(inputType, "UserInputType")
		if t == nil then
			Util.badArg(1, "IsMouseButtonPressed", "Enum.UserInputType", inputType)
		end
		return state(ctx).mouseButtons[t] ~= nil
	end
	function UIS.GetMouseButtonsPressed(self)
		local ctx = uisCtx(self, "GetMouseButtonsPressed")
		local out = {}
		for _, io in state(ctx).mouseButtons do
			out[#out + 1] = io
		end
		return out
	end
	function UIS.GetLastInputType(self)
		local ctx = uisCtx(self, "GetLastInputType")
		return state(ctx).lastType
	end
	function UIS.GetFocusedTextBox(self)
		local ctx = uisCtx(self, "GetFocusedTextBox")
		local tb = state(ctx).focused
		if tb and getmt(tb).destroyed then
			state(ctx).focused = nil
			return nil
		end
		return tb
	end
	function UIS.GetConnectedGamepads(self)
		uisCtx(self, "GetConnectedGamepads")
		return {}
	end
	function UIS.GetGamepadConnected(self, gamepad)
		uisCtx(self, "GetGamepadConnected")
		if Enum.coerce(gamepad, "UserInputType") == nil then
			Util.badArg(1, "GetGamepadConnected", "Enum.UserInputType", gamepad)
		end
		return false
	end
	function UIS.GetGamepadState(self, gamepad)
		uisCtx(self, "GetGamepadState")
		return {}
	end
	function UIS.GetNavigationGamepads(self)
		uisCtx(self, "GetNavigationGamepads")
		return {}
	end
	function UIS.IsNavigationGamepad(self, gamepad)
		uisCtx(self, "IsNavigationGamepad")
		return false
	end
	function UIS.SetNavigationGamepad(self, gamepad, enabled)
		uisCtx(self, "SetNavigationGamepad")
	end
	function UIS.GamepadSupports(self, gamepad, keyCode)
		uisCtx(self, "GamepadSupports")
		return false
	end
	function UIS.IsGamepadButtonDown(self, gamepad, keyCode)
		uisCtx(self, "IsGamepadButtonDown")
		return false
	end
	function UIS.GetSupportedGamepadKeyCodes(self, gamepad)
		uisCtx(self, "GetSupportedGamepadKeyCodes")
		return {}
	end
	local keyStrings = {
		Space = " ",
		Return = "\r",
		Tab = "\t",
		Backspace = "\b",
		Zero = "0",
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		Five = "5",
		Six = "6",
		Seven = "7",
		Eight = "8",
		Nine = "9",
		Minus = "-",
		Equals = "=",
		Comma = ",",
		Period = ".",
		Slash = "/",
		Semicolon = ";",
		Quote = "'",
		LeftBracket = "[",
		RightBracket = "]",
		BackSlash = "\\",
		Backquote = "`",
	}
	function UIS.GetStringForKeyCode(self, keyCode)
		uisCtx(self, "GetStringForKeyCode")
		local kc = Enum.coerce(keyCode, "KeyCode")
		if kc == nil then
			Util.badArg(1, "GetStringForKeyCode", "Enum.KeyCode", keyCode)
		end
		local n = kc.Name
		if #n == 1 then
			return n
		end
		return keyStrings[n] or ""
	end
	function UIS.GetImageForKeyCode(self, keyCode)
		uisCtx(self, "GetImageForKeyCode")
		return ""
	end
	function UIS.GetDeviceRotation(self)
		uisCtx(self, "GetDeviceRotation")
		return newInput(nil, Enum.item("UserInputType", "Gyro"), Enum.item("UserInputState", "Change")), DT.CFrame.identity
	end
	function UIS.GetDeviceGravity(self)
		uisCtx(self, "GetDeviceGravity")
		return newInput(nil, Enum.item("UserInputType", "Accelerometer"), Enum.item("UserInputState", "Change"))
	end
	function UIS.GetDeviceAcceleration(self)
		uisCtx(self, "GetDeviceAcceleration")
		return newInput(nil, Enum.item("UserInputType", "Accelerometer"), Enum.item("UserInputState", "Change"))
	end
	function UIS.RecenterUserHeadCFrame(self)
		uisCtx(self, "RecenterUserHeadCFrame")
	end
	function UIS.GetUserCFrame(self, t)
		uisCtx(self, "GetUserCFrame")
		return DT.CFrame.identity
	end
	Inst.registerService("UserInputService", {
		methods = UIS,
		props = {
			KeyboardEnabled = { get = devFlag(true) },
			MouseEnabled = { get = devFlag(true) },
			TouchEnabled = { get = devFlag(false) },
			GamepadEnabled = { get = devFlag(false) },
			VREnabled = { get = devFlag(false) },
			AccelerometerEnabled = { get = devFlag(false) },
			GyroscopeEnabled = { get = devFlag(false) },
			OnScreenKeyboardVisible = { get = devFlag(false) },
			PreferredInput = {
				get = function()
					return Enum.item("PreferredInput", "KeyboardAndMouse")
				end,
			},
		},
	})

	-- =================================================================================================
	--  ContextActionService
	-- =================================================================================================
	local function casCtx(self, m)
		Inst.checkSelf(self, m)
		return ctxOfSvc(self)
	end
	local validInputEnums = { KeyCode = true, UserInputType = true, PlayerActions = true }
	local function bind(self, name, fn, touch, priority, inputs, fname)
		local ctx = casCtx(self, fname)
		name = Util.checkString(name, 1, fname)
		if type(fn) ~= "function" then
			Util.badArg(2, fname, "function", fn)
		end
		if type(touch) ~= "boolean" then
			Util.badArg(3, fname, "boolean", touch)
		end
		local list = {}
		for i = 1, inputs.n do
			local v = inputs[i]
			if Enum.isItem(v) then
				local en = Enum.enumNameOf(v)
				if not validInputEnums[en] then
					raise(fmt("%s: input type '%s' is not supported", fname, tostring(v)))
				end
				list[#list + 1] = v
			elseif type(v) == "string" and #v == 1 then
				list[#list + 1] = v
			else
				raise("Unable to cast value to std::vector<tuple>")
			end
		end
		local s = state(ctx)
		for i = #s.actions, 1, -1 do
			if s.actions[i].name == name then
				table.remove(s.actions, i)
			end
		end
		s.seq += 1
		s.actions[#s.actions + 1] = {
			name = name,
			fn = fn,
			touch = touch,
			priority = priority,
			inputs = list,
			seq = s.seq,
			ctx = Sched.ctx(),
			title = "",
			description = "",
			image = "",
		}
	end
	local CAS = {}
	function CAS.BindAction(self, name, fn, touch, ...)
		bind(self, name, fn, touch, 2000, table.pack(...), "BindAction")
	end
	function CAS.BindActionAtPriority(self, name, fn, touch, priority, ...)
		priority = Util.checkNumber(priority, 4, "BindActionAtPriority")
		bind(self, name, fn, touch, priority, table.pack(...), "BindActionAtPriority")
	end
	function CAS.BindActionToInputTypes(self, name, fn, touch, ...)
		bind(self, name, fn, touch, 2000, table.pack(...), "BindActionToInputTypes")
	end
	function CAS.UnbindAction(self, name)
		local ctx = casCtx(self, "UnbindAction")
		name = Util.checkString(name, 1, "UnbindAction")
		local s = state(ctx)
		for i = #s.actions, 1, -1 do
			if s.actions[i].name == name then
				table.remove(s.actions, i)
			end
		end
	end
	function CAS.UnbindAllActions(self)
		local ctx = casCtx(self, "UnbindAllActions")
		table.clear(state(ctx).actions)
	end
	local function findAction(ctx, name)
		for _, a in state(ctx).actions do
			if a.name == name then
				return a
			end
		end
		return nil
	end
	local function infoOf(a)
		return {
			inputTypes = table.clone(a.inputs),
			priorityLevel = a.priority,
			stackOrder = a.seq,
			createTouchButton = a.touch,
			title = a.title,
			description = a.description,
			image = a.image,
		}
	end
	function CAS.GetBoundActionInfo(self, name)
		local ctx = casCtx(self, "GetBoundActionInfo")
		name = Util.checkString(name, 1, "GetBoundActionInfo")
		local a = findAction(ctx, name)
		return a and infoOf(a) or {}
	end
	function CAS.GetAllBoundActionInfo(self)
		local ctx = casCtx(self, "GetAllBoundActionInfo")
		local out = {}
		for _, a in state(ctx).actions do
			out[a.name] = infoOf(a)
		end
		return out
	end
	local function setter(field, fname)
		return function(self, name, value)
			local ctx = casCtx(self, fname)
			name = Util.checkString(name, 1, fname)
			local a = findAction(ctx, name)
			if a then
				a[field] = value
			end
		end
	end
	CAS.SetTitle = setter("title", "SetTitle")
	CAS.SetDescription = setter("description", "SetDescription")
	CAS.SetImage = setter("image", "SetImage")
	CAS.SetPosition = setter("position", "SetPosition")
	function CAS.GetButton(self, name)
		casCtx(self, "GetButton")
		Util.checkString(name, 1, "GetButton")
		Svc.latency(0)
		return nil -- keine Touch-Knöpfe (Desktop)
	end
	function CAS.GetCurrentLocalToolIcon(self)
		casCtx(self, "GetCurrentLocalToolIcon")
		return ""
	end
	function CAS.BindActivate(self, inputType, ...)
		casCtx(self, "BindActivate")
	end
	function CAS.UnbindActivate(self, inputType, ...)
		casCtx(self, "UnbindActivate")
	end
	Inst.registerService("ContextActionService", { methods = CAS })

	-- Handler synchron ausführen; Ergebnis (wenn ohne Yield fertig) zurückgeben
	local function runHandler(fn, ctx, label, ...)
		local res = nil
		local co = Sched.newThread(function(...)
			res = table.pack(fn(...))
		end, ctx, label)
		Sched.resume(co, ...)
		return res
	end

	local function matches(a, keyCode, inputType)
		for _, inp in a.inputs do
			if inp == keyCode or inp == inputType then
				return true
			end
			if type(inp) == "string" and keyCode and string.upper(inp) == keyCode.Name then
				return true
			end
		end
		return false
	end

	local function dispatch(ctx, io, keyCode, inputType, stateName, gameProcessed)
		local s = state(ctx)
		-- CAS: höchste Priorität zuerst, bei Gleichstand zuletzt gebundene zuerst
		local list = {}
		for _, a in s.actions do
			if matches(a, keyCode, inputType) then
				list[#list + 1] = a
			end
		end
		table.sort(list, function(x, y)
			if x.priority ~= y.priority then
				return x.priority > y.priority
			end
			return x.seq > y.seq
		end)
		local sunk = false
		for _, a in list do
			local res = runHandler(a.fn, a.ctx, "CAS:" .. a.name, a.name, Enum.item("UserInputState", stateName), io)
			local r = res and res[1]
			if r == nil or r == Enum.item("ContextActionResult", "Sink") then
				sunk = true
				break
			end
		end
		local uis = uisOf(ctx)
		if uis then
			local ev = stateName == "Begin" and "InputBegan" or (stateName == "End" and "InputEnded" or "InputChanged")
			Inst.fire(uis, ev, io, gameProcessed == true)
		end
		return sunk
	end

	function In.key(ctx, keyName, down)
		local s = state(ctx)
		local kc = Enum.item("KeyCode", keyName)
		local kb = Enum.item("UserInputType", "Keyboard")
		local io = s.pressed[kc]
		if down then
			if io then
				return
			end
			io = newInput(kc, kb, Enum.item("UserInputState", "Begin"))
			s.pressed[kc] = io
			if s.lastType ~= kb then
				s.lastType = kb
				local uis = uisOf(ctx)
				if uis then
					Inst.fire(uis, "LastInputTypeChanged", kb)
				end
			end
			dispatch(ctx, io, kc, kb, "Begin")
		else
			if not io then
				return
			end
			s.pressed[kc] = nil
			Inst.rawSet(io, "UserInputState", Enum.item("UserInputState", "End"))
			dispatch(ctx, io, kc, kb, "End")
		end
	end

	function In.mouseButton(ctx, n, down, x, y, overGui)
		local s = state(ctx)
		local t = Enum.item("UserInputType", "MouseButton" .. tostring(n or 1))
		if x and y then
			s.mouse = mk.V2(x, y)
		end
		local pos = mk.V3(s.mouse.X, s.mouse.Y, 0)
		if down then
			local io = newInput(nil, t, Enum.item("UserInputState", "Begin"), pos)
			s.mouseButtons[t] = io
			if s.lastType ~= t then
				s.lastType = t
				local uis = uisOf(ctx)
				if uis then
					Inst.fire(uis, "LastInputTypeChanged", t)
				end
			end
			dispatch(ctx, io, nil, t, "Begin", overGui)
			return io
		else
			local io = s.mouseButtons[t] or newInput(nil, t, Enum.item("UserInputState", "End"), pos)
			s.mouseButtons[t] = nil
			Inst.rawSet(io, "UserInputState", Enum.item("UserInputState", "End"))
			dispatch(ctx, io, nil, t, "End", overGui)
			return io
		end
	end

	--- Harness: GuiButton anklicken (Reihenfolge wie Roblox: MouseEnter, InputBegan, MouseButton1Down, InputEnded,
	--- MouseButton1Up, MouseButton1Click, Activated). Liefert false, wenn der Knopf nicht klickbar ist.
	--- Wie Roblox: Interactable = false -> keine Eingabe-Ereignisse; Active = false -> kein Activated
	--- (MouseButton1Click feuert trotzdem). cx/cy optional (Standard: Mitte des Knopfs).
	function In.clickGui(ctx, btn, cx, cy)
		local M = getmt(btn)
		if M.destroyed or not M.cls.isA.GuiButton then
			return false
		end
		if Inst.getProp(btn, "Interactable") == false then
			return false
		end
		if cx == nil or cy == nil then
			local x, y, w, h = Inst.Gui.abs(btn)
			cx, cy = x + w / 2, y + h / 2
		end
		local s = state(ctx)
		if s.hover ~= btn then
			if s.hover and not getmt(s.hover).destroyed then
				Inst.fire(s.hover, "MouseLeave", cx, cy)
			end
			s.hover = btn
			Inst.fire(btn, "MouseEnter", cx, cy)
		end
		local io = In.mouseButton(ctx, 1, true, cx, cy, true)
		Inst.fire(btn, "InputBegan", io)
		Inst.fire(btn, "MouseButton1Down", cx, cy)
		Sched.flush()
		local io2 = In.mouseButton(ctx, 1, false, cx, cy, true)
		Inst.fire(btn, "InputEnded", io2)
		Inst.fire(btn, "MouseButton1Up", cx, cy)
		Inst.fire(btn, "MouseButton1Click")
		if Inst.getProp(btn, "Active") ~= false then
			Inst.fire(btn, "Activated", io2, 1)
		end
		Sched.flush()
		return true
	end

	--- Harness: Maus verlässt das zuletzt "überfahrene" GUI-Objekt (MouseLeave)
	function In.unhover(ctx)
		local s = state(ctx)
		if s.hover and not getmt(s.hover).destroyed then
			local x, y = s.mouse.X, s.mouse.Y
			Inst.fire(s.hover, "MouseLeave", x, y)
		end
		s.hover = nil
	end

	function In.windowFocus(ctx, focused)
		local uis = uisOf(ctx)
		if uis then
			Inst.fire(uis, focused and "WindowFocused" or "WindowFocusReleased")
		end
	end

	-- TextBox-Fokus (für UI-Crawl) – CaptureFocus/ReleaseFocus der TextBox nutzen das mit
	function In.focusTextBox(ctx, tb)
		local s = state(ctx)
		if s.focused == tb then
			return
		end
		if s.focused then
			In.releaseTextBox(ctx, s.focused, false)
		end
		s.focused = tb
		local M = getmt(tb)
		M.ext = M.ext or {}
		M.ext.focused = true
		-- wie Roblox: ClearTextOnFocus (Standard true) leert den Text beim Fokussieren
		if Inst.getProp(tb, "ClearTextOnFocus") ~= false and (M.props.Text or "") ~= "" then
			Inst.setProp(tb, "Text", "")
		end
		Inst.fire(tb, "Focused")
		local uis = uisOf(ctx)
		if uis then
			Inst.fire(uis, "TextBoxFocused", tb)
		end
	end
	function In.releaseTextBox(ctx, tb, enter)
		local s = state(ctx)
		local M = getmt(tb)
		if not (M.ext and M.ext.focused) then
			return
		end
		M.ext.focused = false
		if s.focused == tb then
			s.focused = nil
		end
		local io = newInput(
			enter and Enum.item("KeyCode", "Return") or nil,
			Enum.item("UserInputType", enter and "Keyboard" or "MouseButton1"),
			Enum.item("UserInputState", "Begin")
		)
		Inst.fire(tb, "FocusLost", enter == true, io)
		local uis = uisOf(ctx)
		if uis then
			Inst.fire(uis, "TextBoxFocusReleased", tb)
		end
	end
	Inst.define("TextBox", {
		methods = {
			CaptureFocus = function(self)
				Inst.checkSelf(self, "CaptureFocus")
				local ctx = Svc.ctxOf(self)
				if ctx.isClient then
					In.focusTextBox(ctx, self)
				end
			end,
			ReleaseFocus = function(self, submitted)
				Inst.checkSelf(self, "ReleaseFocus")
				local ctx = Svc.ctxOf(self)
				In.releaseTextBox(ctx, self, submitted == true)
			end,
			IsFocused = function(self)
				local M = Inst.checkSelf(self, "IsFocused")
				return M.ext ~= nil and M.ext.focused == true
			end,
		},
	})

	Inst.define("InputObject", {
		methods = {
			IsModifierKeyDown = function(self, key)
				Inst.checkSelf(self, "IsModifierKeyDown")
				if Enum.coerce(key, "ModifierKey") == nil then
					Util.badArg(1, "IsModifierKeyDown", "Enum.ModifierKey", key)
				end
				return false
			end,
		},
	})

	-- =================================================================================================
	--  GuiService
	-- =================================================================================================
	local GS = {}
	function GS.GetGuiInset(self)
		Inst.checkSelf(self, "GetGuiInset")
		local ctx = ctxOfSvc(self)
		if not ctx.isClient then
			return mk.V2(0, 0), mk.V2(0, 0)
		end
		return mk.V2(0, R.config.topInset or 58), mk.V2(0, 0)
	end
	function GS.IsTenFootInterface(self)
		Inst.checkSelf(self, "IsTenFootInterface")
		return false
	end
	function GS.CloseInspectMenu(self)
		Inst.checkSelf(self, "CloseInspectMenu")
	end
	function GS.InspectPlayerFromUserId(self, userId)
		Inst.checkSelf(self, "InspectPlayerFromUserId")
		Util.checkNumber(userId, 1, "InspectPlayerFromUserId")
	end
	function GS.InspectPlayerFromHumanoidDescription(self, desc, name)
		Inst.checkSelf(self, "InspectPlayerFromHumanoidDescription")
	end
	function GS.GetEmotesMenuOpen(self)
		Inst.checkSelf(self, "GetEmotesMenuOpen")
		return false
	end
	function GS.GetInspectMenuEnabled(self)
		Inst.checkSelf(self, "GetInspectMenuEnabled")
		return true
	end
	function GS.GetGameplayPausedNotificationEnabled(self)
		Inst.checkSelf(self, "GetGameplayPausedNotificationEnabled")
		return true
	end
	function GS.DismissNotification(self, id)
		Inst.checkSelf(self, "DismissNotification")
		return false
	end
	for _, m in {
		"SetEmotesMenuOpen",
		"SetInspectMenuEnabled",
		"SetGameplayPausedNotificationEnabled",
		"AddSelectionParent",
		"AddSelectionTuple",
		"RemoveSelectionGroup",
		"Select",
	} do
		if R.api.classes.GuiService.m and R.api.classes.GuiService.m[m] ~= nil and not string.find(R.api.classes.GuiService.m[m], "x") then
			GS[m] = function(self)
				Inst.checkSelf(self, m)
			end
		end
	end
	if R.api.classes.GuiService.m and R.api.classes.GuiService.m.GetInsetArea == "" then
		function GS.GetInsetArea(self, kind)
			Inst.checkSelf(self, "GetInsetArea")
			local vp = R.config.viewport or { 1280, 720 }
			return DT.Rect.new(0, R.config.topInset or 58, vp[1], vp[2])
		end
	end
	Inst.registerService("GuiService", {
		methods = GS,
		props = {
			TopbarInset = {
				get = function(u)
					local vp = R.config.viewport or { 1280, 720 }
					if not Svc.ctxOf(u).isClient then
						return DT.Rect.new(0, 0, 0, 0)
					end
					return DT.Rect.new(64, 0, vp[1] - 64, R.config.topInset or 58)
				end,
			},
			MenuIsOpen = {
				get = function()
					return false
				end,
			},
		},
		init = function(u, M)
			M.props.TouchControlsEnabled = true
			M.props.AutoSelectGuiEnabled = true
			M.props.GuiNavigationEnabled = true
		end,
	})

	-- =================================================================================================
	--  StarterGui (SetCore/GetCore/SetCoreGuiEnabled)
	-- =================================================================================================
	local setCoreNames = {
		ChatActive = "boolean",
		PointsNotificationsActive = "boolean",
		BadgesNotificationsActive = "boolean",
		ResetButtonCallback = "any",
		ChatMakeSystemMessage = "table",
		SendNotification = "table",
		TopbarEnabled = "boolean",
		DevConsoleVisible = "boolean",
		PromptSendFriendRequest = "Instance",
		PromptUnfriend = "Instance",
		PromptBlockPlayer = "Instance",
		PromptUnblockPlayer = "Instance",
		AvatarContextMenuEnabled = "boolean",
		AvatarContextMenuTarget = "Instance",
		AddAvatarContextMenuOption = "any",
		RemoveAvatarContextMenuOption = "any",
		AvatarContextMenuTheme = "table",
		CoreGuiChatConnections = "table",
		ChatWindowSize = "UDim2",
		ChatWindowPosition = "UDim2",
		ChatBarDisabled = "boolean",
		VRRotationIntensity = "string",
	}
	local SG = {}
	local function coreState(ctx)
		local s = ctx.data.core
		if s == nil then
			s = { values = {}, guis = {} }
			ctx.data.core = s
		end
		return s
	end
	function SG.SetCore(self, name, value)
		Inst.checkSelf(self, "SetCore")
		name = Util.checkString(name, 1, "SetCore")
		local ctx = ctxOfSvc(self)
		if not ctx.isClient then
			raise(fmt("SetCore: %s has not been registered by the CoreScripts", name))
		end
		local t = setCoreNames[name]
		if t == nil then
			raise(fmt("SetCore: %s has not been registered by the CoreScripts", name))
		end
		if t ~= "any" and typeof(value) ~= t then
			raise(fmt("SetCore: %s expects a %s, got %s", name, t, typeof(value)))
		end
		if name == "SendNotification" then
			if type(value.Title) ~= "string" or type(value.Text) ~= "string" then
				raise("SetCore: SendNotification requires Title and Text strings")
			end
		end
		coreState(ctx).values[name] = value
	end
	function SG.GetCore(self, name)
		Inst.checkSelf(self, "GetCore")
		name = Util.checkString(name, 1, "GetCore")
		local ctx = ctxOfSvc(self)
		local known = {
			PointsNotificationsActive = true,
			BadgesNotificationsActive = true,
			AvatarContextMenuEnabled = true,
			ChatActive = true,
			ChatWindowSize = true,
			ChatWindowPosition = true,
			ChatBarDisabled = true,
			GetBlockedUserIds = true,
			PlayerBlockedEvent = true,
			PlayerUnblockedEvent = true,
			PlayerMutedEvent = true,
			PlayerUnmutedEvent = true,
			PlayerFriendedEvent = true,
			PlayerUnfriendedEvent = true,
			DevConsoleVisible = true,
			VRRotationIntensity = true,
		}
		if not ctx.isClient or not known[name] then
			raise(fmt("GetCore: %s has not been registered by the CoreScripts", name))
		end
		local v = coreState(ctx).values[name]
		if v ~= nil then
			return v
		end
		if name == "GetBlockedUserIds" then
			return {}
		elseif name == "DevConsoleVisible" or name == "ChatBarDisabled" then
			return false
		elseif string.find(name, "Event$") then
			return R.Signal.new(name)
		end
		return true
	end
	function SG.SetCoreGuiEnabled(self, coreGuiType, enabled)
		Inst.checkSelf(self, "SetCoreGuiEnabled")
		local t = Enum.coerce(coreGuiType, "CoreGuiType")
		if t == nil then
			Util.badArg(1, "SetCoreGuiEnabled", "Enum.CoreGuiType", coreGuiType)
		end
		enabled = Util.checkBool(enabled, 2, "SetCoreGuiEnabled")
		local ctx = ctxOfSvc(self)
		coreState(ctx).guis[t] = enabled
	end
	function SG.GetCoreGuiEnabled(self, coreGuiType)
		Inst.checkSelf(self, "GetCoreGuiEnabled")
		local t = Enum.coerce(coreGuiType, "CoreGuiType")
		if t == nil then
			Util.badArg(1, "GetCoreGuiEnabled", "Enum.CoreGuiType", coreGuiType)
		end
		local ctx = ctxOfSvc(self)
		local s = coreState(ctx).guis
		local v = s[t]
		if v == nil then
			v = s[Enum.item("CoreGuiType", "All")]
		end
		if v == nil then
			return true
		end
		return v
	end
	Inst.registerService("StarterGui", { methods = SG })

	-- =================================================================================================
	--  HapticService / VRService / GamepadService
	-- =================================================================================================
	Inst.registerService("HapticService", {
		methods = {
			IsVibrationSupported = function(self)
				Inst.checkSelf(self, "IsVibrationSupported")
				return false
			end,
			IsMotorSupported = function(self)
				Inst.checkSelf(self, "IsMotorSupported")
				return false
			end,
			SetMotor = function(self)
				Inst.checkSelf(self, "SetMotor")
			end,
			GetMotor = function(self)
				Inst.checkSelf(self, "GetMotor")
				return 0
			end,
		},
	})
	Inst.registerService("VRService", {
		methods = {
			GetUserCFrameEnabled = function(self)
				Inst.checkSelf(self, "GetUserCFrameEnabled")
				return false
			end,
			GetUserCFrame = function(self)
				Inst.checkSelf(self, "GetUserCFrame")
				return DT.CFrame.identity
			end,
			RecenterUserHeadCFrame = function(self)
				Inst.checkSelf(self, "RecenterUserHeadCFrame")
			end,
			RequestNavigation = function(self)
				Inst.checkSelf(self, "RequestNavigation")
			end,
			GetTouchpadMode = function(self)
				Inst.checkSelf(self, "GetTouchpadMode")
				return Enum.item("VRTouchpadMode", "Touch")
			end,
			SetTouchpadMode = function(self)
				Inst.checkSelf(self, "SetTouchpadMode")
			end,
		},
	})
	Inst.registerService("GamepadService", {
		methods = {
			EnableGamepadCursor = function(self)
				Inst.checkSelf(self, "EnableGamepadCursor")
			end,
			DisableGamepadCursor = function(self)
				Inst.checkSelf(self, "DisableGamepadCursor")
			end,
		},
	})
end
