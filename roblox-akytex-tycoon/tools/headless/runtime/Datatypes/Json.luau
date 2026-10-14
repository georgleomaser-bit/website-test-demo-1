--!nocheck
-- =====================================================================
--  Headless-Harness · JSON wie HttpService:JSONEncode/JSONDecode
--  Roblox-Eigenheiten (laut Doku/Verhalten):
--   - leere Tabelle -> "[]"; Tabelle mit Zahl-Schlüsseln -> Array (String-Schlüssel werden dann IGNORIERT)
--   - nil-Lücken im Array -> null; zyklische Tabellen -> Fehler "tables cannot be cyclic"
--   - inf/nan werden (ungültiges JSON) als inf/-inf/nan ausgegeben
--   - Funktionen/userdata (Vector3, Instanzen …) werden zu null (kein Fehler) -> DT.json.lossy meldet das
--   - Decode: ungültiges JSON -> Fehler "Can't parse JSON"; null -> nil
--  DT.json.encode(v) / DT.json.decode(s) – Fehler werden per Util.raise im Spiel-Code verortet.
--  Außerdem DT.json.encodeStrict(v) für Harness-Berichte (wirft nie, Strings für Userdata).
-- =====================================================================
return function(R, DT)
	local Util = R.Util
	local raise = Util.raise
	local fmt = string.format
	local J = {}
	DT.json = J

	local escapes = {
		['"'] = '\\"',
		["\\"] = "\\\\",
		["\b"] = "\\b",
		["\f"] = "\\f",
		["\n"] = "\\n",
		["\r"] = "\\r",
		["\t"] = "\\t",
	}
	local function encStr(s)
		return '"'
			.. string.gsub(s, '[%c"\\]', function(c)
				return escapes[c] or fmt("\\u%04x", string.byte(c))
			end)
			.. '"'
	end
	J.quote = encStr

	local function encNum(x)
		if x ~= x then
			return "nan"
		elseif x == math.huge then
			return "inf"
		elseif x == -math.huge then
			return "-inf"
		end
		if x == math.floor(x) and math.abs(x) < 1e15 then
			return fmt("%d", x)
		end
		return tostring(x)
	end
	J.number = encNum

	local function isArrayLike(t)
		local maxn, hasNum = 0, false
		for k in t do
			if type(k) == "number" then
				hasNum = true
				if k > maxn and k == math.floor(k) then
					maxn = k
				end
			end
		end
		return hasNum, maxn
	end

	local function encode(v, stack, out, lossy, strict)
		local t = type(v)
		if v == nil then
			out[#out + 1] = "null"
		elseif t == "boolean" then
			out[#out + 1] = v and "true" or "false"
		elseif t == "number" then
			out[#out + 1] = encNum(v)
		elseif t == "string" then
			out[#out + 1] = encStr(v)
		elseif t == "table" then
			if stack[v] then
				if strict then
					out[#out + 1] = '"<zyklisch>"'
					return
				end
				raise("tables cannot be cyclic")
			end
			stack[v] = true
			local hasNum, maxn = isArrayLike(v)
			if next(v) == nil then
				out[#out + 1] = "[]"
			elseif hasNum then
				out[#out + 1] = "["
				for i = 1, maxn do
					if i > 1 then
						out[#out + 1] = ","
					end
					encode(rawget(v, i), stack, out, lossy, strict)
				end
				out[#out + 1] = "]"
			else
				local keys = {}
				for k in v do
					keys[#keys + 1] = k
				end
				if strict then
					table.sort(keys, function(a, b)
						return tostring(a) < tostring(b)
					end)
				end
				out[#out + 1] = "{"
				local first = true
				for _, k in keys do
					if type(k) == "string" then
						if not first then
							out[#out + 1] = ","
						end
						first = false
						out[#out + 1] = encStr(k)
						out[#out + 1] = ":"
						encode(rawget(v, k), stack, out, lossy, strict)
					elseif strict then
						if not first then
							out[#out + 1] = ","
						end
						first = false
						out[#out + 1] = encStr(tostring(k))
						out[#out + 1] = ":"
						encode(rawget(v, k), stack, out, lossy, strict)
					else
						lossy[#lossy + 1] = "Schlüssel vom Typ " .. Util.typeof(k)
					end
				end
				out[#out + 1] = "}"
			end
			stack[v] = nil
		elseif strict then
			out[#out + 1] = encStr(tostring(v))
		else
			lossy[#lossy + 1] = Util.typeof(v)
			out[#out + 1] = "null"
		end
	end

	--- Roblox-JSONEncode. Liefert (string, lossy-Liste) – lossy nennt Werte, die zu null wurden.
	function J.encode(v)
		local out, lossy = {}, {}
		encode(v, {}, out, lossy, false)
		return table.concat(out), lossy
	end

	--- Für Berichte: nie Fehler, Schlüssel sortiert, Userdata als String
	function J.encodeStrict(v)
		local out = {}
		encode(v, {}, out, {}, true)
		return table.concat(out)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Decoder
	-- ---------------------------------------------------------------------------------------------
	local function decodeError()
		raise("Can't parse JSON")
	end

	function J.decode(s)
		if type(s) ~= "string" then
			Util.badArg(1, "JSONDecode", "string", s)
		end
		local pos = 1
		local len = #s
		local function ws()
			pos = string.find(s, "[^ \t\r\n]", pos) or len + 1
		end
		local value
		local function str()
			pos += 1
			local buf = {}
			while true do
				local c = string.sub(s, pos, pos)
				if c == "" then
					decodeError()
				elseif c == '"' then
					pos += 1
					break
				elseif c == "\\" then
					local e = string.sub(s, pos + 1, pos + 1)
					if e == "u" then
						local hex = string.sub(s, pos + 2, pos + 5)
						if not string.match(hex, "^%x%x%x%x$") then
							decodeError()
						end
						local cp = tonumber(hex, 16)
						pos += 6
						if cp >= 0xD800 and cp <= 0xDBFF and string.sub(s, pos, pos + 1) == "\\u" then
							local lo = tonumber(string.sub(s, pos + 2, pos + 5), 16)
							if lo and lo >= 0xDC00 and lo <= 0xDFFF then
								cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
								pos += 6
							end
						end
						buf[#buf + 1] = utf8.char(cp)
					else
						local map = {
							['"'] = '"',
							["\\"] = "\\",
							["/"] = "/",
							b = "\b",
							f = "\f",
							n = "\n",
							r = "\r",
							t = "\t",
						}
						local r = map[e]
						if not r then
							decodeError()
						end
						buf[#buf + 1] = r
						pos += 2
					end
				else
					local j = string.find(s, '["\\]', pos)
					if not j then
						decodeError()
					end
					buf[#buf + 1] = string.sub(s, pos, j - 1)
					pos = j
				end
			end
			return table.concat(buf)
		end
		function value()
			ws()
			local c = string.sub(s, pos, pos)
			if c == "{" then
				pos += 1
				local obj = {}
				ws()
				if string.sub(s, pos, pos) == "}" then
					pos += 1
					return obj
				end
				while true do
					ws()
					if string.sub(s, pos, pos) ~= '"' then
						decodeError()
					end
					local k = str()
					ws()
					if string.sub(s, pos, pos) ~= ":" then
						decodeError()
					end
					pos += 1
					obj[k] = value()
					ws()
					local d = string.sub(s, pos, pos)
					pos += 1
					if d == "}" then
						return obj
					elseif d ~= "," then
						decodeError()
					end
				end
			elseif c == "[" then
				pos += 1
				local arr = {}
				ws()
				if string.sub(s, pos, pos) == "]" then
					pos += 1
					return arr
				end
				local i = 0
				while true do
					i += 1
					arr[i] = value()
					ws()
					local d = string.sub(s, pos, pos)
					pos += 1
					if d == "]" then
						return arr
					elseif d ~= "," then
						decodeError()
					end
				end
			elseif c == '"' then
				return str()
			elseif string.sub(s, pos, pos + 3) == "true" then
				pos += 4
				return true
			elseif string.sub(s, pos, pos + 4) == "false" then
				pos += 5
				return false
			elseif string.sub(s, pos, pos + 3) == "null" then
				pos += 4
				return nil
			else
				local num = string.match(s, "^-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
				if not num or num == "" or num == "-" then
					decodeError()
				end
				local x = tonumber(num)
				if x == nil then
					decodeError()
				end
				pos += #num
				return x
			end
		end
		local v = value()
		ws()
		if pos <= len then
			decodeError()
		end
		return v
	end
end
