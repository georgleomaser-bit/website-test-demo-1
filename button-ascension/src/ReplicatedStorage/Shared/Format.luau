--[[
	Format (ModuleScript)
	Location: ReplicatedStorage/Shared/Format

	Number and time formatting used by every UI and by server messages.
	  Format.short(1234567)    -> "1.23M"
	  Format.commas(1234567)   -> "1,234,567"
	  Format.time(3725)        -> "1h 02m"
	  Format.pct(0.25)         -> "25%"
	  Format.mult(2.5)         -> "×2.50"
]]

local Format = {}

local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
}

local function trimZeros(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

function Format.short(n: number?, keepDecimals: boolean?): string
	local value = n or 0
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "∞"
	end
	local negative = value < 0
	value = math.abs(value)
	local text
	if value < 1000 then
		if value < 10 and value ~= math.floor(value) then
			text = trimZeros(string.format("%.2f", math.floor(value * 100) / 100))
		elseif value < 100 and value ~= math.floor(value) and keepDecimals then
			text = trimZeros(string.format("%.1f", math.floor(value * 10) / 10))
		else
			text = tostring(math.floor(value))
		end
	else
		local tier = math.floor(math.log10(value) / 3)
		if tier >= #SUFFIXES then
			local exponent = math.floor(math.log10(value))
			local mantissa = value / 10 ^ exponent
			text = string.format("%.2fe%d", math.floor(mantissa * 100) / 100, exponent)
		else
			local scaled = value / 10 ^ (tier * 3)
			-- Floor instead of rounding so a value never displays higher than it is.
			if scaled < 10 then
				text = trimZeros(string.format("%.2f", math.floor(scaled * 100) / 100))
			elseif scaled < 100 then
				text = trimZeros(string.format("%.1f", math.floor(scaled * 10) / 10))
			else
				text = tostring(math.floor(scaled))
			end
			text ..= SUFFIXES[tier + 1]
		end
	end
	return if negative then "-" .. text else text
end

function Format.commas(n: number?): string
	local value = math.floor(n or 0)
	if math.abs(value) >= 1e15 then
		return Format.short(value)
	end
	local s = tostring(math.abs(value))
	local formatted = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	formatted = string.gsub(formatted, "^,", "")
	return if value < 0 then "-" .. formatted else formatted
end

function Format.time(seconds: number?): string
	local s = math.max(0, math.floor(seconds or 0))
	local d = math.floor(s / 86400)
	local h = math.floor((s % 86400) / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if d > 0 then
		return string.format("%dd %02dh", d, h)
	elseif h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, sec)
	end
	return string.format("%ds", sec)
end

function Format.clock(seconds: number?): string
	local s = math.max(0, math.floor(seconds or 0))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

function Format.pct(fraction: number?, decimals: number?): string
	local v = (fraction or 0) * 100
	local d = decimals or (if math.abs(v) < 10 and v ~= math.floor(v) then 1 else 0)
	if math.abs(v) >= 1000 then
		return Format.short(v) .. "%"
	end
	return trimZeros(string.format("%." .. d .. "f", v)) .. "%"
end

function Format.mult(m: number?): string
	local v = m or 1
	if v >= 1000 then
		return "×" .. Format.short(v)
	end
	return "×" .. trimZeros(string.format("%.2f", v))
end

-- Formats a value according to an upgrade Display hint (see Config/Upgrades).
function Format.display(kind: string, value: number): string
	if kind == "flat" then
		return "+" .. Format.short(value)
	elseif kind == "flatx" then
		return "+" .. trimZeros(string.format("%.2f", value)) .. "×"
	elseif kind == "pct" then
		return "+" .. Format.pct(value)
	elseif kind == "mult" then
		return Format.mult(value)
	elseif kind == "cps" then
		return trimZeros(string.format("%.1f", value)) .. "/s"
	elseif kind == "chance" then
		return "+" .. Format.pct(value, 1)
	elseif kind == "persec" then
		return "+" .. Format.short(value, true) .. "/s"
	elseif kind == "hours" then
		return "+" .. tostring(value) .. "h"
	elseif kind == "unlock" then
		return if value > 0 then "Active" else "Inactive"
	end
	return tostring(value)
end

return Format
