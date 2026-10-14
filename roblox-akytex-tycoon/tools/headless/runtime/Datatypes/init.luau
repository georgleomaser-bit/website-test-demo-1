--!nocheck
-- =====================================================================
--  Headless-Harness · Datentypen (Loader + gemeinsame Bausteine)
--
--  Alle Roblox-Datentypen sind newproxy(true)-userdata mit eigener Metatabelle; die Metatabelle ist zugleich die
--  Datenablage des Objekts (spart eine Tabelle je Wert). Spiel-Code sieht über die Umgebung (Globals.luau)
--  typeof()/type()/getmetatable() wie in Roblox.
--
--  DT.<Name>       = die globale Tabelle, die Spiel-Code sieht (z. B. DT.Vector3.new, DT.CFrame.identity)
--  DT.is.<Name>(v) = schnelle Typprüfung für Harness-Code
--  DT.make.<Name>  = interne Schnellkonstruktoren ohne Argumentprüfung (z. B. DT.make.V3(x, y, z))
--  DT.get(v)       = interne Datenablage (Metatabelle) eines Datentyp-Werts
--
--  Untermodule: Vector (Vector3/2, int16), CFrame, Color (Color3, BrickColor, ColorSequence), Gui (UDim, UDim2,
--  Rect, Font, Content), Misc (NumberRange, NumberSequence, TweenInfo, Ray, Region3, PhysicalProperties, Axes,
--  Faces, PathWaypoint, RaycastParams, OverlapParams, RaycastResult, CatalogSearchParams, SharedTable,
--  Secret, …), Time (DateTime, Random), Json (Roblox-JSON für HttpService).
-- =====================================================================
return function(R)
	local Util = R.Util
	local DT = { is = {}, make = {} }
	local typeof = Util.typeof
	local raise = Util.raise

	--- Gemeinsame Fehler-Metamethoden (Roblox nennt den Typnamen statt "userdata")
	function DT.concatError(a, b)
		raise(string.format("attempt to concatenate %s with %s", typeof(a), typeof(b)))
	end
	function DT.ltError(a, b)
		raise(string.format("attempt to compare %s < %s", typeof(a), typeof(b)))
	end
	function DT.leError(a, b)
		raise(string.format("attempt to compare %s <= %s", typeof(a), typeof(b)))
	end
	function DT.arithError(op)
		return function(a, b)
			raise(string.format("attempt to perform arithmetic (%s) on %s and %s", op, typeof(a), typeof(b)))
		end
	end

	--- Fehler für Zuweisung an Datentyp-Felder (Roblox: "X cannot be assigned to")
	function DT.readonlyNewindex(_self, k)
		raise(tostring(k) .. " cannot be assigned to")
	end

	--- Erzeugt einen leeren Host-Wert mit Standard-Metamethoden; liefert (userdata, metatable).
	function DT.newHost(index, tname, tostr, eq)
		local u = newproxy(true)
		local mt = getmetatable(u)
		mt.__index = index
		mt.__newindex = DT.readonlyNewindex
		mt.__type = tname
		mt.__tostring = tostr
		mt.__eq = eq
		mt.__concat = DT.concatError
		mt.__lt = DT.ltError
		mt.__le = DT.leError
		return u, mt
	end

	function DT.get(v)
		return Util.hostMeta(v)
	end

	--- Standard-Fehler für unbekannte Member eines Datentyps
	function DT.badMember(tname, k)
		raise(tostring(k) .. " is not a valid member of " .. tname)
	end

	-- Reihenfolge wichtig: CFrame braucht Vector, Gui braucht Color usw.
	require("@self/Vector")(R, DT)
	require("@self/CFrame")(R, DT)
	require("@self/Color")(R, DT)
	require("@self/Gui")(R, DT)
	require("@self/Misc")(R, DT)
	require("@self/Time")(R, DT)
	require("@self/Json")(R, DT)

	--- Liste der globalen Datentyp-Namen für Script-Umgebungen
	DT.globalNames = {
		"Vector3",
		"Vector2",
		"Vector3int16",
		"Vector2int16",
		"CFrame",
		"Color3",
		"BrickColor",
		"ColorSequence",
		"ColorSequenceKeypoint",
		"UDim",
		"UDim2",
		"Rect",
		"Font",
		"Content",
		"NumberRange",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"TweenInfo",
		"Ray",
		"Region3",
		"Region3int16",
		"PhysicalProperties",
		"Axes",
		"Faces",
		"PathWaypoint",
		"RaycastParams",
		"OverlapParams",
		"CatalogSearchParams",
		"SharedTable",
		"DateTime",
		"Random",
		"FloatCurveKey",
		"RotationCurveKey",
		"ValueCurveKey",
		"Path2DControlPoint",
		"SecurityCapabilities",
		"User",
		"InstanceHandle",
		"Secret",
		"DockWidgetPluginGuiInfo",
	}

	return DT
end
