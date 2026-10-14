--!nocheck
-- =====================================================================
--  Headless-Harness · Instanz-System (Kern)
--
--  Jede Instanz ist newproxy(true)-userdata; ihre Metatabelle M ist zugleich der interne Zustand:
--    M.cls       Klassen-Record (siehe Inst.class)          M.name, M.parent, M.children (Array, Einfügereihenfolge)
--    M.props     gesetzte Property-Werte (Rest = Defaults) M.attrs, M.tags (Liste), M.tagSet
--    M.signals   Event-Signale (lazy)                      M.propSignals, M.attrSignals (lazy)
--    M.callbacks gesetzte Callbacks (OnServerInvoke …)     M.destroyed, M.parentLocked, M.id, M.ext (frei)
--  Zugriff wie Roblox: Properties/Methoden/Events (laut API + Harness-Verhalten) vor Kindern; unbekannt ->
--  'X is not a valid member of Part "Workspace.Foo"'. Schreiben prüft Typ (float32/int-Rundung, Enum aus
--  EnumItem/Name/Zahl, Instanz-Klasse), read only und Sicherheitsstufe.
--
--  Klassen-Verhalten (Harness-API für spätere Module):
--    Inst.define(className, {
--      init = function(inst, M) end,                         -- nach Erzeugung (auch bei Clone)
--      props = { Prop = { get = fn(inst, M, name), set = fn(inst, M, value, name) } },  -- Wert ist bereits geprüft
--      methods = { Method = fn(self, ...) },                 -- muss laut API existieren
--      callbacks = { Callback = { onSet = fn(inst, M, fn) } },
--      onChanged = fn(inst, M, prop),                        -- nach jeder Property-Änderung
--      onAncestry = fn(inst, M, oldParent, newParent),       -- wenn sich Parent dieser Instanz ändert
--      postClone = fn(copy, CM, src, SM),                    -- nach Clone (Referenzen bereits umgebogen)
--      onDestroy = fn(inst, M),
--    })
--  Nicht implementierte, laut API existierende Methoden sind Stubs: geben nil zurück und landen als
--  "unmocked" im Report (kein Fehler). Nicht existierende Methoden -> Roblox-Fehler.
--
--  Harness-Helfer: Inst.create(class, props?, parent?) (ohne creatable-Prüfung), Inst.meta(inst), Inst.is(v),
--  Inst.getProp/setProp (mit Typprüfung, ohne read only/Sicherheit), Inst.rawSet(inst, prop, v[, silent]),
--  Inst.changed(inst, M, prop), Inst.fire(inst, event, …), Inst.signal(inst, event), Inst.setParent(inst, p),
--  Inst.destroy, Inst.clone, Inst.fullName, Inst.isA, Inst.findChild, Inst.descendants, Inst.dataModelOf,
--  Inst.observe(kind, fn) mit kind = created|changed|reparented|destroying|attribute|tag,
--  Inst.setVisibilityFilter(fn(inst, ctx) -> bool) (für Server/Client-Sichtbarkeit, Streaming).
-- =====================================================================
return function(R)
	local Util = R.Util
	local Report = R.Report
	local Sched = R.Sched
	local Signal = R.Signal
	local DT = R.DT
	local Enum = R.Enum
	local api = R.api
	local raise = Util.raise
	local typeof = Util.typeof
	local getmt = getmetatable
	local fmt = string.format

	local Inst = {}
	Inst.observers = { created = {}, changed = {}, reparented = {}, destroying = {}, attribute = {}, tag = {} }
	local observers = Inst.observers

	function Inst.observe(kind, fn)
		local list = observers[kind]
		assert(list, "Harness: unbekannter Observer-Typ " .. tostring(kind))
		list[#list + 1] = fn
		return function()
			local i = table.find(list, fn)
			if i then
				table.remove(list, i)
			end
		end
	end

	local function notify(kind, a, b, c, d)
		local list = observers[kind]
		if #list == 0 then
			return
		end
		for _, fn in list do
			local ok, err = xpcall(fn, debug.traceback, a, b, c, d)
			if not ok then
				Report.harnessError("Observer " .. kind .. " fehlgeschlagen: " .. Util.errToString(err))
			end
		end
	end
	Inst.notify = notify

	-- Sichtbarkeit (nil = alles sichtbar)
	local visibilityFilter = nil
	function Inst.setVisibilityFilter(fn)
		visibilityFilter = fn
	end
	local function visible(inst)
		if visibilityFilter == nil then
			return true
		end
		return visibilityFilter(inst, Sched.ctx())
	end
	Inst.visible = visible

	-- =================================================================================================
	--  Klassen-Records
	-- =================================================================================================
	local behaviours = {}
	local records = {}
	local instIndex, instNewindex, instToString
	local findChildFwd -- = findChild (weiter unten definiert)

	local function capitalize(s)
		return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
	end

	local function secError(name)
		raise(fmt("The current thread cannot access '%s' (lacking capability RobloxScript)", name))
	end

	-- Typprüfung/Umwandlung beim Schreiben ------------------------------------------------------------
	local function assignErr(prop, expected, v)
		raise(fmt("Unable to assign property %s. %s expected, got %s", prop, expected, typeof(v)))
	end
	local function toNumber(v)
		local t = type(v)
		if t == "number" then
			return v
		elseif t == "string" then
			return tonumber(v)
		end
		return nil
	end
	local coercers = {}
	coercers.b = function(d, v)
		if type(v) ~= "boolean" then
			assignErr(d.name, "bool", v)
		end
		return v
	end
	coercers.s = function(d, v)
		local t = type(v)
		if t == "string" then
			return v
		elseif t == "number" then
			return tostring(v)
		end
		assignErr(d.name, "string", v)
	end
	coercers.f = function(d, v)
		local x = toNumber(v)
		if x == nil then
			assignErr(d.name, "number", v)
		end
		return Util.f32(x)
	end
	coercers.d = function(d, v)
		local x = toNumber(v)
		if x == nil then
			assignErr(d.name, "number", v)
		end
		return x
	end
	coercers.n = coercers.d
	coercers.i = function(d, v)
		local x = toNumber(v)
		if x == nil then
			assignErr(d.name, "number", v)
		end
		return Util.toInt(x)
	end
	coercers.l = coercers.i
	coercers.a = function(d, v)
		return v
	end
	coercers.F = function(d, v)
		if v ~= nil and type(v) ~= "function" then
			assignErr(d.name, "function", v)
		end
		return v
	end
	coercers.C = function(d, v)
		local sub = d.sub
		if v == nil and sub == "PhysicalProperties" then
			return nil
		end
		local t = typeof(v)
		if t ~= sub then
			assignErr(d.name, sub, v)
		end
		if sub == "Font" then
			return DT.copyFont(v)
		end
		return v
	end
	coercers.E = function(d, v)
		local it = Enum.coerce(v, d.sub)
		if it == nil then
			if Enum.isItem(v) then
				raise(
					fmt(
						"Unable to assign property %s. EnumItem of type %s expected, got an EnumItem of type %s",
						d.name,
						d.sub,
						Enum.enumNameOf(v)
					)
				)
			elseif type(v) == "string" or type(v) == "number" then
				raise(fmt('Invalid value "%s" for enum %s', tostring(v), d.sub))
			end
			assignErr(d.name, "EnumItem", v)
		end
		return it
	end
	coercers.I = function(d, v)
		if v == nil then
			return nil
		end
		local M = Util.hostMeta(v)
		if M == nil or M.__index ~= instIndex then
			assignErr(d.name, "Instance", v)
		end
		local sub = d.sub
		if sub ~= "Instance" and not M.cls.isA[sub] then
			raise(fmt("Unable to assign property %s. %s expected, got %s", d.name, sub, M.cls.name))
		end
		return v
	end

	-- Desc-Erzeugung ---------------------------------------------------------------------------------
	local function makePropDesc(name, spec, owner)
		local t, flags = string.match(spec, "^([^|]*)|?(.*)$")
		local base = string.sub(t, 1, 1)
		local sub = nil
		if base == "C" or base == "E" or base == "I" then
			sub = string.sub(t, 3)
		end
		local d = {
			kind = "prop",
			name = name,
			owner = owner,
			t = base,
			sub = sub,
			ro = string.find(flags, "r", 1, true) ~= nil,
			nowrite = string.find(flags, "w", 1, true) ~= nil,
			inaccessible = string.find(flags, "x", 1, true) ~= nil,
			deprecated = string.find(flags, "d", 1, true) ~= nil,
			hidden = string.find(flags, "h", 1, true) ~= nil,
			copy = (base == "C" and sub == "Font"),
		}
		d.coerce = coercers[base] or coercers.a
		return d
	end

	local function makeStub(owner, name)
		return function(self, ...)
			local M = Util.hostMeta(self)
			if M == nil or M.__index ~= instIndex then
				raise(fmt("Expected ':' not '.' calling member function %s", name))
			end
			Report.unmockedCall(M.cls.name, name, "method")
			return nil
		end
	end

	local function wrapDeprecated(owner, name, fn)
		local label = owner .. ":" .. name
		return function(...)
			Report.deprecatedUse(label)
			return fn(...)
		end
	end

	local function makeMethodDesc(name, flags, owner)
		local d = {
			kind = "method",
			name = name,
			owner = owner,
			deprecated = string.find(flags, "d", 1, true) ~= nil,
			yields = string.find(flags, "y", 1, true) ~= nil,
			inaccessible = string.find(flags, "x", 1, true) ~= nil,
			impl = false,
		}
		if d.inaccessible then
			d.fn = function()
				raise(fmt("The current thread cannot call '%s' (lacking capability RobloxScript)", name))
			end
		else
			d.fn = makeStub(owner, name)
		end
		return d
	end

	local function copyDesc(d)
		local c = {}
		for k, v in d do
			c[k] = v
		end
		return c
	end

	local function applyBehaviour(rec, members, className, spec)
		if spec.props then
			for pname, acc in spec.props do
				local d = members[pname]
				if d == nil or d.kind ~= "prop" then
					Report.harnessError(
						"Inst.define(" .. className .. "): Property " .. pname .. " existiert laut API nicht"
					)
				else
					d = copyDesc(d)
					if acc.get then
						d.get = acc.get
					end
					if acc.set then
						d.set = acc.set
					end
					if acc.readonly ~= nil then
						d.ro = acc.readonly
					end
					members[pname] = d
				end
			end
		end
		if spec.methods then
			for mname, fn in spec.methods do
				local d = members[mname]
				if d == nil or d.kind ~= "method" then
					Report.harnessError(
						"Inst.define(" .. className .. "): Methode " .. mname .. " existiert laut API nicht"
					)
				else
					d = copyDesc(d)
					d.impl = true
					d.rawFn = fn
					d.fn = d.deprecated and wrapDeprecated(d.owner, mname, fn) or fn
					members[mname] = d
				end
			end
		end
		if spec.callbacks then
			for cname, acc in spec.callbacks do
				local d = members[cname]
				if d == nil or d.kind ~= "callback" then
					Report.harnessError(
						"Inst.define(" .. className .. "): Callback " .. cname .. " existiert laut API nicht"
					)
				else
					d = copyDesc(d)
					d.onSet = acc.onSet
					members[cname] = d
				end
			end
		end
		if spec.init then
			rec.inits[#rec.inits + 1] = spec.init
		end
		if spec.onChanged then
			rec.changedHooks[#rec.changedHooks + 1] = spec.onChanged
		end
		if spec.onAncestry then
			rec.ancestryHooks[#rec.ancestryHooks + 1] = spec.onAncestry
		end
		if spec.postClone then
			rec.cloneHooks[#rec.cloneHooks + 1] = spec.postClone
		end
		if spec.onDestroy then
			rec.destroyHooks[#rec.destroyHooks + 1] = spec.onDestroy
		end
		-- Signal-Optionen (z. B. onConnect für lazy aktivierte Abs-Größen-Überwachung)
		if spec.signalOpts then
			rec.signalOpts = rec.signalOpts or {}
			for k, v in spec.signalOpts do
				rec.signalOpts[k] = v
			end
		end
		if spec.propSignalOpts then
			rec.propSignalOpts = rec.propSignalOpts or {}
			for k, v in spec.propSignalOpts do
				rec.propSignalOpts[k] = v
			end
		end
	end

	-- Kleinbuchstaben-Aliase (className, findFirstChild, childAdded …) auf die Hauptversion abbilden
	local function resolveAliases(members)
		for name, d in members do
			local first = string.sub(name, 1, 1)
			if first ~= string.upper(first) then
				local main = members[capitalize(name)]
				if main and main.kind == d.kind and main ~= d then
					if d.kind == "method" and not d.impl and main.impl then
						local nd = copyDesc(d)
						nd.impl = true
						nd.fn = wrapDeprecated(d.owner, name, main.rawFn or main.fn)
						members[name] = nd
					elseif d.kind == "prop" and not d.get and not d.set then
						local nd = copyDesc(main)
						nd.name = name
						nd.deprecated = true
						nd.alias = main.name
						members[name] = nd
					elseif d.kind == "event" then
						local nd = copyDesc(d)
						nd.alias = main.name
						members[name] = nd
					end
				end
			end
		end
	end

	local function buildRecord(rec)
		local name = rec.name
		local data = rec.data
		local superRec = rec.superRec
		local members = {}
		rec.inits, rec.changedHooks, rec.ancestryHooks, rec.cloneHooks, rec.destroyHooks = {}, {}, {}, {}, {}
		rec.isA = {}
		rec.rawDefaults = {}
		rec.signalOpts = nil
		rec.propSignalOpts = nil
		if superRec then
			if superRec.signalOpts then
				rec.signalOpts = table.clone(superRec.signalOpts)
			end
			if superRec.propSignalOpts then
				rec.propSignalOpts = table.clone(superRec.propSignalOpts)
			end
			for k, v in superRec.members do
				members[k] = v
			end
			for k in superRec.isA do
				rec.isA[k] = true
			end
			for k, v in superRec.rawDefaults do
				rec.rawDefaults[k] = v
			end
			for _, f in superRec.inits do
				rec.inits[#rec.inits + 1] = f
			end
			for _, f in superRec.changedHooks do
				rec.changedHooks[#rec.changedHooks + 1] = f
			end
			for _, f in superRec.ancestryHooks do
				rec.ancestryHooks[#rec.ancestryHooks + 1] = f
			end
			for _, f in superRec.cloneHooks do
				rec.cloneHooks[#rec.cloneHooks + 1] = f
			end
			for _, f in superRec.destroyHooks do
				rec.destroyHooks[#rec.destroyHooks + 1] = f
			end
		end
		rec.isA[name] = true
		if data.p then
			for pname, spec in data.p do
				members[pname] = makePropDesc(pname, spec, name)
			end
		end
		if data.m then
			for mname, flags in data.m do
				members[mname] = makeMethodDesc(mname, flags, name)
			end
		end
		if data.e then
			for ename, flags in data.e do
				members[ename] = {
					kind = "event",
					name = ename,
					owner = name,
					deprecated = string.find(flags, "d", 1, true) ~= nil,
					inaccessible = string.find(flags, "x", 1, true) ~= nil,
				}
			end
		end
		if data.c then
			for cname, flags in data.c do
				members[cname] = {
					kind = "callback",
					name = cname,
					owner = name,
					deprecated = string.find(flags, "d", 1, true) ~= nil,
					inaccessible = string.find(flags, "x", 1, true) ~= nil,
				}
			end
		end
		if data.d then
			for k, v in data.d do
				rec.rawDefaults[k] = v
			end
		end
		local specs = behaviours[name]
		if specs then
			for _, spec in specs do
				applyBehaviour(rec, members, name, spec)
			end
		end
		resolveAliases(members)
		rec.members = members
		rec.defaultCache = {}
		rec.valueBase = rec.isA.ValueBase == true
		rec.isGui = rec.isA.GuiBase2d == true
		rec.isPart = rec.isA.BasePart == true
	end

	local function getRecord(name)
		local rec = records[name]
		if rec then
			return rec
		end
		local data = api.classes[name]
		if data == nil then
			return nil
		end
		local superRec = data.s and getRecord(data.s) or nil
		local flags = data.f or ""
		rec = {
			name = name,
			data = data,
			superRec = superRec,
			creatable = string.find(flags, "c", 1, true) ~= nil,
			service = string.find(flags, "s", 1, true) ~= nil,
			notReplicated = string.find(flags, "n", 1, true) ~= nil,
			deprecated = string.find(flags, "d", 1, true) ~= nil,
			subclasses = {},
		}
		records[name] = rec
		if superRec then
			superRec.subclasses[#superRec.subclasses + 1] = rec
		end
		buildRecord(rec)
		return rec
	end
	Inst.class = getRecord

	local function rebuildTree(rec)
		buildRecord(rec)
		for _, sub in rec.subclasses do
			rebuildTree(sub)
		end
	end

	function Inst.define(className, spec)
		if api.classes[className] == nil then
			error("Harness: Inst.define für unbekannte Klasse " .. tostring(className), 2)
		end
		behaviours[className] = behaviours[className] or {}
		table.insert(behaviours[className], spec)
		local rec = records[className]
		if rec then
			rebuildTree(rec) -- bereits gebaute Records in-place aktualisieren
		end
	end

	-- Defaults ---------------------------------------------------------------------------------------
	local function decodeRaw(raw, d)
		local t = type(raw)
		if t ~= "table" then
			if d.t == "E" then
				return Enum.fromValue(d.sub, raw) or Enum.first(d.sub)
			end
			if d.t == "C" or d.t == "I" then
				return nil
			end
			return raw
		end
		local tag = raw[1]
		local mk = DT.make
		if tag == "V3" then
			return mk.V3(raw[2], raw[3], raw[4])
		elseif tag == "V2" then
			return mk.V2(raw[2], raw[3])
		elseif tag == "CF" then
			return mk.CF(
				raw[2],
				raw[3],
				raw[4],
				raw[5],
				raw[6],
				raw[7],
				raw[8],
				raw[9],
				raw[10],
				raw[11],
				raw[12],
				raw[13]
			)
		elseif tag == "C3" then
			return mk.C3(raw[2], raw[3], raw[4])
		elseif tag == "U2" then
			return mk.U2(raw[2], raw[3], raw[4], raw[5])
		elseif tag == "U" then
			return mk.UD(raw[2], raw[3])
		elseif tag == "BC" then
			return mk.BC(raw[2])
		elseif tag == "NR" then
			return mk.NR(raw[2], raw[3])
		elseif tag == "NS" then
			local kps = {}
			for i = 2, #raw, 3 do
				kps[#kps + 1] = mk.NSK(raw[i], raw[i + 1], raw[i + 2])
			end
			return mk.NS(kps)
		elseif tag == "CS" then
			local kps = {}
			for i = 2, #raw, 4 do
				kps[#kps + 1] = mk.CSK(raw[i], mk.C3(raw[i + 1], raw[i + 2], raw[i + 3]))
			end
			return mk.CS(kps)
		elseif tag == "FT" then
			return mk.FT(raw[2], raw[3], raw[4])
		elseif tag == "RC" then
			return mk.RC(raw[2], raw[3], raw[4], raw[5])
		elseif tag == "FA" then
			return mk.FAbits(raw[2])
		elseif tag == "AX" then
			return mk.AXbits(raw[2])
		elseif tag == "PP" then
			return mk.PP(raw[2], raw[3], raw[4], raw[5], raw[6], raw[7])
		elseif tag == "RY" then
			return mk.RY(mk.V3(raw[2], raw[3], raw[4]), mk.V3(raw[5], raw[6], raw[7]))
		elseif tag == "V3i" then
			return mk.V3i(raw[2], raw[3], raw[4])
		elseif tag == "V2i" then
			return mk.V2i(raw[2], raw[3])
		end
		return nil
	end

	local typeDefaults = {}
	local function typeDefault(d)
		local t = d.t
		if t == "b" then
			return false
		elseif t == "s" then
			return ""
		elseif t == "f" or t == "d" or t == "i" or t == "l" or t == "n" then
			return 0
		elseif t == "E" then
			return Enum.first(d.sub)
		elseif t == "C" then
			local sub = d.sub
			local v = typeDefaults[sub]
			if v ~= nil then
				return v
			end
			local mk = DT.make
			if sub == "Vector3" then
				v = DT.Vector3.zero
			elseif sub == "Vector2" then
				v = DT.Vector2.zero
			elseif sub == "CFrame" then
				v = DT.CFrame.identity
			elseif sub == "Color3" then
				v = mk.C3(0, 0, 0)
			elseif sub == "UDim2" then
				v = mk.U2(0, 0, 0, 0)
			elseif sub == "UDim" then
				v = mk.UD(0, 0)
			elseif sub == "BrickColor" then
				v = mk.BC(194)
			elseif sub == "Font" then
				v = mk.FT("rbxasset://fonts/families/LegacyArial.json", "Regular", "Normal")
			elseif sub == "NumberRange" then
				v = mk.NR(0, 0)
			elseif sub == "NumberSequence" then
				v = mk.NS({ mk.NSK(0, 0, 0), mk.NSK(1, 0, 0) })
			elseif sub == "ColorSequence" then
				local w = mk.C3(1, 1, 1)
				v = mk.CS({ mk.CSK(0, w), mk.CSK(1, w) })
			elseif sub == "Rect" then
				v = mk.RC(0, 0, 0, 0)
			elseif sub == "Faces" then
				v = mk.FAbits(0)
			elseif sub == "Axes" then
				v = mk.AXbits(0)
			elseif sub == "Ray" then
				v = mk.RY(DT.Vector3.zero, DT.Vector3.zero)
			elseif sub == "Content" then
				v = DT.Content.none
			elseif sub == "Vector3int16" then
				v = mk.V3i(0, 0, 0)
			elseif sub == "Vector2int16" then
				v = mk.V2i(0, 0)
			else
				return nil
			end
			typeDefaults[sub] = v
			return v
		end
		return nil
	end

	local NONE = {}
	local function defaultValue(rec, d)
		local name = d.alias or d.name
		local cache = rec.defaultCache
		local v = cache[name]
		if v ~= nil then
			if v == NONE then
				return nil
			end
			return v
		end
		local raw = rec.rawDefaults[name]
		if raw ~= nil then
			v = decodeRaw(raw, d)
		end
		if v == nil then
			v = typeDefault(d)
		end
		cache[name] = v == nil and NONE or v
		return v
	end
	Inst.defaultValue = function(inst, prop)
		local M = getmt(inst)
		local d = M.cls.members[prop]
		return d and defaultValue(M.cls, d)
	end

	-- =================================================================================================
	--  Instanzen
	-- =================================================================================================
	local nextId = 0

	local function isInst(v)
		if type(v) ~= "userdata" then
			return false
		end
		local M = getmt(v)
		return type(M) == "table" and rawget(M, "__index") == instIndex
	end
	Inst.is = isInst

	local function meta(v)
		if type(v) ~= "userdata" then
			return nil
		end
		local M = getmt(v)
		if type(M) == "table" and rawget(M, "__index") == instIndex then
			return M
		end
		return nil
	end
	Inst.meta = meta

	local function checkInst(self, mname)
		local M = meta(self)
		if M == nil then
			raise(fmt("Expected ':' not '.' calling member function %s", mname))
		end
		return M
	end
	Inst.checkSelf = checkInst

	local function newInstance(rec)
		nextId += 1
		local u = newproxy(true)
		local M = getmt(u)
		M.__index = instIndex
		M.__newindex = instNewindex
		M.__tostring = instToString
		M.__type = "Instance"
		M.__concat = DT.concatError
		M.__lt = DT.ltError
		M.__le = DT.leError
		M.cls = rec
		M.name = rec.name
		M.props = {}
		M.children = {}
		M.id = nextId
		M.self = u
		for _, init in rec.inits do
			init(u, M)
		end
		notify("created", u)
		return u, M
	end
	Inst.newRaw = newInstance

	function instToString(self)
		return getmt(self).name
	end

	local function fullName(u)
		local M = getmt(u)
		if M.parent == nil then
			return M.name
		end
		local parts = {}
		local cur = u
		while cur do
			local CM = getmt(cur)
			if CM.parent == nil and CM.cls.name == "DataModel" then
				break
			end
			table.insert(parts, 1, CM.name)
			cur = CM.parent
		end
		return table.concat(parts, ".")
	end
	Inst.fullName = fullName

	local function notMember(self, M, k)
		raise(fmt('%s is not a valid member of %s "%s"', tostring(k), M.cls.name, fullName(self)))
	end

	-- Signale --------------------------------------------------------------------------------------
	local function eventSignal(self, M, name)
		local sigs = M.signals
		if sigs == nil then
			sigs = {}
			M.signals = sigs
		end
		local s = sigs[name]
		if s == nil then
			s = Signal.new(name, self, M.cls.signalOpts and M.cls.signalOpts[name])
			sigs[name] = s
		end
		return s
	end
	Inst.signal = function(inst, name)
		local M = getmt(inst)
		local d = M.cls.members[name]
		if d and d.alias then
			name = d.alias
		end
		return eventSignal(inst, M, name)
	end

	--- Event feuern (deferred), nur wenn das Signal existiert
	local function fire(M, name, ...)
		local sigs = M.signals
		if sigs then
			local s = sigs[name]
			if s then
				Signal.fire(s, ...)
			end
		end
	end
	Inst.fire = function(inst, name, ...)
		fire(getmt(inst), name, ...)
	end
	Inst.fireImmediate = function(inst, name, ...)
		local M = getmt(inst)
		local sigs = M.signals
		if sigs and sigs[name] then
			Signal.fireImmediate(sigs[name], ...)
		end
	end
	local function hasListeners(M, name)
		local sigs = M.signals
		if sigs == nil then
			return false
		end
		local s = sigs[name]
		return s ~= nil and (Signal.count(s) > 0 or Signal.hasWaiting(s))
	end
	Inst.hasListeners = function(inst, name)
		return hasListeners(getmt(inst), name)
	end

	--- Property-Änderung melden: GetPropertyChangedSignal, Changed (ValueBase: nur Value, mit Wert), Hooks, Observer
	local function changed(self, M, k)
		local ps = M.propSignals
		if ps then
			local s = ps[k]
			if s then
				Signal.fire(s)
			end
		end
		local sigs = M.signals
		if sigs then
			local c = sigs.Changed
			if c then
				if M.cls.valueBase then
					if k == "Value" then
						Signal.fire(c, self.Value)
					end
				else
					Signal.fire(c, k)
				end
			end
		end
		local hooks = M.cls.changedHooks
		for i = 1, #hooks do
			hooks[i](self, M, k)
		end
		if #observers.changed > 0 then
			notify("changed", self, k)
		end
	end
	Inst.changed = changed

	-- Property-Zugriff -------------------------------------------------------------------------------
	local function getPropValue(self, M, d)
		local g = d.get
		if g then
			return g(self, M, d.name)
		end
		local key = d.alias or d.name
		local v = M.props[key]
		if v == nil then
			v = defaultValue(M.cls, d)
			if v == nil then
				return nil
			end
		end
		if d.copy then
			return DT.copyFont(v)
		end
		return v
	end

	local function storeProp(self, M, key, v, d)
		local props = M.props
		local old = props[key]
		if old == nil then
			old = defaultValue(M.cls, d)
		end
		if old == v and (v ~= nil or props[key] == nil) then
			return false
		end
		props[key] = v
		changed(self, M, key)
		return true
	end
	Inst.storeProp = function(inst, key, v)
		local M = getmt(inst)
		return storeProp(inst, M, key, v, M.cls.members[key])
	end

	function instIndex(self, k)
		local M = getmt(self)
		local d = M.cls.members[k]
		if d ~= nil then
			local kind = d.kind
			if kind == "prop" then
				if d.inaccessible then
					secError(k)
				end
				if d.deprecated then
					Report.deprecatedUse(M.cls.name .. "." .. k)
				end
				return getPropValue(self, M, d)
			elseif kind == "method" then
				return d.fn
			elseif kind == "event" then
				if d.inaccessible then
					secError(k)
				end
				if d.deprecated then
					Report.deprecatedUse(M.cls.name .. "." .. k)
				end
				return eventSignal(self, M, d.alias or k)
			else
				raise(
					fmt(
						"%s is a callback member of %s; you can only set the callback value, get is not available",
						k,
						M.cls.name
					)
				)
			end
		end
		if type(k) == "string" then
			local c = findChildFwd(M, k)
			if c then
				return c
			end
		end
		notMember(self, M, k)
	end
	Util.registerHostIndex(instIndex)

	function instNewindex(self, k, v)
		local M = getmt(self)
		local d = M.cls.members[k]
		if d == nil then
			notMember(self, M, k)
		end
		local kind = d.kind
		if kind == "prop" then
			if d.inaccessible or d.nowrite then
				secError(k)
			end
			if d.ro then
				raise(fmt("Unable to assign property %s. Property is read only", k))
			end
			if d.deprecated then
				Report.deprecatedUse(M.cls.name .. "." .. k)
			end
			v = d.coerce(d, v)
			local s = d.set
			if s then
				s(self, M, v, d.alias or k)
				return
			end
			storeProp(self, M, d.alias or k, v, d)
		elseif kind == "callback" then
			if d.inaccessible then
				secError(k)
			end
			if v ~= nil and type(v) ~= "function" then
				raise(fmt("Unable to assign property %s. function expected, got %s", k, typeof(v)))
			end
			local cbs = M.callbacks
			if cbs == nil then
				cbs = {}
				M.callbacks = cbs
			end
			cbs[k] = v
			if d.onSet then
				d.onSet(self, M, v)
			end
		else
			raise(fmt("%s cannot be assigned to", tostring(k)))
		end
	end

	--- Harness: Property lesen (ohne Sicherheits-/Deprecated-Zählung)
	function Inst.getProp(inst, k)
		local M = getmt(inst)
		local d = M.cls.members[k]
		if d == nil or d.kind ~= "prop" then
			error("Harness: " .. M.cls.name .. " hat keine Property " .. tostring(k), 2)
		end
		return getPropValue(inst, M, d)
	end
	--- Harness: Property schreiben mit Typprüfung, aber ohne read only/Sicherheit
	function Inst.setProp(inst, k, v)
		local M = getmt(inst)
		local d = M.cls.members[k]
		if d == nil or d.kind ~= "prop" then
			error("Harness: " .. M.cls.name .. " hat keine Property " .. tostring(k), 2)
		end
		v = d.coerce(d, v)
		if d.set and not d.ro then
			d.set(inst, M, v, d.alias or k)
			return
		end
		storeProp(inst, M, d.alias or k, v, d)
	end
	--- Harness: Wert direkt ablegen (keine Prüfung); silent = keine Changed-Signale
	function Inst.rawSet(inst, k, v, silent)
		local M = getmt(inst)
		if silent then
			M.props[k] = v
			return
		end
		local d = M.cls.members[k]
		if d then
			storeProp(inst, M, k, v, d)
		else
			M.props[k] = v
		end
	end
	function Inst.callback(inst, name)
		local cbs = getmt(inst).callbacks
		return cbs and cbs[name]
	end

	-- =================================================================================================
	--  Baum
	-- =================================================================================================
	local function isAncestor(anc, u)
		local p = getmt(u).parent
		while p do
			if p == anc then
				return true
			end
			p = getmt(p).parent
		end
		return false
	end
	Inst.isAncestor = isAncestor

	local function forSubtree(u, fn)
		fn(u)
		local ch = getmt(u).children
		for i = 1, #ch do
			forSubtree(ch[i], fn)
		end
	end
	Inst.forSubtree = forSubtree

	local function dataModelOf(u)
		local cur = u
		while true do
			local M = getmt(cur)
			local p = M.parent
			if p == nil then
				if M.cls.name == "DataModel" then
					return cur
				end
				return nil
			end
			cur = p
		end
	end
	Inst.dataModelOf = dataModelOf

	-- WaitForChild-Warter (pro Parent)
	local waitersByParent = setmetatable({}, { __mode = "k" })
	local activeWaiters = {}
	Inst.activeWaiters = activeWaiters

	local function wakeWaiter(w, child)
		if w.done then
			return
		end
		w.done = true
		local list = waitersByParent[w.parent]
		if list then
			local i = table.find(list, w)
			if i then
				table.remove(list, i)
			end
		end
		local j = table.find(activeWaiters, w)
		if j then
			table.remove(activeWaiters, j)
		end
		Sched.queueResume(w.co, { n = 1, child })
	end

	local function checkWaiters(parent, child)
		local list = waitersByParent[parent]
		if list == nil or #list == 0 then
			return
		end
		local name = getmt(child).name
		for _, w in table.clone(list) do
			if not w.done and w.name == name then
				local ok = visibilityFilter == nil or visibilityFilter(child, w.ctx)
				if ok then
					wakeWaiter(w, child)
				end
			end
		end
	end

	--- Kern-Reparent ohne Lock-/Typprüfung (Prüfungen macht der Parent-Setter)
	local function reparent(u, M, newParent)
		local old = M.parent
		if old == newParent then
			return
		end
		local totals = Signal.totalByName
		-- DescendantRemoving an alten Vorfahren
		if old then
			if totals.DescendantRemoving > 0 then
				local a = old
				local listeners = {}
				while a do
					local AM = getmt(a)
					if hasListeners(AM, "DescendantRemoving") then
						listeners[#listeners + 1] = AM
					end
					a = AM.parent
				end
				if #listeners > 0 then
					forSubtree(u, function(x)
						for _, AM in listeners do
							fire(AM, "DescendantRemoving", x)
						end
					end)
				end
			end
			local OM = getmt(old)
			local ch = OM.children
			for i = #ch, 1, -1 do
				if ch[i] == u then
					table.remove(ch, i)
					break
				end
			end
			local idx = OM.nameIndex
			if idx then
				local l = idx[M.name]
				if l then
					local j = table.find(l, u)
					if j then
						table.remove(l, j)
					end
					if #l == 0 then
						idx[M.name] = nil
					end
				end
			end
			fire(OM, "ChildRemoved", u)
		end
		M.parent = newParent
		if newParent then
			local PM = getmt(newParent)
			PM.children[#PM.children + 1] = u
			local idx = PM.nameIndex
			if idx then
				local l = idx[M.name]
				if l then
					l[#l + 1] = u
				else
					idx[M.name] = { u }
				end
			end
		end
		changed(u, M, "Parent")
		if totals.AncestryChanged > 0 then
			forSubtree(u, function(x)
				fire(getmt(x), "AncestryChanged", u, newParent)
			end)
		end
		if newParent then
			local PM = getmt(newParent)
			fire(PM, "ChildAdded", u)
			if totals.DescendantAdded > 0 then
				local a = newParent
				local listeners = {}
				while a do
					local AM = getmt(a)
					if hasListeners(AM, "DescendantAdded") then
						listeners[#listeners + 1] = AM
					end
					a = AM.parent
				end
				if #listeners > 0 then
					forSubtree(u, function(x)
						for _, AM in listeners do
							fire(AM, "DescendantAdded", x)
						end
					end)
				end
			end
		end
		local hooks = M.cls.ancestryHooks
		for i = 1, #hooks do
			hooks[i](u, M, old, newParent)
		end
		if #observers.reparented > 0 then
			notify("reparented", u, old, newParent)
		end
		if newParent then
			checkWaiters(newParent, u)
		end
	end
	Inst.reparentRaw = function(u, newParent)
		reparent(u, getmt(u), newParent)
	end

	--- Parent setzen mit allen Roblox-Prüfungen
	local function setParent(u, M, newParent)
		if M.parentLocked then
			raise(
				fmt(
					"The Parent property of %s is locked, current parent: %s, new parent %s",
					fullName(u),
					M.parent and getmt(M.parent).name or "NULL",
					newParent and (meta(newParent) and getmt(newParent).name or tostring(newParent)) or "NULL"
				)
			)
		end
		if newParent ~= nil then
			local PM = meta(newParent)
			if PM == nil then
				raise(fmt("Unable to assign property Parent. Instance expected, got %s", typeof(newParent)))
			end
			if newParent == u then
				raise(fmt("Attempt to set %s as its own parent", fullName(u)))
			end
			if isAncestor(u, newParent) then
				raise(
					fmt(
						"Attempt to set parent of %s to %s would result in circular reference",
						fullName(u),
						fullName(newParent)
					)
				)
			end
		end
		reparent(u, M, newParent)
	end
	Inst.setParent = function(u, p)
		setParent(u, getmt(u), p)
	end

	-- Namensindex (lazy) für Eltern mit vielen Kindern: name -> Liste in Kinder-Reihenfolge.
	-- Wird bei Hinzufügen/Entfernen gepflegt und bei Umbenennung eines Kindes verworfen.
	local INDEX_MIN = 24
	local function nameIndex(M)
		local idx = M.nameIndex
		if idx == nil then
			idx = {}
			for _, c in M.children do
				local n = getmt(c).name
				local l = idx[n]
				if l then
					l[#l + 1] = c
				else
					idx[n] = { c }
				end
			end
			M.nameIndex = idx
		end
		return idx
	end
	local function findChild(M, name)
		local ch = M.children
		if #ch < INDEX_MIN then
			for i = 1, #ch do
				local c = ch[i]
				if getmt(c).name == name and (visibilityFilter == nil or visible(c)) then
					return c
				end
			end
			return nil
		end
		local l = nameIndex(M)[name]
		if l then
			for i = 1, #l do
				local c = l[i]
				if visibilityFilter == nil or visible(c) then
					return c
				end
			end
		end
		return nil
	end
	findChildFwd = findChild
	Inst.findChild = function(inst, name)
		return findChild(getmt(inst), name)
	end

	local function findDescendant(M, pred)
		local ch = M.children
		for i = 1, #ch do
			local c = ch[i]
			if visibilityFilter == nil or visible(c) then
				local CM = getmt(c)
				if pred(c, CM) then
					return c
				end
				local r = findDescendant(CM, pred)
				if r then
					return r
				end
			end
		end
		return nil
	end

	local function collectDescendants(M, out)
		local ch = M.children
		for i = 1, #ch do
			local c = ch[i]
			if visibilityFilter == nil or visible(c) then
				out[#out + 1] = c
				collectDescendants(getmt(c), out)
			end
		end
		return out
	end
	Inst.descendants = function(inst)
		return collectDescendants(getmt(inst), {})
	end
	Inst.children = function(inst)
		return getmt(inst).children
	end

	-- Destroy ----------------------------------------------------------------------------------------
	local function disconnectAll(M)
		if M.signals then
			for _, s in M.signals do
				Signal.disconnectAll(s)
			end
		end
		if M.propSignals then
			for _, s in M.propSignals do
				Signal.disconnectAll(s)
			end
		end
		if M.attrSignals then
			for _, s in M.attrSignals do
				Signal.disconnectAll(s)
			end
		end
	end

	local function destroy(u, M)
		if M.destroyed then
			return
		end
		M.destroying = true
		if M.signals and M.signals.Destroying then
			Signal.fireImmediate(M.signals.Destroying)
		end
		if #observers.destroying > 0 then
			notify("destroying", u)
		end
		reparent(u, M, nil)
		M.parentLocked = true
		M.destroyed = true
		disconnectAll(M)
		local ch = M.children
		while #ch > 0 do
			local c = ch[#ch]
			local CM = getmt(c)
			if CM.destroyed then
				table.remove(ch)
				CM.parent = nil
				M.nameIndex = nil
			else
				destroy(c, CM)
			end
		end
		local hooks = M.cls.destroyHooks
		for i = 1, #hooks do
			hooks[i](u, M)
		end
	end
	Inst.destroy = function(u)
		destroy(u, getmt(u))
	end

	-- Clone ------------------------------------------------------------------------------------------
	local function isArchivable(M)
		local v = M.props.Archivable
		if v == nil then
			return true
		end
		return v
	end

	local function cloneInto(src, SM, map, ignoreArchivable)
		if not ignoreArchivable and not isArchivable(SM) then
			return nil
		end
		local rec = SM.cls
		if rec.service or rec.name == "DataModel" then
			return nil
		end
		local copy, CM = newInstance(rec)
		CM.name = SM.name
		for k, v in SM.props do
			if DT.is.Font(v) then
				v = DT.copyFont(v)
			end
			CM.props[k] = v
		end
		if SM.attrs then
			CM.attrs = {}
			for k, v in SM.attrs do
				CM.attrs[k] = DT.is.Font(v) and DT.copyFont(v) or v
			end
		end
		if SM.tags then
			CM.tags = table.clone(SM.tags)
			CM.tagSet = table.clone(SM.tagSet)
		end
		if SM.ext and SM.ext.cloneExt then
			SM.ext.cloneExt(SM, CM)
		end
		map[src] = copy
		return copy, CM
	end

	local function cloneTree(src, map, ignoreArchivable, withChildren)
		local SM = getmt(src)
		local copy, CM = cloneInto(src, SM, map, ignoreArchivable)
		if copy == nil then
			return nil
		end
		if withChildren then
			for _, c in SM.children do
				local cc = cloneTree(c, map, false, true)
				if cc then
					getmt(cc).parent = copy
					CM.children[#CM.children + 1] = cc
				end
			end
		end
		return copy
	end

	local function finishClone(map)
		for src, cp in map do
			local CM = getmt(cp)
			for k, v in CM.props do
				if type(v) == "userdata" and map[v] then
					CM.props[k] = map[v]
				end
			end
		end
		for src, cp in map do
			local CM = getmt(cp)
			local hooks = CM.cls.cloneHooks
			for i = 1, #hooks do
				hooks[i](cp, CM, src, getmt(src))
			end
		end
	end

	local function clone(src)
		local map = {}
		local root = cloneTree(src, map, false, true)
		if root == nil then
			return nil
		end
		finishClone(map)
		return root
	end
	Inst.clone = clone

	-- Erzeugung --------------------------------------------------------------------------------------
	--- Harness: Instanz erzeugen (ohne creatable-Prüfung). props werden über Inst.setProp gesetzt.
	function Inst.create(className, props, parent)
		local rec = getRecord(className)
		if rec == nil then
			error("Harness: unbekannte Klasse " .. tostring(className), 2)
		end
		local u, M = newInstance(rec)
		if props then
			for k, v in props do
				if k == "Name" then
					M.name = v
				else
					Inst.setProp(u, k, v)
				end
			end
		end
		if parent then
			setParent(u, M, parent)
		end
		return u
	end

	Inst.global = {}
	function Inst.global.new(className, parent)
		className = Util.checkString(className, 1, "new")
		local rec = getRecord(className)
		if rec == nil or not rec.creatable then
			raise(fmt('Unable to create an Instance of type "%s"', className))
		end
		local u, M = newInstance(rec)
		if parent ~= nil then
			setParent(u, M, parent)
		end
		return u
	end
	function Inst.global.fromExisting(existing)
		local M = meta(existing)
		if M == nil then
			Util.badArg(1, "fromExisting", "Instance", existing)
		end
		local map = {}
		local copy = cloneTree(existing, map, true, false)
		if copy == nil then
			raise(fmt('Unable to create an Instance of type "%s"', M.cls.name))
		end
		finishClone(map)
		return copy
	end

	-- =================================================================================================
	--  Attribute & Tags
	-- =================================================================================================
	local attrTypes = {
		boolean = true,
		number = true,
		string = true,
		UDim = true,
		UDim2 = true,
		BrickColor = true,
		Color3 = true,
		Vector2 = true,
		Vector3 = true,
		CFrame = true,
		NumberSequence = true,
		ColorSequence = true,
		NumberRange = true,
		Rect = true,
		Font = true,
		EnumItem = true,
	}
	local function validateAttrName(name)
		if #name == 0 then
			raise("Attribute name must not be empty")
		end
		if #name > 100 then
			raise("Attribute name is too long (more than 100 characters)")
		end
		if string.find(name, "[^%w%._%-/]") then
			raise(
				fmt(
					"Attribute name '%s' contains invalid characters (only alphanumeric characters, periods, hyphens, slashes and underscores are allowed)",
					name
				)
			)
		end
		if string.sub(name, 1, 3) == "RBX" then
			raise(fmt("Attribute name '%s' is reserved (names starting with RBX are reserved for Roblox)", name))
		end
	end

	local function setAttribute(u, M, name, value)
		if value ~= nil then
			local t = typeof(value)
			if not attrTypes[t] then
				raise(fmt("Unable to set attribute '%s': type %s is not supported", name, t))
			end
			if t == "Font" then
				value = DT.copyFont(value)
			end
		end
		local attrs = M.attrs
		if attrs == nil then
			if value == nil then
				return
			end
			attrs = {}
			M.attrs = attrs
		end
		local old = attrs[name]
		if old == value and (value ~= nil or old == nil) then
			if not (type(value) == "number" and value ~= value) then
				return
			end
		end
		attrs[name] = value
		if M.attrSignals and M.attrSignals[name] then
			Signal.fire(M.attrSignals[name])
		end
		fire(M, "AttributeChanged", name)
		if #observers.attribute > 0 then
			notify("attribute", u, name, value)
		end
	end
	Inst.setAttribute = function(u, name, value)
		setAttribute(u, getmt(u), name, value)
	end

	local function addTag(u, M, tag)
		local set = M.tagSet
		if set == nil then
			set = {}
			M.tagSet = set
			M.tags = {}
		end
		if set[tag] then
			return
		end
		set[tag] = true
		M.tags[#M.tags + 1] = tag
		if #observers.tag > 0 then
			notify("tag", u, tag, true)
		end
	end
	local function removeTag(u, M, tag)
		local set = M.tagSet
		if set == nil or not set[tag] then
			return
		end
		set[tag] = nil
		local i = table.find(M.tags, tag)
		if i then
			table.remove(M.tags, i)
		end
		if #observers.tag > 0 then
			notify("tag", u, tag, false)
		end
	end
	Inst.addTag = function(u, tag)
		addTag(u, getmt(u), tag)
	end
	Inst.removeTag = function(u, tag)
		removeTag(u, getmt(u), tag)
	end
	Inst.hasTag = function(u, tag)
		local s = getmt(u).tagSet
		return s ~= nil and s[tag] == true
	end

	-- =================================================================================================
	--  Methoden von Object/Instance
	-- =================================================================================================
	local function isA(M, className)
		return M.cls.isA[className] == true
	end
	Inst.isA = function(inst, className)
		local M = meta(inst)
		return M ~= nil and M.cls.isA[className] == true
	end

	local O = {}
	function O.IsA(self, className)
		local M = checkInst(self, "IsA")
		className = Util.checkString(className, 1, "IsA")
		return isA(M, className)
	end
	function O.GetPropertyChangedSignal(self, prop)
		local M = checkInst(self, "GetPropertyChangedSignal")
		prop = Util.checkString(prop, 1, "GetPropertyChangedSignal")
		local d = M.cls.members[prop]
		if d == nil or d.kind ~= "prop" or d.inaccessible then
			raise(fmt("%s is not a valid property name.", prop))
		end
		local key = d.alias or prop
		local ps = M.propSignals
		if ps == nil then
			ps = {}
			M.propSignals = ps
		end
		local s = ps[key]
		if s == nil then
			s = Signal.new(key, self, M.cls.propSignalOpts and M.cls.propSignalOpts[key])
			ps[key] = s
		end
		return s
	end
	Inst.define("Object", {
		props = {
			ClassName = {
				get = function(_, M)
					return M.cls.name
				end,
			},
		},
		methods = O,
	})

	local I = {}
	function I.FindFirstChild(self, name, recursive)
		local M = checkInst(self, "FindFirstChild")
		name = Util.checkString(name, 1, "FindFirstChild")
		if recursive then
			return findDescendant(M, function(_, CM)
				return CM.name == name
			end)
		end
		return findChild(M, name)
	end
	function I.FindFirstChildOfClass(self, className)
		local M = checkInst(self, "FindFirstChildOfClass")
		className = Util.checkString(className, 1, "FindFirstChildOfClass")
		for _, c in M.children do
			if getmt(c).cls.name == className and (visibilityFilter == nil or visible(c)) then
				return c
			end
		end
		return nil
	end
	function I.FindFirstChildWhichIsA(self, className, recursive)
		local M = checkInst(self, "FindFirstChildWhichIsA")
		className = Util.checkString(className, 1, "FindFirstChildWhichIsA")
		if recursive then
			return findDescendant(M, function(_, CM)
				return CM.cls.isA[className] == true
			end)
		end
		for _, c in M.children do
			if getmt(c).cls.isA[className] and (visibilityFilter == nil or visible(c)) then
				return c
			end
		end
		return nil
	end
	function I.FindFirstDescendant(self, name)
		local M = checkInst(self, "FindFirstDescendant")
		name = Util.checkString(name, 1, "FindFirstDescendant")
		return findDescendant(M, function(_, CM)
			return CM.name == name
		end)
	end
	function I.FindFirstAncestor(self, name)
		local M = checkInst(self, "FindFirstAncestor")
		name = Util.checkString(name, 1, "FindFirstAncestor")
		local p = M.parent
		while p do
			local PM = getmt(p)
			if PM.name == name then
				return p
			end
			p = PM.parent
		end
		return nil
	end
	function I.FindFirstAncestorOfClass(self, className)
		local M = checkInst(self, "FindFirstAncestorOfClass")
		className = Util.checkString(className, 1, "FindFirstAncestorOfClass")
		local p = M.parent
		while p do
			local PM = getmt(p)
			if PM.cls.name == className then
				return p
			end
			p = PM.parent
		end
		return nil
	end
	function I.FindFirstAncestorWhichIsA(self, className)
		local M = checkInst(self, "FindFirstAncestorWhichIsA")
		className = Util.checkString(className, 1, "FindFirstAncestorWhichIsA")
		local p = M.parent
		while p do
			local PM = getmt(p)
			if PM.cls.isA[className] then
				return p
			end
			p = PM.parent
		end
		return nil
	end
	function I.GetChildren(self)
		local M = checkInst(self, "GetChildren")
		local out = table.create(#M.children)
		for _, c in M.children do
			if visibilityFilter == nil or visible(c) then
				out[#out + 1] = c
			end
		end
		return out
	end
	function I.GetDescendants(self)
		local M = checkInst(self, "GetDescendants")
		return collectDescendants(M, {})
	end
	function I.IsDescendantOf(self, ancestor)
		checkInst(self, "IsDescendantOf")
		if ancestor == nil then
			return false
		end
		if not isInst(ancestor) then
			Util.badArg(1, "IsDescendantOf", "Instance", ancestor)
		end
		return isAncestor(ancestor, self)
	end
	function I.IsAncestorOf(self, descendant)
		checkInst(self, "IsAncestorOf")
		if descendant == nil then
			return false
		end
		if not isInst(descendant) then
			Util.badArg(1, "IsAncestorOf", "Instance", descendant)
		end
		return isAncestor(self, descendant)
	end
	function I.GetFullName(self)
		checkInst(self, "GetFullName")
		return fullName(self)
	end
	function I.Destroy(self)
		local M = checkInst(self, "Destroy")
		if M.cls.service or M.cls.name == "DataModel" then
			raise(fmt("The Parent property of %s is locked", M.name))
		end
		destroy(self, M)
	end
	function I.Remove(self)
		local M = checkInst(self, "Remove")
		if M.parentLocked then
			raise(fmt("The Parent property of %s is locked, current parent: NULL, new parent NULL", fullName(self)))
		end
		reparent(self, M, nil)
	end
	function I.ClearAllChildren(self)
		local M = checkInst(self, "ClearAllChildren")
		for _, c in table.clone(M.children) do
			local CM = getmt(c)
			if not CM.cls.service then
				destroy(c, CM)
			end
		end
	end
	function I.Clone(self)
		checkInst(self, "Clone")
		return clone(self)
	end
	function I.WaitForChild(self, name, timeout)
		local M = checkInst(self, "WaitForChild")
		if name == nil then
			Util.missingArg(1)
		end
		name = Util.checkString(name, 1, "WaitForChild")
		if timeout ~= nil then
			timeout = Util.checkNumber(timeout, 2, "WaitForChild")
		end
		local c = findChild(M, name)
		if c then
			return c
		end
		local co = Sched.assertYieldable()
		local w = {
			parent = self,
			name = name,
			co = co,
			start = Sched.now,
			timeout = timeout,
			done = false,
			ctx = Sched.ctx(),
		}
		local list = waitersByParent[self]
		if list == nil then
			list = {}
			waitersByParent[self] = list
		end
		list[#list + 1] = w
		activeWaiters[#activeWaiters + 1] = w
		if timeout then
			Sched.addTimer(Sched.now + math.max(timeout, 0), function()
				if not w.done then
					wakeWaiter(w, nil)
				end
			end)
		end
		return coroutine.yield()
	end
	function I.GetAttribute(self, name)
		local M = checkInst(self, "GetAttribute")
		name = Util.checkString(name, 1, "GetAttribute")
		local attrs = M.attrs
		if attrs == nil then
			return nil
		end
		local v = attrs[name]
		if DT.is.Font(v) then
			return DT.copyFont(v)
		end
		return v
	end
	function I.SetAttribute(self, name, value)
		local M = checkInst(self, "SetAttribute")
		name = Util.checkString(name, 1, "SetAttribute")
		validateAttrName(name)
		setAttribute(self, M, name, value)
	end
	function I.GetAttributes(self)
		local M = checkInst(self, "GetAttributes")
		local out = {}
		if M.attrs then
			for k, v in M.attrs do
				out[k] = DT.is.Font(v) and DT.copyFont(v) or v
			end
		end
		return out
	end
	function I.GetAttributeChangedSignal(self, name)
		local M = checkInst(self, "GetAttributeChangedSignal")
		name = Util.checkString(name, 1, "GetAttributeChangedSignal")
		local as = M.attrSignals
		if as == nil then
			as = {}
			M.attrSignals = as
		end
		local s = as[name]
		if s == nil then
			s = Signal.new(name, self)
			as[name] = s
		end
		return s
	end
	function I.AddTag(self, tag)
		local M = checkInst(self, "AddTag")
		tag = Util.checkString(tag, 1, "AddTag")
		addTag(self, M, tag)
	end
	function I.RemoveTag(self, tag)
		local M = checkInst(self, "RemoveTag")
		tag = Util.checkString(tag, 1, "RemoveTag")
		removeTag(self, M, tag)
	end
	function I.HasTag(self, tag)
		local M = checkInst(self, "HasTag")
		tag = Util.checkString(tag, 1, "HasTag")
		return M.tagSet ~= nil and M.tagSet[tag] == true
	end
	function I.GetTags(self)
		local M = checkInst(self, "GetTags")
		return M.tags and table.clone(M.tags) or {}
	end
	function I.GetActor(self)
		local M = checkInst(self, "GetActor")
		local p = M.parent
		while p do
			local PM = getmt(p)
			if PM.cls.isA.Actor then
				return p
			end
			p = PM.parent
		end
		return nil
	end
	function I.IsPropertyModified(self, prop)
		local M = checkInst(self, "IsPropertyModified")
		prop = Util.checkString(prop, 1, "IsPropertyModified")
		local d = M.cls.members[prop]
		if d == nil or d.kind ~= "prop" then
			raise(fmt("%s is not a valid property name.", prop))
		end
		local v = M.props[d.alias or prop]
		return v ~= nil and v ~= defaultValue(M.cls, d)
	end
	function I.ResetPropertyToDefault(self, prop)
		local M = checkInst(self, "ResetPropertyToDefault")
		prop = Util.checkString(prop, 1, "ResetPropertyToDefault")
		local d = M.cls.members[prop]
		if d == nil or d.kind ~= "prop" then
			raise(fmt("%s is not a valid property name.", prop))
		end
		if d.ro then
			return
		end
		local key = d.alias or prop
		if M.props[key] ~= nil then
			M.props[key] = nil
			changed(self, M, key)
		end
	end
	I.children = function(self)
		return I.GetChildren(self)
	end

	Inst.define("Instance", {
		props = {
			Name = {
				get = function(_, M)
					return M.name
				end,
				set = function(u, M, v)
					if M.name == v then
						return
					end
					M.name = v
					if M.parent then
						getmt(M.parent).nameIndex = nil
					end
					changed(u, M, "Name")
					if M.parent then
						checkWaiters(M.parent, u)
					end
				end,
			},
			Parent = {
				get = function(_, M)
					return M.parent
				end,
				set = function(u, M, v)
					setParent(u, M, v)
				end,
			},
		},
		methods = I,
	})

	-- Skript-Quelltexte (vom Bundler gesetzt): M.ext.source / M.ext.chunkName; Clone übernimmt sie
	function Inst.setScriptSource(inst, source, chunkName)
		local M = getmt(inst)
		M.ext = M.ext or {}
		M.ext.source = source
		M.ext.chunkName = chunkName
	end
	function Inst.scriptSource(inst)
		local e = getmt(inst).ext
		if e then
			return e.source, e.chunkName
		end
		return nil
	end
	Inst.define("LuaSourceContainer", {
		postClone = function(copy, CM, src, SM)
			if SM.ext and SM.ext.source then
				CM.ext = CM.ext or {}
				CM.ext.source = SM.ext.source
				CM.ext.chunkName = SM.ext.chunkName
				CM.ext.clonedFrom = src
			end
		end,
	})

	-- =================================================================================================
	--  Infinite-Yield-Überwachung (5 s simulierte Zeit ohne Timeout)
	-- =================================================================================================
	Inst.infiniteYieldAfter = R.config.infiniteYieldAfter or 5
	Sched.addHook("late", function()
		local now = Sched.now
		for _, w in activeWaiters do
			if not w.done and not w.warned and w.timeout == nil and now - w.start >= Inst.infiniteYieldAfter then
				w.warned = true
				local msg = fmt("Infinite yield possible on '%s:WaitForChild(\"%s\")'", fullName(w.parent), w.name)
				local tb = debug.traceback(w.co, msg)
				Report.print(w.ctx, "warn", msg)
				Report.warn(msg, w.ctx, tb, "infiniteYield")
			end
		end
	end, "InfiniteYield")

	-- =================================================================================================
	--  Weitere Klassen-Verhalten laden
	-- =================================================================================================
	require("@self/BasePart")(R, Inst)
	require("@self/Gui")(R, Inst)
	require("@self/DataModel")(R, Inst)

	return Inst
end
