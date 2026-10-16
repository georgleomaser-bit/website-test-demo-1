--[[
	Zahlen schön anzeigen: 1500 -> "1.5K", 2.3e12 -> "2.3T" …
]]

local Format = {}

local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc",
	"Vg", "UVg", "DVg", "TVg", "QaVg", "QiVg", "SxVg", "SpVg", "OcVg", "NoVg", "Tg",
}

local function trimZeros(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

-- 3 gültige Stellen, abgerundet (damit nie mehr angezeigt wird als man hat)
local function threeDigits(x: number): string
	if x >= 100 then
		return tostring(math.floor(x + 1e-9))
	elseif x >= 10 then
		return trimZeros(string.format("%.1f", math.floor(x * 10 + 1e-9) / 10))
	else
		return trimZeros(string.format("%.2f", math.floor(x * 100 + 1e-9) / 100))
	end
end

function Format.Number(n: number?): string
	local value = tonumber(n) or 0
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "∞"
	end
	local negative = value < 0
	value = math.abs(value)

	local out
	if value < 1000 then
		out = threeDigits(value)
	else
		local tier = math.floor(math.log10(value) / 3)
		local scaled = value / 10 ^ (tier * 3)
		if scaled >= 1000 then
			tier += 1
			scaled /= 1000
		elseif scaled < 1 then
			tier -= 1
			scaled *= 1000
		end
		if tier + 1 > #SUFFIXES then
			local exponent = math.floor(math.log10(value))
			out = string.format("%.2fe%d", value / 10 ^ exponent, exponent)
		else
			out = threeDigits(scaled) .. SUFFIXES[tier + 1]
		end
	end
	return (negative and "-" or "") .. out
end

function Format.Cash(n: number?): string
	return "$" .. Format.Number(n)
end

-- Ganze Zahlen mit Tausenderpunkt (für kleine Werte wie Level)
function Format.Int(n: number?): string
	local value = math.floor(tonumber(n) or 0)
	if math.abs(value) >= 1e15 then
		return Format.Number(value)
	end
	local s = tostring(math.abs(value))
	local result = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1.")))
	if string.sub(result, 1, 1) == "." then
		result = string.sub(result, 2)
	end
	return (value < 0 and "-" or "") .. result
end

function Format.Time(seconds: number?): string
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	if s < 60 then
		return s .. "s"
	elseif s < 3600 then
		return string.format("%dm %02ds", s // 60, s % 60)
	elseif s < 86400 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	else
		return string.format("%dT %dh", s // 86400, (s % 86400) // 3600)
	end
end

-- Kurze Zeit für Zykluszeiten: 0.6s, 12s, 1m 36s
function Format.Cycle(seconds: number): string
	if seconds < 10 then
		return trimZeros(string.format("%.2f", seconds)) .. "s"
	elseif seconds < 60 then
		return string.format("%.1fs", seconds)
	end
	return Format.Time(seconds)
end

function Format.Percent(fraction: number): string
	local p = fraction * 100
	if p >= 1000 then
		return Format.Number(p) .. " %"
	end
	return trimZeros(string.format("%.1f", p)) .. " %"
end

return Format
