# REUSE.md – what AKYTEX TYCOON takes from CLUTCH CLASH (+ AKYTEX brand sheet)

> **Kurzfassung (Deutsch):** CLUTCH CLASH (CC) hat nach Runde 2 eine fertige, geprüfte Plattform: Service-Lader,
> der EINE Server-Takt (Scheduler), Remotes + Spam-Bremsen, Spielstände mit Session-Lock, State-Sync mit Ready-Gate,
> Robux-Käufe mit Beleg-Liste (nie doppelt), PolicyService, Admin nur für den Besitzer (Bann, Ansagen, Admin-Abuse
> serverübergreifend), Anti-Cheat-Gerüst, Bestenlisten, Analytics, Selbsttest, zweisprachige Texte (DE/EN) und das
> **AKYTEX-UI-Kit** (Glas-Fenster, Knopf-Varianten, Toasts, Zähler, Balken). Diese Teile übernehmen wir fast 1:1.
> Alles Shooter-Spezifische (Waffen, Treffer, Matches, Bots, Kisten, Glücksrad, Kamera, Bewegung) übernehmen wir
> **nicht** – Kisten/Glücksrad/Quoten schon gar nicht (Glücksspiel-Nähe). Neu bauen: Markt-Simulation, Charts aus
> GUI-Frames (Abschnitt 5), Trading-Terminal, Tower/Grundstücke, Stadt, Events, Lizenzen. Am Ende steht das
> AKYTEX-Marken-Blatt von der Website (Farben, Schriften, Bewegung, Logo, Slogans, Feature-Namen, Tabus).
> In CC, Meteor Heist und der Website wird **nichts** verändert.

- Source (read-only, never edit): `CC = /home/user/website-test-demo-1/roblox-shooter` (≈ 83k lines Luau, git `090eef7` "Runde 2").
- Brand source (read-only): `/home/user/website-test-demo-1/{index.html, css/app.css, css/fonts.css, README.md, ueber-akytex.html, BUSINESS.md, icons/logo.svg, js/market.js, js/indicators.js, nova/}`.
- Target: `AT = /home/user/website-test-demo-1/roblox-akytex-tycoon` (Rojo, same tooling as CC).
- Owner wishes: `AT/docs/BESITZER-WUENSCHE.md` (ULTRA BIG, ultra smooth, Future-Licht, Flagship, Admin-Panel, Reichweite).
- Everything below was read from the files on 2026-10-13. Engine facts marked **VERIFIED (API 0.742)** were checked in
  `Full-API-Dump.json` / `rbxManifest.txt` of client 0.742.0.7421053 (scratchpad `assets_dl/`). **UNVERIFIED** = test in Studio.

| Verdict | Meaning |
|---|---|
| **COPY** | Copy nearly verbatim. Rename `CLUTCH CLASH`/`Clutch Clash`/`CC_` → `AKYTEX TYCOON`/`AKYTEX Tycoon`/`AT_`, keep German comments and every listed fix. |
| **ADAPT** | Keep the skeleton, API and conventions. Rewrite the game-specific parts as described. |
| **PATTERN** | Do not copy the file. Re-implement the proven pattern in a new tycoon file. |
| **DROP** | Not useful for the tycoon (or forbidden for compliance reasons). |

---

## 1. Reuse map (file by file)

### 1.1 Root / tooling

