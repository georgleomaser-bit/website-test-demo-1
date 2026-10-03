-- Kleine Helfer, die Server UND Client benutzen.

local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K", 15000000 -> "15M"
function Util.FormatNumber(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = tostring(math.floor(n))
		return negative and ("-" .. s) or s
	end
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n = n / 1000
		index += 1
	end
	local text
	if n >= 100 then
		text = string.format("%d", math.floor(n))
	elseif n >= 10 then
		text = string.format("%.1f", math.floor(n * 10) / 10)
	else
		text = string.format("%.2f", math.floor(n * 100) / 100)
	end
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return (negative and "-" or "") .. text .. SUFFIXES[index]
end

function Util.FormatCash(n: number): string
	return "$" .. Util.FormatNumber(n)
end

-- 75 -> "1:15"
function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

function Util.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value :: any) do
		copy[k] = Util.DeepCopy(v)
	end
	return copy :: any
end

-- Ergänzt fehlende Felder aus "template" (für Spielstände nach Updates).
function Util.Reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in pairs(template) do
		if target[k] == nil then
			target[k] = Util.DeepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" then
			Util.Reconcile(target[k], v)
		end
	end
end

-- Gewichtete Zufallsauswahl: list = { {Weight = 5, ...}, ... }
function Util.WeightedPick(list: { any }, weightOf: ((any) -> number)?, rng: Random?)
	local total = 0
	for _, item in ipairs(list) do
		total += weightOf and weightOf(item) or item.Weight
	end
	local roll = (rng or Random.new()):NextNumber() * total
	for _, item in ipairs(list) do
		roll -= weightOf and weightOf(item) or item.Weight
		if roll <= 0 then
			return item
		end
	end
	return list[#list]
end

-- Einfache Spam-Bremse pro Spieler.
function Util.RateLimiter(maxCalls: number, perSeconds: number)
	local buckets: { [any]: { number } } = {}
	local limiter = {}
	function limiter.Check(key: any): boolean
		local now = os.clock()
		local bucket = buckets[key]
		if not bucket then
			bucket = {}
			buckets[key] = bucket
		end
		while bucket[1] and now - bucket[1] > perSeconds do
			table.remove(bucket, 1)
		end
		if #bucket >= maxCalls then
			return false
		end
		table.insert(bucket, now)
		return true
	end
	function limiter.Clear(key: any)
		buckets[key] = nil
	end
	return limiter
end

return Util
