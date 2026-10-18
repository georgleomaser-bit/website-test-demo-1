# Tests — headless mock-Roblox harness

The game scripts are executed **in-process with virtual time** using
[Lune](https://github.com/lune-org/lune), a standalone Luau runtime. No Roblox
Studio is needed: the harness rebuilds the Rojo project as mock Instances,
runs the real `Script`s / `LocalScript`s / `ModuleScript`s, simulates several
players, replicates server → client, and lets tests fire remotes directly the
way an exploiter would.

## Install Lune

Tested with **Lune 0.10.4**.

1. Download the archive for your platform from
   <https://github.com/lune-org/lune/releases/tag/v0.10.4>
   (e.g. `lune-0.10.4-linux-x86_64.zip`, `lune-0.10.4-macos-aarch64.zip`,
   `lune-0.10.4-windows-x86_64.zip`).
2. Unzip it and put the `lune` binary on your `PATH`
   (or install with Rokit/Aftman: `rokit add lune-org/lune@0.10.4`).
3. Check: `lune --version` → `lune 0.10.4`.

## Run

From the `button-ascension/` folder:

```sh
lune run tests/run.luau                # all specs
lune run tests/run.luau -- economy     # only specs/tests whose name contains "economy"
lune run tests/run.luau -- --verbose   # also echo print/warn from game scripts
```

The runner exits with code 1 if any test fails, so it can be used in CI.
It also works from the repository root (it detects the `button-ascension/` folder).

## Writing specs

Specs live in `tests/specs/*.spec.luau`:

```luau
local Test = require("../harness/Test")
local describe, it = Test.describe, Test.it

describe("Clicking", function()
	it("rejects clicks above the rate limit", function(ctx)
		local h = ctx.harness                     -- fresh harness per test
		local server = h:createServer()          -- loads default.project.json, runs Scripts
		local player, client = h:addPlayer(server, { userId = 1, name = "Alice" })
		h:advance(3)                              -- 3 virtual seconds
		for _ = 1, 100 do
			h:exploitFire(server, player, "Click") -- straight to the server remote
		end
		h:advance(1)
		local result = h:exploitInvoke(server, player, "Action", "SomeAction", { forged = true })
		ctx.expect(result.ok).toBe(false)
	end)
end)

return Test.collect()
```

Tests may yield (`h.scheduler:wait(5)`, `InvokeServer`, `exploitInvoke` …): the
runner keeps stepping the virtual clock until the test continues. Any
uncaught error in a game script fails the test unless it calls
`ctx.allowScriptErrors()`.

Useful harness calls (`tests/harness/Harness.luau`):

| Call | Purpose |
|---|---|
| `h:createServer({ isStudio, jobId, creatorId, loadProject, start })` | server world (project loaded, Scripts started) |
| `h:createWorld({ role, loadProject })` | bare world, e.g. to `world:requirePath("ReplicatedStorage.Shared.Format")` |
| `h:addPlayer(server, { userId, name, input = { touch, gamepad }, groupRanks })` | joins a player; returns server `Player` + client world |
| `h:removePlayer(player)` / `h:shutdown(server)` | PlayerRemoving / BindToClose (30 s limit) |
| `h:advance(seconds, step?)`, `h:run(fn)` | move virtual time / run yielding code from outside a test thread |
| `h:exploitFire(server, player, name, ...)`, `h:exploitInvoke(...)` | call server remotes directly with arbitrary arguments |
| `h:click(button)`, `h:typeInto(textBox, text)`, `h:triggerAction(client, name)`, `h:pressKey(client, keyCode)`, `h:chatCommand(client, "/admin help")` | drive client UI and input |
| `h:findByText(root, "Buy")`, `h:findDescendant(root, name, class)` | locate UI |
| `h.backend:failNext("UpdateAsync", n, msg)`, `:setFailureRate(p)`, `:setUnavailable(msg)`, `:peek(store, key)`, `:poke(store, key, value)` | DataStore failure injection and inspection |
| `h.backend:failPublishNext(n)`, `h.backend:failFilterNext(n)` | MessagingService / TextService failures |
| `server.kicks`, `world.logs`, `h:errors()` | what happened |

## How the harness works

| File | Role |
|---|---|
| `harness/Scheduler.luau` | virtual clock + full `task` library replacement (`spawn/defer/delay/wait/cancel`), legacy `wait/delay/spawn/tick`, virtual `os`, error capture with tracebacks |
| `harness/Instance.luau` | userdata-based mock Instances (`typeof` → `"Instance"`). Property reads/writes are validated against the Roblox reflection database shipped with Lune; unknown members, read-only writes and type mismatches raise Roblox-style errors; engine methods that are not modelled raise `Harness: Class:Method() is not implemented` |
| `harness/Reflection.luau` | property metadata/defaults (Lune reflection DB) + events/methods/callbacks (`generated/ApiMembers.luau`) |
| `harness/Classes.luau`, `harness/Services.luau` | behaviour of GUI geometry, parts, humanoids, sounds, tweens, remotes, bindables, players and ~40 services |
| `harness/Backend.luau` | shared in-memory DataStores (UpdateAsync cancel semantics, JSON checks), MessagingService bus, text filter |
| `harness/Loader.luau` | builds worlds from `default.project.json` with Rojo 7 file conventions |
| `harness/World.luau` | one VM: `game`, services, script environment, `require` (with cycle detection), script runner |
| `harness/Network.luau` | server → client replication, remote delivery and Roblox argument serialisation rules |
| `harness/Test.luau`, `run.luau` | tiny test framework and runner |

`generated/ApiMembers.luau` is generated from the luau-lsp Roblox definitions
(`globalTypes.None.d.luau`) with `lune run tests/harness/tools/generate_api.luau -- <path>`.

### Known limitations

* No physics, rendering or layout engine. `AbsoluteSize`/`AbsolutePosition`
  are computed from `Size`/`Position` and the parent chain (UIScale, layouts
  and AutomaticSize are ignored); `TextBounds` is an estimate.
* Signals run handlers immediately (Roblox "Immediate" signal behaviour).
* Client → server replication only happens through remotes (FilteringEnabled).
  Characters are simple models (HumanoidRootPart, Head, Humanoid); movement is not simulated.
* `StarterCharacterScripts`, animations, sounds' audio and HTTP requests are not simulated.
* Engine methods not listed in `Classes.luau`/`Services.luau` raise a clear
  "not implemented" error instead of guessing.