| CC file | Verdict | AT file | What to change |
|---|---|---|---|
| `default.project.json` | ADAPT | same | `"name": "AkytexTycoon"`. Same tree (`ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`; `StarterCharacterScripts` only if needed). **`Lighting.Technology = "Future"`** (scripts CANNOT set it: `Technology` is RobloxScriptSecurity, VERIFIED API 0.742; CC uses `ShadowMap`). Add `EnvironmentSpecularScale: 1`, `EnvironmentDiffuseScale: 1` (owner wish 10). Keep `Players.BanningEnabled = true` (NotScriptable, must be here), `CharacterAutoLoads`, `RejectCharacterDeletions`, `ReplicateInstanceDestroySetting`, `TextChatService`, `ResetPlayerGuiOnSpawn = false`. Change `StarterPlayer`: `CameraMaxZoomDistance` ≈ 40–60 (city/tower, CC = 14 for a shooter), remove `CharacterJumpHeight 7.2`/`CameraMode Classic` overrides unless wanted. **Streaming decision** (CC: `StreamingEnabled = false`): a BIG city should use `StreamingEnabled = true` + `ModelStreamingMode = Atomic/Persistent` on own tower + landmarks; then every client lookup of world parts must use `WaitForChild` with timeout and survive streamed-out parts (CC REUSE §14.3 #9). Decide in the spec. |
| `rbx.yml`, `selene.toml`, `stylua.toml` | COPY | same | Verbatim (selene std `rbx`, StyLua Luau/Tabs/120). |
| `.gitignore` | COPY | same | `sourcemap.json` (CC has it). |
| `scripts/check.sh` | ADAPT | same | Output `AkytexTycoon.rbxlx`; **add** `python3 scripts/contract_check.py .` (CC's check.sh does not run it). See §6. |
| `scripts/contract_check.py` | ADAPT | same | Generic. Change only `LANG_PREFIX` (line 262) to the AT prefixes (§3.6) and the docstring name. Everything else (Services/Modules API, Request↔Handle, Net.RemoteList, Lang keys, Config sections, Hooks) works unchanged if AT keeps CC's folder layout and naming. |
| `tests/*.test.luau` | ADAPT | same | Keep `util.test.luau` verbatim (Util is copied). Add `marketmath.test.luau`, `indicators.test.luau`, `format.test.luau` for the new pure modules. `odds.test.luau`, `progressmath.test.luau` DROP. |
| `ClutchClash.rbxlx`, `sourcemap.json` | DROP | – | Build outputs. |

### 1.2 Shared (`ReplicatedStorage.Shared`)

| CC file | Verdict | AT file | Notes |
|---|---|---|---|
| `Util.luau` (342) | **COPY verbatim** | `Util.luau` | Already contains the FormatNumber fix (REUSE §14.2), RateLimiter, TokenBucket, UtcDay/IsoWeek, Hash. Pure module, `--!strict`. |
| `Spring.luau` (97) | **COPY verbatim** | `Spring.luau` | Vector3 spring; use `.X` only for scalar UI springs (§4.2). |
| `Net.luau` (241) | ADAPT | `Net.luau` | Keep `RemoteList`, `GetRemotes()`, the quantization helpers (`finite`, `intIn`) and the "never error while encoding" rule. **Drop** Look/LookBatch/FX codecs and `LookFlags`. **Add** `EncodeQuotes/DecodeQuotes`, `EncodeCandles/DecodeCandles` (§5.3). New RemoteList §3.3. |
| `Types.luau` (289) | ADAPT | `Types.luau` | Keep `Lang`, `NotifyKind`, `Reply`, `PlayerData`. Replace `Grant`/`Currency`. Drop all combat/match/arena/map types. Add `Company`, `Quote`, `Candle`, `Order`, `Position`, `TowerFloor`, `MarketEvent`. |
| `Config/init.luau` (553) | ADAPT | `Config/init.luau` | Keep sections 1–4 (Admin, Tech, Studio, Debug), the child loader (`loadChild`, client waits `game.Loaded`), `Validate()` collector and `validateCore()`. Rename stores (`AT_Player_v1`, `AT_Global`, `AT_Live_v1`, `AT_Stats_v1`, `AT_Mod_v1`, `AT_LB_`). **Drop** section 9 (weapon lookups + live balance) or turn it into `Config.ApplyTuning` for market knobs (volatility, event odds) with the same clamp-to-bounds logic. Server/Player/Colors sections rewritten. Children: `Market`, `Companies`, `Tower`, `City`, `Events`, `Progression`, `Season`, `Security`, `Shop`, `Client`, `Quality`. |
| `Config/Security.luau` | ADAPT | same | Keep sections 2 (suspicion), 4 (rates), 5 (bans), 6 (admin limits). Section 1 (movement) simplified: no slide/air-jump chains; add car/elevator/teleporter allowances. Drop section 3 shot statistics. |
| `Config/Client.luau` | ADAPT | same | Keep structure (Keys/Gamepad/DefaultSettings/SettingsSchema/Sounds/TouchButtonMin/Validate). New actions and settings (§3.18). |
| `Config/Shop.luau` | PATTERN | same | Keep: `Id = 0` = "Bald verfügbar", `ProductsByKey/ById`, `PassesByKey/ById`, duplicate asserts, `ForbiddenRobuxFields`, `GrantFields`, `Validate`. Drop crates/odds/featured cosmetics. |
| `Lang/init.luau` (205) | **COPY** + edit `FILES` | `Lang/init.luau` | Only the `FILES` table changes (§3.6). |
| `Lang/Core.luau` | ADAPT | same | Keep all `core.*` keys (server uses `core.tooFast`, `core.unknownAction`, `core.invalid`, `core.loading`, `core.error`, `core.noAnswer`, `core.studioNoSave`, `core.studioNoApi`, `core.loadFailed`, `core.dataReset`, `core.settingsSaved`); change `core.gameName`, `core.tagline`, `core.welcome`. |
| `Lang/Admin.luau` | ADAPT | same | Keep generic keys (denied, kicked, banned, unbanned, banList, announce*, abuse*, globalFailed, filterDown, textLen, notSelf, notOwner, studioUser, liveOnly, photoOn/photoOnTouch, dbgTitle, selfTest …). Drop weapon/match/balance keys. |
| `Odds.luau`, `ProgressMath.luau`, `Ballistics/Damage/Hitbox/Spread.luau`, `WeaponModels.luau`, `CosmeticModels.luau` | DROP | – | `Odds` = paid random crates → **forbidden direction** for this game (§9). ProgressMath is shooter XP/MMR (write a new `LicenseMath`). |
| *(new)* | PATTERN | `MarketMath.luau`, `Indicators.luau`, `Format.luau` | Pure `--!strict` modules, Luau-CLI-testable like Util. `MarketMath` = port of `js/market.js` (`generate`, `season`, `tickStep`, `aggregate`, vol regime, jumps). `Indicators` = port of `js/indicators.js` (SMA, EMA, Bollinger, RSI, MACD, VWAP, ATR, Stochastik). `Format` = money/price/percent formatting on top of `Util.FormatNumber`. |

### 1.3 Server (`ServerScriptService.Server`)

| CC file | Verdict | AT file | Notes |
|---|---|---|---|
| `Main.server.luau` (130) | **COPY** | same | Change `PREFIX = "[AKYTEX Tycoon] "` and the `order` list (§2.1). Keep the 4 phases, Remotes-first block, xpcall everywhere, Config boot-validation printout. |
| `Lib/Scheduler.luau` (366) | **COPY verbatim** | same | The ONE Heartbeat. Market tick, tower income, ambient city, autosave all go through it. |
| `Services/Remotes.luau` (72) | **COPY** | same | Only the `export type Remotes` field list changes to the AT RemoteList. |
| `Services/DataService.luau` (744) | **COPY** + new `DEFAULT_DATA` | same | Keep every fix (session lock, 6 load / 4 save attempts, serialized saves, release guard, snapshot auto-save, Studio NoSave for `UserId <= 0`, NoApi detection, kick on live load failure, `Reset` keeps receipts). Rewrite `DEFAULT_DATA` (Cash, Portfolio, Orders, Tower, Licenses, Stats, Quests, Login, Season, Purchases, Flags, Settings, Mod). Add `SavedAt = os.time()` in the final release save (offline income). Never put market candles into player data (4 MB/key limit). |
| `Services/PlayerStateService.luau` (840) | **COPY** | same | Change `LEADERSTATS` (e.g. `Vermögen` as **StringValue** with `Util.FormatNumber`, because `SetLeaderstat` clamps IntValues to ±2^52) and `TUTORIAL_FLAGS`. Everything else verbatim (Handle/Provide/MarkDirty/Notify/Effect/Ready-Gate/Settings schema/Ping attribute). |
| `Services/MonetizationService.luau` (721) | ADAPT (keep core verbatim) | same | Keep verbatim: `Core.HasReceipt/AddReceipt/Sanitize/ProcessReceiptWith`, `waitForData`, `prepare` (all yielding) → `grantProduct` (no yield), `LoadPasses` (3 tries + loading guard), PolicyService (`RandomAllowed`, unknown = restricted, `SetPolicyOverride`, `Debug.ForceRestricted`), `SimulatePurchase` (SIM-GUID through the same path), state keys `Passes`, `RandomAllowed`. Rewrite `Core.BuildGrant` for tycoon products, `BLOCKED_PHASES` → tycoon states (no offer during crash/rally events, order confirmation, tutorial), Party boost → optional server-wide income boost (compliance check §9). |
| `Services/ShopService.luau` (1353) | PATTERN | `ShopService.luau` | Keep the rules: `Grant/Spend` are the ONLY way to change money/ownership, never yield, validate first then apply all-or-nothing, prices only from server Config, `withBusy` per player, `Core.*` pure functions for tests, `metricsEconomy` Source/Sink. Drop crates, loadouts, weapons, cosmetics-per-weapon, featured rotation. |
| `Services/AdminService.luau` (2195) | ADAPT | same | Keep verbatim: owner rule (`computeAdmin`, `isOwnerId`), cache + `IsAdmin` attribute, rate limit BEFORE admin check, denied-log once, `dispatch` (with Runde-2 `p.Parent` guard), `QUIET`, `resolveTargets` (me/all/others/name/prefix/UserId), `filterBroadcast`, Kick/Ban/Unban/BanList/BanHistory/Warn/Freeze/Bring/Goto/Give/PlayerData/Receipts/Regrant/ResetData/SetPower/GiveAll/LockServer/KickAll/ServerInfo/Announce/AdminAbuse/Confetti/GetStats/Flags/DismissFlag/Reports/SimulatePurchase/SimulatePolicy/SkipDay/SetDebug/RunSelfTest, `publishGlobal` (fallback local), `handleGlobal` (every field validated, upper time bound), `startEvent` with `workspace:GetServerTimeNow()`. Drop Pop/Heal/GiveXp-shooter bits, AdminWeapon, Matches/EndMatch/StartMatch/SpawnBot/FillPads, Mutator, LobbyGravity/LobbyLook, balance tab. **Add market actions** (§3.13). |
| `Services/AntiCheatService.luau` (1726) | ADAPT (slim) | same | Keep: suspicion model (weights, decay, review flag, kick), flag/report/ban-log stores (`AT_Mod_v1`), honeypot, `present(p)` guard, `NoteTeleport/Grace/SetAllowance/Exempt/Add/Score/Flags/Snapshot/Reports/AllFlags/AllReports/Dismiss/LogBan/BanLog/MarkUnbanned`, movement budget at 5 Hz staggered. Drop shot statistics (`checkMismatch/checkStats`, Los, Rate). Add allowances for cars/elevators/teleporters/jump pads (§3.14). |
| `Services/LeaderboardService.luau` (623) | ADAPT | same | Keep write/read cadence, change-only writes, bounded name cache, `OnProfileReleasing` write, NoSave/TestPlayer skip, AKYTEX SurfaceGui board builder (constants already AKYTEX). New boards (§3.15). |
| `Services/MetricsService.luau` (217) | **COPY verbatim** | same | Change only Funnel step names in callers. |
| `Services/SelfTestService.luau` (143) | **COPY verbatim** | same | Loads `Server/Tests/*`. |
| `Services/GraphicsService.luau` | PATTERN | `GraphicsService.luau` | `clearOld` own classes before building (no doubled Bloom/Atmosphere). AT needs day/night + Future-light budgets → rewrite. |
| `Services/RewardService.luau` | PATTERN | `RewardService.luau` | Daily/weekly quests, login streak, playtime per UTC day, codes, `Track()` via pcall. **Drop the Glücksrad (SpinWheel)**. |
| `Services/CommunityService.luau` | PATTERN | – | `Announce(key,args,filter)` (localized system announcement = Effect "Announce" without UserId → Toast), friend-in-server hint via `IsFriendsWithAsync` (pcall, 1× per friend/session). |
| `Tests/CoreTests.luau` | ADAPT | same | Keep Util/Net/Spring/Lang/Config/DEFAULT_DATA/Scheduler tests; replace Net round-trips with Quotes/Candles. `EconomyTests` PATTERN for receipts/grants. |
| all combat/match/bot/world services | DROP | – | Weapon/Combat/Projectile/History/Replication/Character/Bot/Range/Match/Queue/Arena/Lobby/Balance/Progression(MMR). |

### 1.4 Client (`StarterPlayerScripts.Client`)

| CC file | Verdict | AT file | Notes |
|---|---|---|---|
| `Main.client.luau` (598) | ADAPT | same | Keep: ScreenGui (+ UIScale via UI.Init) + unscaled TouchGui (`ScreenInsets = DeviceSafeInsets`), `ctx` backpack, `load()` in pcall, Init-all-then-Start-all with the Runde-2 fix, `RequestFull/Request`, State sticky-merge + `changed` list/set, Notify→Toast, Effect→`Effects.Play` + `Effect:<Name>` hook, admin modules on `IsAdmin` attribute, ONE PreRender loop (`FRAME_MODULES`) + 1-s tick (`TICK_MODULES`), GetFull after 5 s, CoreGui Backpack/Health off (retry), welcome toasts per input type. Rename GUIs `AkytexTycoonUI`/`AkytexTycoonTouch`. Drop Match/Combat/Armed/Popped/World-slot logic and LiveBalance (or keep as `LiveTuning`). |
| `Modules/UI.luau` (1963) | **COPY** + small edits | same | The AKYTEX UI kit (§4). Edit: blur name `AkytexTycoonWindowBlur`, replace the `World` hook (`MATCH_TOAST_TOP`) with a tycoon offset (e.g. when the ticker bar is visible), optionally add FontFace tokens (§4.1). |
| `Modules/Hooks.luau` (122) | **COPY verbatim** | same | |
| `Modules/Controls.luau` (566) | ADAPT | same | Keep CAS engine (BindActionAtPriority, no CAS touch buttons, Emit for virtual input, `Input()` live from PreferredInput, window open → context "Menu", `Input` hook, text-box guard). Replace `ACTIONS`/contexts/cycle logic (§3.18). |
| `Modules/TouchControls.luau` (710) | PATTERN | same | Keep: lives in unscaled TouchGui, ≥ `Config.Client.TouchButtonMin` (64) px, left-hand mirror, button scale 90–130 %, Controls.Emit, AKYTEX glass discs. Rewrite buttons (Terminal, Tower, Sprint/Interact) – no fire/aim/slots. |
| `Modules/Hud.luau` (523) | ADAPT | same | Keep: glass stats card (bottom-left, moves to top-left on Touch live), flowing counters, big primary button bottom centre, right square buttons `AddRightButton(icon, captionKey, color, order, onClick)`, FPS/Ping corner, `SetVisible`, Refresh/Tick split, `CoinAnchor/PulseCoins` (→ cash). Replace Level/XP/Coins/Gems/Keys with Cash / Vermögen / Lizenz-XP; PLAY → **TRADE** (opens Terminal window). |
| `Modules/Settings.luau` (786) | ADAPT | same | Schema-driven window, switches/sliders/enums, debounced `SaveSettings` (0.8 s), auto "ReducedFx" after 5 s < 35 FPS, info/rules/appeal section. New sections (§3.18). Drop crosshair preview. |
| `Modules/Effects.luau` (1133) | ADAPT | same | Keep `Announce` (owner banner: avatar + Accent name + self-drawn blue check, no box, ~8 s; no sender → Toast), `AdminWarn`, `Confetti`, `LevelUp`, `CoinFly`→cash fly, `Shake`, `Flash`, `Burst/Ring/Puff`, `SetHidden/IsHidden`, own unscaled overlay. Replace lobby notices with tycoon events (Crash, Rally, IPO, MoneyRain, TowerDone, AdminAbuse banner). |
| `Modules/Sfx.luau` (603) | **COPY engine**, new roles | same | Recipe engine (layers, PlaybackRegion, EQ/Echo/Distortion, voice pools, SoundGroups, Config ID override 0 = recipe). Only the 9 FILES paths (docs/ASSETS.md). New roles §3.18. |
| `Modules/Highlights.luau` (241) | **COPY verbatim** | same | 31-highlight budget broker (selection outline of floors/furniture, admin ESP ≤ 20). |
| `Modules/AdminPanel.luau` (2015) | ADAPT | same | Keep framework (window 720×600 "Admin", sidebar `navItem`, target field, status pill, `needsConfirm` 5 s, `slider`, `cycler`, `chip`, `statTile`, `rowCard`, `rowActions`, `outputBox`, spectate + key X, HUD button order 99 + key P). New tabs §3.13. |
| `Modules/AdminTools.luau` (648) | ADAPT (small) | same | Keep only local Noclip/Speed/Jump application and optional ESP via Highlights. Drop aimbot/silent aim/triggerbot/taint shield. |
| `Modules/Fly.luau` (233) | **COPY verbatim** | same | `CanFly` attribute, key G, Shift boost, reports `SetPower{CanFly}`. |
| `Modules/PhotoMode.luau` (228) | **COPY** | same | Hides ctx.Gui, TouchGui, CoreGui (restored), ProximityPrompts, Effects; long-press exit on touch (Runde 2). `tryCall` tolerates missing Viewmodel/CombatHud. |
| `Modules/DebugOverlay.luau` (432) | ADAPT | same | Keep F8 glass card, 1/s poll only while visible, Scheduler stats + top costly jobs, memory, FPS/ping, fallback theme. Replace arena/bot/projectile/hitbox lines with market tick cost, quotes/s, towers, part count, monitor count. |
| everything else (FpsCamera, Viewmodel, Movement, WeaponClient, CombatFX/Hud, AimAssist, Replication, MatchUI, QueueUI, Spectate, Scoreboard, BotAnimator, Training, Locker, CrateReveal, Finishers, ArenaLook, Tutorial, Progress, Shop, ChatClient) | DROP / PATTERN | – | `Shop.luau` + `Progress.luau` are useful only as layout references for AKYTEX windows. `Tutorial.luau` = PATTERN for step overlays. `ChatClient` = PATTERN for VIP chat tags. |

### 1.5 Docs

| CC doc | Use in AT |
|---|---|
| `docs/STYLE-AKYTEX.md` | **COPY** and extend: world = also AKYTEX (glass, marble, neon accents), not "bunt" like CC arenas. Add chart rules (§5) and the website brand sheet (§8). |
| `docs/ASSETS.md` | Reference as is (11 built-in sounds, 9 usable; particle textures; fonts). Add the FontFace families from §4.1. |
| `ANLEITUNG.md` | PATTERN for the German beginner guide (Mac keys table, bold click paths, Fahrplan table, glossary, Fragebogen chapter – rewrite the answers for AT, §9). |
| `docs/KOPIERVORLAGEN.md`, `TESTPLAN.md`, `ADMIN-WUENSCHE.md` | PATTERN (copy templates for passes/products, Solo + "2 Players" test plan, admin wishes). |

---

## 2. Architecture contract to keep

### 2.1 Server
- `Main.server.luau`: Remotes module first (clients wait for it) → Phase 1 require all (xpcall, `FindFirstChild`, no 10-s wait) → Phase 2 `Init(Services)` in order (build world, set references, register `Provide`/`Handle`) → Phase 3 `Start()` for all except DataService (events, remote handlers, Scheduler jobs) → Phase 4 `DataService.Start()` LAST (all OnProfileLoaded callbacks already registered) → `Config.Validate()` warnings (max 25) + "Server gestartet ✅".
- Each service: `local X = {}; local Services: any = nil; function X.Init(services) Services = services end; function X.Start() … end; return X`. Cross-service calls via `Services.Y.Fn` or the `try/call(name, fnName, …)` helper (pcall, optional service). The contract checker understands both forms.
- Per-player tables are cleared in `PlayerRemoving`; limiters `.Clear(p)`.
- No `while` loop per player (CC Muss-Regel 9): everything periodic is `Scheduler.Every/Staggered`. Callbacks never yield; yielding work → `task.spawn` inside the job (see DataAutoSave).
- Suggested AT order (adapt in the spec): `DataService, MonetizationService, PlayerStateService, GraphicsService, CityBuilder, PlotService, MarketService, OrderService, TowerService, EventService, ProgressionService, RewardService, GrowthService, ShopService, AntiCheatService, AdminService, LeaderboardService, MetricsService, SelfTestService`. Avoid naming our services like Roblox services (`SocialService`, `TextService` …) – confusing next to `game:GetService`.

### 2.2 Client
- `ctx` (C7.1): `Player, Config, Lang, Util, Net, Types, Remotes, Gui, TouchGui, State, StateTime, Hooks, UI, Windows, Modules` + `Request(action,arg?) -> reply|nil`, `RequestFull(action,arg?,silent?) -> {Ok,Message?,...}`, `Toast(text,kind?)`, `T(key,...)`, `Lang_()`.
- Module form: `Init(ctx)` (build UI, register windows, bind hooks), `Start()`, optional `Frame(dt)` (only modules listed in `FRAME_MODULES`) and `Tick()` (1 s, `TICK_MODULES`). Init failure → module removed (Runde 2).
- Remotes are connected AFTER all modules started (Roblox queues packets → nobody misses the first full State).
- Hooks used: `State(state, changed)`, `Notify(text, kind)`, `Effect:<Name>(strength, data)`, `WindowOpened/WindowClosed(name)`, `Settings(settings)`, `Input(kind)`, `PhotoMode(on)`. Add AT hooks (`Quotes`, `Market:<Kind>`, `Tower:<Kind>`) fired by Main.client.
- Suggested AT client order: `UI, Hooks, Sfx, Effects, Highlights, Controls, TouchControls, Hud, Settings, Quality, WorldLook, CityLife, Ticker, Monitors, Terminal, Portfolio, Tower, Build, News, Quests, Shop, Boards, Tutorial`; admin: `AdminPanel, AdminTools, Fly, PhotoMode, DebugOverlay`. `ChartView` is a library module required by Terminal/Monitors (not started).

---

## 3. Exact APIs of reusable modules

### 3.1 `Shared/Util` (COPY, `--!strict`, pure)
```
Util.IsFinite(n: any): boolean                       -- kein NaN/±inf/String
Util.IsFiniteVector(v: any): boolean
Util.FormatNumber(n: number): string                 -- 1150->"1.15K", math.huge->"MAX", -0.5->"0", Suffixe bis "Dc" (1e33)
Util.FormatTime(seconds: number): string             -- "3:07" bzw. "5h 12m"
Util.DeepCopy<T>(value: T): T
Util.Reconcile(target, template)                     -- fehlende Felder ergänzen
Util.Snapshot<K,V>(t: {[K]: V}): {K}                 -- Schlüssel-Liste (sicher iterieren)
Util.WeightedPick<T>(list: {T}, weightOf: ((T)->number)?, rng: Random?): T?   -- Gewicht 0/NaN nie
Util.RateLimiter(maxCalls, perSeconds, clock?) -> { Check(key): boolean, Clear(key) }
Util.TokenBucket(capacity, refillPerSecond, clock?) -> { Take(key, n?): boolean, Clear(key) }
Util.UtcDay(now?): number      Util.IsoWeek(now?): number (JJJJWW)
Util.SetDayOffset(n)           Util.GetDayOffset(): number      -- Debug "SkipDay"
Util.Hash(s: string): number   -- FNV-1a 32 Bit, 0..2^31-1 (Seeds: Util.Hash(companyKey .. day))
```

### 3.2 `Shared/Spring` (COPY, `--!strict`)
```
Spring.new(initial: Vector3, speed: number, damper: number): SpringObj
spring:Step(dt): Vector3        -- dt auf 0..1/30 geklemmt, feste Unterschritte ≤ 1/240 s, NaN-Netz
spring:Impulse(v: Vector3)      spring:SetTarget(v: Vector3)
Felder: Position, Velocity, Target, Speed (rad/s), Damper (1 = kritisch)
```

### 3.3 `Shared/Net` (ADAPT)
Kept: `Net.RemoteList: {{Name, Class}}`, `Net.GetRemotes(): {[string]: Instance}` (client: `ReplicatedStorage.Remotes`, `WaitForChild` 10 s per name, cached only when complete), types `RemoteClass = "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent"`.

Proposed AT RemoteList (names are the contract; checker validates them):

| Name | Class | Direction / payload |
|---|---|---|
| `Notify` | RemoteEvent | S→C `(text, kind)` – already localized (COPY) |
| `State` | RemoteEvent | S→C `(partial, full)` sticky merge (COPY) |
| `Effect` | RemoteEvent | S→C `(name, strength, data?)` (COPY) |
| `Request` | RemoteFunction | C→S `(action, arg?)` → Reply (COPY) |
| `Admin` | RemoteFunction | C→S `(action, args?)` → `{Ok, Message, Data}` (COPY) |
| `Quotes` | UnreliableRemoteEvent | S→C buffer, all live prices, 1–2 Hz (§5.3). CC keeps unreliable packets ≤ 871 B (engine limit ≈ 900 B). |
| `Market` | RemoteEvent | S→C `(kind, data)`: candle close, news, event start/end, IPO, halt |
| `GrantCash` | RemoteEvent | **Honeypot** (CC `GrantCoins`): created, never fired by our code, AntiCheat +100 + kick |

### 3.4 `Shared/Types` (ADAPT)
Keep verbatim: `Lang = "de" | "en"`, `NotifyKind = "Info" | "Success" | "Error" | "Event" | "Alarm" | "Announce"`, `Reply = { Ok: boolean, Message: string?, [string]: any }`, `PlayerData = { [string]: any }`. Pure type module returning `{}`.

### 3.5 `Shared/Config/init` (ADAPT)
- Sections to keep with identical semantics: `Config.GameName`, `Config.Version`, `Config.Admin = { OwnerIsAdmin = true, StudioIsAdmin = true, StudioAllPlayersAdmin = false }` (keep false → "Test → 2 Players": Player1 (-1) admin, Player2 (-2) NOT admin → denial path testable), `Config.Tech` (DataStoreName, DataVersion, MessagingTopic, AutoSaveSeconds 90, AutoSaveStagger 0.5, LoadAttempts 6, SaveAttempts 4, LockStaleSeconds 1800, BindToCloseSeconds 25 (≤ 29), ReceiptKeep 60, StateFlush 0.2, FullStateEvery 20, LiveStore, StatsStore, ModStore, Shards 8, BoardPrefix, BoardWriteSeconds 300, StatsFlushSeconds 600, PingAttrEvery 2), `Config.Studio = { NoSave = true, SelfTest = true }` (to test offline income/persistence in Studio: NoSave false + "Studio Access to API Services"), `Config.Debug = { LogRejects?, ForceRestricted = false }`.
- Child loader: `CHILDREN` list + `Config.<Name> = loadChild("<Name>")`; missing child → `{}` + Validate error, rest runs. Every child may export `Validate(Config): {string}`.
- `Config.Validate(): {string}` = children + `validateCore()` (checkNumber/checkColors helpers). SelfTest asserts it is empty.
- Config replicates to every client → **no secrets**.

### 3.6 `Shared/Lang` (COPY + `FILES`)
```
Lang.T(lang, key, ...): string            -- string.format in pcall; Fallback Englisch -> Schlüssel
Lang.Pick(lang, {de, en}): string         -- Config-Anzeigenamen
Lang.For(p, override?): "de" | "en"       -- Einstellung "de"/"en", sonst LocaleId "de…" -> "de", sonst "en"
Lang.Missing(): {string}                  -- fehlende Schlüssel je Sprache + Ladefehler (SelfTest: leer)
Lang.Has(key): boolean
```
Each file returns `{ de = {[key]=text}, en = {[key]=text} }`; prefix enforced, duplicates warned. Proposed AT `FILES`: `Core core.` · `World world.` · `Market mkt.` · `Trade trade.` · `Tower tower.` · `Events evt.` · `Admin admin.` · `Progress prog.` · `Shop shop.`/`item.` · `Ui ui.` · `Tutorial tut.`. Mirror the same list in `contract_check.py` `LANG_PREFIX`.

### 3.7 `Server/Lib/Scheduler` (COPY)
```
Scheduler.Every(name, hz, fn(dt)) -> stop()                 -- z. B. MarketTick 2 Hz, TowerIncome 1 Hz
Scheduler.EveryFrame(name, fn(dt)) -> stop()
Scheduler.Staggered<T>(name, hz, items: () -> {T}, fn(item, dt)) -> stop()   -- pro Item hz-mal/s, über Frames verteilt
Scheduler.Stats(): { [name]: { AvgMs, MaxMs } }  (+ "_Total"; Fenster 5 s)
```
Rules: pcall per callback, error log ≤ 1 per 10 s per name, frame dt clamped 0..0.25, every/staggered dt ≤ max(0.25, 2/hz), yielding callback is skipped until it returns (warning), duplicate names get `#2`, max 200 jobs.

### 3.8 `Server/Services/Remotes` (COPY)
`require(script.Parent:WaitForChild("Remotes"))` → `Remotes.<Name>` typed; idempotent creation under `ReplicatedStorage.Remotes`; wrong class replaced with warn; wrong `Remotes` object renamed `Remotes_Alt`.

### 3.9 `DataService` (COPY)
```
DataService.Get(p): PlayerData?             DataService.IsLoaded(p): boolean
DataService.IsNoSave(p): boolean            DataService.NoSaveReason(p): "Config" | "TestPlayer" | "NoApi" | nil
DataService.OnProfileLoaded(cb(p, data))    -- task.spawn je Callback; später registriert -> nachgereicht
DataService.OnProfileReleasing(cb(p, data)) -- pcall, VOR dem letzten Speichern (Bestenliste, Offline-Zeitstempel)
DataService.Save(p): boolean                -- yieldet; NoSave -> true; während Release -> false
DataService.Reset(p): boolean               -- frischer Stand, behält Purchases.Receipts/Starter/PassSeasons/FirstPack
DataService.Migrate(data)                   DataService.DefaultData(): PlayerData
DataService.Profiles                        -- {[Player]: Profile} (nur lesen)
```
Rules: dictionaries with **string keys only** (JSON); migrate THEN reconcile; `sanitize` resets wrong types/NaN to defaults (also inside lists of records via the first pattern element); `Reset` keeps the same table (other services hold references).

### 3.10 `PlayerStateService` (COPY)
```
PlayerStateService.Handle(action, fn(p, arg) -> Reply, opts?)   -- opts { Rate? = 8, Per? = 1, NeedsReady? = true }
  Ablauf: p.Parent-Guard -> globales Limit (Config.Security.Rates.Request = {8,1}) -> action-Typ -> Handler -> Aktions-Limit
          -> Ready-Gate ("core.loading") -> pcall(fn) -> normalize (Ok bool, Message string)
PlayerStateService.Provide(key, fn(p) -> any)    -- nie yielden; nie nil für "leer" (false/{}), Client behält fehlende Schlüssel
PlayerStateService.MarkDirty(p, ...keys)         -- ohne keys = voller State; Flush alle 0.2 s, voll alle 20 s
PlayerStateService.Notify(p, langKey, args?, kind?)       NotifyAll(langKey, args?, kind?, filter?)
PlayerStateService.NotifyRaw(p, text, kind?)              -- Text schon lokalisiert/gefiltert, max 500 Zeichen
PlayerStateService.Effect(p, name, strength, data?)      EffectAll(name, strength, data?, filter?)
PlayerStateService.IsReady(p)   OnReady(cb(p))   LangOf(p): "de"|"en"   SetLeaderstat(p, name, value)
Eigene Aktionen: "GetFull" (1/5 s), "SaveSettings" (2/s, Schema-geklemmt), "TutorialFlag" (1/s)
Eigene State-Schlüssel: Settings, Flags, Server = { Version, Studio, NoSave }; Player-Attribut "PingMs"
```
Ready = profile loaded → passes loaded (`MonetizationService.LoadPasses`) → policy request started → `readyPlayers[p]` → full State next flush → OnReady callbacks → Studio NoSave toasts after 2 s.

### 3.11 `MonetizationService` (ADAPT, core COPY)
```
MonetizationService.HasPass(p, key): boolean
MonetizationService.LoadPasses(p)                 -- 3 Versuche je Pass, loading-Guard, danach ShopService.RefreshPlayer
MonetizationService.RandomAllowed(p): boolean?    -- nil = unbekannt = eingeschränkt behandeln
MonetizationService.SetPolicyOverride(p, allowed?)
MonetizationService.SimulatePurchase(p, productKey): (boolean, string)   -- gleicher Weg wie ein echter Kauf
MonetizationService.TryOffer(p, offerKey): boolean                      -- max. 1 Angebot pro Sitzung
MonetizationService.Core.ProcessReceiptWith(receipt, env): Enum.ProductPurchaseDecision
  env = { FindPlayer, Product, WaitData (≤ 60 s), CurrentData, Prepare (darf yielden), Grant (darf NICHT yielden),
          Save, Wait }
```
Receipt flow (keep exactly): callback set early in Start · unknown product → NotProcessedYet (+warn "in Config eintragen") · wait ≤ 60 s for the profile · same PurchaseId in progress → wait ≤ 60 s, re-check receipts · receipt present → Granted · Prepare (yield) → verify `CurrentData == data` and no receipt → Grant + AddReceipt (last 60) + RobuxSpent in ONE non-yielding block → Granted only after `DataService.Save` succeeded (else NotProcessedYet; the receipt in data prevents a double grant).

### 3.12 `ShopService` (PATTERN)
Signatures to mirror: `ShopService.Grant(p, grant, reason): boolean` (no yield, validate → apply), `ShopService.Spend(p, currency, amount, reason): boolean`, `ShopService.Core.{Ensure, Balance, Spend, ValidateGrant, ApplyGrant}` (pure, tested in `EconomyTests`), `withBusy(handler)` per player, `RefreshPlayer(p)` (attributes VIP/Supporter + MarkDirty). `Core.Spend` only accepts positive integers → **store money as integers** (whole currency units or cents) and positions as integer share counts; prices stay floats only inside the market.

### 3.13 `AdminService` (ADAPT)
```
AdminService.IsAdmin(p): boolean     -- Live: CreatorType == User and UserId == CreatorId and CreatorId ~= 0
                                     -- Studio: StudioIsAdmin and (UserId > 0 or UserId == -1); -2 nie Admin
AdminService.Power(p, name): any     -- nil, wenn kein Admin
AdminService.EventMult(kind): number -- Admin-Abuse aktiv -> 2 (CC: "Xp" | "Coins"; AT: "Income" | "Xp" …)
AdminService.IsServerLocked(): boolean
Remote "Admin": (action, args) -> { Ok, Message, Data }; Rate 12/1 s VOR der Admin-Prüfung
```
- Group owner: CC returns false for group-owned games (`CreatorType == User` only). If the owner ever publishes under a group, extend `isOwnerId` with `GroupService:GetRolesInGroupAsync`/owner rank (not `GetRankInGroup`).
- Global message kinds (MessagingService `AT_Global`, sender also receives): keep `Announce {Text, UserId, Name}`, `AdminAbuse {Until, …boosts}`; add `MarketEvent {Kind = "Crash"|"Rally"|"Pump"|"Dump"|"Halt"|"Resume"|"IPO"|"News", Company?, Strength, Until, Id}` – validate every field + `Until ≤ now + max`, dedupe by `Id`.
- Ban (keep exactly): presets `1h/1d/7d/30d/perm`, `Duration = -1 or ≥ 60`, `DisplayReason ≤ 400`, `PrivateReason ≤ 1000` (with anti-cheat snapshot), `ApplyToUniverse = true`, `ExcludeAltAccounts = false`, never self/owner/admin/`UserId ≤ 0`, ≤ 50 ids, log to AntiCheat BanLog; BanHistory live only.
- Fairness (owner wish 9): every admin market action sets a season "taint" window (`EventService.MarkAdminWindow(from, to)`) so return-based season boards ignore or flag gains made inside it (CC analogue: `MatchService.Taint` + "ADMIN-SHOW" chip).
- AdminPanel tabs for AT: **Spieler** (list, kick/ban/unban/ban list, freeze, bring/goto, spectate, player data, receipts/regrant, reset) · **Markt** (crash/rally, push/dump company, insider news, pause/resume, IPO, volatility slider) · **Events** (announce local/global, admin abuse 2× income for X min, money rain, confetti) · **Geld & Items** (give cash/items/floors/licenses, give all) · **Kräfte** (fly, noclip, speed, invisible, photo mode, visit any tower) · **Statistik** (online, money supply, most traded, purchases, suspicious players) · **Moderation** (flags, reports, dismiss) · **Debug** (SkipDay, SimulatePurchase/Policy, SetDebug, RunSelfTest, F8).

### 3.14 `AntiCheatService` (ADAPT)
```
AntiCheatService.NoteTeleport(p, cf)                          -- 1 s Gnade nach Server-Teleport (Aufzug, Tower-Besuch)
AntiCheatService.Grace(p, kind, seconds, maxSpeed?)            -- "Impulse" | "Launch" | "Teleport"
AntiCheatService.SetAllowance(p, { SpeedMult?, VerticalMult?, AirJumps? })   -- ersetzt die alte Erlaubnis
AntiCheatService.Exempt(p, seconds)                            -- z. B. im Auto/Fahrstuhl (0 = beenden)
AntiCheatService.Add(p, reason, points, evidence?)   Score(p)   Flags()   Snapshot(p)   Reports()
AntiCheatService.AllFlags(days?)  AllReports(days?)  Dismiss(id)  LogBan(entry)  BanLog()  MarkUnbanned(userId)
Request "Report" (3 pro 10 min) bleibt.
```
Economy cheats are prevented by server authority (prices, fills, income all server-side), not by detection; movement checks only protect tower privacy/locked doors. Anything hidden or opened **locally** (own-tower doors, VIP doors) must be ignorable in the noclip ray test (CC Runde 2: crate machine false positive).

### 3.15 `LeaderboardService` (ADAPT)
`LeaderboardService.Submit(p)` – write changed values ≥ 300 s apart and on release; read top 10 per board every 300 s (0.5 s stagger); `OrderedDataStore "AT_LB_<Name>_v1"`, weekly boards `"AT_LB_<Name>_<IsoWeek>"`; values **integers 0..9e15** → encode return % as basis points plus a fixed offset (no negatives), net worth capped/clamped; Studio NoSave and `UserId ≤ 0` never write; new #1 in this server → announcement. AT boards: Vermögen (net worth), Saison-Rendite (return %, taint-filtered), Wochen-Rendite, Tower-Höhe, Skill-Score.

### 3.16 `MetricsService` (COPY)
```
MetricsService.Funnel(p, step, name)        -- 1× pro Schritt und Sitzung (Schritt 1 "Joined" automatisch)
MetricsService.Economy(p, flow, currency, amount, balance, txType, sku?)   -- "Source" | "Sink"
MetricsService.Progression(p, path, status, level)    -- "Start" | "Complete" | "Fail"
MetricsService.Custom(p, name, value?, fields?)       -- bis 3 Custom-Fields
```
Throttle: token bucket 30 + 0.5/s per player (Roblox ≈ 120 + 20 × players events/min/server).

### 3.17 `SelfTestService` (COPY)
`SelfTestService.Run(): (passed, total)`, `SelfTestService.LastReport(): {Passed, Total, Failures, At}?`; auto in Studio 3 s after start when `Config.Studio.SelfTest`; prints `[SelfTest] n/n PASS`. Tests: `Server/Tests/*.luau` returning `{ [name]: (Services) -> () }`.

### 3.18 Client modules
```
Hooks.On(name, fn) -> disconnect   Hooks.Once(name, fn)   Hooks.Fire(name, ...)   Hooks.Count(name?)
Controls.Bind(action, fn(state: "Begin"|"End"|"Change", input?), priority?) -> unbind
Controls.IsDown(action)   Controls.Input(): "KBM"|"Gamepad"|"Touch"   Controls.SetContext(c)   Controls.Context()
Controls.Emit(action, state, source?)                        -- virtuelle Eingabe (Touch-Knöpfe)
TouchControls.Show(set)   (+ SetAutoFire/SetSlots/SetAmmo = Shooter, DROP)
Hud.AddRightButton(icon, captionKey, color, order, onClick): UI.Button   Hud.SetVisible(on)
Hud.CoinAnchor(): Vector2?   Hud.PulseCoins(amount?)   Hud.Refresh(state)   Hud.Tick()
Settings.Get()   Settings.Set(path, value)   Settings.Fps()   Settings.Open()   Settings.Frame(dt)   Settings.Tick()
Effects.Play(name, strength, data?)   Effects.Flash(color, text?)   Effects.Burst(pos, color, amount, flash?)
Effects.Ring(pos, color, size, time?)   Effects.Puff(pos, color, amount)   Effects.Shake(strength)
Effects.Confetti(amount?)   Effects.SetHidden(on)   Effects.IsHidden()
Sfx.Play(role, pos?, { Volume?, Speed? }?)   Sfx.Has(role)   Sfx.Duck(amount, seconds)   Sfx.SetMusic(kind?)
Sfx.ApplySettings(settings?)
Highlights.Acquire(owner, adornee, { Outline?, Fill?, FillTransparency?, Depth? }): handle?   (nil bei vollem Budget 31)
Highlights.Update(handle, props)   Highlights.Release(handle)   Highlights.ReleaseOwner(owner)
Highlights.Count()   Highlights.CountOwner(owner)   Highlights.Pulse(owner, seconds)
AdminPanel.Toggle()   Fly.Toggle()   Fly.IsFlying()   PhotoMode.Toggle()   PhotoMode.IsActive()   DebugOverlay.Toggle()
```
- **Controls** AT actions (proposal): `Interact, Terminal, Portfolio, Tower, Shop, Quests, Menu, Sprint, CameraZoom, ChartTf, ChartType, AdminPanel, Fly, Spectate, Debug, PhotoMode`; contexts `World | Vehicle | Terminal | Menu | Spectate`; keep `ALWAYS = { Menu, AdminPanel, Fly, Spectate, Debug }`.
- **Settings** AT schema (proposal): `Lang`, `Sfx/Music/Ui` volumes, `Quality` (auto/low/medium/high/ultra), `ReducedFx`, `ChartType` (candles/hollow/line), `ChartTf`, `Indicators` (table of booleans), `NumberStyle` (`1.2K` / `1.200`), `Colorblind` (Up/Down → Accent/Orange), `Shake`, `ShowNet`, `TickerBar`, `NotifyNews`.
- **Sfx** AT roles (built-in files only): `UIClick/UIHover/UIError` (keep), `Buy` (Tick 1.26→1.5), `Sell` (Tick 1.5→1.26), `Profit` (Win arpeggio), `Loss` (Lose), `CashRegister` (Land 3.0 + Tick 2.0), `TickerTick` (Tick 2.2, vol 0.15), `MarketBell` (Tick 1.0/1.26/1.5 + echo), `CrashAlarm` (Tick 0.841/0.667 repeated + distortion), `RallyFanfare` (LevelUp), `ElevatorDing` (Tick 2.0 + echo), `Construct` (Land 0.8), `MoneyRain` (Tick random 1.5–2.5).

---

## 4. The AKYTEX UI kit (`Client/Modules/UI.luau`) – complete API

### 4.1 Tokens and fonts
`UI.Theme` (never hard-code colours in client code):

| Token | Hex | Use |
|---|---|---|
| `Bg` / `Bg2` | #0b0f17 / #0f141d | full surfaces, bar backs |
| `Surface` (= `Panel`) | #121824 | windows (T 0.08), HUD panels (T 0.12) |
| `Surface2` (= `PanelLight`) | #1a2130 | cards, rows, text boxes |
| `Hover` | #1f2838 | hover |
| `Border` | #1f2937 | 1-px strokes, dividers, chart grid |
| `Text` / `Text2` (= `SubText`) / `Muted` | #e6ecf5 / #aab4c3 / #7d889a | text levels |
| `Accent` (= `Blue`) / `AccentDeep` | #4f8cff / #2962ff | primary, focus, progress |
| `Up` (= `Green`, `Cash`) | #22c55e | gains, bullish candles |
| `Down` (= `Red`) | #ef4444 | losses, bearish candles, errors |
| `Warn` (= `Yellow`) | #eab308 | warnings, premium |
| extra | `Orange` #f59e0b · `Purple` #8b5cf6 · `Pink` #ec4899 · `Gold` #facc15 · `Cyan` #22d3ee · `Gray` = Muted · `Black` | accents only |

`UI.Fonts = { Main = BuilderSansBold, Body = BuilderSans, Strong = BuilderSansExtraBold, Heading = Michroma, Number = TitilliumWeb, Banner = Michroma, Pop = BuilderSansExtraBold }`, `UI.Font = BuilderSansBold`. Legacy fonts (FredokaOne/LuckiestGuy/Bangers/Gotham*) are auto-replaced in `UI.Create/Label/TextBox`.

**Recommended additions for AT (closer to the website's Manrope/Unbounded, all built-in, VERIFIED in rbxManifest 0.742 `content/fonts/`):**
- `BuilderExtended` (Regular/SemiBold/Bold .otf) – wide geometric display face ≈ **Unbounded** → logo, window titles, big numbers: `Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)`.
- `BuilderMono` (Light/Regular/Bold) – tabular digits for **prices, P/L, axes, order book** (no jitter while ticking): `Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Regular)`.
- `Montserrat` (Regular/Medium/Bold/Black) ≈ **Manrope** for body text if wanted.
- These are NOT in `Enum.Font` → set `TextLabel.FontFace`, not `.Font`. Add `UI.Faces = { Display, Mono, Body }` and let `UI.Label` accept `props.FontFace`. Umlauts/Greek "Λ" in these files are **UNVERIFIED** → check in Studio; fallback Michroma/TitilliumWeb.

### 4.2 Motion (iOS-like, same as the website)
Kit constants: hover 0.12 s Quad Out · press 0.08 s → scale 0.97 + colour flash (+16 %) · release 0.3 s **Back Out** (light spring) · window open fade 0.18 s Quint Out + scale 0.96→1 in 0.26 s Quint Out + slide 8 px from below · close 0.14 s Quad In · blur 9 behind windows (in 0.22 s Quart Out) · bar fill 0.35 s Quart Out · pulse 0.3 s Quint Out · toast in 0.22 s Quint Out / out 0.2 s Quad In · counters exponential approach `alpha = 1 - exp(-t*7)` at ≤ 30 Hz.

Website → Roblox mapping (for new AT animations):

| Website token | Value | Roblox equivalent |
|---|---|---|
| `--ease-ios` | `cubic-bezier(0.32, 0.72, 0, 1)` | `TweenInfo.new(d, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)` (or Exponential Out) |
| `--ease-out` | `cubic-bezier(0.22, 1, 0.36, 1)` | Quart/Quint Out |
| `--spring` | overshoot ≈ 10.8 %, used 0.5–0.7 s | `Spring.new(v, speed ≈ 25–30, damper ≈ 0.58)` (ζ from overshoot) or `TweenInfo(0.5, Back, Out)` |
| `--spring-soft` | overshoot ≈ 4.7 %, used ~1.4 s (needle) | `Spring.new(v, speed ≈ 8–12, damper ≈ 0.70)` |

### 4.3 Primitives
```
UI.Init(ctxOrGui)        -- ScreenGui oder ctx (nimmt ctx.Gui); RootScale = clamp(min(W/1280, H/760), 0.55, 1.15),
                         -- Toast-Spalte, Modal-Knopf, ProximityPrompt-Attribut "Window" öffnet Fenster
UI.Frame(dt)             -- vom einen PreRender-Loop (Zähler)       UI.Start()      UI.Root: ScreenGui?
UI.Create(className, props?, children?): Instance     -- Parent zuletzt gesetzt
UI.Corner(radius? = 12)  UI.Stroke(color?, thickness?)   -- schwarz/nil = 1-px Border; farbig max 2 px
UI.TextStroke(thickness?)                                -- feine Kontur über der 3D-Welt (T 0.5)
UI.Gradient(top, bottom, rotation? = 90)   UI.ButtonSequence(color): ColorSequence (dezent)
UI.FormatMult(v): string   UI.FormatSteps(v, formatNumber): string   UI.Upper(text): string (ä/ö/ü -> Ä/Ö/Ü)
UI.Label(props): TextLabel     -- TextScaled + UITextSizeConstraint(MaxText = 28), props.Outline = feine Kontur
UI.TextBox(props): TextBox     -- Surface2, Ecke 10, Fokus = Accent-Rahmen
```

### 4.4 Buttons
`UI.Button(props, onClick?) -> { Frame, Button, Label, Sub?, Stroke, SetText, SetSub, SetColor, SetVariant }`
props: `Name, Size (120×40), Position, AnchorPoint, LayoutOrder, Parent, Visible, ZIndex, Text, Sub, Variant, Color, MaxText (22), SubMax (15), Corner (12, clamped 6–14), Wrap, Silent`.

| Variant | Look | Use in AT |
|---|---|---|
| `Primary` (default) | Accent fill, white text | TRADE, Kaufen-Bestätigen neutral, Etage bauen |
| `Secondary` | Surface2 + Border | normal actions, timeframe chips |
| `Success` | Up fill | **KAUFEN / Long** |
| `Danger` | Down fill | **VERKAUFEN / Short**, Ban |
| `Ghost` | transparent, Text2 | ✕, tertiary |
| `Premium` | white × Warn→Orange gradient, dark text | Robux offers |
| `Muted` | Surface2 T 0.25, Muted text | locked/disabled |
| `Custom` | any `Color` not matching a token → full fill in that colour | sector colours |

`Color` without `Variant` maps tokens → variant (Accent/AccentDeep/Orange → Primary, Down → Danger, Up → Success, Warn/Gold → Premium, Muted → Muted, Surface*/Hover/Bg* → Secondary). Built-in: hover sound (≥ 0.08 s gap), click sound, **busy flag** (double clicks ignored while the callback runs, pcall), controller selection = hover. Server must still be idempotent (button busy is UX only).

### 4.5 Windows
```
UI.Window(title, width, height, color?): Window  -- Glas-Panel (Surface T 0.08, Ecke 16, 1-px Border, weicher Schatten),
    Kopf 58 px: Titel Michroma GROSS + Akzent-Unterstrich, Ghost-✕; Content = ScrollingFrame (UIListLayout 8 px,
    AutomaticCanvasSize Y). Felder: Group, Fader (CanvasGroup NUR während der Animation), Panel, Shadow, Scale,
    Content, IsOpen, Token, OnOpen (task.spawn beim Öffnen), Title
UI.OpenWindow(win)   UI.CloseWindow(win)   UI.ToggleWindow(win)   UI.CloseAll()   UI.IsAnyWindowOpen(): boolean
UI.Windows (= ctx.Windows): Register(name, open, close?), Open(name), Close(name?), IsOpen(name?), Toggle(name)
    -- immer nur EIN Fenster offen; Hooks "WindowOpened"/"WindowClosed"(name); Blur + Modal-Knopf (Maus frei)
```
The Terminal (trading) needs a large layout (≈ 1100×680 desktop, full-screen sheet on phones): build it as its own Frame registered via `Windows.Register("Terminal", open, close)` (foreign window, `entry.Flag` path) or as a big `UI.Window` with custom content (Content is a ScrollingFrame – for the chart use a non-scrolling child frame).

### 4.6 Layout helpers
```
UI.Section(parent, text, order, color?): TextLabel   -- Text2 + 3×14 Akzent-Streifen links
UI.Row(parent, order, height? = 40): Frame           -- horizontale Liste, 8 px
UI.Grid(parent, order, cellX, cellY): Frame          -- UIGridLayout 10 px, AutomaticSize Y
UI.Card(props): Frame     -- Surface2, Ecke 12, 1-px Border
UI.Panel(props): Frame    -- Surface T 0.12, Ecke 12, 1-px Border (HUD über der Welt)
UI.Divider(parent, order?): Frame                    -- 1 px Border
```

### 4.7 Bars, counters, badges
```
UI.Bar(props): { Frame, Fill, Text, Ratio }   -- props Size (voll × 24), Position, AnchorPoint, LayoutOrder, Parent, Color, MaxText
UI.SetBar(bar, ratio, text?)                  -- Füllung gleitet 0.35 s (nur bei Änderung > 0.001)
UI.Counter(label, format): Counter            -- zählt weich, ≤ 30 Hz, Farbblitz Up/Down, Pop wenn UIScale am Label
UI.SetCounter(counter, value, instant?)       UI.RedrawCounter(counter)
UI.Pulse(scale: UIScale, amount? = 0.1)
UI.Badge(button, text?): Frame                UI.SetBadge(badge, text?, color?, pulse?)   -- nur bei Änderung
```
`UI.Counter(label, Util.FormatNumber)` is exactly the "rolling digits" feel of the website ticker for cash/net worth.

### 4.8 Toasts
`UI.Toast(text, kind?)` – pill top centre, coloured dot (Info/Announce Accent, Success Up, Error/Alarm Down, Event Warn), Alarm/Announce with coloured stroke, max 5 visible (lowest priority oldest dropped), pooled (8). `UI.SetToastTop(offset?)` moves the column (CC: below the match bar) → AT: below the ticker bar / terminal header.

### 4.9 Robux / policy helpers
`UI.FetchPrice(id, infoType, cb(price?))` (cached, deduped `GetProductInfoAsync`), `UI.WhenRandomItemsKnown(cb(allowed))`, `UI.RandomItemsAllowed(): boolean?` (state `RandomAllowed`, after 30 s own PolicyService query; error = not allowed).

### 4.10 Lift from `AdminPanel.luau` into the kit (they are generic)
`chip(parent, text, color, props?)` (pill), `statTile(parent, caption, order)` (KPI tile), `rowCard(parent, order, height)` + `rowActions(card, width)`, `slider(...)` (sends on release), `cycler(parent, title, options, size, emptyLabel?)`, `navItem(parent, text, order, onClick)` (sidebar tab with accent bar). Expose as `UI.Chip, UI.StatTile, UI.RowCard, UI.Slider, UI.Cycler, UI.NavItem` and let AdminPanel use them.

### 4.11 New kit pieces AT needs
`UI.Segmented(parent, options, onChange)` (timeframes 1m/5m/15m/1H/4H/1T/1W, chart type), `UI.Sheet(...)` (mobile bottom sheet = website "Bottom-Sheets"), `UI.PriceTag(label, value, change)` (Up/Down colour + ▲/▼), `UI.Sparkline(parent, points)` (mini line, §5), `UI.Ticker(parent)` (scrolling quote band, one `TextLabel` per company pooled, scroll by one UIListLayout container offset per frame), `ChartView` (§5).

---

## 5. Drawing charts on top of the kit (no assets, 60 FPS)

### 5.1 Market model (server-authoritative)
- Port `js/market.js` into pure `Shared/MarketMath.luau`: per company `sigmaD = v / sqrt(365)`, minute sigma `sigmaD / sqrt(1440) * LIVELY`, volatility regime `vs = exp(0.92*ln(vs) + 0.22*gauss)` (daily) / `exp(0.9995*ln(vs) + 0.012*gauss)` (tick), drift changes every 60 days, intraday activity `season(t) = 0.55 + 0.9*(exp(-((h-9.5)^2)/3) + exp(-((h-16)^2)/3))`, rare jumps (`p = 0.0004` per tick, `6×sigma`), `tickStep(price)` (0.005/0.01/0.02/0.05/0.2), `aggregate(src, tf)` for timeframes. Use `Random.new(Util.Hash(companyKey .. ":" .. utcDay))` instead of mulberry32 so the history is deterministic per day (same on all servers – design option: deterministic hourly anchors + bridge so every server shows the same chart without MessagingService; decide in the spec).
- Events (crash/rally/news/IPO, admin or scheduled) are multipliers on drift/vol with start/end timestamps from `workspace:GetServerTimeNow()`.
- **Never** real tickers/names (the website's `js/data.js` lists Apple, NVIDIA … → do NOT reuse). Invent fictional companies; fundamentals (sector, KGV, dividend) are game data in `Config.Companies`.
- Server keeps ring buffers per company × timeframe (e.g. 120 candles each); candle close → `Market` remote `("Candle", {id, tf, …})` only to players who have that chart open (track subscriptions via `Request "Watch"`).

### 5.2 Indicators
Port `js/indicators.js` 1:1 to `Shared/Indicators.luau` (same semantics: output arrays same length as input, `nil` until warm-up): `sma(values, n)`, `ema(values, n)` (k = 2/(n+1), seeded with SMA), `bollinger(values, n=20, mult=2)`, `rsi`, `macd`, `vwap`, `atr`, `stoch`. Compute on the client for display; server uses the same module for alarms/bots/skill checks. Luau-CLI tests with fixed series.

### 5.3 Network
- `Quotes` (UnreliableRemoteEvent, 1–2 Hz): `u16 seq, u32 serverTimeSec, u8 n, n × (u8 companyId, f32 price, i16 changeBp)` = 7 + 7n bytes → 48 companies = 343 B (≤ ~900 B). Lost packets are healed by the next one. Client fires hook `Quotes`.
- Candles on demand: `Request "GetCandles" {Id, Tf}` → buffer `u8 tf, u32 startTime, u16 n, n × (f32 o, f32 h, f32 l, f32 c, u32 vol)` = 20 B/candle (120 → 2.4 KB). f32 = 7 significant digits – fine for display; truth stays f64 on the server. Same "clamp/never error" rules as CC `Net` codecs; Decode returns `nil` for wrong length.
- Orders: `Request "PlaceOrder" {Id, Side, Qty, Type, Limit?, Stop?, Tp?, Nonce}` – server prices/fills with its own quote, rejects stale/oversized, idempotent by `Nonce` (sequence windows must advance on reject – CC Runde 2 critical bug).

### 5.4 `ChartView` (client library on top of `UI`)
```
ChartView.new(parent: GuiObject, opts) -> view
  opts { Candles = 120, Volume = true, Pane = "RSI"|"MACD"|nil, Style = "Candles"|"Hollow"|"Line", Mono: Font? }
view:SetData(candles: {Candle}, tf)    view:PushQuote(price, t)    view:SetIndicators({SMA20=true, …})
view:SetStyle(style)    view:Step(dt)  -- vom Terminal-Frame(dt)    view:Destroy()
```
Layout (all inside one non-rotated `Frame` with `ClipsDescendants = true`): price plot (≈ 72 %), volume strip (≈ 14 %, bars at 35 % transparency), optional indicator pane, right price axis (≈ 56 px), bottom time axis (≈ 18 px). Colours: grid `Border`, axis text `Muted`, bull `Up`, bear `Down`, last-price line + pill `Up`/`Down` by direction, SMA/EMA `Accent`/`Warn`/`Purple`, Bollinger `Text2` at 60 % transparency.

Rendering rules (the "ultra smooth" part):
1. **Pool everything once** in `new()`: per candle slot one `Frame` body + one `Frame` wick + one volume `Frame`; ≤ 120 slots → ≤ 360 frames. Axis labels pooled (8 price + 6 time). No `Instance.new` while ticking.
2. **Scale coordinates**: x = `(i - 0.5) / N` (Scale), y = `1 - (price - lo) / (hi - lo)` (Scale) → resolution-independent, free under `RootScale`/UIScale and in SurfaceGuis. Body `Size = UDim2.new(0.7/N, 0, |o-c|/(hi-lo), minPx)`, wick 1 px wide (`UDim2.new(0, 1, (h-l)/(hi-lo), 0)`).
3. **Write only on change** (like `UI.Counter`/`SetBadge`): compare with cached values before setting `Position/Size/BackgroundColor3/Visible`.
4. **Per frame only the live candle moves**: smooth its close/high/low toward the newest quote with `alpha = 1 - exp(-dt * 12)`; y-range `lo/hi` eases with `1 - exp(-dt * 6)` (no axis jumps). On candle close shift the slot index (reuse the oldest slot) and tween a strip container's X by one slot width (0.25 s Quint Out) instead of touching every candle.
5. **Lines** (price line style, SMA/EMA/Bollinger, sparklines): preferred **`Path2D`** (VERIFIED in API 0.742: `SetControlPoints`, `Thickness`, `Color3`, `GetMaxControlPoints`; behaviour/clipping UNVERIFIED → test) with `Path2DControlPoint.new(UDim2.fromScale(x, y))`, one Path2D per series; respect `GetMaxControlPoints()` (split if needed). Fallback: one rotated `Frame` per segment – compute in pixels from `plot.AbsoluteSize` (divide by the accumulated UIScale, e.g. `UI.Root.RootScale.Scale`, because AbsoluteSize is post-scale while offsets are pre-scale): `len = sqrt(dx²+dy²)`, `Position` = midpoint, `AnchorPoint (0.5,0.5)`, `Size (len, thickness)`, `Rotation = deg(atan2(dy, dx))`. **Engine limit:** `ClipsDescendants` is ignored when the clipping frame or an ancestor is rotated; rotated children inside an unrotated clip – verify in Studio → clamp segments to the plot rect in code anyway.
6. **No CanvasGroup** around live charts (re-renders the whole group on every change, blurry text on phones – CC pitfall). No `TextScaled` on pooled axis labels (fixed `TextSize`, `BuilderMono`).
7. Area fill (website "Fläche/Baseline"): optional on High/Ultra only – thin vertical frames under the line with a `UIGradient` transparency ramp; off on Low.
8. Crosshair + OHLC tooltip: two 1-px frames + pill, driven by `InputChanged` (mouse) / touch drag; Controller: D-pad moves the cursor one candle.
9. **Budgets by quality tier** (`Quality` module): candles 120/90/60, indicator count, area fill on/off, monitor count.

### 5.5 World monitors and tickers (SurfaceGui)
- Built **client-side** (SurfaceGui in PlayerGui with `Adornee` = server part) so each client can budget them: nearest K monitors live (K by tier, e.g. 2/4/8/12), the rest frozen snapshots; update ≤ 2 Hz; reuse the same `ChartView` with fewer candles (30–60) and no labels.
- `SurfaceGui.LightInfluence = 0`, `Brightness` 1.5–3 (glows with Bloom under Future light), `MaxDistance` (CC boards use 300), `PixelsPerStud` 30–50, `SizingMode = PixelsPerStud`; `UIStroke.StrokeSizingMode` exists for constant stroke width.
- Trading-floor ticker walls / LED band: pooled `TextLabel`s in a horizontal `UIListLayout` container scrolled by Position each frame (wrap by moving the first label to the end) – exactly the website `.ticker` (120 s loop, pause on hover).
- Server-side boards (leaderboards) keep CC's approach: SurfaceGui on server parts with AKYTEX constants (server has no `UI.Theme`).

---

## 6. Tooling (identical to CC, verified paths)

```bash
SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad
cd /home/user/website-test-demo-1/roblox-akytex-tycoon
stylua --check src tests                      # StyLua 2.5.2 (Luau, Tabs, 120)
selene src                                    # selene 0.31.0, std = "rbx" (rbx.yml)
rojo sourcemap default.project.json -o sourcemap.json
/tmp/luau-lsp/build/luau-lsp analyze --platform=roblox --definitions=$SP/globalTypes.d.luau --sourcemap=sourcemap.json src
rojo build default.project.json -o AkytexTycoon.rbxlx   # Rojo 7.7.1
for t in tests/*.test.luau; do $SP/luau-build/luau "$t" || exit 1; done   # pure modules, require("../src/shared/Util")
python3 scripts/contract_check.py .           # ERROR -> exit 1
```
`scripts/check.sh` = CC's script with the output name changed and the contract checker appended; it prints `ALLE PRÜFUNGEN OK`. In Studio: `[SelfTest] n/n PASS` in Output (Solo and Test → 2 Players).

Conventions: `--!strict` for pure shared modules (Util, Net, Spring, Types, MarketMath, Indicators, Format, Config.Client); German comments; file header block (`AKYTEX TYCOON – …`, owner package, public API list); no `wait/spawn/delay` (only `task.*`), no `BodyVelocity`, use `*Async` APIs (`GetProductInfoAsync`, `UserOwnsGamePassAsync`, `AwardBadgeAsync`, `IsInGroupAsync`, `GetRolesInGroupAsync`).

---

## 7. Pitfalls already fixed in CC – keep the fix (Runde 2 `124187d`/`090eef7` + earlier REUSE §14)

**Platform / server**
1. Request/Admin calls arriving after `PlayerRemoving` re-created limiter entries → first line of `dispatch`: `if p.Parent ~= Players then return { Ok = false } end` (PlayerStateService + AdminService).
2. Calls into AntiCheat from other services' `PlayerRemoving` handlers re-created tracks forever → `present(p)` guard (`Parent == Players`) in every public entry.
3. A client module whose `Init` failed still got `Start/Frame/Tick` → remove it from `ctx.Modules` (Main.client).
4. Instances as **weak** table keys can be collected while the instance lives → strong tables + explicit cleanup on `AncestryChanged`/removal.
5. One message, one owner: PartyBoost was announced by Effect AND NotifyAll; Mutator toast came twice → exactly one path per notification.
6. System announcements without sender must not show the owner banner with blue check → `Effect "Announce"` without `UserId/Name` = `Toast(…, "Announce")`.
7. Global messages: validate every field incl. an **upper** time bound (`Until ≤ now + max`), also for values restored from DataStore at boot.
8. **No pay-to-win leak:** Robux pass tiers granted Coins/Keys through the shared reward table → paid paths filtered (`ForbiddenRobuxFields` + only XP-reached tiers pay currency) and tested.
9. Shared pools paid per winner (2v2 bounty doubled) → split once.
10. A quest kind (`Assist`) that nobody tracked was unsolvable → SelfTest: every quest kind in Config has a `Track()` caller.
11. Leaving to dodge a loss (MMR) → leaving must settle the outcome (AT: positions/orders keep their server state; define offline behaviour explicitly).
12. Admin action credited a player (admin pop gave the last attacker XP/bounty) → admin actions never credit players; AT: admin market moves tainted for season boards.
13. Teleport put `HumanoidRootPart` at floor height (legs in the floor) → target CFrame + root height offset, then `AntiCheatService.NoteTeleport`.
14. UI state not reset after respawn/new round (HP display) → re-sync HUD on `CharacterAdded` / teleport.
15. `RaycastParams` `Include` with an EMPTY list filters everything → guard empty include lists.
16. `pairs` vs `ipairs` on sparse lists (cards 1–2 missing indices).
17. **Critical:** sequence/ID windows stuck after a rejection (shooting stopped for the rest of the match) → windows advance on reject too (AT: order nonces).
18. Lost client action (rate bucket) → server reconciles to the client's plausible state instead of rejecting everything forever (AT: re-send State).
19. Anti-cheat false positives from locally hidden parts and from momentum after launches → ignore locally hidden geometry in noclip checks; keep impulse speed until landing (`ImpulseAirSeconds`) → AT: elevators, jump pads, cars, teleporters need `Grace/Exempt/SetAllowance`.
20. Movement sums: whoever raises movement values re-checks the allowance sum (Config.Security comment) – same for any AT speed boosts/cars.

**Data / money (MH-era, kept in CC)**
21. Auto-save iterated `pairs(Profiles)` with yields → snapshot list + pcall per save.
22. Auto-save finishing after release re-locked the profile → serialized saves; release waits; no lock while releasing.
23. Studio tests touched live data / created `Player_-1` keys → NoSave for `UserId <= 0` (+ `Config.Studio.NoSave`), NoApi detection without 30-s retries.
24. `forceTake` of a fresh lock on the last attempt → allowed but `warn` with both JobIds.
25. ProcessReceipt before profile load / concurrent same PurchaseId → wait (60 s) instead of NotProcessedYet.
26. Yield between granting and writing the receipt → all yields in `Prepare`, grant + receipt without yield.
27. Ban `Duration` 0 / over-long reasons → clamp (≥ 60 s or −1, 400/1000 bytes).
28. Studio: everybody admin → Player2 (−2) never admin.
29. Admin log flooding → rate limit before admin check, "Unerlaubter Zugriff" once per player.
30. Double pass load / double release → `loading[p]` and `profile.Releasing` guards.
31. Leaderboard name cache unbounded, unchanged values rewritten → bounded cache, change-only writes.
32. Dead sound paths (`swordslash.wav`, `electronicpingshort.wav`) → only `docs/ASSETS.md` paths.
33. `Util.FormatNumber` float bugs (1150 → "1.14K", `math.huge`) → fixed version in Util.

**UI**
34. CanvasGroup makes text blurry and re-renders on every change → content inside the CanvasGroup only while animating (`beginFade/endFade`).
35. Toasts covering a top bar → `UI.SetToastTop`.
36. Touch buttons shrinking under UIScale → separate unscaled TouchGui, ≥ 64 px, DeviceSafeInsets.
37. Photo mode on phones had no exit (UI hidden) → long press ends it.
38. Debug/admin overlays must render even if the UI kit failed → fallback AKYTEX colours.
39. One owner per indicator (taint chip shown by two modules) → AT: one module owns each banner.

**Engine facts to remember (VERIFIED API 0.742)**
40. `Lighting.Technology` is RobloxScriptSecurity → only via `default.project.json`. `Players.BanningEnabled` is NotScriptable → project file.
41. Leaderstats `IntValue` (CC clamps ±2^52) and Luau doubles (exact to 2^53 ≈ 9e15) → cap money or use StringValue display for huge net worth; `OrderedDataStore` needs integers.

---

## 8. AKYTEX brand sheet (from the website)

### 8.1 Names
- Brand: **AKYTEX**; logo/wordmark spelling **ΛKYTEX** (Greek capital Lambda U+039B as the "A", no crossbar). Alternate names on the site: "ΛKYTEX", "Akytex", "AKYTEX Trading".
- Company: **akytex united**, Hamburg. Products: **AKYTEX** (trading simulator with AI) and **NOVA** (AI assistant, separate brand).
- AI assistant character: **Aky** ("KI-Assistent", badge "KI"); AI product: **AKYTEX AI** (eyebrow "ΛKYTEX AI").
- Do not put founders' names, address or e-mail into the game (real private persons; not needed).

### 8.2 Taglines and voice
- Main: **"Markets move. Ideas stay."** (title, og:title, README, logo ring).
- Logo ring second line: **"CAPITAL BUILDS TOMORROW"** – perfect for the tower building loop.
- Website headlines (German, short, confident, "du"): "Alles, was Trader brauchen." · "Mehr als eine Trading-App." · "Echtzeit. Wirklich." · "Wer holt am meisten raus?" · "Triff dein Zukunfts-Ich." · "3 Minuten am Tag. Ein Leben lang reicher." · "Sprich einfach mit Aky." · "Die Ideen-Börse." · "Einfache Preise. Keine Überraschungen." · "Dein Depot. Mit Verstand." · "Gebaut für Einsteiger und Profis – schnell, schön und bis ins Detail durchdacht."
- Disclaimer voice (fits Roblox compliance): **"Simulierte Kurse · virtuelles Geld"**, "Übungsgeld, kein echtes Geld", "keine Anlageberatung". Game version: "Spielgeld · erfundene Firmen · kein echtes Geld".
- Style: two-beat headlines with a period, numbers as proof ("40+ Aktien", "12 Indikatoren", "24/7"), emoji only as small feature icons (📈 🤖 💡 ⚡ 🔔 📱), eyebrow labels ("Neu · Nur bei AKYTEX").

### 8.3 Colours
| Set | Values |
|---|---|
| Classic dark (= CC `UI.Theme`, use for UI) | bg #0b0f17 · bg-2 #0f141d · panel #121824 · panel-2 #1a2130 · hover #1f2838 · border #1f2937 · text #e6ecf5 · text-2 #aab4c3 · muted #7d889a · accent #4f8cff · up #22c55e · down #ef4444 · warn #eab308 · up-bg rgba(34,197,94,.14) · down-bg rgba(239,68,68,.14) · shadow 0 12px 40px rgba(0,0,0,.5) |
| Space design (current site dark theme, use for skybox/night/hero moments) | bg #03040a · bg-2 #060812 · panel rgba(12,15,31,.84) · panel-2 rgba(28,33,64,.55) · border rgba(140,160,255,.13) · text #eef1ff · text-2 #b6bfdc · muted #7c86a8 · accent #7c9cff · **cosmic gradient** 100° #3b5bdb → #7c5cff → #b36bff · text gradient #9db4ff → #c8a8ff → #ffcf6e · nebula glows rgba(124,92,255,.2), rgba(59,91,219,.18), rgba(255,207,110,.07) · orbit rings rgba(140,160,255,.18) and gold dashed rgba(255,207,110,.14) |
| Logo | background radial #0d2345 → #081630 → #040a16 · ring #6ea2f2 (2.6 px, glow) · inner glow #2f6fd6 22 % · letters #eaf1ff (4.6 px strokes) · candles #3f74c4 (10–43 % opacity, rising) · moving-average line #4f86dc 45 % · ring text #5c7fb8 70 % · header mark drop-shadow rgba(110,162,242,.45) |
| Light theme (not for the game) | accent #2962ff · up #089981 · down #f23645 |
| NOVA (separate brand, only if referenced) | accent #5b4ff5 (dark #8b82ff) · accent-2 #0ea5a4 (dark #2dd4bf) · bg dark #111214 · logo = circle + tilted orbit ellipse |

Up/Down are the trading colours everywhere (candles, P/L, ticker). Neon facades at night: Accent #4f8cff, Up #22c55e, Down #ef4444 (owner wish 3) + cosmic purple #7c5cff/#b36bff for premium/penthouse.

### 8.4 Fonts
Website: **Manrope** (body, 400–800) and **Unbounded** (display, 300–700; brand name in Unbounded 300 with 0.32 em letter spacing). Roblox has neither → use `BuilderExtended` (display), `BuilderSans`/`Montserrat` (body), `BuilderMono` (numbers), Michroma as current CC heading fallback (§4.1). Roblox `TextLabel` has no letter spacing → wide wordmark = one label per letter in a horizontal `UIListLayout` (padding ≈ 0.3 × size) or the Frame logo below.

### 8.5 Logo built without assets
`icons/logo.svg` (512×512) letters are plain strokes – rebuild with rotated Frames (UI) or thin Neon/Glass parts (tower facade, plaza floor, holograms):
```
Λ  M60 285 L81 227 L102 285
K  M132 227 V285   M170 227 L134 258   M144 250 L172 285
Y  M200 227 L221 256 L242 227   M221 256 V285
T  M270 230 H312   M291 230 V285
E  M377 230 H340 V282 H377   M340 256 H372
X  M410 227 L452 285   M452 227 L410 285
Ring: circle cx 256 cy 256 r 228, stroke #6ea2f2 2.6 px; ring texts "MARKETS / MOVE / IDEAS / STAY" (x 118, y 146–206)
and "CAPITAL / BUILDS / TOMORROW" (x 330, y 386–426), 11.5 px, letter-spacing 6.5, #5c7fb8 70 %.
Background: 46 rising candlesticks from (58, ~390) to (470, ~110) + MA line, opacity 0.10 → 0.43.
```
Splash animation on the site: ring draws in 1.3 s (ease-ios), candles rise one by one (18 ms stagger), MA line draws 1.2 s, letters draw with 0.09 s stagger, word glow, taglines fade in at 1.25 s / 1.45 s, exit = scale 1.12 + blur. → loading screen for AT.

### 8.6 Motion & haptics
`--ease-ios`, `--ease-out`, `--spring`, `--spring-soft` (§4.2); press feedback on every control (spring transform 0.5 s); modal in = translateY 18 px + scale 0.94 → spring 0.6 s, backdrop blur; views enter 0.55 s ease-ios; reveal on scroll (28 px, 0.8–0.9 s); ripple 0.65 s; ticker 120 s linear loop; "Rollziffern" (rolling digits) on prices; "Dynamic-Island" notifications; 3D tilt + spotlight on cards; `prefers-reduced-motion` respected (AT: `ReducedFx`).

### 8.7 Feature names the game may reference (in-game, with Spielgeld only)
| Website feature | Game use (proposal) |
|---|---|
| **AKYTEX AI / Aky** | in-game helper character/hologram giving tips and the tutorial ("Aky"), clearly a game tip, no advice claims |
| **Ideen-Börse** ("versiegelt · gemessen · handelbar · belohnt") | players publish trade ideas (sealed, measured hit rate), others follow them; rewards in Spielgeld/XP only |
| **Copy-Trading** / **Rangliste** / **Top-Trader** | follow top players' portfolios with Spielgeld; leaderboards in the trading floor |
| **Autopilot** (Strategie-Presets, Not-Aus, Tagesverlust-Notbremse) | trading bots you hire for your tower (strategies, limits, kill switch) |
| **Liga** ("gleiches Startkapital, vier Wochen, ein Sieger") | seasons/hedge-fund groups with return-based ranking |
| **Geld-Akademie** (Lektion + Quiz, Streak, Abzeichen) | license exams (Azubi → Trader → Fondsmanager → Börsen-Legende), daily lesson quest |
| **Zukunfts-Ich** | offline-income / "what your tower earns while you are away" preview |
| **Depot-Doktor**, **Chancen-Scan**, **Heatmap**, **Screener**, **Orderbuch**, **Umsätze (Time & Sales)**, **Laufband**, **Preisalarme**, **Wenn-Dann-Regeln / Zeitplan** | terminal panels, tower departments, alarms |
| **Spotlight** / **Store** | in-game shop showcase (Spielgeld items) |
| **Clips** | "Clip-Momente" camera moments (big win, tower done) |
| **NOVA** | optional easter egg (separate brand) |
| Tarife Free/Plus/Pro/Elite/Ultra | **do not mirror as Robux tiers with euro wording**; at most as in-game license names without prices |

### 8.8 Do NOT take from the website
- Real tickers/company names (`js/data.js`: Apple, NVIDIA, SAP …, also copy like "Zeig mir Nvidia auf 4 Stunden").
- Euro prices, subscriptions, Stripe, AKYTEX Pay, checkout, "14 Tage kostenlos", "ab 239 €/Monat", order fees in €, royalties as real income ("Trading-Wissen wird zum Einkommen").
- URLs/links (github.io), "App installieren", any call to leave Roblox.
- Real-money/investment claims ("Ein Leben lang reicher" as financial promise, "Milliarden-Hebel", BaFin/Anlageberatung topics).
- Founder names, address, e-mail.

---

## 9. Compliance pointers for the reuse decisions (final wording comes from the dedicated compliance research)
- **DROP all random-reward mechanics** from CC: `Odds.luau`, crates (`OpenCrate`, `CrateReveal`, pity), the Glücksrad (`SpinWheel`), crate announcements. Even unpaid random wheels sit close to "simulated gambling"; the stock sim must stay skill/information-based (news lead time, indicators) with transparent rules.
- Keep the CC safety rails anyway: `ForbiddenRobuxFields` + `Core.Sanitize` (what Robux may never grant), `PolicyService` path (`RandomAllowed`, unknown = restricted) and `SimulatePolicy` admin action – so a later product can be gated, and so tests prove nothing paid is random.
- Robux must not look like betting: no "double or nothing", no buying market outcomes/events, no leverage casino; the spec decides whether Robux may buy Spielgeld at all (CC rule: Robux never buys currency).
- Offers: CC's `TryOffer` (max 1 popup per session, never during live action) → never during crash/rally events or while an order dialog is open.
- Branding: own brand only; no real companies, logos, tickers or real-money references (§8.8).

---

## 10. Quick start for builders (copy order)
1. Copy tooling (`rbx.yml`, `selene.toml`, `stylua.toml`, `.gitignore`, `scripts/*`) and write `default.project.json` (§1.1).
2. Copy verbatim: `Shared/Util`, `Shared/Spring`, `Shared/Lang/init` (edit `FILES`), `Server/Lib/Scheduler`, `Server/Services/Remotes`, `MetricsService`, `SelfTestService`, `Client/Modules/{UI, Hooks, Highlights, Fly, PhotoMode}`, Sfx engine.
3. Copy with renames + new data: `Main.server`, `DataService` (new DEFAULT_DATA), `PlayerStateService` (leaderstats), `MonetizationService` (BuildGrant/phases), `Config/init` (+ children), `Net` (new list + codecs), `Main.client` (module lists).
4. Adapt: `AdminService` + `AdminPanel` (market tabs), `AntiCheatService` (slim), `LeaderboardService` (boards), `Hud`, `Settings`, `Effects`, `Controls`, `DebugOverlay`, `TouchControls` (pattern).
5. New: MarketMath, Indicators, Format, ChartView, Terminal, Market/Order/Tower/Plot/Event/City services, world builder, Future-light graphics with quality tiers.
6. Run §6 checks; SelfTest in Studio Solo and "Test → 2 Players" (Player2 = non-admin path).
