--!nocheck
-- =====================================================================
--  AKYTEX TYCOON · Headless-Harness · Selbsttest (Fundament: Datentypen, Enums, Instanzen, Signale, Scheduler)
--  Aufruf im Projektordner:  $SP/luau-build/luau tools/headless/selftest.luau
--  Endet mit "SELFTEST OK (n Prüfungen)" oder bricht mit Fehler ab (Exit-Code ≠ 0).
--  Spiel-Code-Schnipsel laufen mit Chunk-Namen "src/selftest/…", damit Fehlerpositionen wie echte Spiel-Bugs
--  aussehen (Report-Kategorie A).
-- =====================================================================
local R = require("./runtime").boot({ frameRate = 30, startUnix = 1700000000, seed = 7 })
local Util, Report, Sched, Signal, DT, Enum, Inst, Globals =
	R.Util, R.Report, R.Sched, R.Signal, R.DT, R.Enum, R.Inst, R.Globals

local Vector3, Vector2, CFrame, Color3, UDim, UDim2, BrickColor =
	DT.Vector3, DT.Vector2, DT.CFrame, DT.Color3, DT.UDim, DT.UDim2, DT.BrickColor
local Instance = Inst.global
local typeof = Util.typeof
local EnumG = Enum.global
local neon = EnumG.Material.Neon

local passed, failed = 0, {}
local section = "?"
local function sec(name)
	section = name
