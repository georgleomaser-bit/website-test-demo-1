# REUSE.md: what the shooter takes from Meteor Heist

> **Kurzfassung (Deutsch):** Meteor Heist (MH) hat eine bewährte Grundlage: Service-Lader, Remotes, Spam-Bremse,
> sicherer Spielstand mit Session-Lock, Käufe mit Beleg-Liste, Admin nur für den Besitzer, Bann/Ansagen,
> UI-Baukasten im Roblox-Stil, Admin-Panel-Gerüst, Fliegen, Foto-Modus und die Anleitungs-/Kopiervorlagen-Idee.
> Diese Teile übernehmen wir fast 1:1 (mit den Fixes aus Abschnitt 14). Alles Spielspezifische (Eier, Basen,
> Laufbänder, Klauen, Handel, Nacht) übernehmen wir **nicht**. Neu bauen müssen wir: Waffen, Treffer-Prüfung,
> Matches/Arenen, Bots, Touch-Steuerung, Sprachen (DE/EN). MH ist nur Deutsch und hat keinen ContextActionService.
> In MH wird **nichts** verändert.

- Source (read-only, never edit): `MH = /home/user/website-test-demo-1/roblox-meteor-heist` (git clean, 34,642 lines Luau).
- Target: `RS = /home/user/website-test-demo-1/roblox-shooter`.
- Everything below was read from the MH source on 2026-10-11. Tool runs and edge-case tests were done on copies in the scratchpad.
- Companion docs: `docs/ASSETS.md` (built-in sounds/textures; dead MH sounds), `docs/ADMIN-WUENSCHE.md` (owner's admin wishes).

Legend:

| Verdict | Meaning |
|---|---|
| **COPY** | Copy nearly verbatim. Rename `MeteorHeist`/`MH_` prefixes, keep the German comments, apply the listed fixes. |
| **ADAPT** | Keep the skeleton/framework and its conventions. Rewrite the game-specific parts. |
| **PATTERN** | Do not copy the file. Re-implement the proven pattern in a new shooter file. |
| **DROP** | Not useful for a shooter. |

---

## 1. Reuse map (file by file)

### 1.1 Root / tooling

| MH file | Verdict | RS file | Adaptations |
|---|---|---|---|
| `default.project.json` | ADAPT | `default.project.json` | Keep the 3 mounts exactly (`src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService.Server`, `src/client` → `StarterPlayer.StarterPlayerScripts.Client`) so every `WaitForChild("Shared")`/`script.Parent:WaitForChild("Services"/"Modules")` path still works. Keep `Lighting.Technology = "ShadowMap"` and `Workspace.ReplicateInstanceDestroySetting = "Enabled"`. **Add `Players.BanningEnabled = true`** (NotScriptable but CanSave; verified: Rojo 7.7.1 builds it, otherwise `BanAsync` can be switched off). Optionally `Players.RespawnTime`. Decide `Workspace.StreamingEnabled` (MH: `false`; see 14.3 #9). |
| `rbx.yml` | COPY + extend | `rbx.yml` | MH's std lacks globals a shooter needs. Verified with selene 0.31.0: `OverlapParams`, `DateTime`, `Font`, `PhysicalProperties`, `BrickColor`, `Rect` (plus `Ray`, `Region3`, `Vector3int16`, `Axes`, `Faces`) give `undefined_variable` errors. Append each as `  Name: {any: true}`. `buffer`, `utf8`, `bit32`, `os`, `debug` already come from `base: luau`. |
| `selene.toml` | COPY | `selene.toml` | `std = "rbx"` (selene looks for `rbx.yml` in the cwd, so run it from the project root). |
| `stylua.toml` | COPY | `stylua.toml` | `column_width = 120`, `indent_type = "Tabs"`, `syntax = "Luau"`. |
| `.gitignore` | COPY | `.gitignore` | `sourcemap.json`. MH commits the built `.rbxlx` (the owner downloads it), so the shooter commits its `.rbxlx` too. |
| `MeteorHeist.rbxlx` | DROP | `<GameName>.rbxlx` | Rebuilt by `rojo build`. Never edited by hand. |

### 1.2 Shared (`ReplicatedStorage.Shared`)

| MH file | Verdict | RS file | Adaptations |
|---|---|---|---|
| `src/shared/Util.luau` (137 lines) | COPY + fix | `src/shared/Util.luau` | Keep `FormatNumber`, `FormatTime`, `DeepCopy`, `Reconcile`, `WeightedPick` (weight-0 entries are never picked, NaN/negative weights count as 0), `RateLimiter`. **Replace `FormatNumber` with the fixed version in 14.2.** Drop `FormatCash` (`"$"..`) or turn it into `FormatCoins`. Pure module, so it can be unit-tested with the `luau` CLI (Section 13). |
| `src/shared/Config.luau` (1,460 lines) | PATTERN | `src/shared/Config.luau` | Copy the **structure**: German banner, numbered sections ("1) ADMINS", "2) MONETARISIERUNG – IDs … 0 = noch nicht eingerichtet", "3) SPIEL-BALANCE", …, "6) TECHNIK … DataStoreName ändern = alle Spielstände sind weg!"), then auto-built lookup tables (`…ById`, `…ByKey`) with `assert` on duplicate IDs and `warn` on broken references, then shared calculation helpers used by server **and** client. Admin section: `Config.OwnerIsAdmin = true`, `Config.StudioIsAdmin = true`, **no `Config.AdminUserIds`** (owner-only rule). Keep `Config.GamePasses`/`Config.Products` entry shape (`Key`, `Id = 0`, `Name`, `Description`, `Icon`, `Type`, …), but names/descriptions need DE+EN (`Name = { De = …, En = … }` or a Lang key). Mark random products explicitly (`Random = true`). Config is replicated, so it must not hold secrets. |
| `src/shared/Aliens.luau` | DROP | n/a | Egg/alien content. |
| (new) | n/a | `src/shared/Lang.luau` | MH has no localization (German literals everywhere, no `LocaleId` use). The shooter needs `Lang` (DE/EN, pick by `player.LocaleId` prefix `"de"`, default English). Every MH string pattern (`Notify(player, "…")`, `{ Ok, Message }`) must go through it. |

### 1.3 Server (`ServerScriptService.Server`)

| MH file | Verdict | RS file | Adaptations |
|---|---|---|---|
| `src/server/Main.server.luau` (74) | COPY | `src/server/Main.server.luau` | Same loader (Section 2). Only the `order` list, the `[Meteor Heist]` log prefix and the banner change. |
| `Services/Remotes.luau` (35) | COPY + extend | `Services/Remotes.luau` | Same `make(className, name)` idempotent creator in `ReplicatedStorage.Remotes`. Keep `Notify`, `State`, `Effect`, `Request`, `Admin`. Drop `Trade`/`TradeEvent`. Add combat remotes (Section 3). |
| `Services/DataService.luau` (467) | COPY + fixes | `Services/DataService.luau` | Keep the whole lock/retry/migrate/BindToClose machine (Section 8). New `DEFAULT_DATA` + `DATA_VERSION = 1`, new `Migrate`/sanitize functions. **Apply fixes 14.3 #1–#4.** `Reset` keeps `Receipts` and one-time purchase flags. |
| `Services/MonetizationService.luau` (399) | ADAPT | `Services/MonetizationService.luau` | Keep verbatim: `HasPass`, `LoadPasses` (3 retries, `loading` guard, only after `player.Parent` check), `GrantPassSession` (admin test gift, not saved), `paidRandomRestricted` (cached per session, "in doubt = restricted"), receipt log handling, `PromptGamePassPurchaseFinished`, PlayerRemoving cleanup. Rewrite `grantProduct`/`grantStarterPack`/`OnPassChanged` for shooter products (coins, keys/cases, fixed skin bundles, cosmetic boosts). **Apply ProcessReceipt fixes 14.3 #5–#7** (Section 7). |
| `Services/AdminService.luau` (1,545) | ADAPT | `Services/AdminService.luau` | Keep: `isGameOwner`/`computeAdmin`/`IsAdmin` cache (minus `AdminUserIds`), `resolveTargets` ("me"/"all"/"others"/UserId/name/prefix), `num` clamp helper, `names`, `filterBroadcast`, `publishGlobal`/`handleGlobal`/`SubscribeAsync`, `showAnnouncement`, `setInvisible`, `updateTag` (overhead ADMIN/VIP, hidden in Studio), `tryCall`, `pingMs`, `Actions` dispatcher, and the actions `GetPlayers`, `GivePass`, `Announce`, `Kick`, `Ban`, `Unban`, `BanList`, `BanHistory`, `Warn`, `LockServer`, `KickAll`, `ServerInfo`, `TeleportTo`, `Bring`, `Freeze`, `SetPower`, `SetSpeed`, `SetJump`, `Invisible`, `ResetData`, `ConfettiAll`, `Gravity`. Drop every meteor/egg/base/night/photo-showcase action. Add the shooter wishes from `ADMIN-WUENSCHE.md` as **attributes on the admin player** (same pattern as `AdminGod`/`AdminNoclip`, Section 5). |
| `Services/LeaderboardService.luau` (166) | ADAPT | `Services/LeaderboardService.luau` | Same OrderedDataStore + SurfaceGui board pattern, but several boards (e.g. wins, eliminations, rating), board CFrames from the lobby builder, value-changed check before writing, skip admin-tainted stats (Section 9). |
| `Services/GraphicsService.luau` (282) | COPY + trim | `Services/GraphicsService.luau` | Keep `clearOld` (remove duplicate Atmosphere/Sky/Bloom/SunRays/ColorCorrection), `applyLighting`, `buildEffects`, `buildClouds`, the `LOOKS` table + `SetNight` tween engine (handy for events). Rename `MH_*` instance names. Drop `lanternLights` (searches `MeteorHeistMap`). One server hosts lobby + several arenas, but Lighting is global: per-arena looks must be applied **client-side** (a LocalScript tweening Lighting when the local player enters an arena slot; client Lighting changes stay local). |
| `Services/EconomyService.luau` (1,057) | PATTERN | `Services/PlayerStateService.luau` (name free) | Re-implement: `Notify`/`NotifyAll`/`Effect`/`EffectAll` wrappers (check `player.Parent`), `MarkDirty` + 0.2 s flush loop over a **snapshot list** (comment in MH: "neue Einträge während pairs(dirty) wären nicht erlaubt"), "sticky" rarely-changing state keys + full state every 20 s, `readyPlayers` gate (profile loaded → `LoadPasses` → setup → ready; requests answer "Lädt noch..." before that), `Request.OnServerInvoke` dispatcher (rate limit → type check → ready check → action → `dirty[player] = true` → `{ Ok, Message, ...extras }`), `leaderstats` (StringValue for formatted numbers), 1 s game tick with `dt = clamp(clock - last, 0, 5)` and per-player `pcall`. Cash/income/rebirth logic: DROP. |
| `Services/RewardService.luau` (732) | ADAPT | `Services/RewardService.luau` | Keep: playtime gifts per **UTC day across all visits** (stored in data, no rejoin trick), daily quests (3 per UTC day, 1 reroll per day, `Track(player, kind, amount)` called through `pcall` so a quest bug never breaks the core loop), `FillState`. Quest kinds become shooter kinds (wins, eliminations, headshots, matches played, damage). Spin wheel only if it stays free or the sale of spins is gated by PolicyService (paid spins = paid random items). |
| `Services/CarryService.luau` (1,101) | PATTERN | `Services/AntiCheatService.luau` | Lift the **movement budget** (`MoveStatus`, `NoteTeleport`, `allowKnockback`, lines 88–204): a token bucket of allowed horizontal distance, refilled at `WalkSpeed * 1.5 + 16` studs/s, capacity 0.75 s worth; violation → flagged 1.5 s; 1 s grace after a server teleport, with only positions within 30 studs of the target accepted; admins exempt. In the shooter: arena teleports call `NoteTeleport`, explosions/dashes call `allowKnockback`, flagged players get their shots rejected. Everything else (carrying eggs): DROP. |
| `Services/MapBuilder.luau` (1,088) | PATTERN | `Services/LobbyBuilder.luau` / `ArenaBuilder.luau` | Copy the helpers `part(props)` (Anchored, smooth surfaces, `CanTouch = false` by default), `folder`, `disc`, `anchorPart`, `studs`, `addLight`, `worldSign` (BillboardGui, no box, FredokaOne + thick black stroke) and the rule "build the whole map while it is **not** parented, then parent once (one replication burst)". Build-result type (`MapResult`) pattern: return CFrames for spawns/boards instead of searching the workspace later. |
| `GadgetService`, `TreadmillService`, `MeteorService`, `MeteorFactory`, `AlienFactory`, `BaseBuilder`, `PlotService`, `FieldService`, `NightService`, `RunService` (the MH service, not Roblox's), `TradeService` | DROP | n/a | Egg-heist gameplay. Only small ideas carry over (`GadgetService` re-gives owned tools on every `CharacterAdded` after `WaitForChild("Backpack", 10)`; `TradeService` has a second limiter for "requests per 15 s"). |

### 1.4 Client (`StarterPlayerScripts.Client`)

| MH file | Verdict | RS file | Adaptations |
|---|---|---|---|
| `src/client/Main.client.luau` (300) | COPY skeleton | `src/client/Main.client.luau` | Keep: one ScreenGui (`ResetOnSpawn = false`, `ZIndexBehavior = Sibling`), `UI.Init`, the shared `ctx` table, `ctx.RequestFull`/`ctx.Request` (pcall around `InvokeServer`, auto-toast of `result.Message`, "📡 Keine Antwort vom Server" fallback), `STICKY_KEYS` merge on `State`, `Notify` → `UI.Toast`, `Effect` → `Effects.Play`, 1 s `tick()` loop wrapped in `pcall`, admin panel built only when `player:GetAttribute("IsAdmin") == true` (attribute changed signal + initial check). Replace the module list, welcome toasts (via `Lang`) and the treadmill-sign code. |
| `Modules/UI.luau` (1,294) | COPY + small adds | `Modules/UI.luau` | The UI kit (API in Section 11). Adds needed for a shooter: (a) export `UI.IsAnyWindowOpen()` (today the local `anyWindowOpen`), (b) while a window is open set a `Modal = true` button so the mouse is freed in first person, and let the camera module stop forcing `MouseBehavior.LockCenter`, (c) rename the blur instance `MeteorHeistWindowBlur`, (d) touch controls must live in a **separate ScreenGui without the root UIScale** (the root scale goes down to 0.55, which would shrink touch targets below 44 px). |
| `Modules/Hud.luau` (1,000) | ADAPT | `Modules/Hud.luau` | Keep: `inputStyle()` ("Touch"/"Gamepad"/"Keyboard"), `squareButton`, `squareBar` (2-column grid, `SQUARE = 86` px ≥ 44 px on phones), `priceTag` (green "99 R$" badge on the top edge), `Hud.AddRightButton(icon, caption, color, order, onClick)` (unique `LayoutOrder`s, admin = 99), badge refresh only on change, `Hud.Refresh(state)`/`Hud.Tick()` split. New shooter HUD (health, ammo, crosshair, hit marker, kill feed, round timer/score, scoreboard) is new code. Improve `inputStyle` with `UserInputService.PreferredInput` (verified in the current API dump: `KeyboardAndMouse`, `Gamepad`, `Touch`, `MicroGamepad`) and its changed signal. |
| `Modules/AdminPanel.luau` (1,579) | ADAPT | `Modules/AdminPanel.luau` | Keep the framework: `built` guard, `UI.Window("🛠️ ADMIN", 720, 600, Theme.Red)`, tab bar + pages + `selectTab` with `onTabOpen` hooks, shared target box (me/all/others/name/UserId), status line with pop, `admin(action, args)` invoker, `needsConfirm(key, label)` (second click within 5 s), `gridButtons`, `slider` (sends on release), `listFrame`, `clearChildren`, player list via `GetPlayers`, spectate (`Camera.CameraSubject`, key X), client noclip from attribute `AdminNoclip`, open via HUD button 99 + key P. Replace tab contents (Section 5). |
| `Modules/Effects.luau` (2,090) | ADAPT | `Modules/Effects.luau` | Keep: `Effects.Play(name, strength, data)` router, `localPart`, `makeEmitter`, `burst` (range cull 450 studs, max 3 light flashes per 0.25 s), `ring`, `puff`, shard pool, `confetti`, fly-number pool (→ damage numbers), coin fly to counter (→ match rewards), reveal queue (→ case/skin reveal), `RebirthFlash` (→ level-up/victory flash), frozen indicator, **`announce` + `adminWarn` verbatim** (Section 6), `SetHidden`/`IsHidden` for photo mode. Drop deliver/hatch/nest/bonk. Shake uses `Humanoid.CameraOffset` (position only): fine for explosions, but gun recoil must be a camera **rotation** in the FPS camera module. |
| `Modules/Fly.luau` (126) | COPY | `Modules/Fly.luau` | Works as is (LinearVelocity + AlignOrientation, `CanFly` attribute, stops on respawn/attribute loss). Move keys to `Config.Keys` (G may be a gadget key, LeftShift is usually sprint, Q often an ability); suggested: fly toggle configurable, down = LeftControl/C. Anti-cheat must exempt admins (MH `MoveStatus` returns "ok" for admins). |
| `Modules/PhotoMode.luau` (132) | COPY | `Modules/PhotoMode.luau` | Remove the `ctx.Prompts`/`ctx.NestField` calls, additionally hide viewmodel, crosshair and touch controls. Keeps: 1.5 s delay with toast first, CoreGui state saved and restored, prompts disabled and re-hidden if the server re-enables them. |
| `Modules/Windows.luau` (1,347) | PATTERN | `Modules/Shop.luau` etc. | Shop patterns: pass cards with `UI.FetchPrice` + "owned" state from `state.Passes`, product cards, random cards hidden until `UI.WhenRandomItemsKnown(allowed)`, odds text shown **before** purchase, one-time product lock until the server confirms (`starterPendingUntil` + `PromptProductPurchaseFinished` reset on cancel). |
| `Modules/Rewards.luau` (995) | PATTERN | `Modules/Rewards.luau` | Gift/quest window layouts and badge logic, if the shooter keeps gifts/quests. |
| `Bat`, `Base`, `MeteorRun`, `NestField`, `Night`, `Prompts`, `Trade`, `WorldFX` | DROP | n/a | Game-specific. `Bat.luau` and `MeteorRun.luau` also use **dead sounds** (`swordslash.wav`, `electronicpingshort.wav`, see ASSETS.md §2.1). |

### 1.5 Docs / `vorbereitet/`

| MH file | Verdict | RS file | Notes |
|---|---|---|---|
| `ANLEITUNG.md` (547) | ADAPT structure | `ANLEITUNG.md` | Section list in 15.1. |
| `vorbereitet/KOPIERVORLAGEN.md` (683) | ADAPT approach | `vorbereitet/KOPIERVORLAGEN.md` | Structure in 15.2. |
| `vorbereitet/startplan.html` (428) | ADAPT approach | `vorbereitet/startplan.html` | Checklist page (15.3). |
| `vorbereitet/FOTOS-MACHEN.md` (254) | ADAPT | `vorbereitet/FOTOS-MACHEN.md` | Same idea: owner takes N named screenshots, we turn them into icon + thumbnails. |
| `vorbereitet/bilder/_generator/` (`generate.js`, Node, CommonJS) | PATTERN | `vorbereitet/bilder/_generator/` | Draws 512×512 pass/product icons and 1920×1080 thumbnails; uses a screenshot when one exists. One `ICONS` entry per image; images are drawn independently so old images stay byte-identical (check with `md5sum`). |

---

## 2. Service architecture (copy this contract)

`Main.server.luau` (MH, unchanged logic):

```lua
local order = { "DataService", "MonetizationService", "GraphicsService", ... , "AdminService", "LeaderboardService" }
local Services, loaded = {}, {}
for _, name in ipairs(order) do
	local module = ServicesFolder:WaitForChild(name, 10)
	if not module or not module:IsA("ModuleScript") then warn("[Spiel] Service fehlt: " .. name) continue end
	local ok, result = xpcall(require, debug.traceback, module)
	if ok and type(result) == "table" then Services[name] = result; table.insert(loaded, name)
	else warn("[Spiel] Fehler beim Laden von " .. name .. ": " .. tostring(result)) end
end
local function run(name, phase, fn, ...)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then warn("[Spiel] Fehler in " .. name .. "." .. phase .. ": " .. tostring(err)) end
end
for _, name in ipairs(loaded) do if Services[name].Init then run(name, "Init", Services[name].Init, Services) end end
for _, name in ipairs(loaded) do
	if name ~= "DataService" and Services[name].Start then run(name, "Start", Services[name].Start) end
end
if Services.DataService then run("DataService", "Start", Services.DataService.Start) end -- ZULETZT
```

Rules the MH services follow (keep them):

1. **Module shape:** `local X = {}`, `local Services` upvalue, `function X.Init(services) Services = services ... end`, `function X.Start() ... end`, `return X`. Shared requires at top: `require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))`. Server-only modules: `require(script.Parent:WaitForChild("Remotes"))`.
2. **Init** (in `order`): store `Services`, build the world (map, boards), create instances. No player logic. A service may read results of services earlier in `order` (MH: `LeaderboardService.Init` reads `PlotService.LeaderboardCFrame` and `MapFolder`). A crash in one Init only logs (others continue).
3. **Start**: connect events, set remote handlers, start loops. `DataService.Start` runs **last**, so every `OnProfileLoaded` callback is registered before the first profile loads.
4. **Cross-service calls** happen at runtime through `Services.X.Fn(...)`. Optional/unfinished services are called defensively (`tryCall(serviceName, fnName, ...)` in AdminService, `type(fn) == "function"` checks in Monetization, `pcall(rewards.Track, ...)` in Economy).
5. **Every per-player table is cleared on `PlayerRemoving`** (MH examples: `limiter.Clear`, `adminCache`, `warnedDenied`, `joinedAt`, `owned`, `loading`, `adminGranted`, `randomRestricted`, `dirty`, `readyPlayers`, `sent*`).
6. **Loops**: `task.spawn(function() while true do task.wait(T) ... end end)`, iterate a snapshot (`Players:GetPlayers()` or a copied list), `pcall` per player, clamp `dt`. Players already in game at Start are handled with `for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end` (DataService, AdminService do this; MonetizationService relies on `EconomyService.onProfileLoaded → LoadPasses` instead).

Proposed shooter order (final names come from the design doc): `DataService`, `MonetizationService`, `GraphicsService`, `LobbyBuilder`/`ArenaService` (builds lobby + arena slots), `AntiCheatService`, `WeaponService`/`CombatService`, `BotService`, `MatchService` (queues, duels, slot allocation, bot fill), `PlayerStateService` (state flush + `Request`), `RewardService`, `ShopService`, `AdminService`, `LeaderboardService` (Init after the lobby builder because it needs board CFrames). `DataService.Start` stays last.

---

## 3. Remote conventions

- One server module `Services/Remotes.luau` creates everything under `ReplicatedStorage.Remotes` with an idempotent `make(className, name)` and returns typed handles (`:: RemoteEvent`). The client builds its own table with `RemotesFolder:WaitForChild(name)`.
- MH remotes and payloads (keep):

| Remote | Type | Direction | Payload |
|---|---|---|---|
| `Notify` | RemoteEvent | S→C | `(text, kind)`; kinds `Info`, `Success`, `Error`, `Event`, `Alarm`, `Announce` → `UI.Toast` |
| `State` | RemoteEvent | S→C | full or partial state table; client merges `STICKY_KEYS` (fields missing in a packet keep the last value); full packet every 20 s; flush ≤ 5×/s per player |
| `Effect` | RemoteEvent | S→C | `(name, strength, data)` → `Effects.Play`; `data` holds positions/ids; unknown names are ignored |
| `Request` | RemoteFunction | C→S | `(action: string, arg)` → `{ Ok: boolean, Message: string, ...extras }`; the client toasts `Message` unless called silently |
| `Admin` | RemoteFunction | C→S | `(action, args: table)` → `{ Ok, Message, Data }` |

- Shooter additions (suggestion): `Combat` (RemoteEvent C→S: fire/reload/equip/melee with timestamp + origin + direction; **always** validated server-side), `CombatFX` (`UnreliableRemoteEvent` S→C: tracers/muzzle/impacts of *other* players; cosmetic only, so losing a packet is fine; keep payloads small), `Match` (RemoteEvent S→C: queue/countdown/round/score) or a sticky part of `State`.
- Hard rules from MH: the server never calls `InvokeClient`; every handler starts with the rate limiter, then `type()` checks, then clamps (`num(value, default, min, max)`), then a ready check; handlers return a table, never throw (`pcall` around actions). Client-supplied numbers are untrusted (NaN check: `n ~= n`).
- Localization: the server builds the final text with `Lang` for that player's `LocaleId` before `Notify`/`Message`. Admin free text (announcements) is filtered and sent as-is.

---

## 4. Rate limiter (`Util.RateLimiter`)

```lua
local limiter = Util.RateLimiter(maxCalls, perSeconds) -- gleitendes Fenster pro Schlüssel (meist der Player)
if not limiter.Check(player) then return { Ok = false, Message = "Zu schnell" } end
-- PlayerRemoving: limiter.Clear(player)  (sonst hält die Tabelle den Player fest)
```

- Sliding window per key (`os.clock()` timestamps, `table.remove(bucket, 1)` is O(n), fine for small `maxCalls`).
- MH sizes: Admin 12/1 s, Request 8/1 s, steal 6/1 s, gadget use 4/1 s, meteor actions 6/1 s, night crates 3/1 s, trade actions 12/1 s, trade requests 3/15 s.
- **Rate-limit before the admin check and before logging** (MH fix in `df976fe`: otherwise exploiters flood the server log). Log a denied admin access only once per player (`warnedDenied`).
- Do **not** use it as the fire-rate check. Fire rate needs a per-weapon cooldown (RPM) with a small burst tolerance for network jitter (token bucket), plus ammo/reload state on the server. Keep `RateLimiter` for "packets per second" spam caps on `Combat`.

---

## 5. Owner-only admin

MH code (`AdminService.luau` 32–60) minus `AdminUserIds`, plus a Studio refinement:

```lua
-- Nur der Besitzer ist Admin: Spiel unter dem EIGENEN Account veröffentlicht (keine Gruppe).
-- Admin kann man nicht kaufen. Der Server prüft das bei JEDER Aktion.
local function computeAdmin(player: Player): boolean
	if Config.OwnerIsAdmin and game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0
		and player.UserId == game.CreatorId then
		return true
	end
	if RunService:IsStudio() and Config.StudioIsAdmin then
		-- Solo-Test: echte UserId (> 0). "Test -> 2 Players": Player1 = -1, Player2 = -2 ...
		-- Player2 bleibt normaler Spieler -> man kann testen, dass Nicht-Admins abgewiesen werden.
		return player.UserId > 0 or player.UserId == -1 or Config.StudioAllPlayersAdmin == true
	end
	return false
end
```

(MH made **every** Studio player admin. That satisfies "Studio test counts as admin", but the "denied" path could never be tested. Keep `Config.StudioAllPlayersAdmin = false` as the default.)

- Cache per player (`adminCache`), only stored while `player.Parent`. On join: `player:SetAttribute("IsAdmin", true)` (+ `CanFly`). The client builds the panel only when that attribute is true. **Every** `Admin` invoke is re-checked on the server.
- Server-locked servers kick non-admins on join (`LockServer`, kick text in `LOCKED_KICK_TEXT`).
- Admin powers are **attributes on the admin's Player** (replicated, read by server and client): MH uses `AdminGod`, `AdminNoclip`, `AdminSpeed`, `AdminJump`, `CanFly`. Shooter wishes map 1:1: `AdminAimbot` (+ `AdminSilentAim`, `AdminTriggerbot`), `AdminESP`, `AdminInfAmmo`, `AdminNoReload`, `AdminRapidFire`, `AdminOneShot`, `AdminInvisible`, plus admin weapons as a server-side weapon list with `AdminOnly = true`. The server honours a power only if `IsAdmin(player)` **and** the attribute is set (for example: silent-aim shots are accepted only then).
- Fairness flag (ADMIN-WUENSCHE): when any combat power or admin weapon is used in a match, mark the match `AdminTainted`. Tainted matches do not change rating/ELO, global leaderboards or other players' stats.
- Anti-cheat exempts admins (MH `MoveStatus` returns "ok" for admins).
- `GetRankInGroup` note: MH never used group checks, keep it that way. If the game is ever moved to a group: `Player:GetRankInGroup` **and** `Player:GetRankInGroupAsync` are both deprecated in the current API (luau-lsp `globalTypes.d.luau` lines 16022–16029 say: use `GroupService:GetRolesInGroupAsync(userId, groupId)`, which returns `{ IsMember, Roles = { { Id, Name, Rank } } }`, highest role first). Owner = `Roles[1].Rank == 255`. Wrap it in `pcall` and cache the result.

---

## 6. Kick / ban / unban / announce / global events

**Kick:** `resolveTargets(admin, args.Target)`, never kicks the admin themself, default reason "Vom Admin gekickt".

**Ban (keep, with clamps):**

```lua
Players:BanAsync({
	UserIds = { userId },                 -- max. 50
	ApplyToUniverse = true,
	Duration = if days > 0 then math.max(60, math.floor(days * 86400)) else -1, -- 0 ist ungültig, -1 = für immer
	DisplayReason = string.sub(reason, 1, 400), -- Roblox-Grenze 400, wird von Roblox gefiltert
	PrivateReason = string.sub("Gebannt von " .. admin.Name .. " (" .. admin.UserId .. ")", 1, 1000),
	ExcludeAltAccounts = false,           -- Zweit-Accounts mitbannen
})
```

- MH refuses: target = admin, target = owner (`CreatorType == User and userId == CreatorId`). Add: `userId <= 0` (Studio test players) → "Im Studio-Test nicht möglich".
- Banned users are evicted by Roblox automatically. `BanAsync` needs `Players.BanningEnabled` (set it in `default.project.json`). It can be tested in Studio, but those bans do not apply to the live game (Roblox docs).
- `Unban`: `Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })`.
- `BanHistory`: `Players:GetBanHistoryAsync(userId):GetCurrentPage()`, newest 5 shown (fields `DisplayReason`, `Duration`, `Ban`, `StartTime`).
- `BanList` in MH is **session-only** (Roblox offers no "list all bans" API). Optional improvement: persist the last ~100 bans in one DataStore key via `UpdateAsync` (owner-only, low frequency).

**Announce (keep verbatim, it matches the owner's "Steal a Brainrot" wish):**

1. Admin panel → `Admin` RF `"Announce"` `{ Text, Global }`; 1–200 chars.
2. Server: `TextService:FilterStringAsync(text, admin.UserId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()` in `pcall`; filter down → refuse ("Text-Filter nicht erreichbar").
3. Local: `Remotes.Effect:FireAllClients("Announce", 0, { Text, UserId, Name })`. Global: `MessagingService:PublishAsync(Config.MessagingTopic, { Type = "Announce", ... })`; every server (the sender too) gets it via `SubscribeAsync` → `handleGlobal` → `showAnnouncement`. If publishing fails, the message is handled locally (`publishGlobal` fallback). In Studio `SubscribeAsync` may fail, which is logged as normal.
4. Client `Effects.announce`: queue (max 5, oldest dropped), round avatar from `Players:GetUserThumbnailAsync(userId, HeadShot, Size150x150)` (cached), name in blue, **self-drawn verified badge** (two rotated blue squares + white "✓", no asset), ":" and white text, no box, pop-in, 8 s, fade.

- `Warn`: filtered (1–150 chars), red center text on target screens (`Effect "Warn"`).
- Same global channel types in MH: `Announce`, `Luck`, `Shower`, `AdminAbuse`, `Gravity`, `Night`, `EggRush`, `RareNests`, `RaceEvent`. Shooter: `Announce`, `AdminAbuse` (global boost: `{ Type, Mult, Until = workspace:GetServerTimeNow() + seconds }`, so all servers end at the same time), `Gravity`, optional `ServerBoost`. Validate every field in `handleGlobal` with `num()`.
- MessagingService limits (Roblox reference): message size 1 kB; sent per server `600 + 240 × players` per minute; received per topic `40 + 80 × servers` per minute; whole game `400 + 200 × servers` per minute. Admin events are far below that.

---

## 7. Monetization

**Keep:**
- `Config.GamePasses` / `Config.Products` with `Id = 0` until created. The shop greys out or hides `Id == 0` entries. `Config.ProductsById` is only filled for `Id ~= 0` (asserts duplicates).
- `LoadPasses(player)`: `UserOwnsGamePassAsync` per pass with 3 attempts (`task.wait(attempt)`), `loading` guard against double loads, result stored only if still in game, `VIP` attribute for the overhead tag. `HasPass(player, key)` = owned or admin-granted (session).
- `PromptGamePassPurchaseFinished(player, id, purchased)` → mark owned, `OnPassChanged`, toast + server-wide toast + confetti.
- PolicyService: server `paidRandomRestricted(player)` (cached, **in doubt = restricted**, prefetched on join); client `UI.WhenRandomItemsKnown(cb)` hides random cards until known and when not allowed.
- When a restricted player still ends up buying a random product (exploiters can prompt any product), MH grants a **non-random equivalent** (starter pack: fixed egg + 1.5× cash). Do the same for keys/cases (fixed item or coins).
- Shop odds shown before purchase must be **exactly** the server's roll table (MH fix `168da25`: `DayOnly = true` so night eggs never distort displayed odds).
- `Config.MessagingTopic`, `Config.DataStoreName`, `Config.LeaderboardStoreName` are versioned names (`…_v1`).

**ProcessReceipt (keep the receipt log, fix the flow):** MH stores the last 60 `PurchaseId`s in `data.Receipts` (session-locked profile), then saves immediately. Roblox calls ProcessReceipt on purchase, on prompt success, **and when the user joins**; it does **not** retry on a timer, and a yielding callback has no timeout (Roblox reference). Therefore:

```lua
local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	-- Beim Beitritt ruft Roblox das oft VOR dem Laden des Spielstands auf -> warten statt aufgeben
	-- (sonst bleibt der Kauf bis zum nächsten Beitritt liegen)
	local data = waitForProfile(player, 60)
	if not data then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local product = Config.ProductsById[receipt.ProductId]
	if not product then warn("[Monetization] Unbekannte ProductId " .. receipt.ProductId) return Enum.ProductPurchaseDecision.NotProcessedYet end
	while processing[receipt.PurchaseId] do task.wait(0.2) end -- gleicher Kauf läuft schon: warten
	if table.find(data.Receipts, receipt.PurchaseId) then return Enum.ProductPurchaseDecision.PurchaseGranted end
	processing[receipt.PurchaseId] = true
	local prepared = prepare(player, product)      -- ALLES, was warten muss (PolicyService ...), HIER
	local granted = false
	if Services.DataService.Get(player) == data then
		-- ab hier KEIN yield: gutschreiben + Beleg in einem Rutsch (kein Speichern dazwischen möglich)
		local ok, result = pcall(grantNoYield, player, data, product, prepared)
		granted = ok and result == true
		if granted then
			table.insert(data.Receipts, receipt.PurchaseId)
			while #data.Receipts > MAX_RECEIPTS do table.remove(data.Receipts, 1) end
			data.Stats.RobuxSpent += receipt.CurrencySpent or 0
		end
	end
	processing[receipt.PurchaseId] = nil
	if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
	return if Services.DataService.Save(player) then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet -- Beleg steht im Spielstand -> nie doppelt
end
```

- Grant functions are all-or-nothing: check first, then mutate. They never yield (MH's `grantStarterPack` yields in `paidRandomRestricted` **between** reading and writing data, and the grant can be saved by a concurrent release before the receipt is written → double grant on rejoin; the version above closes that gap).
- Set `MarketplaceService.ProcessReceipt` once, early in `Start` (if no callback is set, Roblox auto-acknowledges receipts and the purchase is lost to the game).
- Unknown product IDs stay `NotProcessedYet` (never eat a purchase). One-time products bought twice are still granted, with a `warn`.
- Products that act on a match (e.g. a "nuke" or global boost) must check that the target exists **before** granting and must return `false` (= retry later) if it does not (MH `grantShield`: no base on this server → `false`).

---

## 8. DataService (session lock, retries, migration, Studio fallback)

**API (keep):**

| Function | Behaviour |
|---|---|
| `DataService.Profiles` | `{ [Player]: { Loaded, Data, NoSave, Releasing } }` |
| `Get(player)` | data table or `nil` until loaded |
| `IsLoaded(player)` | boolean |
| `OnProfileLoaded(cb(player, data))` | each callback `task.spawn`ed after load |
| `OnProfileReleasing(cb(player, data))` | `pcall`ed before the final save (cancel running actions, write leaderboard) |
| `Save(player)` | `true` on success; `true` for NoSave profiles; refuses while releasing |
| `Reset(player)` | fresh `DEFAULT_DATA`, keeps `Receipts` and one-time purchase flags |
| `Migrate(data)` | version-gated changes, sanitize fields (invalid → `nil`), then `Util.Reconcile(data, DEFAULT_DATA)` fills defaults |

**Record format:** key `"Player_" .. userId`, value `{ Data = {...}, Lock = { JobId, Time } | nil }`; `jobId()` = `game.JobId` or `"studio"`.

**Load:** up to `LOAD_ATTEMPTS = 6` `UpdateAsync` calls. Inside the transform: if `Lock` belongs to another JobId and is younger than `LOCK_EXPIRE = 30 min` → return `nil` (write nothing) and wait `LOCK_WAIT = 5 s`. On the last attempt the lock is taken anyway (`forceTake`, about 30 s worst case after a crashed server). Errors back off `attempt * 1.5 s`. Then `pcall(Migrate)` (on failure keep `Version` so it retries next time), then `Reconcile`.

**Save:** up to 4 attempts; the transform refuses (returns `nil`, `lostLock = true`) when another JobId owns the lock, so a server that lost the lock can never overwrite newer data. Release writes `Lock = nil`.

**Join failure:** live → kick ("Dein Spielstand konnte nicht geladen werden …"). Studio → `NoSave = true`, defaults, warning "Enable Studio Access to API Services". Studio access errors (`studio`, `publish`, `api services`, `403` in the message) stop retrying at once so the Studio test starts immediately.

**Leave during load:** the lock just taken is released at once (`saveData(..., true)`).

**Release:** `Releasing` guard; a second caller (PlayerRemoving + BindToClose) waits until the profile is gone (MH's "double release" protection). Releasing callbacks, final save, remove profile.

**Auto-save:** every `Config.AutoSaveInterval = 90 s`, staggered `0.5 s` per player. **BindToClose:** release all in parallel, wait up to 25 s (Roblox gives 30).

**Fixes for the shooter (see 14.3):** snapshot the auto-save list, serialize saves per profile, NoSave for `UserId <= 0`, optional separate Studio store.

---

## 9. Leaderboards (OrderedDataStore)

MH pattern (`LeaderboardService.luau`): `DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)` in `pcall`; value `math.floor(math.clamp(v, 0, 9e18))`; key `tostring(UserId)`; `SetAsync` per player every 300 s (first after 10 s, 0.5 s between players) and on profile release; `GetSortedAsync(false, 10)`; names via `GetNameFromUserIdAsync` cached; board = Part 36×24×1 + SurfaceGui (`PixelsPerStud = 25`, `LightInfluence = 0`), FredokaOne rows with gold/silver/bronze, "NOCH KEINE EINTRÄGE – SEI DER ERSTE!" when empty.

Shooter changes: one ordered store per stat (`…_Wins_v1`, `…_Elims_v1`, `…_Rating_v1`); write only if the value changed since the last write (`lastWritten[player]`); skip admin-tainted contributions; bound the name cache (it grows forever in MH); `DisplayName` is not available for offline users, so show `Name`; keep the board build in `Init` (needs lobby CFrames) and the loop in `Start`.

---

## 10. Client architecture (from `Main.client.luau`)

- `ctx` fields: `Player`, `Config`, `Util`, `Remotes`, `Gui`, `State`, `StateTime` (os.clock of last state; countdowns inside the state are relative to it), `Toast = UI.Toast`, `Request`, `RequestFull`, `Hooks` (cross-module callbacks such as `OnCash`), plus module references (`Hud`, `Windows`, `Effects`, `Fly`, `PhotoMode`, …).
- Start order: `UI.Init(gui)` → `Effects.Init(ctx)` → `Windows.Init` → `Hud.Init` → `Fly.Init(UI.Toast)` → `PhotoMode.Init(ctx)` → others; modules that need the map wait in a `task.spawn` with `workspace:WaitForChild(mapName, 120)`.
- `refreshAll()` calls each module's `Refresh(state)` on every `State` packet. A 1 s `tick()` runs `Hud.Tick()`/countdowns inside `pcall` ("Ein Fehler darf die Schleife nicht für immer anhalten").
- Keybinds use `UserInputService.InputBegan` with `if processed or UserInputService:GetFocusedTextBox() then return end` (P panel, G fly, H photo, X stop spectating). For **gameplay** input the shooter uses `ContextActionService` (MH has none): `BindAction` for fire/aim/reload/switch with keyboard, mouse and gamepad inputs, `createTouchButton = false`, and custom touch buttons in an unscaled ScreenGui.

---

## 11. UI kit API surface (`Modules/UI.luau`, copy verbatim)

Style: FredokaOne everywhere (Gotham fonts are auto-replaced), white text with black `UIStroke`, chunky buttons with gradient, black stroke, 4 px darker "lip", shine strip, hover grow (1.06), press squash, elastic release. Windows are light blue with a 5 px black stroke, UPPERCASE title, red X, pop-in, background blur 6, and only one window open at a time. Toasts have no box.

```lua
UI.Font                      -- Enum.Font.FredokaOne
UI.Theme                     -- Panel, PanelDark, PanelLight, Text, SubText, Black, Yellow, Cash, Red, Blue, Green,
                             -- Orange, Purple, Pink, Gray, Gold, Cyan
UI.Root                      -- ScreenGui (after Init)
UI.Init(screenGui: ScreenGui)  -- root UIScale = clamp(min(w/1280, h/760), 0.55, 1.15), toast holder, counter stepper
UI.Create(className: string, props: { [string]: any }?, children: { Instance }?): any  -- Parent set last
UI.Corner(radius: number?): UICorner                       -- default 12
UI.Stroke(color: Color3?, thickness: number?): UIStroke    -- border, round joins, default black 3
UI.TextStroke(thickness: number?): UIStroke                -- default 2
UI.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
UI.ButtonSequence(color: Color3): ColorSequence
UI.FormatMult(value: number?): string                      -- 1.25 -> "1.25", 2 -> "2"
UI.FormatSteps(value: number, formatNumber: (number) -> string): string
UI.Upper(text: string): string                             -- also ä/ö/ü -> Ä/Ö/Ü (not ß)
UI.Label(props): TextLabel        -- any TextLabel props + MaxText (UITextSizeConstraint, default 28) + Outline (stroke px)
UI.TextBox(props): TextBox        -- dark field, MaxTextSize 18, padding 8
UI.Button(props, onClick: (() -> ())?): UI.Button
	-- props: Name, Size, Position, AnchorPoint, LayoutOrder, Parent, Visible, ZIndex, Text, Sub, Color,
	--        MaxText (24), SubMax (16), Corner (12), StrokeSize (3), Wrap
	-- returns { Frame, Button: TextButton, Label, Sub?, Stroke, SetText(text), SetSub(text), SetColor(color) }
	-- onClick runs in task.spawn + pcall; double clicks are ignored while it runs
UI.Badge(target: UI.Button, text: string?): Frame          -- red pill top-right
UI.SetBadge(badge: Frame, text: string?, color: Color3?, pulse: boolean?)  -- nil/"" hides; writes only on change
UI.Section(parent, text, order, color?): TextLabel
UI.Row(parent, order, height?): Frame                      -- horizontal list
UI.Grid(parent, order, cellX, cellY): Frame                -- grid, AutomaticSize Y
UI.Card(props): Frame                                      -- PanelLight + corner + stroke
UI.Bar(props): UI.Bar   -- props: Size, Position, LayoutOrder, Parent, Color, MaxText; returns { Frame, Fill, Text, Ratio }
UI.SetBar(bar, ratio: number, text: string?)               -- NaN-safe, tweened
UI.Pulse(scale: UIScale, amount: number?)
UI.Counter(target: TextLabel, format: (number) -> string): UI.Counter  -- smooth count-up, ≤ 30 redraws/s
UI.SetCounter(counter, value: number, instant: boolean?)   -- flash white up / red down, pop on increase
UI.RedrawCounter(counter)
UI.Window(title: string, width: number, height: number, color: Color3?): UI.Window
	-- returns { Group, Fader: CanvasGroup, Panel, Scale, Content: ScrollingFrame (UIListLayout by LayoutOrder),
	--           IsOpen, Token, OnOpen: (() -> ())? }
	-- content sits in the CanvasGroup only while animating (sharp text on phones)
UI.OpenWindow(win) / UI.CloseWindow(win) / UI.ToggleWindow(win) / UI.CloseAll()
UI.Toast(text: string, kind: string?)   -- Info/Success/Error/Event/Alarm/Announce; max 5, low priority dropped first;
                                         -- 7 s for Event/Announce, else 4 s; pooled frames
UI.SetToastTop(offset: number?)          -- move toasts down while something else is at the top (default 56)
UI.FetchPrice(id: number, infoType: Enum.InfoType, callback: (number?) -> ())  -- GetProductInfoAsync, cached, id 0 -> nil
UI.WhenRandomItemsKnown(callback: (allowed: boolean) -> ())  -- PolicyService once; error = not allowed
UI.RandomItemsAllowed(): boolean?        -- nil until known
```

Related helpers in other modules worth copying:
- `Hud`: `inputStyle(): "Touch" | "Gamepad" | "Keyboard"`, `squareButton(parent, icon, caption, color, order, onClick): UI.Button`, `squareBar(name, anchor, position, align): Frame`, `priceTag(button, id, infoType)`, `Hud.AddRightButton(icon, caption, color, order, onClick)`.
- `AdminPanel`: `slider(parent, order, title, min, max, default, onRelease): { Set, Get }`, `listFrame(parent, order)`, `gridButtons(parent, order, cellX, { { text, color, fn } })`, `needsConfirm(key, label): boolean`, `textBox(props)` (wraps `UI.TextBox`; see pitfall 14.1 #1).
- `Effects`: `Effects.Play(name, strength, data)`, `Effects.Burst(pos, color, amount, flash?)`, `Effects.Ring(pos, color, size, time?)`, `Effects.Puff(pos, color, amount)`, `Effects.Shake(strength)`, `Effects.SetHidden(bool)`, `Effects.IsHidden()`, `Effects.RebirthFlash()`.
- `Fly`: `Fly.Init(toast)`, `Fly.Toggle()`. `PhotoMode`: `PhotoMode.Init(ctx)`, `PhotoMode.Toggle()`.

---

## 12. Shooter-specific adaptations of reused client code

- **Mouse in first person:** opening any window must free the cursor (`GuiButton.Modal = true` inside the open window plus the camera module skipping `MouseBehavior = LockCenter` while `UI.IsAnyWindowOpen()`), and closing restores it.
- **Toasts vs. HUD:** toasts sit top-center at 56 px; the round timer/score usually lives there → `UI.SetToastTop(...)` during matches, kill feed top-right.
- **Touch:** fire/aim/reload/jump/switch buttons ≥ 64 px in a separate ScreenGui without `UIScale`, respecting safe areas; `UserInputService.PreferredInput` decides which prompts and buttons show.
- **Photo mode:** also hide viewmodel parts (camera children), crosshair, touch GUI.
- **Effects budget:** keep the MH budgets (range cull, max flashes per window, pools instead of `Instance.new` per shot). Tracers/impacts must use pools too (one shot = no new instance in the hot path).

---

## 13. Tooling commands (verified 2026-10-11 on MH, read-only)

Versions: Rojo 7.7.1, StyLua 2.5.2, selene 0.31.0, luau-lsp 1.70.1 (`/tmp/luau-lsp/build/luau-lsp`), Luau CLI at `<scratchpad>/luau-build/luau`.
On MH: `stylua --check src` OK, `selene src` 0 errors / 0 warnings, `luau-lsp analyze` 0 diagnostics, `rojo build` OK.

```bash
cd /home/user/website-test-demo-1/roblox-shooter
SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad

stylua src                         # formatieren (stylua --check src = nur prüfen)
selene src                         # Lint mit std "rbx" (rbx.yml im Projekt-Root)
rojo sourcemap default.project.json -o sourcemap.json
/tmp/luau-lsp/build/luau-lsp analyze --platform=roblox \
  --definitions=$SP/globalTypes.d.luau --sourcemap=sourcemap.json src
rojo build default.project.json -o <GameName>.rbxlx

# reine Module (Util, Lang, Config-Rechnungen) schnell testen – Kopie im Scratchpad:
cd $SP/<testdir> && $SP/luau-build/luau test.luau   # require("./Util") funktioniert
```

- `--sourcemap` is required so luau-lsp resolves `script.Parent:WaitForChild(...)` requires.
- The definitions file is session-local (scratchpad). It is current (it flags `GetRankInGroupAsync` as deprecated).
- Never run `rojo build`/`sourcemap` inside MH with default output paths (they would rewrite MH files); write to the scratchpad when inspecting MH.

---

## 14. Known pitfalls

### 14.1 Fixed in MH (keep the fix)

| # | Pitfall | Fix in MH |
|---|---|---|
| 1 | Admin panel text-box helper called **itself** → endless recursion, panel never built (`ec307f0`) | wrapper must call `UI.TextBox(props)`, not `textBox(props)`. Watch every thin wrapper. |
| 2 | Double release (PlayerRemoving + BindToClose both save) | `profile.Releasing` guard + second caller waits until the profile is gone |
| 3 | Double pass load | `loading[player]` guard in `LoadPasses` |
| 4 | Double click on buttons / one-time product bought twice | `busy` flag in `UI.Button`; client lock until server confirms; server still grants + warns |
| 5 | Admin log flooding by exploiters | rate limit **before** the admin check; "Unerlaubter Zugriff" logged once per player |
| 6 | Studio without API access waited ~30 s before the test started | detect Studio access errors, stop retrying, NoSave profile |
| 7 | Gifts re-claimable by rejoining | playtime stored per UTC day in the profile |
| 8 | Displayed odds ≠ server odds (night eggs) | `DayOnly` pool for paid random products |
| 9 | Two systems writing the same `Transparency` (admin invisible vs cloak) | end the other effect first, store originals in attributes (`AdminOrigT`) |
| 10 | `pairs(dirty)` while callbacks add entries | copy keys into `flushList`, then clear and iterate the list |
| 11 | Requests before the player was set up | `readyPlayers` gate ("Lädt noch... ⏳") until passes are checked |
| 12 | Teleport/wall exploits | movement budget with teleport grace (Section 1.3 AntiCheat) |
| 13 | Toasts covering another top HUD element | `UI.SetToastTop(offset)` |
| 14 | CanvasGroup makes text blurry on phones | content only inside the CanvasGroup while animating |
| 15 | Deprecated APIs | MH uses `GetProductInfoAsync`, `UserOwnsGamePassAsync`, `GetNameFromUserIdAsync`, `task.*`, `AssemblyLinearVelocity`; no `wait/spawn/delay`, no `BodyVelocity`. Keep it that way (`AwardBadge` → `AwardBadgeAsync`, `IsInGroup` → `IsInGroupAsync`, group rank → `GroupService:GetRolesInGroupAsync`). |

### 14.2 `Util.FormatNumber` bug (still in MH, fix in the shooter)

Tested with the Luau CLI on a copy: `1150 → "1.14K"`, `4350000 → "4.34M"` (`math.floor(n * 100)` on binary floats), `1e33 → "999No"` (repeated division drifts below 1000), `math.huge → "-9223372036854775808Dc"`, `-math.huge → "--9223…Dc"`, `-0.5 → "-0"`. Fixed version (tested: all of these and all powers of 1000 up to 1e36 correct):

```lua
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local EPS = 1e-9

-- 1234 -> "1.23K", 15000000 -> "15M" (abgerundet, nie "1000K")
function Util.FormatNumber(n: number): string
	if n ~= n then
		return "0"
	elseif n == math.huge or n == -math.huge then
		return if n > 0 then "MAX" else "-MAX"
	end
	local negative = n <= -1 -- -0.5 -> "0" statt "-0"
	n = math.abs(n)
	if n < 1000 then
		local s = string.format("%d", math.floor(n + EPS))
		return if negative then "-" .. s else s
	end
	-- Stufe über Vergleiche statt wiederholtem Teilen (sonst wird 1e33 zu "999No")
	local index, scale = 1, 1
	while index < #SUFFIXES and n * (1 + EPS) >= scale * 1000 do
		scale *= 1000
		index += 1
	end
	local v = n / scale
	local text
	if v >= 100 then
		text = string.format("%.0f", math.floor(v + EPS)) -- %.0f: kein Überlauf bei riesigen Zahlen
	elseif v >= 10 then
		text = string.format("%.1f", math.floor(v * 10 + EPS) / 10)
	else
		text = string.format("%.2f", math.floor(v * 100 + EPS) / 100)
	end
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return (if negative then "-" else "") .. text .. SUFFIXES[index]
end
```

### 14.3 Still in MH (fix when copying)

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | `DataService.Start` auto-save | `for player in pairs(DataService.Profiles)` with `task.wait(0.5)` inside: joins add keys and leaves remove keys **during** traversal. Lua does not allow adding keys while traversing; `next` can throw and the unprotected loop dies silently (no more auto-saves on that server). | Copy the keys into a list first; `pcall` each save. |
| 2 | `DataService` save vs release | An auto-save still in flight (e.g. in its retry wait) can finish **after** the release and write `Lock = { this JobId }` again → the player's next join elsewhere waits ~30 s until `forceTake`. | Serialize saves per profile (`profile.Saving` flag / queue); release waits for the in-flight save; the transform skips the lock when `profile.Releasing`. |
| 3 | `DataService` in Studio | With "Studio Access to API Services" on, Studio tests read/write the **live** store, and local multi-client test players (UserId -1, -2) create keys `Player_-1`. | `NoSave` for `UserId <= 0`; optional `Config.StudioUsesLiveData = false` → Studio uses `DataStoreName .. "_Studio"`. |
| 4 | `DataService` `forceTake` | On attempt 6 a non-expired lock is stolen (deliberate trade-off). Fine, but invisible. | Keep, add a `warn` with both JobIds. |
| 5 | `MonetizationService.processReceipt` | Returns `NotProcessedYet` when the profile is not loaded yet. ProcessReceipt fires on join, often before the load, and has no timed retry → purchase stuck until the next rejoin. | Wait for the profile (Section 7). |
| 6 | same | `processing[id]` → `NotProcessedYet` for a concurrent call: same "stuck until rejoin" problem. | Wait while processing, then re-check `Receipts`. |
| 7 | same | Grant may yield between data mutation and receipt insert (`grantStarterPack` → PolicyService) → a release save in between persists the grant without the receipt → double grant. | Do all yielding work before mutating; grant + receipt without yield. |
| 8 | `AdminService.Ban` | `Duration = floor(days * 86400)` can be 0 for tiny values (invalid); reasons are not length-limited (`DisplayReason` max 400, `PrivateReason` max 1000) → `BanAsync` error. | Clamp as in Section 6. |
| 9 | Project | `Workspace.StreamingEnabled = false` (fine for MH's single map). Several arenas in one server multiply the client's part count. | Keep arenas low-part (pooled, simple Parts), or enable streaming and call `player:RequestStreamAroundAsync(target)` before every arena teleport. Server hit validation is unaffected. |
| 10 | `LeaderboardService` | `nameCache` grows forever; values are written even when unchanged. | Bounded cache; write only on change. |
| 11 | `Bat.luau:27`, `MeteorRun.luau:31` | Sounds `swordslash.wav` / `electronicpingshort.wav` are not shipped (silent). | Only use paths verified in `docs/ASSETS.md`. |
| 12 | `AdminService` Studio | All Studio players are admin, so the denial path is never exercised. | Section 5 Studio rule. |
| 13 | `AdminService.handleGlobal` | Only some types clamp their fields with `num()` (e.g. the `Luck` toast concatenates the raw `message.Mult`). Messages can only come from the game's own servers, so this is hygiene, not an exploit. | Validate every field of every type. |

---

## 15. Docs approach (owner is a German beginner on a Mac)

### 15.1 `ANLEITUNG.md` (MH sections → shooter)

1. Title + one-paragraph pitch in a blockquote (what the game is, in kid-friendly words).
2. `📦 Was alles drin ist` (feature list).
3. `🎮 So läuft das Spiel` (core loop + subsections per feature: weapons, modes, ranks, cases …).
4. `🚀 SCHRITT 1 – Spiel in Roblox Studio öffnen` (download `.rbxlx` from GitHub "Download raw file", File → Open from File…).
5. `👑 SCHRITT 2 – Admin-Panel (passiert automatisch!)` (owner = admin, nothing to enter, cannot be bought).
6. `▶️ SCHRITT 3 – Testen` (Play F5, what to try, `Test → Clients and Servers → 2 Players`, key table, buttons list, HUD description).
7. `🌍 SCHRITT 4 – Veröffentlichen` (Publish, name without emoji, Team Create OFF; the proven **"Save failed"** recovery: publish an empty Baseplate first, then `Publish to Roblox As… → Overwrite`; Game Settings → Security → "Enable Studio Access to API Services"; Max Players; Playability Public).
8. `💰 SCHRITT 5 – Geld verdienen (Robux)` (create passes/products, copy IDs, send them to Claude, price table).
9. `📈 SCHRITT 6 – Spieler bekommen`.
10. `🛠️ Admin-Panel – was kann es?`
11. `⚙️ Balancing – alles in Config`.
12. `🔄 Updates mit mir (Claude) machen` (A: new `.rbxlx`; B: replace single scripts, new ModuleScript names; C: Rojo live sync via Rokit `rokit add rojo-rbx/rojo`, `rojo serve`; note on the Roblox Studio MCP server).
13. `🧯 Fehlerbehebung` (table problem → solution; keep "Studio does not save", "Admin panel missing → published under a group", "Shop shows 'Bald verfügbar' → ID 0", "random products missing → country rule", "Save failed", "red text in Output → send it to me", "purchase not received → Roblox retries").
14. `🧠 Technik: warum das für sehr viele Spieler funktioniert` (servers scale automatically; save budget; receipts; server-authoritative anti-cheat; performance budgets). Rewrite for multi-arena servers and hit validation.
15. `📁 Dateien` (tree).

Style: short sentences, bold UI paths (`Home → Game Settings → Security`), emoji headings, Mac keys (Cmd), no jargon without explanation.

### 15.2 `vorbereitet/KOPIERVORLAGEN.md`

Sections: purpose; "So kopierst du richtig" (copy button on grey boxes, Cmd + V); mini glossary (Robux ≈ 70 % payout, Gamepass, Developer Product, ID, Config-Key); 1 game name (options); 2 description DE + EN; 3 genre; 4 images; 5 gamepasses (click path in the Creator Dashboard, then per pass: `Name:` code block, `Beschreibung:` code block, price, image file, Config-Key); 6 developer products (same); 7 maturity questionnaire guidance (answer honestly: weapons shoot, players get eliminated, **no blood/gore**, cartoon style; **Paid Random Items = YES** if keys/cases are sold, odds are shown, hidden where forbidden); 8 cheat sheet table (type, name, price, image, Config-Key); 9 return template (`Key = ` per line → owner pastes IDs into the chat).

### 15.3 `vorbereitet/startplan.html`

Single-page mission checklist: sticky progress bar, steps as cards with a check button, parts with time estimates (open → try → publish → earn Robux), state in `localStorage` wrapped in `try/catch` (page works without it), Google Fonts (Lilita One, Nunito, JetBrains Mono), `kbd` styled click paths. MH's page is dark-only: if the shooter version is published as an artifact, define colour tokens for light **and** dark.

---

## 16. Not reusable (and why)

- Egg/alien content and economy (`Aliens`, `MeteorService`, `MeteorFactory`, `AlienFactory`, cash income, rebirth, offline income): different genre.
- Base/plot system (`PlotService`, `BaseBuilder`, `Base.luau`, locks, floors): the shooter has a lobby and arena slots.
- Carry/steal, bat, traps, cloak, treadmills, trade, night cycle, meteor run, nest field, prompts: no equivalent in an arena shooter. A single exception is the movement budget, moved into `AntiCheatService`.
- MH's "server luck", "shower", "egg rush" products: these are pay-to-affect-the-server mechanics. In a shooter the only acceptable equivalent is cosmetic or a fair server-wide boost (e.g. 2× coins for everyone), never combat power.
