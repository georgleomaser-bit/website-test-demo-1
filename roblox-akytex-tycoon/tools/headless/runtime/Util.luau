--!nocheck
-- =====================================================================
--  Headless-Harness · Util
--  Gemeinsame Helfer: Roblox-artige Fehler (mit Position im SPIEL-Code), Argument-Prüfungen, typeof/type,
--  Host-Objekt-Erkennung, float32-Rundung, Zahlformatierung für tostring von Datentypen.
--
--  Host-Objekte (Datentypen, Instanzen, Signale, Enums) sind newproxy(true)-userdata. Jedes hat eine EIGENE
--  Metatabelle (Luau erlaubt kein Teilen bei newproxy), deren __index-Funktion in Util.hostIndex registriert ist.
--  Daran erkennt Util.typeof unsere Objekte (Luau-typeof ignoriert __type bei newproxy-userdata!).
-- =====================================================================
return function(R)
	local Util = {}

	local rawtype = type
	local getmt = getmetatable
	local dinfo = debug.info
	local fmt = string.format
	local vcreate = vector.create

	-- Registrierte __index-Funktionen unserer Host-Typen (Schlüssel = Funktion)
	Util.hostIndex = setmetatable({}, { __mode = "k" })

	function Util.registerHostIndex(fn)
		Util.hostIndex[fn] = true
		return fn
	end

	--- Liefert die interne Metatabelle (= Datenablage) eines Host-Objekts oder nil.
	function Util.hostMeta(v)
		if rawtype(v) ~= "userdata" then
			return nil
		end
		local mt = getmt(v)
		if rawtype(mt) == "table" and Util.hostIndex[rawget(mt, "__index")] then
			return mt
		end
		return nil
	end
	local hostMeta = Util.hostMeta

	--- Roblox-typeof: "Vector3", "Instance", "EnumItem", … für Host-Objekte, sonst Luau-type.
	function Util.typeof(v)
		local t = rawtype(v)
		if t == "userdata" then
			local mt = getmt(v)
			if rawtype(mt) == "table" and Util.hostIndex[rawget(mt, "__index")] then
				return rawget(mt, "__type") or "userdata"
			end
			return "userdata"
		end
		return t
	end
	local typeof = Util.typeof

	--- Roblox-type: Vector3 ist in Roblox der native Luau-Typ "vector" (type(Vector3.new()) == "vector").
	function Util.type(v)
		local t = rawtype(v)
		if t == "userdata" then
			local mt = getmt(v)
			if
				rawtype(mt) == "table"
				and rawget(mt, "__type") == "Vector3"
				and Util.hostIndex[rawget(mt, "__index")]
			then
				return "vector"
			end
		end
		return t
	end

	--- getmetatable für Spiel-Code: Roblox-Objekte haben eine gesperrte Metatabelle.
	function Util.getmetatable(v)
		if hostMeta(v) then
			return "The metatable is locked"
		end
		return getmt(v)
	end

	-- ---------------------------------------------------------------------------------------------------------
	--  Fehler mit Position im Spiel-Code
	-- ---------------------------------------------------------------------------------------------------------

	-- Wurzel des Harness, so wie sie in Chunk-Namen erscheint (von init.luau gesetzt, z. B. "./tools/headless/")
	Util.harnessRoots = {}

	function Util.isHarnessSource(src)
		if src == nil or src == "[C]" then
			return true
		end
		for _, root in Util.harnessRoots do
			if string.sub(src, 1, #root) == root then
				return true
			end
		end
		return false
	end
	local isHarnessSource = Util.isHarnessSource

	--- Stack-Ebene (für error/debug.info, relativ zum AUFRUFER von gameLevel) des ersten Nicht-Harness-Frames.
	--- 0, wenn es keinen gibt (dann Fehler ohne Positionspräfix).
	function Util.gameLevel(extra)
		local level = 2 + (extra or 0)
		while true do
			local s = dinfo(level + 1, "s")
			if s == nil then
				return 0
			end
			if not isHarnessSource(s) then
				return level
			end
			level += 1
		end
	end

	--- error() mit Position der aufrufenden Spiel-Code-Zeile (wie Roblox' Reflection-Fehler).
	-- Letzte bewusst (Roblox-artig) geworfene Nachricht – Report unterscheidet so API-Fehler von Harness-Abstürzen.
	Util.lastRaised = nil

	function Util.raise(msg)
		Util.lastRaised = msg
		local level = 2
		while true do
			local s = dinfo(level, "s")
			if s == nil then
				error(msg, 0)
			end
			if not isHarnessSource(s) then
				error(msg, level)
			end
			level += 1
		end
	end
	local raise = Util.raise

	--- Erste Spiel-Code-Position "datei:zeile" im aktuellen Stack (oder nil).
	function Util.gameLocation()
		local level = 2
		while true do
			local s, l = dinfo(level, "sl")
			if s == nil then
				return nil
			end
			if not isHarnessSource(s) then
				return s .. ":" .. tostring(l)
			end
			level += 1
		end
	end

	-- ---------------------------------------------------------------------------------------------------------
	--  Argument-Prüfungen (Roblox-Wortlaut)
	-- ---------------------------------------------------------------------------------------------------------

	function Util.badArg(n, fname, expected, got)
		raise(fmt("invalid argument #%d to '%s' (%s expected, got %s)", n, fname, expected, typeof(got)))
	end
	local badArg = Util.badArg

	function Util.missingArg(n)
		raise(fmt("Argument %d missing or nil", n))
	end

	--- Zahl (oder numerischer String wie luaL_checknumber) – sonst Roblox-Fehler.
	function Util.checkNumber(v, n, fname)
		if rawtype(v) == "number" then
			return v
		end
		if rawtype(v) == "string" then
			local x = tonumber(v)
			if x then
				return x
			end
		end
		badArg(n, fname, "number", v)
	end

	function Util.optNumber(v, n, fname, default)
		if v == nil then
			return default
		end
		return Util.checkNumber(v, n, fname)
	end

	--- String (Zahlen werden wie luaL_checkstring umgewandelt).
	function Util.checkString(v, n, fname)
		local t = rawtype(v)
		if t == "string" then
			return v
		end
		if t == "number" then
			return tostring(v)
		end
		if v == nil then
			Util.missingArg(n)
		end
		badArg(n, fname, "string", v)
	end

	function Util.optString(v, n, fname, default)
		if v == nil then
			return default
		end
		return Util.checkString(v, n, fname)
	end

	function Util.checkBool(v, n, fname)
		if rawtype(v) == "boolean" then
			return v
		end
		badArg(n, fname, "boolean", v)
	end

	--- Host-Datentyp prüfen (z. B. "Vector3").
	function Util.checkType(v, tname, n, fname)
		if typeof(v) == tname then
			return v
		end
		badArg(n, fname, tname, v)
	end

	function Util.optType(v, tname, n, fname)
		if v == nil then
			return nil
		end
		return Util.checkType(v, tname, n, fname)
	end

	--- Prüft, dass eine Methode mit ':' aufgerufen wurde (self vom erwarteten Typ).
	function Util.checkSelf(self, tname, mname)
		if typeof(self) ~= tname then
			raise(fmt("Expected ':' not '.' calling member function %s", mname))
		end
		return getmt(self)
	end

	-- ---------------------------------------------------------------------------------------------------------
	--  Zahlen
	-- ---------------------------------------------------------------------------------------------------------

	--- Rundet auf float32 (wie Roblox-Float-Properties und Datentyp-Komponenten).
	function Util.f32(x)
		return vcreate(x, 0, 0).x
	end

	--- Ganzzahl-Konvertierung wie Luau lua_tointeger (Abschneiden Richtung 0).
	function Util.toInt(x)
		if x ~= x then
			return 0
		end
		if x >= 0 then
			return math.floor(x)
		end
		return -math.floor(-x)
	end

	--- Kürzeste Darstellung, die als float32 wieder denselben Wert ergibt (für tostring(Vector3) usw.).
	local pack, unpack = string.pack, string.unpack
	function Util.fmtFloat(x)
		if x ~= x then
			return "nan"
		end
		if x == math.huge then
			return "inf"
		end
		if x == -math.huge then
			return "-inf"
		end
		if x == math.floor(x) and math.abs(x) < 1e15 then
			if x == 0 and 1 / x < 0 then
				return "-0"
			end
			return fmt("%d", x)
		end
		local target = unpack("<f", pack("<f", x))
		for prec = 6, 9 do
			local s = fmt("%." .. prec .. "g", x)
			local y = tonumber(s)
			if y and unpack("<f", pack("<f", y)) == target then
				return s
			end
		end
		return tostring(x)
	end

	--- Zahl wie Luau tostring (double)
	function Util.fmtNumber(x)
		return tostring(x)
	end

	-- ---------------------------------------------------------------------------------------------------------
	--  Kleinkram
	-- ---------------------------------------------------------------------------------------------------------

	function Util.shallowCopy(t)
		local o = {}
		for k, v in t do
			o[k] = v
		end
		return o
	end

	function Util.keys(t)
		local o = {}
		for k in t do
			o[#o + 1] = k
		end
		table.sort(o, function(a, b)
			return tostring(a) < tostring(b)
		end)
		return o
	end

	--- Fehlerwert in String wandeln (Roblox-Ausgabe zeigt Tabellen als "table: 0x…").
	function Util.errToString(e)
		if rawtype(e) == "string" then
			return e
		end
		if e == nil then
			return "nil"
		end
		return tostring(e)
	end

	--- Erste Spiel-Position "datei:zeile" aus einem Traceback-Text (für Deduplizierung).
	function Util.firstGameFrame(tb)
		if rawtype(tb) ~= "string" then
			return nil
		end
		for line in string.gmatch(tb, "[^\n]+") do
			local src, ln = string.match(line, "^(.-):(%d+)")
			if src and not isHarnessSource(src) then
				return src .. ":" .. ln
			end
		end
		return nil
	end

	return Util
end
