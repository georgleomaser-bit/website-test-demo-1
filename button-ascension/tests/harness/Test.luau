--[[
	Test.luau

	A tiny test framework.

	Spec files (tests/specs/*.spec.luau) either return a table of tests:
	    return {
	        ["adds numbers"] = function(ctx) ctx.expect(1 + 1).toBe(2) end,
	    }
	or use describe/it:
	    local Test = require("../harness/Test")
	    Test.describe("Economy", function()
	        Test.it("rejects negative prices", function(ctx) ... end)
	    end)
	    return Test.collect()

	ctx:
	    ctx.harness          a fresh Harness (created lazily, one per test)
	    ctx.expect(value)    matchers (see below)
	    ctx.allowScriptErrors()  do not fail the test because of script errors
	    ctx.log(...)         print only when the runner is verbose

	Matchers: toBe, toEqual (deep), toBeTruthy, toBeFalsy, toBeNil,
	toBeGreaterThan(OrEqual), toBeLessThan(OrEqual), toBeCloseTo(value, tolerance),
	toContain (string or array), toMatch (Lua pattern), toHaveLength, toThrow(pattern?),
	toBeA(typeName). Prefix with .never to negate: expect(x).never.toBe(y)
]]

local Types = require("./Types")

local Test = {}

local function describeValue(v): string
	local t = Types.typeof(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "table" then
		local parts = {}
		local count = 0
		for k, val in pairs(v) do
			count += 1
			if count > 8 then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, tostring(k) .. "=" .. (if type(val) == "table" then "{...}" else tostring(val)))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v) .. " (" .. t .. ")"
end
Test.describeValue = describeValue

local function deepEqual(a, b, path: string): (boolean, string?)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		if type(a) == "number" and type(b) == "number" and a ~= a and b ~= b then
			return true
		end
		return false, string.format("at %s: %s ~= %s", path, describeValue(a), describeValue(b))
	end
	for k, v in pairs(a) do
		local ok, why = deepEqual(v, b[k], path .. "." .. tostring(k))
		if not ok then
			return false, why
		end
	end
	for k, v in pairs(b) do
		if a[k] == nil and v ~= nil then
			return false, string.format("at %s.%s: missing on actual side", path, tostring(k))
		end
	end
	return true
end
Test.deepEqual = deepEqual

local function makeMatchers(actual, negate: boolean)
	local m = {}
	local function check(pass: boolean, message: string)
		if negate then
			pass = not pass
			message = "NOT " .. message
		end
		if not pass then
			error("expectation failed: " .. message, 3)
		end
	end
	function m.toBe(expected)
		check(actual == expected, string.format("expected %s to be %s", describeValue(actual), describeValue(expected)))
	end
	function m.toEqual(expected)
		local ok, why = deepEqual(actual, expected, "value")
		check(ok, "expected deep equality: " .. tostring(why or "values are equal"))
	end
	function m.toBeTruthy()
		check(actual ~= nil and actual ~= false, string.format("expected %s to be truthy", describeValue(actual)))
	end
	function m.toBeFalsy()
		check(actual == nil or actual == false, string.format("expected %s to be falsy", describeValue(actual)))
	end
	function m.toBeNil()
		check(actual == nil, string.format("expected %s to be nil", describeValue(actual)))
	end
	function m.toBeGreaterThan(n)
		check(type(actual) == "number" and actual > n, string.format("expected %s > %s", describeValue(actual), tostring(n)))
	end
	function m.toBeGreaterThanOrEqual(n)
		check(type(actual) == "number" and actual >= n, string.format("expected %s >= %s", describeValue(actual), tostring(n)))
	end
	function m.toBeLessThan(n)
		check(type(actual) == "number" and actual < n, string.format("expected %s < %s", describeValue(actual), tostring(n)))
	end
	function m.toBeLessThanOrEqual(n)
		check(type(actual) == "number" and actual <= n, string.format("expected %s <= %s", describeValue(actual), tostring(n)))
	end
	function m.toBeCloseTo(n, tolerance)
		local tol = tolerance or 1e-6
		check(type(actual) == "number" and math.abs(actual - n) <= tol, string.format("expected %s to be within %s of %s", describeValue(actual), tostring(tol), tostring(n)))
	end
	function m.toContain(item)
		local found = false
		if type(actual) == "string" then
			found = string.find(actual, tostring(item), 1, true) ~= nil
		elseif type(actual) == "table" then
			for _, v in pairs(actual) do
				if v == item then
					found = true
					break
				end
			end
		end
		check(found, string.format("expected %s to contain %s", describeValue(actual), describeValue(item)))
	end
	function m.toMatch(pattern)
		check(type(actual) == "string" and string.match(actual, pattern) ~= nil, string.format("expected %s to match pattern %q", describeValue(actual), pattern))
	end
	function m.toHaveLength(n)
		local len = if type(actual) == "string" or type(actual) == "table" then #actual else -1
		check(len == n, string.format("expected length %d, got %d", n, len))
	end
	function m.toBeA(typeName)
		check(Types.typeof(actual) == typeName, string.format("expected %s to be a %s", describeValue(actual), typeName))
	end
	function m.toThrow(pattern)
		if type(actual) ~= "function" then
			error("toThrow expects a function", 2)
		end
		local ok, err = pcall(actual)
		local message = tostring(err)
		local pass = not ok and (pattern == nil or string.find(message, pattern, 1, true) ~= nil or string.match(message, pattern) ~= nil)
		check(pass, if ok then "expected function to throw" else string.format("expected error matching %q, got %q", tostring(pattern), message))
	end
	return m
end

function Test.expect(actual)
	local matchers = makeMatchers(actual, false)
	matchers.never = makeMatchers(actual, true)
	return matchers
end

-- describe / it ------------------------------------------------------------------------------

local collected = {}
local prefix = {}

function Test.describe(name: string, fn: () -> ())
	table.insert(prefix, name)
	fn()
	table.remove(prefix)
end

function Test.it(name: string, fn)
	local full = table.concat(prefix, " > ")
	full = if full == "" then name else full .. " > " .. name
	table.insert(collected, { name = full, fn = fn })
end

-- Returns the tests registered since the last collect() as an ordered list.
function Test.collect()
	local out = collected
	collected = {}
	return out
end

return Test