end
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed[#failed + 1] = section .. " / " .. name .. (detail and (" -> " .. tostring(detail)) or "")
	end
end
local function near(a, b, eps)
	eps = eps or 1e-4
	return math.abs(a - b) <= eps
end
local function nearV3(v, x, y, z, eps)
	return near(v.X, x, eps) and near(v.Y, y, eps) and near(v.Z, z, eps)
end
local function expectError(name, fn, pattern)
	local ok, err = pcall(fn)
	if ok then
		check(name, false, "kein Fehler")
		return
	end
	err = tostring(err)
	check(name, string.find(err, pattern, 1, true) ~= nil, "Fehler war: " .. err)
end
local function noError(name, fn)
	local ok, err = pcall(fn)
	check(name, ok, err)
end

-- Kontexte + DataModels (gemeinsamer Baum reicht für den Selbsttest)
local server = Sched.newContext({ kind = "server", name = "server" })
local client = Sched.newContext({ kind = "client", name = "client:Tester" })
local game = Inst.newDataModel({ name = "SelfTest", context = server })
server.game = game
client.game = game
local workspace = game.Workspace

--- Spiel-Code (Chunk "src/selftest/<name>.luau") im Kontext ausführen; liefert Handle von Sched.invoke
local function runGame(ctx, name, code, ...)
	local fn = Globals.compile(code, "src/selftest/" .. name .. ".luau")
	assert(fn, "Selbsttest-Schnipsel kompiliert nicht: " .. name)
	setfenv(fn, Globals.makeEnv(ctx, nil))
	return Sched.invoke(ctx, fn, ...)
end
local function findError(pattern)
	for _, e in Report.errors do
		if string.find(e.message, pattern, 1, true) then
			return e
		end
	end
	return nil
end
local function findWarning(pattern)
	for _, w in Report.warnings do
		if string.find(w.message, pattern, 1, true) then
			return w
		end
	end
	return nil
end

-- =====================================================================
sec("API-Daten")
do
	check("Boot ohne Harness-Fehler", #Report.harness == 0, Report.harness[1] and Report.harness[1].message)
	local C = R.api.classes
	check("Part.Super", C.Part.s == "FormFactorPart")
	check("BasePart.Super", C.BasePart.s == "PVInstance")
	check("TextLabel.Super", C.TextLabel.s == "GuiLabel")
	check("Humanoid hat WalkSpeed", Inst.class("Humanoid").members.WalkSpeed ~= nil)
	check("TextChatService ist Service", Inst.class("TextChatService").service)
	check("ProximityPrompt.Triggered", Inst.class("ProximityPrompt").members.Triggered.kind == "event")
	check("Enum-Werte vorhanden", R.api.enums.KeyCode.E == 101)
	-- Vollständigkeit der Datentyp-Konstruktoren laut globalTypes
	local missingStatics = {}
	for dn, info in R.api.datatypes do
		local T = DT[dn]
		if T ~= nil and type(T) == "table" then
			for _, st in info.statics do
				if T[st] == nil then
					missingStatics[#missingStatics + 1] = dn .. "." .. st
				end
			end
		end
	end
	check("alle Datentyp-Konstruktoren (laut API) vorhanden", #missingStatics == 0, table.concat(missingStatics, ", "))

	-- =====================================================================
end
sec("Vector3")
do
	local v = Vector3.new(1, 2, 3)
	check("typeof", typeof(v) == "Vector3")
	check("type() nativ userdata", type(v) == "userdata")
	check("type() in Spiel-Umgebung = vector", Util.type(v) == "vector")
	check("Interning (rawequal)", rawequal(Vector3.new(1, 2, 3), v))
	local key = {}
	key[Vector3.new(4, 5, 6)] = true
	check("als Tabellenschlüssel", key[Vector3.new(4, 5, 6)] == true)
	check("Addition", v + Vector3.new(1, 1, 1) == Vector3.new(2, 3, 4))
	check("Skalar *", v * 2 == Vector3.new(2, 4, 6) and 2 * v == Vector3.new(2, 4, 6))
	check("Division", v / 2 == Vector3.new(0.5, 1, 1.5))
	check("Ganzzahl-Division", Vector3.new(7, 8, -3) // 2 == Vector3.new(3, 4, -2))
	check("komponentenweise *", v * v == Vector3.new(1, 4, 9))
	check("Negation", -v == Vector3.new(-1, -2, -3))
	check("Cross", Vector3.xAxis:Cross(Vector3.yAxis) == Vector3.zAxis)
	check("Dot", v:Dot(Vector3.new(1, 1, 1)) == 6)
	check("Magnitude", Vector3.new(3, 4, 0).Magnitude == 5)
	check("Unit", nearV3(Vector3.new(0, 0, 9).Unit, 0, 0, 1))
	check("Angle", near(Vector3.xAxis:Angle(Vector3.yAxis), math.pi / 2))
	check("Angle mit Achse +", near(Vector3.xAxis:Angle(Vector3.yAxis, Vector3.zAxis), math.pi / 2))
	check("Angle mit Achse -", near(Vector3.yAxis:Angle(Vector3.xAxis, Vector3.zAxis), -math.pi / 2))
	check("Lerp", Vector3.zero:Lerp(Vector3.new(10, 0, 0), 0.25) == Vector3.new(2.5, 0, 0))
	check(
		"FuzzyEq",
		Vector3.new(1, 2, 3):FuzzyEq(Vector3.new(1.000001, 2, 3))
			and not Vector3.new(1, 2, 3):FuzzyEq(Vector3.new(1.000001, 2, 3), 1e-8)
	)
	check(
		"Min/Max",
		Vector3.new(1, 5, 3):Min(Vector3.new(2, 0, 3)) == Vector3.new(1, 0, 3)
			and Vector3.max(Vector3.new(1, 5, 3), Vector3.new(2, 0, 4)) == Vector3.new(2, 5, 4)
	)
	check(
		"Abs/Floor/Ceil/Sign",
		Vector3.new(-1.5, 2.5, 0):Abs() == Vector3.new(1.5, 2.5, 0)
			and Vector3.new(1.5, -1.5, 0):Floor() == Vector3.new(1, -2, 0)
			and Vector3.new(1.2, -1.2, 0):Ceil() == Vector3.new(2, -1, 0)
			and Vector3.new(-3, 0, 2):Sign() == Vector3.new(-1, 0, 1)
	)
	check("float32", Vector3.new(0.1, 0, 0).X == 0.10000000149011612)
	check("Kleinbuchstaben x/magnitude", v.x == 1 and Vector3.new(3, 4, 0).magnitude == 5)
	check("tostring", tostring(Vector3.new(1, 0.5, -2)) == "1, 0.5, -2")
	check("fromNormalId", Vector3.fromNormalId(Enum.item("NormalId", "Front")) == Vector3.new(0, 0, -1))
	expectError("falscher Argumenttyp", function()
		Vector3.new("a")
	end, "invalid argument #1 to 'new' (number expected, got string)")
	expectError("Vector3 + Zahl", function()
		return v + 1
	end, "invalid argument #2 (Vector3 expected, got number)")
	expectError("Zuweisung an X", function()
		v.X = 5
	end, "X cannot be assigned to")
	expectError("unbekanntes Member", function()
		return v.Foo
	end, "Foo is not a valid member of Vector3")
	expectError("Methode mit Punkt", function()
		return v.Dot(5)
	end, "Expected ':' not '.' calling member function Dot")
	expectError("Vergleich <", function()
		return v < v
	end, "attempt to compare Vector3 < Vector3")
	expectError("Verkettung", function()
		return "Pos: " .. v
	end, "attempt to concatenate string with Vector3")
end
sec("Vector2")
do
	local v2 = Vector2.new(3, 4)
	check("Magnitude", v2.Magnitude == 5)
	check("Arithmetik", v2 + Vector2.new(1, 1) == Vector2.new(4, 5) and v2 * 2 == Vector2.new(6, 8))
	check("Cross (Zahl)", Vector2.new(1, 0):Cross(Vector2.new(0, 1)) == 1)
	check("kein Interning", not rawequal(Vector2.new(1, 1), Vector2.new(1, 1)))
	check("Angle signed", near(Vector2.new(1, 0):Angle(Vector2.new(0, -1), true), -math.pi / 2))

	-- =====================================================================
end
sec("CFrame")
do
	local rx, ry, rz = 0.3, -0.7, 1.1
	local cf = CFrame.new(1, 2, 3) * CFrame.Angles(rx, ry, rz)
	check(
		"Inverse * cf = identity",
		(cf * cf:Inverse()):FuzzyEq(CFrame.identity, 1e-5) and (cf:Inverse() * cf):FuzzyEq(CFrame.identity, 1e-5)
	)
	local ex, ey, ez = CFrame.Angles(rx, ry, rz):ToEulerAnglesXYZ()
	check("Euler XYZ Rundreise", near(ex, rx) and near(ey, ry) and near(ez, rz), string.format("%f %f %f", ex, ey, ez))
	local yx, yy, yz = CFrame.fromEulerAnglesYXZ(rx, ry, rz):ToEulerAnglesYXZ()
	check("Euler YXZ Rundreise", near(yx, rx) and near(yy, ry) and near(yz, rz))
	local ox, oy, oz = CFrame.fromOrientation(rx, ry, rz):ToOrientation()
	check("Orientation Rundreise", near(ox, rx) and near(oy, ry) and near(oz, rz))
	check(
		"Angles = X*Y*Z",
		CFrame.Angles(rx, ry, rz)
			:FuzzyEq(CFrame.Angles(rx, 0, 0) * CFrame.Angles(0, ry, 0) * CFrame.Angles(0, 0, rz), 1e-5)
	)
	local orderOk = true
	for _, item in Enum.items("RotationOrder") do
		local a, b, c = CFrame.fromEulerAngles(rx, ry, rz, item):ToEulerAngles(item)
		if not (near(a, rx) and near(b, ry) and near(c, rz)) then
			orderOk = false
		end
	end
	check("alle RotationOrder-Rundreisen", orderOk)
	check(
		"Gimbal-Lock ohne NaN",
		(function()
			local a, b, c = CFrame.Angles(0.2, math.pi / 2, 0.1):ToEulerAnglesXYZ()
			return a == a and b == b and c == c and near(b, math.pi / 2)
		end)()
	)
	local look = CFrame.lookAt(Vector3.zero, Vector3.new(10, 0, 0))
	check(
		"lookAt LookVector",
		nearV3(look.LookVector, 1, 0, 0) and nearV3(look.UpVector, 0, 1, 0) and nearV3(look.RightVector, 0, 0, 1)
	)
	check(
		"lookAt senkrecht nach oben ohne NaN",
		(function()
			local lv = CFrame.new(Vector3.zero, Vector3.new(0, 10, 0)).LookVector
			return nearV3(lv, 0, 1, 0)
		end)()
	)
	local p = Vector3.new(4, -2, 7)
	check("PointToObjectSpace(cf*p) = p", nearV3(cf:PointToObjectSpace(cf * p), 4, -2, 7))
	check(
		"VectorToWorldSpace",
		nearV3(CFrame.Angles(0, math.pi / 2, 0):VectorToWorldSpace(Vector3.new(1, 0, 0)), 0, 0, -1)
	)
	check("fromAxisAngle", nearV3(CFrame.fromAxisAngle(Vector3.yAxis, math.pi / 2) * Vector3.new(1, 0, 0), 0, 0, -1))
	local axis, ang = CFrame.fromAxisAngle(Vector3.new(1, 2, 3), 1.2):ToAxisAngle()
	check(
		"ToAxisAngle Rundreise",
		near(ang, 1.2)
			and nearV3(axis, Vector3.new(1, 2, 3).Unit.X, Vector3.new(1, 2, 3).Unit.Y, Vector3.new(1, 2, 3).Unit.Z)
	)
	local ia, iang = CFrame.identity:ToAxisAngle()
	check("ToAxisAngle identity", iang == 0 and ia == Vector3.xAxis)
	local mid = CFrame.new():Lerp(CFrame.new(10, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.5)
	check(
		"Lerp (Slerp)",
		nearV3(mid.Position, 5, 0, 0) and mid.Rotation:FuzzyEq(CFrame.Angles(0, math.pi / 4, 0), 1e-5)
	)
	check(
		"Quaternion-Konstruktor",
		CFrame.new(0, 0, 0, 0, math.sin(math.pi / 4), 0, math.cos(math.pi / 4))
			:FuzzyEq(CFrame.fromAxisAngle(Vector3.yAxis, math.pi / 2), 1e-5)
	)
	check(
		"CFrame +/- Vector3",
		(CFrame.new(1, 1, 1) + Vector3.new(1, 2, 3)).Position == Vector3.new(2, 3, 4)
			and (CFrame.new(1, 1, 1) - Vector3.one).Position == Vector3.zero
	)
	check("GetComponents (12)", select("#", cf:GetComponents()) == 12)
	check("tostring", tostring(CFrame.new(1, 2, 3)) == "1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1")
	check("fromMatrix", CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.yAxis):FuzzyEq(CFrame.identity))
	check(
		"fromRotationBetweenVectors",
		nearV3(CFrame.fromRotationBetweenVectors(Vector3.yAxis, Vector3.xAxis) * Vector3.yAxis, 1, 0, 0)
	)
	check(
		"ToWorldSpace/ToObjectSpace",
		cf:ToObjectSpace(cf:ToWorldSpace(CFrame.new(1, 2, 3))):FuzzyEq(CFrame.new(1, 2, 3), 1e-4)
	)
	check("Orthonormalize", CFrame.new(0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2):Orthonormalize():FuzzyEq(CFrame.identity))
	expectError("new(Zahl, Zahl)", function()
		CFrame.new(1, 2)
	end, "invalid argument #1 to 'new' (Vector3 expected, got number)")
	expectError("falsche Argumentanzahl", function()
		CFrame.new(1, 2, 3, 4)
	end, "Invalid number of arguments: 4")
	expectError("cf * Zahl", function()
		return cf * 5
	end, "invalid argument #2 (Vector3 expected, got number)")

	-- =====================================================================
end
sec("Color3/BrickColor")
do
	local h, s, val = Color3.fromHSV(0.25, 0.5, 0.8):ToHSV()
	check("HSV Rundreise", near(h, 0.25) and near(s, 0.5) and near(val, 0.8))
	local rh, rs, rv = Color3.fromRGB(255, 0, 0):ToHSV()
	check("Rot -> HSV", rh == 0 and rs == 1 and rv == 1)
	check("Hex", Color3.fromHex("#FFAA00"):ToHex() == "ffaa00" and Color3.fromHex("FA0") == Color3.fromHex("FFAA00"))
	check("Lerp", Color3.new(1, 0, 0):Lerp(Color3.new(0, 0, 1), 0.5) == Color3.new(0.5, 0, 0.5))
	check("fromRGB float32", Color3.fromRGB(100, 0, 0).R == Util.f32(100 / 255))
	expectError("fromHex ungültig", function()
		Color3.fromHex("xyz")
	end, "Unable to convert characters to hex value")
	expectError("Color3 + Color3", function()
		return Color3.new() + Color3.new()
	end, "attempt to perform arithmetic (add) on Color3 and Color3")
	check(
		"BrickColor Name/Nummer",
		BrickColor.new("Really red").Number == 1004 and BrickColor.new(1004).Name == "Really red"
	)
	check("BrickColor aus Color3", BrickColor.new(Color3.new(1, 0, 0)).Name == "Really red")
	check("BrickColor unbekannt -> Standard", BrickColor.new("Nope").Number == 194)
	check("BrickColor.palette", BrickColor.palette(70).Name == "Gold")

	-- =====================================================================
end
sec("UDim/UDim2")
do
	check("UDim2 +", UDim2.new(0.5, 10, 1, -5) + UDim2.new(0.25, 5, 0, 5) == UDim2.new(0.75, 15, 1, 0))
	check("UDim2 -", UDim2.new(1, 10, 1, 10) - UDim2.new(0.5, 5, 0, 10) == UDim2.new(0.5, 5, 1, 0))
	check("UDim2 unär", -UDim2.new(1, 2, 3, 4) == UDim2.new(-1, -2, -3, -4))
	check("UDim2 Lerp", UDim2.new():Lerp(UDim2.new(1, 100, 1, 100), 0.5) == UDim2.new(0.5, 50, 0.5, 50))
	check(
		"fromScale/fromOffset",
		UDim2.fromScale(0.5, 0.25) == UDim2.new(0.5, 0, 0.25, 0) and UDim2.fromOffset(10, 20) == UDim2.new(0, 10, 0, 20)
	)
	check("X/Width", UDim2.new(0.5, 10, 1, 0).X.Scale == 0.5 and UDim2.new(0.5, 10, 1, 0).Width.Offset == 10)
	check("tostring", tostring(UDim2.new(0.5, 10, 1, 0)) == "{0.5, 10}, {1, 0}")
	check("Offset int", UDim.new(0, 10.7).Offset == 10)
	expectError("UDim2 + UDim", function()
		return UDim2.new() + UDim.new()
	end, "invalid argument #2 (UDim2 expected, got UDim)")

	-- =====================================================================
end
sec("weitere Datentypen")
do
	check("NumberSequence(n)", #DT.NumberSequence.new(0.5).Keypoints == 2)
	expectError("NumberSequence Ende ≠ 1", function()
		DT.NumberSequence.new({ DT.NumberSequenceKeypoint.new(0, 1), DT.NumberSequenceKeypoint.new(0.5, 1) })
	end, "time must start at 0, and end at 1")
	check("ColorSequence(c0, c1)", #DT.ColorSequence.new(Color3.new(1, 0, 0), Color3.new(0, 0, 1)).Keypoints == 2)
	expectError("NumberRange min > max", function()
		DT.NumberRange.new(5, 1)
	end, "NumberRange")
	check("NumberRange(n)", DT.NumberRange.new(3).Min == 3 and DT.NumberRange.new(3).Max == 3)
	local ti = DT.TweenInfo.new()
	check(
		"TweenInfo Defaults",
		ti.Time == 1
			and ti.EasingStyle == EnumG.EasingStyle.Quad
			and ti.EasingDirection == EnumG.EasingDirection.Out
			and ti.RepeatCount == 0
	)
	local ray = DT.Ray.new(Vector3.zero, Vector3.new(10, 0, 0))
	check(
		"Ray ClosestPoint/Distance",
		ray:ClosestPoint(Vector3.new(5, 5, 0)) == Vector3.new(5, 0, 0) and ray:Distance(Vector3.new(5, 5, 0)) == 5
	)
	local reg = DT.Region3.new(Vector3.zero, Vector3.new(2, 4, 6))
	check("Region3", reg.Size == Vector3.new(2, 4, 6) and reg.CFrame.Position == Vector3.new(1, 2, 3))
	local rp = DT.RaycastParams.new()
	table.insert(rp.FilterDescendantsInstances, Instance.new("Part"))
	check("RaycastParams Filter ist Kopie", #rp.FilterDescendantsInstances == 0)
	rp.FilterDescendantsInstances = { Instance.new("Part") }
	check(
		"RaycastParams Filter setzen",
		#rp.FilterDescendantsInstances == 1 and rp.FilterType == EnumG.RaycastFilterType.Exclude
	)
	expectError("RaycastParams Filter falscher Inhalt", function()
		rp.FilterDescendantsInstances = { "x" }
	end, "Unable to cast value to Objects")
	local font = DT.Font.fromEnum(EnumG.Font.GothamBold)
	check(
		"Font.fromEnum",
		font.Family == "rbxasset://fonts/families/GothamSSm.json" and font.Weight == EnumG.FontWeight.Bold and font.Bold
	)
	font.Bold = false
	check("Font veränderbar", font.Weight == EnumG.FontWeight.Regular)
	check("PhysicalProperties(Material)", near(DT.PhysicalProperties.new(EnumG.Material.Wood).Density, 0.35))
	check("Faces/Axes", DT.Faces.new(EnumG.NormalId.Top).Top == true and DT.Axes.new(EnumG.Axis.X).X == true)
end
sec("DateTime")
do
	check("Epoche ISO", DT.DateTime.fromUnixTimestamp(0):ToIsoDate() == "1970-01-01T00:00:00Z")
	local d = DT.DateTime.fromIsoDate("2020-01-02T10:30:45Z")
	check("fromIsoDate", d ~= nil and d.UnixTimestamp == 1577961045)
	check("FormatUniversalTime", d:FormatUniversalTime("YYYY-MM-DD HH:mm:ss", "en-us") == "2020-01-02 10:30:45")
	check("Format de-de", d:FormatUniversalTime("dddd, D. MMMM", "de-de") == "Donnerstag, 2. Januar")
	check("Format LL en-us", d:FormatUniversalTime("LL", "en-us") == "January 2, 2020")
	check("ToUniversalTime", d:ToUniversalTime().Month == 1 and d:ToUniversalTime().Hour == 10)
	check("fromIsoDate ungültig -> nil", DT.DateTime.fromIsoDate("kaputt") == nil)
	check("fromUniversalTime Rundreise", DT.DateTime.fromUniversalTime(2020, 1, 2, 10, 30, 45) == d)
	expectError("ungültiges Datum", function()
		DT.DateTime.fromUniversalTime(2021, 2, 29)
	end, "Invalid date")
	check("DateTime.now = simulierte Zeit", DT.DateTime.now().UnixTimestamp == 1700000000 + math.floor(Sched.now))
end
sec("Random")
do
	local r1, r2 = DT.Random.new(42), DT.Random.new(42)
	local same = true
	for _ = 1, 5 do
		if r1:NextNumber() ~= r2:NextNumber() then
			same = false
		end
	end
	check("deterministisch je Seed", same)
	local c1 = r1:Clone()
	check("Clone setzt Folge fort", c1:NextInteger(1, 1000000) == r1:NextInteger(1, 1000000))
	local inRange = true
	for _ = 1, 200 do
		local n = r1:NextInteger(1, 6)
		if n < 1 or n > 6 or n ~= math.floor(n) then
			inRange = false
		end
	end
	check("NextInteger im Bereich", inRange)
	check("Seeds 0 und 0.99 gleich", DT.Random.new(0):NextNumber() == DT.Random.new(0.99):NextNumber())
	expectError("NextInteger leeres Intervall", function()
		r1:NextInteger(5, 1)
	end, "interval is empty")
	expectError("Shuffle mit Loch", function()
		r1:Shuffle({ 1, nil, 3 })
	end, "holes")
	local u = r1:NextUnitVector()
	check("NextUnitVector Länge 1", near(u.Magnitude, 1, 1e-5))
end
sec("JSON")
do
	local J = DT.json
	local src = { a = 1, b = { 1, 2, 3 }, c = 'x\n"y"', d = true, e = { f = 1.5 } }
	local enc = J.encode(src)
	local dec = J.decode(enc)
	check("Rundreise", dec.a == 1 and dec.b[3] == 3 and dec.c == src.c and dec.d == true and dec.e.f == 1.5, enc)
	check("leere Tabelle = []", J.encode({}) == "[]")
	check("Array hat Vorrang", J.encode({ 1, 2, x = 3 }) == "[1,2]")
	check("Vector3 -> null", J.encode({ v = Vector3.new() }) == '{"v":null}')
	expectError("zyklisch", function()
		local t = {}
		t.self = t
		J.encode(t)
	end, "tables cannot be cyclic")
	expectError("kaputtes JSON", function()
		J.decode("[1,")
	end, "Can't parse JSON")
	check("null -> nil", next(J.decode('{"a":null}')) == nil)
	check("Unicode-Escape", J.decode('"\\u00e4"') == "ä")

	-- =====================================================================
end
sec("Enum")
do
	check("Typen", typeof(neon) == "EnumItem" and typeof(EnumG.Material) == "Enum" and typeof(EnumG) == "Enums")
	check("Name/Value/EnumType", neon.Name == "Neon" and neon.Value == 288 and neon.EnumType == EnumG.Material)
	check("tostring", tostring(neon) == "Enum.Material.Neon")
	check(
		"FromName/FromValue",
		EnumG.Material:FromName("Neon") == neon
			and EnumG.Material:FromValue(288) == neon
			and EnumG.Material:FromName("Nope") == nil
	)
	check("GetEnumItems", #EnumG.Material:GetEnumItems() > 10)
	check("IsA", neon:IsA("Material") and not neon:IsA("PartType"))
	check("Singleton", rawequal(EnumG.KeyCode.E, EnumG.KeyCode.E))
	expectError("unbekanntes Item", function()
		return EnumG.Material.Nope
	end, 'Nope is not a valid member of "Enum.Material"')
	expectError("unbekanntes Enum", function()
		return EnumG.Nope
	end, 'Nope is not a valid member of "Enum"')

	-- =====================================================================
end
sec("Instanzen: Eigenschaften")
do
	local part = Instance.new("Part")
	check(
		"Defaults",
		part.Size == Vector3.new(4, 1.2, 2)
			and part.Anchored == false
			and part.Material == EnumG.Material.Plastic
			and part.Name == "Part"
	)
	check(
		"ClassName/IsA",
		part.ClassName == "Part" and part:IsA("BasePart") and part:IsA("Instance") and not part:IsA("Model")
	)
	check("typeof Instance", typeof(part) == "Instance")
	check("getmetatable gesperrt", Util.getmetatable(part) == "The metatable is locked")
	expectError("nicht erzeugbar", function()
		Instance.new("BasePart")
	end, 'Unable to create an Instance of type "BasePart"')
	expectError("unbekannte Klasse", function()
		Instance.new("Foo")
	end, 'Unable to create an Instance of type "Foo"')
	expectError("unbekannte Eigenschaft lesen", function()
		return part.Foo
	end, 'Foo is not a valid member of Part "Part"')
	expectError("unbekannte Eigenschaft schreiben", function()
		part.Foo = 1
	end, 'Foo is not a valid member of Part "Part"')
	expectError("falscher Typ bool", function()
		part.Anchored = 1
	end, "Unable to assign property Anchored. bool expected, got number")
	expectError("falscher Typ Vector3", function()
		part.Size = 5
	end, "Unable to assign property Size. Vector3 expected, got number")
	expectError("read only", function()
		part.ClassName = "X"
	end, "Unable to assign property ClassName. Property is read only")
	expectError("Sicherheitsstufe", function()
		return part.RobloxLocked
	end, "cannot access 'RobloxLocked'")
	part.Transparency = "0.5"
	check("numerischer String", part.Transparency == 0.5)
	part.Transparency = 0.1
	check("float32-Property", part.Transparency == Util.f32(0.1) and part.Transparency ~= 0.1)
	part.Size = Vector3.new(0, -1, 5000)
	check("Size geklemmt", part.Size == Vector3.new(0.001, 0.001, 2048))
	part.Material = "Neon"
	check("Enum aus Name", part.Material == neon)
	part.Material = 512
	check("Enum aus Zahl", part.Material == EnumG.Material.Wood)
	expectError("Enum falscher Typ", function()
		part.Material = EnumG.PartType.Ball
	end, "EnumItem of type Material expected")
	expectError("Enum unbekannter Name", function()
		part.Material = "Nope"
	end, 'Invalid value "Nope" for enum Material')
	local folder = Instance.new("Folder")
	folder.Name = 5
	check("Name aus Zahl", folder.Name == "5")
	local iv = Instance.new("IntValue")
	iv.Value = 3.7
	check("int-Property abgeschnitten", iv.Value == 3)
	local om = Instance.new("ObjectValue")
	expectError("Instanz-Property falscher Typ", function()
		om.Value = 5
	end, "Instance expected, got number")
	local mdl = Instance.new("Model")
	expectError("Instanz-Property falsche Klasse", function()
		mdl.PrimaryPart = Instance.new("Folder")
	end, "BasePart expected, got Folder")
	check(
		"Font-Property liefert Kopie",
		(function()
			local tl = Instance.new("TextLabel")
			local f = tl.FontFace
			f.Weight = EnumG.FontWeight.Heavy
			return tl.FontFace.Weight ~= EnumG.FontWeight.Heavy
		end)()
	)
	local rf = Instance.new("RemoteFunction")
	expectError("Callback lesen", function()
		return rf.OnServerInvoke
	end, "OnServerInvoke is a callback member of RemoteFunction")
	expectError("Callback falscher Typ", function()
		rf.OnServerInvoke = 5
	end, "function expected, got number")
	noError("Callback setzen", function()
		rf.OnServerInvoke = function() end
	end)
	expectError("GetPropertyChangedSignal unbekannt", function()
		part:GetPropertyChangedSignal("Foo")
	end, "Foo is not a valid property name.")
	expectError("Methode existiert nicht", function()
		part:Foo()
	end, "Foo is not a valid member of Part")
	expectError("Methode mit Punkt", function()
		part.Destroy()
	end, "Expected ':' not '.' calling member function Destroy")
	check("unmocked Stub gibt nil", part:SubtractAsync({}) == nil and Report.unmocked["Part:SubtractAsync"] ~= nil)
	check(
		"deprecated Alias funktioniert",
		(function()
			local f = Instance.new("Folder")
			local c = Instance.new("Folder")
			c.Name = "Kind"
			c.Parent = f
			return f:findFirstChild("Kind") == c and Report.deprecated["Instance:findFirstChild"] ~= nil
		end)()
	)
end
sec("Instanzen: Baum")
do
	local model = Instance.new("Model")
	model.Name = "M"
	model.Parent = workspace
	local a = Instance.new("Part")
	a.Name = "A"
	a.Parent = model
	local sub = Instance.new("Folder")
	sub.Name = "Sub"
	sub.Parent = model
	local b = Instance.new("WedgePart")
	b.Name = "B"
	b.Parent = sub
	local nameChild = Instance.new("Folder")
	nameChild.Name = "Name"
	nameChild.Parent = model
	check("Kind per Name", model.A == a and model.Sub.B == b)
	check("Property vor Kind", model.Name == "M")
	check("GetFullName", b:GetFullName() == "Workspace.M.Sub.B")
	check("FindFirstChild rekursiv", model:FindFirstChild("B", true) == b and model:FindFirstChild("B") == nil)
	check(
		"FindFirstChildOfClass",
		model:FindFirstChildOfClass("Part") == a and model:FindFirstChildOfClass("BasePart") == nil
	)
	check(
		"FindFirstChildWhichIsA rekursiv",
		sub:FindFirstChildWhichIsA("BasePart") == b and model:FindFirstChildWhichIsA("WedgePart", true) == b
	)
	check(
		"FindFirstAncestor*",
		b:FindFirstAncestor("M") == model
			and b:FindFirstAncestorOfClass("Model") == model
			and b:FindFirstAncestorWhichIsA("PVInstance") == model
	)
	check("FindFirstDescendant", model:FindFirstDescendant("B") == b)
	local desc = model:GetDescendants()
	check(
		"GetDescendants Reihenfolge",
		#desc == 4 and desc[1] == a and desc[2] == sub and desc[3] == b and desc[4] == nameChild
	)
	check(
		"GetChildren ist Kopie",
		(function()
			local ch = model:GetChildren()
			table.remove(ch)
			return #model:GetChildren() == 3
		end)()
	)
	check(
		"IsDescendantOf/IsAncestorOf",
		b:IsDescendantOf(model) and model:IsAncestorOf(b) and not model:IsDescendantOf(b) and b:IsDescendantOf(game)
	)
	expectError("Zirkel", function()
		model.Parent = b
	end, "would result in circular reference")
	expectError("eigener Parent", function()
		model.Parent = model
	end, "as its own parent")
	expectError("Parent falscher Typ", function()
		a.Parent = "x"
	end, "Instance expected, got string")
	local doomed = Instance.new("Part")
	doomed.Parent = workspace
	doomed:Destroy()
	check("Destroy setzt Parent nil", doomed.Parent == nil)
	expectError("Parent nach Destroy gesperrt", function()
		doomed.Parent = workspace
	end, "The Parent property of Part is locked")
	noError("Destroy zweimal", function()
		doomed:Destroy()
	end)
	expectError("Service zerstören", function()
		workspace:Destroy()
	end, "locked")
end
sec("Instanzen: Namensindex (viele Kinder)")
do
	local big = Instance.new("Folder")
	for i = 1, 60 do
		local c = Instance.new("Folder")
		c.Name = "C" .. i
		c.Parent = big
	end
	local c25 = big:FindFirstChild("C25")
	check("Suche in 60 Kindern", c25 ~= nil and c25.Name == "C25" and big.C60.Name == "C60")
	c25.Name = "Z"
	check("nach Umbenennung", big:FindFirstChild("C25") == nil and big:FindFirstChild("Z") == c25)
	local d1, d2 = Instance.new("Folder"), Instance.new("Folder")
	d1.Name, d2.Name = "D", "D"
	d1.Parent, d2.Parent = big, big
	check("doppelte Namen: erstes Kind", big:FindFirstChild("D") == d1)
	d1.Parent = nil
	check("nach Entfernen: nächstes Kind", big:FindFirstChild("D") == d2)
	d1.Parent = big
	check("wieder hinzugefügt hinten", big:FindFirstChild("D") == d2)
	d2:Destroy()
	check("nach Destroy", big:FindFirstChild("D") == d1)
end
sec("Instanzen: Clone/ClearAllChildren")
do
	local cm = Instance.new("Model")
	local cpA, cpB = Instance.new("Part"), Instance.new("Part")
	cpA.Name, cpB.Name = "A", "B"
	cpA.Parent, cpB.Parent = cm, cm
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = cpA, cpB
	weld.Parent = cm
	local hidden = Instance.new("Folder")
	hidden.Archivable = false
	hidden.Parent = cm
	cpA:SetAttribute("Preis", 42)
	cpA:AddTag("Kaufbar")
	local clone = cm:Clone()
	check("Clone tief", clone ~= cm and clone.A ~= cpA and clone.A.Name == "A" and clone.Parent == nil)
	check("Clone ohne Archivable=false", clone:FindFirstChildOfClass("Folder") == nil)
	check("Clone biegt Referenzen um", clone.WeldConstraint.Part0 == clone.A and clone.WeldConstraint.Part1 == clone.B)
	check("Clone kopiert Attribute/Tags", clone.A:GetAttribute("Preis") == 42 and clone.A:HasTag("Kaufbar"))
	check("Archivable=false -> nil", hidden:Clone() == nil)
	check("Instance.fromExisting ohne Kinder", #Instance.fromExisting(cm):GetChildren() == 0)
	cm:ClearAllChildren()
	check("ClearAllChildren", #cm:GetChildren() == 0 and cpA.Parent == nil)
end
sec("Attribute/Tags")
do
	local ap = Instance.new("Part")
	expectError("Attribut Tabelle", function()
		ap:SetAttribute("T", {})
	end, "type table is not supported")
	expectError("Attribut Instanz", function()
		ap:SetAttribute("T", Instance.new("Folder"))
	end, "type Instance is not supported")
	expectError("Attributname ungültig", function()
		ap:SetAttribute("mit Leerzeichen", 1)
	end, "contains invalid characters")
	expectError("Attributname RBX", function()
		ap:SetAttribute("RBXFoo", 1)
	end, "reserved")
	ap:SetAttribute("Geld", 5)
	ap:SetAttribute("Pos", Vector3.new(1, 2, 3))
	ap:SetAttribute("Farbe", EnumG.Material.Neon)
	check(
		"Get/SetAttribute",
		ap:GetAttribute("Geld") == 5
			and ap:GetAttribute("Pos") == Vector3.new(1, 2, 3)
			and ap:GetAttribute("Farbe") == neon
	)
	check("GetAttributes", ap:GetAttributes().Geld == 5)
	ap:SetAttribute("Geld", nil)
	check("Attribut entfernen", ap:GetAttribute("Geld") == nil and ap:GetAttributes().Geld == nil)
	ap:AddTag("X")
	ap:AddTag("X")
	check("Tags", ap:HasTag("X") and #ap:GetTags() == 1)
	ap:RemoveTag("X")
	check("RemoveTag", not ap:HasTag("X"))
	local CS = game:GetService("CollectionService")
	local tagged = Instance.new("Part")
	tagged:AddTag("Lampe")
	check("GetTagged nur im DataModel", #CS:GetTagged("Lampe") == 0)
	local addedLog = {}
	CS:GetInstanceAddedSignal("Lampe"):Connect(function(inst)
		addedLog[#addedLog + 1] = inst
	end)
	tagged.Parent = workspace
	Sched.flush()
	check("GetTagged + InstanceAdded", #CS:GetTagged("Lampe") == 1 and addedLog[1] == tagged)

	-- =====================================================================
end
sec("Signale (Deferred)")
do
	local sp = Instance.new("Part")
	local log = {}
	sp.Changed:Connect(function(prop)
		log[#log + 1] = prop
	end)
	sp.Name = "Neu"
	check("Handler läuft NICHT synchron", #log == 0)
	Sched.flush()
	check("Handler nach Resumption-Punkt", #log == 1 and log[1] == "Name")
	sp.Name = "Neu"
	Sched.flush()
	check("gleicher Wert feuert nicht", #log == 1)
	local pcount = 0
	sp:GetPropertyChangedSignal("Anchored"):Connect(function()
		pcount += 1
	end)
	sp.Anchored = true
	sp.Anchored = false
	Sched.flush()
	check("GetPropertyChangedSignal je Änderung", pcount == 2)
	local onceN = 0
	sp.Changed:Once(function()
		onceN += 1
	end)
	sp.Name = "X1"
	sp.Name = "X2"
	Sched.flush()
	check("Once nur einmal", onceN == 1)
	local discN = 0
	local conn = sp.Changed:Connect(function()
		discN += 1
	end)
	sp.Name = "X3"
	conn:Disconnect()
	Sched.flush()
	check("Disconnect vor Ausführung -> kein Aufruf", discN == 0 and conn.Connected == false)
	expectError("Connect ohne Funktion", function()
		sp.Changed:Connect(5)
	end, "Attempt to connect failed: Passed value is not a function")
	expectError("Signal unbekanntes Member", function()
		return sp.Changed.Foo
	end, "Foo is not a valid member of RBXScriptSignal")
	-- Wait
	local waited = nil
	Sched.spawnHandler(function()
		waited = sp.Changed:Wait()
	end, server)
	sp.Name = "W"
	check("Wait noch wartend", waited == nil)
	Sched.flush()
	check("Wait liefert Argumente", waited == "Name")
	-- ValueBase.Changed liefert den Wert
	local valLog = {}
	local nv = Instance.new("NumberValue")
	nv.Changed:Connect(function(newValue)
		valLog[#valLog + 1] = newValue
	end)
	nv.Name = "Egal"
	nv.Value = 2.5
	Sched.flush()
	check("ValueBase.Changed: nur Value, mit Wert", #valLog == 1 and valLog[1] == 2.5)
	-- ChildAdded / AttributeChanged / Destroying
	local childLog, attrLog, destroyed = {}, {}, false
	local holder = Instance.new("Folder")
	holder.ChildAdded:Connect(function(c)
		childLog[#childLog + 1] = c
	end)
	holder.AttributeChanged:Connect(function(n)
		attrLog[#attrLog + 1] = n
	end)
	holder.Destroying:Connect(function()
		destroyed = true
	end)
	local kid = Instance.new("Folder")
	kid.Parent = holder
	holder:SetAttribute("A", 1)
	Sched.flush()
	check("ChildAdded", childLog[1] == kid)
	check("AttributeChanged", attrLog[1] == "A")
	holder:Destroy()
	check("Destroying läuft", destroyed)
	-- Handler-Fehler werden erfasst, andere Handler laufen weiter
	local after = false
	local ep = Instance.new("Part")
	local hfn = Globals.compile(
		'local ep = ...\nep.Changed:Connect(function() error("Handler kaputt") end)',
		"src/selftest/handler.luau"
	)
	setfenv(hfn, Globals.makeEnv(server, nil))
	Sched.spawnHandler(hfn, server, "test", ep)
	ep.Changed:Connect(function()
		after = true
	end)
	ep.Name = "boom"
	Sched.flush()
	local he = findError("Handler kaputt")
	check(
		"Handler-Fehler erfasst",
		he ~= nil and he.location == "src/selftest/handler.luau:2" and he.category == "A",
		he and he.location
	)
	check("andere Handler laufen weiter", after)
end
sec("Kontexte")
do
	local seen = {}
	local ctxPart = Instance.new("Part")
	Sched.spawnHandler(function()
		ctxPart.Changed:Connect(function()
			seen.handler = Sched.ctx()
			Sched.spawn(function()
				seen.spawned = Sched.ctx()
			end)
			Sched.defer(function()
				seen.deferred = Sched.ctx()
			end)
		end)
	end, client, "ctxtest")
	ctxPart.Name = "Ctx"
	Sched.flush()
	check("Signal-Handler erbt Kontext des Verbinders", seen.handler == client)
	check("task.spawn erbt Kontext", seen.spawned == client)
	check("task.defer erbt Kontext", seen.deferred == client)
	local hctx = runGame(
		client,
		"coro",
		[[
	local co = coroutine.create(function() return 1 end)
	local w = coroutine.wrap(function() return 2 end)
	return co, w()
]]
	)
	check(
		"coroutine.create erbt Kontext",
		hctx.done and Sched.threadCtx[hctx.results[1]] == client and hctx.results[2] == 2
	)
	check("Haupt-Thread = Harness-Kontext", Sched.ctx() == Sched.harnessCtx)

	-- =====================================================================
end
sec("Scheduler")
do
	local t0 = Sched.now
	local waitedFor = nil
	Sched.spawnHandler(function()
		waitedFor = Sched.wait(1)
	end, server)
	Sched.run(0.5)
	check("task.wait noch nicht fertig", waitedFor == nil)
	Sched.run(0.6)
	check("task.wait(1) simuliert", waitedFor ~= nil and waitedFor >= 1 and waitedFor < 1.1, waitedFor)
	local delayedAt = nil
	Sched.delay(0.5, function(x)
		delayedAt = Sched.now - t0
		check("task.delay Argumente", x == "arg")
	end, "arg")
	local order = {}
	Sched.spawnHandler(function()
		Sched.defer(function()
			order[#order + 1] = "defer"
		end)
		Sched.spawn(function()
			order[#order + 1] = "spawn"
		end)
		order[#order + 1] = "nach spawn"
	end, server)
	check(
		"Reihenfolge spawn/defer",
		order[1] == "spawn" and order[2] == "nach spawn" and order[3] == "defer",
		table.concat(order, ",")
	)
	local cancelledRan = false
	local victim = Sched.spawnHandler(function()
		Sched.wait(0.2)
		cancelledRan = true
	end, server)
	Sched.cancel(victim)
	Sched.run(1)
	check("task.delay", delayedAt ~= nil and delayedAt >= 0.5)
	check("task.cancel", not cancelledRan and coroutine.status(victim) == "dead")
	local legacy = runGame(server, "legacy", "local a, b = wait(0.1) return a, b")
	Sched.await(legacy)
	check(
		"wait() alt: zwei Rückgaben",
		legacy.done
			and legacy.results[1] >= 0.1
			and type(legacy.results[2]) == "number"
			and legacy.results[2] <= Sched.now
	)
	check("deprecated wait gezählt", Report.deprecated.wait ~= nil and Report.deprecated.wait.count >= 1)
	local clocks =
		runGame(server, "clocks", "return os.time(), tick(), time(), os.clock(), DateTime.now().UnixTimestamp")
	check(
		"os.time/tick/time simuliert",
		clocks.results[1] == math.floor(1700000000 + Sched.now)
			and near(clocks.results[2], 1700000000 + Sched.now)
			and clocks.results[3] == Sched.now
			and clocks.results[5] == math.floor(1700000000 + Sched.now)
	)
	local srvDate = runGame(server, "date", 'return os.date("%H", 0)')
	check("os.date auf dem Server in UTC", srvDate.results[1] == "00")
	local okNY, msgNY = Sched.callNoYield(function()
		Sched.wait(0.1)
	end)
	check(
		"Yield in nicht-yieldendem Callback",
		okNY == false
			and string.find(tostring(msgNY), "attempt to yield across metamethod/C-call boundary", 1, true) ~= nil,
		msgNY
	)
	local okNY2, msgNY2 = Sched.callNoYield(function()
		coroutine.yield()
	end)
	check(
		"roher Yield in nicht-yieldendem Callback",
		okNY2 == false and string.find(msgNY2, "attempt to yield", 1, true) ~= nil
	)

	-- =====================================================================
end
sec("WaitForChild")
do
	local wmodel = Instance.new("Model")
	wmodel.Name = "W"
	wmodel.Parent = workspace
	local immediate = Instance.new("Folder")
	immediate.Name = "Da"
	immediate.Parent = wmodel
	local hi = runGame(server, "wfc_now", "local m = ... return m:WaitForChild('Da')", wmodel)
	check("sofort ohne Yield", hi.done and hi.results[1] == immediate)
	local hl = runGame(server, "wfc_later", "local m = ... return m:WaitForChild('Spaeter')", wmodel)
	check("wartet", not hl.done)
	Sched.run(1)
	local later = Instance.new("Folder")
	later.Name = "Spaeter"
	later.Parent = wmodel
	Sched.flush()
	check("liefert später hinzugefügtes Kind", hl.done and hl.results[1] == later)
	local hr = runGame(server, "wfc_rename", "local m = ... return m:WaitForChild('Umbenannt')", wmodel)
	later.Name = "Umbenannt"
	Sched.flush()
	check("erkennt Umbenennung", hr.done and hr.results[1] == later)
	local ht = runGame(server, "wfc_timeout", "local m = ... return m:WaitForChild('Nie', 2)", wmodel)
	Sched.run(1.5)
	check("Timeout läuft noch", not ht.done)
	Sched.run(1)
	check("Timeout -> nil", ht.done and ht.results[1] == nil and ht.results.n == 1)
	local hinf = runGame(server, "wfc_inf", "local m = ...\nreturn m:WaitForChild('NieMals')", wmodel)
	Sched.run(4.5)
	check("keine Warnung vor 5 s", findWarning("NieMals") == nil)
	Sched.run(1)
	local iy = findWarning("Infinite yield possible on 'Workspace.W:WaitForChild(\"NieMals\")'")
	check("Infinite-yield-Warnung nach 5 s", iy ~= nil and iy.kind == "infiniteYield")
	check(
		"Warnung mit Traceback/Position",
		iy ~= nil and iy.location == "src/selftest/wfc_inf.luau:2",
		iy and iy.location
	)
	check("Timeout-Warter ohne Warnung", findWarning('WaitForChild("Nie")') == nil)
	expectError("WaitForChild ohne Namen", function()
		wmodel:WaitForChild(nil)
	end, "Argument 1 missing or nil")

	-- =====================================================================
end
sec("require")
do
	local rs = game.ReplicatedStorage
	local function module(name, source, parent)
		local m = Instance.new("ModuleScript")
		m.Name = name
		m.Parent = parent or rs
		getmetatable(m).ext = { source = source }
		return m
	end
	Globals.moduleProvider = function(m)
		local e = getmetatable(m).ext
		return e and e.source, "src/selftest/modules/" .. m.Name .. ".luau"
	end
	local mShared = module("Shared", "return { made = os.clock() }")
	module("RecA", "return require(script.Parent.RecB)")
	module("RecB", "return require(script.Parent.RecA)")
	module("Two", "return 1, 2")
	module("Zero", "local x = 1")
	module("Broken", "local t = nil\nreturn t.x")
	local hq = runGame(
		server,
		"req",
		[[
	local rs = game.ReplicatedStorage
	local a = require(rs.Shared)
	local b = require(rs.Shared)
	local ok1, e1 = pcall(require, rs.RecA)
	local ok2, e2 = pcall(require, rs.Two)
	local ok3, e3 = pcall(require, rs.Zero)
	local ok4, e4 = pcall(require, rs.Broken)
	local ok5, e5 = pcall(require, 12345)
	local ok6, e6 = pcall(require, workspace)
	return a, b, e1, e2, e3, e4, e5, e6
]]
	)
	local qr = hq.results
	check("Cache je Kontext (gleiche Tabelle)", hq.done and qr[1] == qr[2])
	-- Roblox: der innere require wirft "required recursively" (im Report), der äußere Aufrufer sieht den Ladefehler
	check(
		"rekursiv",
		findError("Requested module was required recursively") ~= nil
			and string.find(qr[3], "Requested module experienced an error while loading", 1, true) ~= nil,
		qr[3]
	)
	check("zwei Rückgaben", string.find(qr[4], "Module code did not return exactly one value", 1, true) ~= nil, qr[4])
	check("keine Rückgabe", string.find(qr[5], "Module code did not return exactly one value", 1, true) ~= nil, qr[5])
	check(
		"Modulfehler",
		string.find(qr[6], "Requested module experienced an error while loading", 1, true) ~= nil
			and findError("attempt to index nil with 'x'") ~= nil
	)
	check("require(Zahl) -> Fehler/Harness-Lücke", string.find(qr[7], "not supported", 1, true) ~= nil)
	check(
		"require(ungültig)",
		string.find(qr[8], "Attempted to call require with invalid argument(s).", 1, true) ~= nil
	)
	local hc = runGame(client, "req_client", "return require(game.ReplicatedStorage.Shared)")
	check("Client hat eigene Modul-Instanz", hc.done and hc.results[1] ~= qr[1])

	-- =====================================================================
end
sec("Fehlerpositionen/Report")
do
	local before = #Report.errors
	local h1 = runGame(server, "err_member", "local p = Instance.new('Part')\np.Nope = 1")
	local em = findError('Nope is not a valid member of Part "Part"')
	check(
		"Roblox-API-Fehler mit Spiel-Position",
		em ~= nil and em.location == "src/selftest/err_member.luau:2" and em.category == "A" and em.ctx == "server",
		em and (em.location .. " " .. em.category)
	)
	check(
		"Position im Nachrichtentext",
		em ~= nil and string.find(em.message, "src/selftest/err_member.luau:2:", 1, true) == 1,
		em and em.message
	)
	runGame(server, "err_plain", "error('kaputt')")
	runGame(server, "err_plain", "error('kaputt')")
	local ep2 = findError("err_plain.luau:1: kaputt")
	check("Dedupe mit Zähler", ep2 ~= nil and ep2.count == 2 and ep2.location == "src/selftest/err_plain.luau:1")
	Report.setTrigger("Klick: Hud.Test")
	runGame(server, "err_trigger", "local x = nil; return x.y")
	Report.setTrigger(nil)
	local et = findError("attempt to index nil with 'y'")
	check("Auslöser vermerkt", et ~= nil and et.triggers[1] == "Klick: Hud.Test")
	Sched.spawnHandler(function()
		local t = nil
		return t.harness
	end, server, "harness-test")
	local eb = findError("attempt to index nil with 'harness'")
	check("Harness-Absturz = Kategorie B", eb ~= nil and eb.category == "B")
	local eu =
		runGame(server, "err_unmocked", "local p = Instance.new('Part')\nlocal r = p:UnionAsync({})\nreturn r.Name")
	local eue = findError("attempt to index nil with 'Name'")
	check(
		"Folgefehler nach unmocked-Stub mit Hinweis",
		eue ~= nil and eue.hint ~= nil and string.find(eue.hint, "UnionAsync", 1, true) ~= nil
	)
	local ew = runGame(server, "warn", "warn('Achtung', 42)")
	check("warn() -> Report", findWarning("Achtung 42") ~= nil and Report.findOutput("Achtung 42") ~= nil)
	runGame(server, "print", "print('Server gestartet', Vector3.new(1,2,3))")
	check("print -> Ausgabe", Report.findOutput("Server gestartet 1, 2, 3", "server") ~= nil)
	check(
		"Kompilierfehler erfasst",
		(function()
			Globals.compile("local = 5", "src/selftest/syntax.luau")
			for _, e in Report.errors do
				if e.kind == "compile" and string.find(e.message, "src/selftest/syntax.luau", 1, true) then
					return true
				end
			end
			return false
		end)()
	)

	-- =====================================================================
end
sec("BasePart/Model")
do
	local bp = Instance.new("Part")
	bp.Parent = workspace
	bp.CFrame = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.rad(90), 0)
	check("Position aus CFrame", bp.Position == Vector3.new(1, 2, 3))
	check("Orientation aus CFrame", nearV3(bp.Orientation, 0, 90, 0, 1e-3))
	bp.Orientation = Vector3.new(10, 20, 30)
	local ox2, oy2, oz2 = bp.CFrame:ToOrientation()
	check(
		"Orientation setzen",
		near(math.deg(ox2), 10, 1e-3)
			and near(math.deg(oy2), 20, 1e-3)
			and near(math.deg(oz2), 30, 1e-3)
			and bp.Position == Vector3.new(1, 2, 3)
	)
	bp.Position = Vector3.new(5, 5, 5)
	check("Position setzen behält Rotation", nearV3(bp.Orientation, 10, 20, 30, 1e-3))
	bp.Rotation = Vector3.new(30, 0, 0)
	local rxx = bp.CFrame:ToEulerAnglesXYZ()
	check("Rotation setzen", near(math.deg(rxx), 30, 1e-3))
	local posLog = 0
	bp:GetPropertyChangedSignal("Position"):Connect(function()
		posLog += 1
	end)
	bp.CFrame = CFrame.new(9, 9, 9)
	Sched.flush()
	check("CFrame setzen feuert Position-Signal", posLog == 1)
	local mp = Instance.new("Part")
	check("GetMass", near(mp:GetMass(), 0.7 * 4 * 1.2 * 2, 1e-4) and mp.Mass == mp:GetMass())
	bp.Anchored = true
	expectError("SetNetworkOwner verankert", function()
		bp:SetNetworkOwner(nil)
	end, "Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.")
	expectError("SetNetworkOwner außerhalb Workspace", function()
		Instance.new("Part"):SetNetworkOwner(nil)
	end, "descendent of Workspace")
	local free = Instance.new("Part")
	free.Parent = workspace
	noError("SetNetworkOwner unverankert", function()
		free:SetNetworkOwner(nil)
	end)
	local welded = Instance.new("Part")
	welded.Parent = workspace
	local wc0 = Instance.new("WeldConstraint")
	wc0.Part0, wc0.Part1 = free, welded
	wc0.Parent = free
	welded.Anchored = true
	expectError("SetNetworkOwner an verankertes geschweißt", function()
		free:SetNetworkOwner(nil)
	end, "welded to Anchored parts")
	-- WeldConstraint: CFrame bewegt Baugruppe, Position nur das Teil
	local wa, wb = Instance.new("Part"), Instance.new("Part")
	wa.Parent, wb.Parent = workspace, workspace
	wa.CFrame = CFrame.new(0, 0, 0)
	wb.CFrame = CFrame.new(5, 0, 0)
	local wc = Instance.new("WeldConstraint")
	wc.Part0, wc.Part1 = wa, wb
	wc.Parent = wa
	wa.CFrame = CFrame.new(0, 10, 0)
	check("WeldConstraint: CFrame bewegt mit", nearV3(wb.Position, 5, 10, 0))
	wa.Position = Vector3.new(0, 20, 0)
	check("WeldConstraint: Position bewegt nur ein Teil", nearV3(wb.Position, 5, 10, 0))
	wa.CFrame = CFrame.new(0, 30, 0)
	check("WeldConstraint: neuer Versatz nach Position", nearV3(wb.Position, 5, 20, 0))
	wa.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	check("WeldConstraint: Rotation dreht mit", nearV3(wb.Position, 0, -10, -5, 1e-3))
	-- Weld (JointInstance): Part1 = Part0 * C0 * C1^-1
	local j0, j1 = Instance.new("Part"), Instance.new("Part")
	j0.Anchored = true
	j0.Parent, j1.Parent = workspace, workspace
	j0.CFrame = CFrame.new(0, 0, 0)
	j1.CFrame = CFrame.new(100, 0, 0)
	local jw = Instance.new("Weld")
	jw.C0 = CFrame.new(0, 5, 0)
	jw.Part0, jw.Part1 = j0, j1
	jw.Parent = j0
	check("Weld rastet Part1 ein", nearV3(j1.Position, 0, 5, 0))
	jw.C0 = CFrame.new(0, 0, 3)
	check("Weld folgt C0-Änderung", nearV3(j1.Position, 0, 0, 3))
	check("Verankertes Teil bleibt", j0.Position == Vector3.zero)
	-- Gelenke werden erst beim Eintritt eines ganzen Modells in Workspace aktiv
	local m3 = Instance.new("Model")
	local r3, c3, d3 = Instance.new("Part"), Instance.new("Part"), Instance.new("Part")
	r3.Anchored = true
	r3.CFrame, c3.CFrame, d3.CFrame = CFrame.new(0, 0, 0), CFrame.new(3, 0, 0), CFrame.new(50, 50, 50)
	r3.Parent, c3.Parent, d3.Parent = m3, m3, m3
	local wc3 = Instance.new("WeldConstraint")
	wc3.Part0, wc3.Part1 = r3, c3
	wc3.Parent = r3
	local w3 = Instance.new("Weld")
	w3.C0 = CFrame.new(0, 2, 0)
	w3.Part0, w3.Part1 = r3, d3
	w3.Parent = r3
	r3.CFrame = CFrame.new(1, 0, 0)
	check("außerhalb Workspace keine Gelenkwirkung", nearV3(c3.Position, 3, 0, 0) and nearV3(d3.Position, 50, 50, 50))
	m3.Parent = workspace
	check("Weld rastet beim Eintritt ein", nearV3(d3.Position, 1, 2, 0))
	check("WeldConstraint-Versatz beim Eintritt", nearV3(c3.Position, 3, 0, 0))
	r3.CFrame = CFrame.new(10, 0, 0)
	check("Baugruppe folgt nach Eintritt", nearV3(c3.Position, 12, 0, 0) and nearV3(d3.Position, 10, 2, 0))
	local m3c = m3:Clone()
	m3c.Parent = workspace
	local r3c = m3c:FindFirstChild("Part")
	r3c.CFrame = CFrame.new(-20, 0, 0)
	check(
		"geklonte Gelenke wirken",
		nearV3(m3c:GetChildren()[2].Position, -18, 0, 0) and nearV3(m3c:GetChildren()[3].Position, -20, 2, 0)
	)
	check("Original unberührt", nearV3(c3.Position, 12, 0, 0))
	-- Model
	local m2 = Instance.new("Model")
	m2.Parent = workspace
	local ma, mb = Instance.new("Part"), Instance.new("Part")
	ma.Size, mb.Size = Vector3.one, Vector3.one
	ma.CFrame, mb.CFrame = CFrame.new(0, 0, 0), CFrame.new(4, 0, 0)
	ma.Parent, mb.Parent = m2, m2
	local bcf, bsize = m2:GetBoundingBox()
	check("GetBoundingBox", nearV3(bsize, 5, 1, 1) and nearV3(bcf.Position, 2, 0, 0))
	check("GetPivot ohne PrimaryPart = Box-Mitte", nearV3(m2:GetPivot().Position, 2, 0, 0))
	expectError("SetPrimaryPartCFrame ohne PrimaryPart", function()
		m2:SetPrimaryPartCFrame(CFrame.new())
	end, "Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set")
	m2.PrimaryPart = ma
	m2:PivotTo(CFrame.new(100, 0, 0))
	check("PivotTo mit PrimaryPart", nearV3(ma.Position, 100, 0, 0) and nearV3(mb.Position, 104, 0, 0))
	m2:TranslateBy(Vector3.new(0, 1, 0))
	check("TranslateBy", nearV3(ma.Position, 100, 1, 0))
	m2:MoveTo(Vector3.new(0, 0, 0))
	check("MoveTo", nearV3(ma.Position, 0, 0, 0) and nearV3(mb.Position, 4, 0, 0))
	m2:ScaleTo(2)
	check("ScaleTo", m2:GetScale() == 2 and nearV3(mb.Position, 8, 0, 0) and mb.Size == Vector3.new(2, 2, 2))
	ma.Parent = nil
	check("PrimaryPart bleibt bis zum nächsten Schritt", m2.PrimaryPart == ma)
	Sched.step()
	check("PrimaryPart im nächsten Schritt nil (kein Nachfahre mehr)", m2.PrimaryPart == nil)
	local m4 = Instance.new("Model")
	local early = Instance.new("Part")
	m4.PrimaryPart = early
	early.Parent = m4
	Sched.step()
	check("PrimaryPart vor dem Parenten setzen erlaubt", m4.PrimaryPart == early)

	-- =====================================================================
end
sec("GUI-Geometrie")
do
	local sg = Instance.new("ScreenGui")
	local fr = Instance.new("Frame")
	fr.Size = UDim2.new(0.5, 0, 0.5, 0)
	fr.Position = UDim2.new(0.5, 0, 0.5, 0)
	fr.AnchorPoint = Vector2.new(0.5, 0.5)
	fr.Parent = sg
	check(
		"ScreenGui-Fläche (mit Inset)",
		sg.AbsoluteSize == Vector2.new(1280, 662) and sg.AbsolutePosition == Vector2.new(0, 58)
	)
	check("Frame AbsoluteSize", fr.AbsoluteSize == Vector2.new(640, 331))
	check(
		"Frame AbsolutePosition (AnchorPoint)",
		fr.AbsolutePosition == Vector2.new(320, 223.5),
		tostring(fr.AbsolutePosition)
	)
	sg.IgnoreGuiInset = true
	check("IgnoreGuiInset", sg.AbsoluteSize == Vector2.new(1280, 720) and fr.AbsoluteSize == Vector2.new(640, 360))
	local list = Instance.new("Frame")
	list.Size = UDim2.fromOffset(200, 300)
	list.Parent = sg
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 10)
	lay.Parent = list
	local e1, e2 = Instance.new("Frame"), Instance.new("Frame")
	e1.Size, e2.Size = UDim2.fromOffset(100, 50), UDim2.fromOffset(100, 50)
	e1.LayoutOrder, e2.LayoutOrder = 2, 1
	lay.SortOrder = EnumG.SortOrder.LayoutOrder
	e1.Parent, e2.Parent = list, list
	check(
		"UIListLayout positioniert nach LayoutOrder",
		e2.AbsolutePosition.Y == list.AbsolutePosition.Y and e1.AbsolutePosition.Y == list.AbsolutePosition.Y + 60
	)
	check("AbsoluteContentSize", lay.AbsoluteContentSize == Vector2.new(100, 110))
	local tl = Instance.new("TextLabel")
	tl.Text = "Hallo Welt"
	tl.TextSize = 20
	tl.Size = UDim2.fromOffset(300, 40)
	tl.Parent = sg
	check("TextBounds grob", tl.TextBounds.X > 0 and tl.TextBounds.Y == 20 and tl.TextFits)
	check("isRendered: nicht unter PlayerGui -> false", not Inst.Gui.isRendered(tl))
	local pg = Inst.create("PlayerGui", { Name = "PlayerGui" })
	sg.Parent = pg
	check("isRendered: unter PlayerGui -> true", Inst.Gui.isRendered(tl))
	tl.Visible = false
	check("isRendered: unsichtbar -> false", not Inst.Gui.isRendered(tl))
	tl.Visible = true
	sg.Enabled = false
	check("isRendered: ScreenGui deaktiviert -> false", not Inst.Gui.isRendered(tl))
	sg.Enabled = true
	local absN = 0
	fr:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		absN += 1
	end)
	Sched.step()
	fr.Size = UDim2.new(1, 0, 1, 0)
	Sched.step()
	check("AbsoluteSize-Signal nach Größenänderung", absN == 1 and fr.AbsoluteSize == Vector2.new(1280, 720))

	-- =====================================================================
end
sec("Report")
do
	check("keine unerwarteten Harness-Fehler", #Report.harness == 0, Report.harness[1] and Report.harness[1].message)
	local sum = Report.summary()
	check(
		"Zusammenfassung",
		sum.errorsUnique >= 1 and sum.infiniteYields >= 1 and sum.unmockedApis >= 1 and sum.deprecatedApis >= 1
	)
	check(
		"JSON des Reports",
		(function()
			local ok, txt = pcall(DT.json.encodeStrict, Report.toTable())
			return ok and #txt > 10
		end)()
	)

	-- =====================================================================
end

print(
	string.format(
		"Selbsttest: %d Prüfungen bestanden, %d fehlgeschlagen (Simulationszeit %.2f s)",
		passed,
		#failed,
		Sched.now
	)
)
if #failed > 0 then
	for _, f in failed do
		print("  FEHLER: " .. f)
	end
	error("SELFTEST FEHLGESCHLAGEN (" .. #failed .. ")", 0)
end
print("SELFTEST OK (" .. passed .. " Prüfungen)")
