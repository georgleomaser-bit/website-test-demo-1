--!strict
-- Number and time formatting shared by server billboards and client UI.

local Format = {}

-- "1.50" -> "1.5", "2.00" -> "2", "100" stays "100"
local function trimZeros(s: string): string
	if not string.find(s, ".", 1, true) then
		return s
	end
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
}

-- 1234 -> "1.23K", 15300000 -> "15.3M"
function Format.number(n: number): string
	if n ~= n then
		return "0"
	end
	if n == math.huge then
		return "inf"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s
		if n == math.floor(n) then
			s = tostring(math.floor(n))
		else
			s = trimZeros(string.format("%.1f", n))
		end
		return (negative and "-" or "") .. s
	end
	local index = math.floor(math.log10(n) / 3)
	if index >= #SUFFIXES then
		return (negative and "-" or "") .. string.format("%.2e", n)
	end
	local scaled = n / (1000 ^ index)
	local s
	if scaled >= 100 then
		s = string.format("%.0f", math.floor(scaled))
	elseif scaled >= 10 then
		s = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		s = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	s = trimZeros(s)
	return (negative and "-" or "") .. s .. SUFFIXES[index + 1]
end

-- 2.5 -> "x2.5"
function Format.multiplier(n: number): string
	return "x" .. Format.number(math.floor(n * 100 + 0.5) / 100)
end

-- 3725 -> "1:02:05", 65 -> "1:05"
function Format.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- 0.0123 -> "1.23%"
function Format.percent(fraction: number): string
	local p = fraction * 100
	if p >= 10 then
		return string.format("%.1f%%", p)
	elseif p >= 0.01 then
		return trimZeros(string.format("%.2f", p)) .. "%"
	elseif p > 0 then
		return "1/" .. Format.number(math.floor(1 / fraction + 0.5))
	end
	return "0%"
end

return Format
