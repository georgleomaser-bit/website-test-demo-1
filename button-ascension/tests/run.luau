--[[
	Test runner.

	Usage (from the button-ascension folder):
	    lune run tests/run.luau                 -- every spec
	    lune run tests/run.luau -- economy      -- specs/tests whose name contains "economy"
	    lune run tests/run.luau -- --verbose    -- echo script print/warn output

	Each test runs in its own coroutine with a fresh Harness (ctx.harness).
	When the test yields (task.wait, InvokeServer ...), the runner steps the
	virtual clock until it resumes. Uncaught script errors recorded during a
	test fail it unless the test calls ctx.allowScriptErrors().
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Harness = require("./harness/Harness")
local Loader = require("./harness/Loader")
local Test = require("./harness/Test")

local MAX_VIRTUAL_SECONDS = 4 * 3600
local MAX_REAL_SECONDS = 120

-- Arguments ------------------------------------------------------------------------------------

local filters = {}
local verbose = false
for _, arg in ipairs(process.args) do
	if arg == "--verbose" or arg == "-v" then
		verbose = true
	elseif arg ~= "--" then
		table.insert(filters, string.lower(arg))
	end
end

-- Project root: the folder containing src/ and tests/.
local root = "."
if not (fs.isDir("src") and fs.isDir("tests")) and fs.isDir("button-ascension/src") then
	root = "button-ascension"
end
Harness.setDefaultRoot(root)
-- Lune's fs API yields to Lune's scheduler, so read the whole project now (main thread).
Loader.preload(root)

local specDir = root .. "/tests/specs"
local specFiles = {}
for _, name in ipairs(fs.readDir(specDir)) do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specFiles, name)
	end
end
table.sort(specFiles)

local function matchesFilter(specName: string, testName: string): boolean
	if #filters == 0 then
		return true
	end
	local haystack = string.lower(specName .. " " .. testName)
	for _, f in ipairs(filters) do
		if string.find(haystack, f, 1, true) then
			return true
		end
	end
	return false
end

-- Running ---------------------------------------------------------------------------------------

local function runTest(fn)
	local ctx = {}
	local allowErrors = false
	ctx.expect = Test.expect
	ctx.root = root
	ctx.allowScriptErrors = function()
		allowErrors = true
	end
	ctx.log = function(...)
		if verbose then
			print("   ", ...)
		end
	end
	local harness = nil
	setmetatable(ctx, {
		__index = function(_, key)
			if key == "harness" then
				if not harness then
					harness = Harness.new({ root = root, verbose = verbose })
				end
				return harness
			end
			return nil
		end,
	})

	local outcome = nil
	local thread = coroutine.create(function()
		local ok, err = xpcall(fn, debug.traceback, ctx)
		outcome = { ok = ok, err = err }
	end)
	local startReal = os.clock()
	local ok, err = coroutine.resume(thread)
	if not ok then
		return false, tostring(err)
	end
	while outcome == nil do
		if coroutine.status(thread) == "dead" then
			return false, "test thread died unexpectedly"
		end
		if not harness then
			return false, "test yielded but never used ctx.harness (nothing can resume it)"
		end
		local scheduler = harness.scheduler
		if not scheduler:hasPendingWork() then
			return false, "deadlock: the test is waiting but no scheduled work remains"
		end
		if scheduler.now > MAX_VIRTUAL_SECONDS then
			return false, "virtual time limit exceeded"
		end
		if os.clock() - startReal > MAX_REAL_SECONDS then
			return false, "real time limit exceeded"
		end
		scheduler:step()
	end
	if not outcome.ok then
		return false, tostring(outcome.err)
	end
	if harness and not allowErrors and #harness:errors() > 0 then
		return false, "uncaught script errors:\n" .. harness:formatErrors()
	end
	return true, nil
end

local totalPassed, totalFailed = 0, 0
local failures = {}
local startAll = os.clock()

for _, file in ipairs(specFiles) do
	local specName = string.gsub(file, "%.spec%.luau$", "")
	local ok, spec = pcall(require, "./specs/" .. string.gsub(file, "%.luau$", ""))
	local tests = {}
	if not ok then
		totalFailed += 1
		table.insert(failures, { spec = specName, test = "(load)", message = tostring(spec) })
		print(string.format("✗ %s (failed to load)", specName))
		continue
	end
	if type(spec) == "table" and spec[1] and spec[1].fn then
		tests = spec
	elseif type(spec) == "table" then
		local names = {}
		for name in pairs(spec) do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in ipairs(names) do
			table.insert(tests, { name = name, fn = spec[name] })
		end
	end
	local passed, failed = 0, 0
	local specStart = os.clock()
	for _, t in ipairs(tests) do
		if matchesFilter(specName, t.name) then
			local testStart = os.clock()
			local passedTest, message = runTest(t.fn)
			if passedTest then
				passed += 1
				if verbose then
					print(string.format("  ✓ %s (%.2fs)", t.name, os.clock() - testStart))
				end
			else
				failed += 1
				table.insert(failures, { spec = specName, test = t.name, message = message })
				print(string.format("  ✗ %s", t.name))
			end
		end
	end
	if passed + failed > 0 then
		print(string.format("%s %s — %d passed, %d failed (%.2fs)", if failed == 0 then "✓" else "✗", specName, passed, failed, os.clock() - specStart))
	end
	totalPassed += passed
	totalFailed += failed
end

if #failures > 0 then
	print("\nFailures:")
	for _, f in ipairs(failures) do
		print(string.format("\n● %s > %s\n%s", f.spec, f.test, f.message))
	end
end

print(string.format("\n%d passed, %d failed in %.2fs", totalPassed, totalFailed, os.clock() - startAll))
process.exit(if totalFailed == 0 then 0 else 1)
