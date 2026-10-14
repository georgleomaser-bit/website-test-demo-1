--!nocheck
-- =====================================================================
--  Headless-Harness · DateTime / Random
--  DateTime.now() nutzt die SIMULIERTE Zeit (R.Sched.unixMillis()). „Lokalzeit“ hängt vom Kontext ab:
--  Server = UTC (Roblox-Server laufen in UTC), Client = Zeitzone des Prozesses (run.py setzt TZ, z. B. Europe/Berlin).
--  Formatierung: moment.js-artige Tokens laut Roblox-Doku (en-us + de-de; andere Locales fallen auf en-us zurück).
--  Random: deterministischer xoshiro128**-Generator (nicht Roblox' PCG32-Folge, aber gleiche Semantik/Fehler).
-- =====================================================================
return function(R, DT)
	local Util = R.Util
	local raise = Util.raise
	local checkNumber = Util.checkNumber
	local getmt = getmetatable
	local floor = math.floor
	local fmt = string.format

	-- ---------------------------------------------------------------------------------------------
	--  Kalender (proleptisch gregorianisch, Howard Hinnant)
	-- ---------------------------------------------------------------------------------------------
	local function daysFromCivil(y, m, d)
		if m <= 2 then
			y -= 1
		end
		local era = (y >= 0 and y or y - 399) // 400
		local yoe = y - era * 400
		local mp = (m + 9) % 12
		local doy = (153 * mp + 2) // 5 + d - 1
		local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
		return era * 146097 + doe - 719468
	end
	local function civilFromDays(z)
		z += 719468
		local era = (z >= 0 and z or z - 146096) // 146097
		local doe = z - era * 146097
		local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
		local y = yoe + era * 400
		local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
		local mp = (5 * doy + 2) // 153
		local d = doy - (153 * mp + 2) // 5 + 1
		local m = mp < 10 and mp + 3 or mp - 9
		if m <= 2 then
			y += 1
		end
		return y, m, d
	end
	DT.daysFromCivil = daysFromCivil
	DT.civilFromDays = civilFromDays

	local function isLeap(y)
		return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
	end
	local mdays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	local function daysInMonth(y, m)
		if m == 2 and isLeap(y) then
			return 29
		end
		return mdays[m]
	end

	--- UTC-Zerlegung von Millisekunden
	local function utcParts(ms)
		local secs = ms // 1000
		local milli = ms - secs * 1000
		local days = secs // 86400
		local rem = secs - days * 86400
		local y, m, d = civilFromDays(days)
		local yday = days - daysFromCivil(y, 1, 1) + 1
		local hour = math.floor(rem / 3600)
		local minute = math.floor((rem % 3600) / 60)
		return {
			Year = y,
			Month = m,
			Day = d,
			Hour = hour,
			Minute = minute,
			Second = rem % 60,
			Millisecond = milli,
			wday = (days + 4) % 7, -- 0 = Sonntag
			yday = yday,
		}
	end
	DT.utcParts = utcParts

	--- Lokale Zerlegung je Kontext (Server = UTC, Client = Prozess-Zeitzone)
	local function localParts(ms)
		local ctx = R.Sched and R.Sched.ctx()
		if ctx == nil or not ctx.isClient then
			return utcParts(ms)
		end
		local secs = ms // 1000
		local t = os.date("*t", secs)
		return {
			Year = t.year,
			Month = t.month,
			Day = t.day,
			Hour = t.hour,
			Minute = t.min,
			Second = t.sec,
			Millisecond = ms - secs * 1000,
			wday = t.wday - 1,
			yday = t.yday,
		}
	end
	DT.localParts = localParts

	--- Zeitgm: Komponenten (UTC) -> Sekunden
	function DT.timegm(y, m, d, h, mi, s)
		return daysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (mi or 0) * 60 + (s or 0)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Format-Tokens
	-- ---------------------------------------------------------------------------------------------
	local L10N = {
		en = {
			months = {
				"January",
				"February",
				"March",
				"April",
				"May",
				"June",
				"July",
				"August",
				"September",
				"October",
				"November",
				"December",
			},
			monthsShort = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" },
			days = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" },
			daysShort = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" },
			daysMin = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" },
			LT = "h:mm A",
			LTS = "h:mm:ss A",
			L = "MM/DD/YYYY",
			l = "M/D/YYYY",
			LL = "MMMM D, YYYY",
			ll = "MMM D, YYYY",
			LLL = "MMMM D, YYYY h:mm A",
			lll = "MMM D, YYYY h:mm A",
			LLLL = "dddd, MMMM D, YYYY h:mm A",
			llll = "ddd, MMM D, YYYY h:mm A",
			am = "AM",
			pm = "PM",
		},
		de = {
			months = {
				"Januar",
				"Februar",
				"März",
				"April",
				"Mai",
				"Juni",
				"Juli",
				"August",
				"September",
				"Oktober",
				"November",
				"Dezember",
			},
			monthsShort = {
				"Jan.",
				"Feb.",
				"März",
				"Apr.",
				"Mai",
				"Juni",
				"Juli",
				"Aug.",
				"Sep.",
				"Okt.",
				"Nov.",
				"Dez.",
			},
			days = { "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" },
			daysShort = { "So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa." },
			daysMin = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" },
			LT = "HH:mm",
			LTS = "HH:mm:ss",
			L = "DD.MM.YYYY",
			l = "D.M.YYYY",
			LL = "D. MMMM YYYY",
			ll = "D. MMM YYYY",
			LLL = "D. MMMM YYYY HH:mm",
			lll = "D. MMM YYYY HH:mm",
			LLLL = "dddd, D. MMMM YYYY HH:mm",
			llll = "ddd, D. MMM YYYY HH:mm",
			am = "AM",
			pm = "PM",
		},
	}
	local TOKENS = {
		"LLLL",
		"llll",
		"LLL",
		"lll",
		"LTS",
		"LT",
		"LL",
		"ll",
		"L",
		"l",
		"YYYY",
		"YY",
		"MMMM",
		"MMM",
		"MM",
		"M",
		"DDDD",
		"DDD",
		"DD",
		"D",
		"dddd",
		"ddd",
		"dd",
		"d",
		"HH",
		"H",
		"hh",
		"h",
		"mm",
		"m",
		"ss",
		"s",
		"SSS",
		"SS",
		"S",
		"A",
		"a",
	}
	local function pad(n, w)
		return fmt("%0" .. w .. "d", n)
	end
	local function formatParts(p, format, locale)
		local lang = string.lower(string.sub(locale or "en", 1, 2))
		local L = L10N[lang] or L10N.en
		local out = {}
		local i, n = 1, #format
		while i <= n do
			local ch = string.sub(format, i, i)
			if ch == "[" then
				local j = string.find(format, "]", i + 1, true)
				if j then
					out[#out + 1] = string.sub(format, i + 1, j - 1)
					i = j + 1
					continue
				end
			end
			local matched = nil
			for _, tok in TOKENS do
				if string.sub(format, i, i + #tok - 1) == tok then
					matched = tok
					break
				end
			end
			if not matched then
				out[#out + 1] = ch
				i += 1
				continue
			end
			i += #matched
			local t = matched
			local h12 = p.Hour % 12
			if h12 == 0 then
				h12 = 12
			end
			if L[t] and type(L[t]) == "string" and (t:sub(1, 1) == "L" or t:sub(1, 1) == "l") then
				out[#out + 1] = formatParts(p, L[t], locale)
			elseif t == "YYYY" then
				out[#out + 1] = tostring(p.Year)
			elseif t == "YY" then
				out[#out + 1] = pad(p.Year % 100, 2)
			elseif t == "MMMM" then
				out[#out + 1] = L.months[p.Month]
			elseif t == "MMM" then
				out[#out + 1] = L.monthsShort[p.Month]
			elseif t == "MM" then
				out[#out + 1] = pad(p.Month, 2)
			elseif t == "M" then
				out[#out + 1] = tostring(p.Month)
			elseif t == "DDDD" then
				out[#out + 1] = pad(p.yday, 3)
			elseif t == "DDD" then
				out[#out + 1] = tostring(p.yday)
			elseif t == "DD" then
				out[#out + 1] = pad(p.Day, 2)
			elseif t == "D" then
				out[#out + 1] = tostring(p.Day)
			elseif t == "dddd" then
				out[#out + 1] = L.days[p.wday + 1]
			elseif t == "ddd" then
				out[#out + 1] = L.daysShort[p.wday + 1]
			elseif t == "dd" then
				out[#out + 1] = L.daysMin[p.wday + 1]
			elseif t == "d" then
				out[#out + 1] = tostring(p.wday)
			elseif t == "HH" then
				out[#out + 1] = pad(p.Hour, 2)
			elseif t == "H" then
				out[#out + 1] = tostring(p.Hour)
			elseif t == "hh" then
				out[#out + 1] = pad(h12, 2)
			elseif t == "h" then
				out[#out + 1] = tostring(h12)
			elseif t == "mm" then
				out[#out + 1] = pad(p.Minute, 2)
			elseif t == "m" then
				out[#out + 1] = tostring(p.Minute)
			elseif t == "ss" then
				out[#out + 1] = pad(p.Second, 2)
			elseif t == "s" then
				out[#out + 1] = tostring(p.Second)
			elseif t == "SSS" then
				out[#out + 1] = pad(p.Millisecond, 3)
			elseif t == "SS" then
				out[#out + 1] = pad(p.Millisecond // 10, 2)
			elseif t == "S" then
				out[#out + 1] = tostring(p.Millisecond // 100)
			elseif t == "A" then
				out[#out + 1] = p.Hour < 12 and L.am or L.pm
			elseif t == "a" then
				out[#out + 1] = string.lower(p.Hour < 12 and L.am or L.pm)
			end
		end
		return table.concat(out)
	end
	DT.formatDateParts = formatParts

	-- ---------------------------------------------------------------------------------------------
	--  DateTime
	-- ---------------------------------------------------------------------------------------------
	local DTm = {}
	DT.DateTime = DTm
	local methods = {}
	local DTindex
	local function isDT(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == DTindex
	end
	DT.is.DateTime = isDT
	local function DTtostring(self)
		return tostring(getmt(self).ms)
	end
	local function DTeq(a, b)
		return isDT(a) and isDT(b) and getmt(a).ms == getmt(b).ms
	end
	local function DTlt(a, b)
		if isDT(a) and isDT(b) then
			return getmt(a).ms < getmt(b).ms
		end
		DT.ltError(a, b)
	end
	local function DTle(a, b)
		if isDT(a) and isDT(b) then
			return getmt(a).ms <= getmt(b).ms
		end
		DT.leError(a, b)
	end
	local function newDT(ms)
		local u, mt = DT.newHost(DTindex, "DateTime", DTtostring, DTeq)
		mt.ms = ms
		mt.__lt = DTlt
		mt.__le = DTle
		return u
	end
	DT.make.DateTime = newDT
	function DTindex(self, k)
		local ms = getmt(self).ms
		if k == "UnixTimestamp" then
			return ms // 1000
		elseif k == "UnixTimestampMillis" then
			return ms
		end
		local f = methods[k]
		if f then
			return f
		end
		DT.badMember("DateTime", k)
	end
	Util.registerHostIndex(DTindex)
	local function selfDT(self, m)
		if not isDT(self) then
			raise("Expected ':' not '.' calling member function " .. m)
		end
		return getmt(self).ms
	end
	local function partsTable(p)
		return {
			Year = p.Year,
			Month = p.Month,
			Day = p.Day,
			Hour = p.Hour,
			Minute = p.Minute,
			Second = p.Second,
			Millisecond = p.Millisecond,
		}
	end
	function methods.ToUniversalTime(self)
		return partsTable(utcParts(selfDT(self, "ToUniversalTime")))
	end
	function methods.ToLocalTime(self)
		return partsTable(localParts(selfDT(self, "ToLocalTime")))
	end
	function methods.ToIsoDate(self)
		local p = utcParts(selfDT(self, "ToIsoDate"))
		return fmt("%04d-%02d-%02dT%02d:%02d:%02dZ", p.Year, p.Month, p.Day, p.Hour, p.Minute, p.Second)
	end
	function methods.FormatUniversalTime(self, format, locale)
		local ms = selfDT(self, "FormatUniversalTime")
		format = Util.checkString(format, 1, "FormatUniversalTime")
		locale = Util.checkString(locale, 2, "FormatUniversalTime")
		return formatParts(utcParts(ms), format, locale)
	end
	function methods.FormatLocalTime(self, format, locale)
		local ms = selfDT(self, "FormatLocalTime")
		format = Util.checkString(format, 1, "FormatLocalTime")
		locale = Util.checkString(locale, 2, "FormatLocalTime")
		return formatParts(localParts(ms), format, locale)
	end

	function DTm.now()
		return newDT(R.Sched.unixMillis())
	end
	function DTm.fromUnixTimestamp(t)
		return newDT(floor(checkNumber(t, 1, "fromUnixTimestamp") * 1000))
	end
	function DTm.fromUnixTimestampMillis(t)
		return newDT(floor(checkNumber(t, 1, "fromUnixTimestampMillis")))
	end
	local function fromParts(fname, y, mo, d, h, mi, s, ms)
		y = y == nil and 1970 or floor(checkNumber(y, 1, fname))
		mo = mo == nil and 1 or floor(checkNumber(mo, 2, fname))
		d = d == nil and 1 or floor(checkNumber(d, 3, fname))
		h = h == nil and 0 or floor(checkNumber(h, 4, fname))
		mi = mi == nil and 0 or floor(checkNumber(mi, 5, fname))
		s = s == nil and 0 or floor(checkNumber(s, 6, fname))
		ms = ms == nil and 0 or floor(checkNumber(ms, 7, fname))
		if mo < 1 or mo > 12 or d < 1 or d > daysInMonth(y, mo) then
			raise("Invalid date (" .. y .. "-" .. mo .. "-" .. d .. ")")
		end
		return y, mo, d, h, mi, s, ms
	end
	function DTm.fromUniversalTime(...)
		local y, mo, d, h, mi, s, ms = fromParts("fromUniversalTime", ...)
		return newDT((daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s) * 1000 + ms)
	end
	function DTm.fromLocalTime(...)
		local y, mo, d, h, mi, s, ms = fromParts("fromLocalTime", ...)
		local ctx = R.Sched.ctx()
		if ctx and ctx.isClient then
			local secs = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
			return newDT(secs * 1000 + ms)
		end
		return newDT((daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s) * 1000 + ms)
	end
	function DTm.fromIsoDate(str)
		str = Util.checkString(str, 1, "fromIsoDate")
		local y, mo, d, rest = string.match(str, "^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
		if not y then
			return nil
		end
		y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
		if mo < 1 or mo > 12 or d < 1 or d > daysInMonth(y, mo) then
			return nil
		end
		local h, mi, s, frac, tz = 0, 0, 0, 0, 0
		if rest ~= "" then
			local hh, mm, tail = string.match(rest, "^[Tt ](%d%d):(%d%d)(.*)$")
			if not hh then
				return nil
			end
			h, mi = tonumber(hh), tonumber(mm)
			local ss, tail2 = string.match(tail, "^:(%d%d)(.*)$")
			if ss then
				s = tonumber(ss)
				tail = tail2
				local fr, tail3 = string.match(tail, "^[%.,](%d+)(.*)$")
				if fr then
					frac = floor(tonumber("0." .. fr) * 1000 + 0.5)
					tail = tail3
				end
			end
			if tail == "Z" or tail == "z" or tail == "" then
				tz = 0
			else
				local sign, th, tm = string.match(tail, "^([%+%-])(%d%d):?(%d%d)$")
				if not sign then
					return nil
				end
				tz = (tonumber(th) * 60 + tonumber(tm)) * (sign == "+" and 1 or -1)
			end
			if h > 23 or mi > 59 or s > 60 then
				return nil
			end
		end
		local secs = daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s - tz * 60
		return newDT(secs * 1000 + frac)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Random (xoshiro128**, 32-Bit-Arithmetik über bit32)
	-- ---------------------------------------------------------------------------------------------
	local RND = {}
	DT.Random = RND
	local rmethods = {}
	local RNDindex
	local band, bor, bxor, lshift, rshift, lrotate =
		bit32.band, bit32.bor, bit32.bxor, bit32.lshift, bit32.rshift, bit32.lrotate
	local function mul32(a, b)
		-- (a * b) mod 2^32 ohne Genauigkeitsverlust
		local ah, al = rshift(a, 16), band(a, 0xFFFF)
		local bh, bl = rshift(b, 16), band(b, 0xFFFF)
		local lo = al * bl
		local mid = band(ah * bl + al * bh, 0xFFFF)
		return band(lo + lshift(mid, 16), 0xFFFFFFFF)
	end
	local function nextU32(s)
		local result = mul32(lrotate(mul32(s[2], 5), 7), 9)
		local t = lshift(s[2], 9)
		s[3] = bxor(s[3], s[1])
		s[4] = bxor(s[4], s[2])
		s[2] = bxor(s[2], s[3])
		s[1] = bxor(s[1], s[4])
		s[3] = bxor(s[3], t)
		s[4] = lrotate(s[4], 11)
		return result
	end
	local function splitmix(x)
		-- 32-Bit-Mischfunktion zur Initialisierung
		x = band(x + 0x9E3779B9, 0xFFFFFFFF)
		local z = x
		z = mul32(bxor(z, rshift(z, 16)), 0x85EBCA6B)
		z = mul32(bxor(z, rshift(z, 13)), 0xC2B2AE35)
		z = bxor(z, rshift(z, 16))
		return x, z
	end
	local function seedState(seed)
		local lo = band(seed % 4294967296, 0xFFFFFFFF)
		local hi = band(floor(seed / 4294967296) % 4294967296, 0xFFFFFFFF)
		local st = {}
		local x = bxor(lo, mul32(hi, 0x27D4EB2F))
		for i = 1, 4 do
			local z
			x, z = splitmix(x)
			st[i] = z
		end
		if st[1] == 0 and st[2] == 0 and st[3] == 0 and st[4] == 0 then
			st[1] = 1
		end
		return st
	end
	local function nextFloat(s)
		local a = rshift(nextU32(s), 5) -- 27 Bit
		local b = rshift(nextU32(s), 6) -- 26 Bit
		return (a * 67108864 + b) / 9007199254740992
	end
	local function isRND(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == RNDindex
	end
	DT.is.Random = isRND
	local function RNDtostring()
		return "Random"
	end
	local function newRND(state)
		local u, mt = DT.newHost(RNDindex, "Random", RNDtostring, nil)
		mt.s = state
		return u
	end
	function RNDindex(self, k)
		local f = rmethods[k]
		if f then
			return f
		end
		DT.badMember("Random", k)
	end
	Util.registerHostIndex(RNDindex)
	local function selfR(self, m)
		if not isRND(self) then
			raise("Expected ':' not '.' calling member function " .. m)
		end
		return getmt(self).s
	end
	function rmethods.NextNumber(self, a, b)
		local s = selfR(self, "NextNumber")
		local x = nextFloat(s)
		if a == nil and b == nil then
			return x
		end
		a = checkNumber(a, 1, "NextNumber")
		b = checkNumber(b, 2, "NextNumber")
		return a + (b - a) * x
	end
	function rmethods.NextInteger(self, a, b)
		local s = selfR(self, "NextInteger")
		a = floor(checkNumber(a, 1, "NextInteger"))
		b = floor(checkNumber(b, 2, "NextInteger"))
		if b < a then
			raise("invalid argument #2 to 'NextInteger' (interval is empty)")
		end
		return a + floor(nextFloat(s) * (b - a + 1))
	end
	function rmethods.NextUnitVector(self)
		local s = selfR(self, "NextUnitVector")
		local z = 2 * nextFloat(s) - 1
		local th = 2 * math.pi * nextFloat(s)
		local r = math.sqrt(math.max(0, 1 - z * z))
		return DT.make.V3(r * math.cos(th), r * math.sin(th), z)
	end
	function rmethods.Shuffle(self, tb)
		local s = selfR(self, "Shuffle")
		if type(tb) ~= "table" then
			Util.badArg(1, "Shuffle", "table", tb)
		end
		if table.isfrozen(tb) then
			raise("attempt to modify a readonly table")
		end
		local n = rawlen(tb)
		for i = 1, n do
			if rawget(tb, i) == nil then
				raise("Random:Shuffle(): table must not have holes in its array part")
			end
		end
		for i = n, 2, -1 do
			local j = 1 + floor(nextFloat(s) * i)
			local a, b = rawget(tb, i), rawget(tb, j)
			rawset(tb, i, b)
			rawset(tb, j, a)
		end
	end
	function rmethods.Clone(self)
		local s = selfR(self, "Clone")
		return newRND({ s[1], s[2], s[3], s[4] })
	end
	local autoSeed = 0
	function RND.new(seed)
		if seed == nil then
			autoSeed += 1
			return newRND(seedState((R.config and R.config.seed or 1) * 7919 + autoSeed * 104729))
		end
		seed = checkNumber(seed, 1, "new")
		return newRND(seedState(floor(seed)))
	end
end
