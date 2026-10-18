# Setup

There are three ways to get Click a Button into Roblox Studio. They all
give the same result.

## Option A — open the ready-made place file

1. In Roblox Studio choose **File → Open from File…** and open
   `button-ascension/build/ButtonAscension.rbxlx`.
2. Open **Home → Game Settings → Security** and enable
   **Enable Studio Access to API Services**. This needs a published game; see
   *Publishing* below. Without it, everything works, but each Studio session
   uses temporary data. The HUD shows *"⚠ Not saving (temporary session)"*.
3. Press **Play** (F5).

> The place file is generated from `src/` with `rojo build`. If you change
> the source files, rebuild it (Option B) so the two stay identical.

## Option B — Rojo

1. Install [Rojo 7.4+](https://rojo.space/docs/v7/getting-started/installation/)
   and the Rojo Studio plugin.
2. In the `button-ascension/` folder run one of these:
   * `rojo serve default.project.json`, then click **Connect** in the Rojo
     plugin inside an empty Baseplate place (delete its `Baseplate` part and
     `SpawnLocation` first, see the note below), or
   * `rojo build default.project.json -o build/ButtonAscension.rbxlx` and
     open the file.

## Option C — copy and paste by hand

Use this if you don't want to install anything. Each file under `src/`
becomes one script in Studio. The file name, minus the extension, is the
**Name** of the script; the extension decides its **type**:

| File ends with | Create a… |
|---|---|
| `.server.luau` | **Script** |
| `.client.luau` | **LocalScript** |
| `.luau` | **ModuleScript** |
| (a directory) | **Folder** with the same name |

Steps:

1. **File → New → Baseplate.** Delete `Workspace/Baseplate` and
   `Workspace/SpawnLocation`. The game builds its own arena and spawn at the
   world origin, and the default baseplate would overlap it.
2. Create the folders and scripts below. Paste each file's full contents
   into the script with the same name. Names are case-sensitive and must match
   exactly.

### ReplicatedStorage

```
ReplicatedStorage
├── Shared            (Folder)
│   ├── Config        (Folder)  ← src/ReplicatedStorage/Shared/Config/*.luau
│   │     Achievements, Ascension, Chests, GameConfig, Items, Quests,
│   │     Rarities, Rewards, Skills, Sounds, Upgrades        (ModuleScripts)
│   ├── Format, Formulas, Loot, Remotes, Signal, Util        (ModuleScripts)
└── UI                (Folder)
      Effects, SoundPlayer, Theme, UIKit                     (ModuleScripts)
```

### ServerScriptService

```
ServerScriptService
├── Main              (Script)       ← src/ServerScriptService/Main.server.luau
├── Core              (Folder)
│     DataOps, DataSchema, Guard, Net, RateLimiter           (ModuleScripts)
├── Services          (Folder)
│     AchievementService, ChestService, ClickService, DataService,
│     EconomyService, EventService, InventoryService, LeaderboardService,
│     OrbService, ProgressionService, QuestService, SecurityService,
│     SettingsService, StatsService, SyncService, UpgradeService,
│     WorldService                                           (ModuleScripts)
└── Admin             (Folder)
      AdminActions, AdminCommands, AdminConfig, AdminPermissions,
      AdminService, AuditLog, PlayerResolver                 (ModuleScripts)
```

### ServerStorage

```
ServerStorage
└── AdminClient       (Folder)
    ├── AdminPanel    (LocalScript)  ← src/ServerStorage/AdminClient/AdminPanel.client.luau
    └── AdminUI       (Folder)
        ├── AdminNet, CommandBar, LogRow, Panel, TargetPicker, Widgets   (ModuleScripts)
        └── Tabs      (Folder)
              Dashboard, Economy, Items, Logs, Players, Progression,
              Server, Settings                                           (ModuleScripts)
```

The `AdminPanel` LocalScript does not run in ServerStorage. That is
intended: the server clones it into the PlayerGui of authorised staff only.

### StarterPlayer

```
StarterPlayer
└── StarterPlayerScripts
    ├── ClientMain    (LocalScript)  ← src/StarterPlayer/StarterPlayerScripts/ClientMain.client.luau
    └── Client        (Folder)
        ├── BigButton, ClientNet, Hud, InputController, ItemCard,
        │   Notifications, Orbs, ScreenManager, State, WorldFx       (ModuleScripts)
        └── Screens   (Folder)
              Ascend, ChestOpening, Chests, Collection, Inventory,
              Quests, Settings, Shop, Skills, Stats                    (ModuleScripts)
```

Leave **StarterGui** empty; the interface is created in code.
`ReplicatedStorage/Remotes` and `ReplicatedStorage/ServerState` are also
created automatically when the server starts. Do **not** create them by hand.

3. *(Optional)* Set **StarterPlayer → CameraMaxZoomDistance** to 60. The arena
   sets its own night lighting when it is built.
4. Press **Play**. The Output should show
   `[Main] Click a Button server started with 18 services.`
   and no red errors.

## Publishing

1. **File → Publish to Roblox** and create or choose an experience.
2. **Game Settings → Security → Enable Studio Access to API Services** (for
   Studio testing). Live servers always have DataStore access.
3. Add your staff to `ServerScriptService/Admin/AdminConfig` (see
   [`ADMIN.md`](ADMIN.md)). If the experience belongs to your own account,
   you are already Owner. For group-owned experiences, the group owner is
   Owner.
4. Set the name, description, icon and thumbnails from
   [`branding/STORE_PAGE.md`](../branding/STORE_PAGE.md) in
   **Game Settings → Basic Info**.
5. *(Optional)* Put a music track you are allowed to use into
   `ReplicatedStorage/Shared/Config/Sounds` → `Music.Id = "rbxassetid://…"`.

## Testing in Studio

| What | How |
|---|---|
| Solo play | **Play** (F5). You are Owner if you own the published place, or while the place is unpublished (`AdminConfig.StudioOwnerWhenUnpublished`, Studio only). Press **F2** for the admin panel. |
| Roles side by side | **Test → Clients and Servers → Local Server, 4 players → Start.** In Studio only, `AdminConfig.StudioTestUsers` makes Player1 **Owner**, Player2 **Admin**, Player3 **Moderator**. Player4 is a normal player. |
| Exploit attempt | In Player4's window, choose **Client** in the command bar and run the snippet below. |
| Saving | Enable API access, play, earn something, stop, play again: progress is restored. |

```lua
-- Run on Player4's client. The server must refuse it.
local r = game.ReplicatedStorage.Remotes.Admin:InvokeServer({
	Action = "economy.add",
	Args = { Target = "me", Currency = "Gems", Amount = 1e9 },
	RequestId = "manual-exploit-test-1",
})
print(r.ok, r.err) --> false  Not authorized.
```

Then open the admin panel as Player1. The **Audit Logs → Security** view and
the Dashboard's security counter show the rejected attempt.

The full manual checklist is in [`TESTING.md`](TESTING.md).

## Automated tests (optional)

The headless test suite needs [Lune 0.10.4](https://github.com/lune-org/lune/releases/tag/v0.10.4):

```sh
cd button-ascension
lune run tests/run.luau
```

See [`tests/README.md`](../tests/README.md).
