# Admin system

The admin system lets trusted staff manage players, the economy, items,
progression and the server **without weakening any game rule**. Every admin
action is checked on the server and goes through the same validated game
services as normal gameplay. Every admin action is also recorded in an audit
log.

## Security model

* **Roles come only from server-side data.** That data is the UserId
  allowlist in `ServerScriptService/Admin/AdminConfig`, the place creator
  (for user-owned games), the group owner (for group-owned games) and, in
  Studio only, the test users. Usernames, display names, client-sent values
  and hidden UI never grant anything.
* `AdminConfig` lives in **ServerScriptService**, which never replicates to
  clients. Players cannot read the staff list, roles or limits.
* The admin client code sits in **ServerStorage** and is cloned only into the
  PlayerGui of authorised staff. A normal player never receives it.
* The `Admin` RemoteFunction exists for everyone, as all remotes do. Every
  request runs through this pipeline in `AdminService`, in order:
  1. Look up the role from server config. Non-staff are rejected with
     *"Not authorized."*, the attempt is flagged in `SecurityService`, and it
     is written to the audit log (at most once every 10 s per player, so a
     flood can't fill the log).
  2. Check the request shape: a table, an action name and a unique `RequestId`.
  3. Reject duplicates: a repeated `RequestId` is refused (replay protection).
  4. Apply the global admin rate limit, then the per-category limit.
  5. Check the permission for that specific action.
  6. Validate the arguments: types, ranges, known ids, and the role's limits.
  7. Resolve the target: exactly one online player, or `#UserId` for offline
     tools. Ambiguous names are rejected and the candidates listed.
  8. **Rank protection**: punitive actions (kick, freeze, bring, respawn,
     remove/set currency, item removal, resets, ascension grants) cannot
     target staff of equal or higher rank.
  9. **Confirmation**: destructive actions return a single-use token that
     expires after 45 s. Only the same admin can confirm with it. The token
     stores the target's resolved UserId, so a confirmation can never hit a
     different player who joined with a similar name in the meantime.
  10. Run through the normal services (`EconomyService`, `DataOps`,
      `ChestService`, ...) inside `pcall`, then record an audit entry.
* No arbitrary code execution exists anywhere. There is no `loadstring` and
  no "run Lua" command.
* Kick reasons and announcements are filtered with `TextService`. If
  filtering fails, an announcement is not sent and the kick uses a generic
  reason.

## Roles

| Permission | What it allows | Moderator | Admin | Owner |
|---|---|:-:|:-:|:-:|
| `panel.open` | Open the panel, dashboard, command bar, help | ✓ | ✓ | ✓ |
| `players.view` | List online players | ✓ | ✓ | ✓ |
| `players.inspect` | Full progression and inventory of a player | ✓ | ✓ | ✓ |
| `players.teleport` | Teleport to / bring a player | ✓ | ✓ | ✓ |
| `players.kick` | Kick with a reason | ✓ | ✓ | ✓ |
| `players.freeze` | Freeze / unfreeze | ✓ | ✓ | ✓ |
| `players.respawn` | Reset a character | ✓ | ✓ | ✓ |
| `server.announce` | Server-wide announcement | ✓ | ✓ | ✓ |
| `server.stats` | Server performance statistics | ✓ | ✓ | ✓ |
| `logs.view` | Audit and security logs of this server | ✓ | ✓ | ✓ |
| `economy.grant` | Add / remove / set currencies, test rewards | | ✓ | ✓ |
| `economy.reset` | Reset a player's currencies (confirmation) | | ✓ | ✓ |
| `items.grant` | Grant / remove items and crates | | ✓ | ✓ |
| `items.test` | Simulate crate odds, forced-rarity test drops | | ✓ | ✓ |
| `progression.grant` | Upgrade levels, skills, ascensions, levels, Skill Points | | ✓ | ✓ |
| `server.events` | Start / stop boost events | | ✓ | ✓ |
| `offline.read` | Inspect offline players | | ✓ | ✓ |
| `progression.reset` | Reset progression sections (confirmation) | | | ✓ |
| `server.announce.global` | Game-wide announcements (all servers) | | | ✓ |
| `logs.persisted` | Audit logs saved by all servers | | | ✓ |
| `offline.write` | Change offline players' data (lock-checked) | | | ✓ |
| `players.ban` | Ban / unban in every server, also offline players (up to the role's ban limit) | ✓ | ✓ | ✓ |
| `staff.manage` | Make players Moderator or Admin in the game | | | ✓ |

**Per-action limits** (`AdminConfig.Roles.<Role>.Limits`):

| Limit | Moderator | Admin | Owner |
|---|---|---|---|
| Currency per action | — | 1e15 | 1e100 |
| Items per action | — | 100 | 1,000 |
| Crates per action | — | 100 | 1,000 |
| Ascensions per action | — | 5 | 100 |
| Levels per action | — | 50 | 500 |
| Skill Points per action | — | 50 | 1,000 |
| Longest ban | 7 days | 30 days | any, incl. permanent |

**Rate limits** (token buckets per admin): global 30 burst / 3 per s; read
20 / 4 per s; player 10 / 1 per s; punitive 5 / 1 per 5 s; economy and
items 10 / 1 per s; progression 8 / 1 per 2 s; destructive 3 / 1 per 20 s;
announcements 3 / 1 per 10 s; events 4 / 1 per 10 s; tests 5 / 1 per 4 s;
staff roles 5 / 1 per 10 s.

All of these values are in `AdminConfig` and can be changed there.

## Giving someone a role in the game (Owners)

The easiest way: no code, no publishing.

1. Press **F2** (or the 🛡️ Admin button) and open the **🚫 Moderation** tab.
   You can also select the player in the **Players** tab and press
   **🛡️ Staff role…**.
2. Under **Staff roles**, enter the player (name, `@username` or `#UserId`;
   they do not have to be online), choose **Moderator** or **Admin** and press
   **Give role**. Confirm the dialog.
3. The role applies in **every server within a few seconds**. An online
   player gets the admin panel right away and a message saying so.
4. **Remove role** takes it away again, also in every server; their panel
   disappears.

Command bar: `/admin mod <player>`, `/admin setrole <player> admin`,
`/admin removerole <player>`, `/admin staff`.

How it stays safe:

* Only the `staff.manage` permission can do this (Owners by default).
* Only **Moderator** and **Admin** can be handed out
  (`AdminConfig.Moderation.GrantableRoles`). **Owner** never can.
* Roles are stored **by UserId** in a server-only DataStore
  (`AdminConfig.Moderation.StoreName`), never by name and never from client
  data. Other servers are told over MessagingService and then re-read the
  DataStore themselves; the message content is never trusted.
* Roles written in `AdminConfig.Users`, the place creator and the group owner
  always win and cannot be changed or removed from the game.
* Every change is confirmed, rate-limited and recorded in the audit log.
* In Studio without API access, roles last for that session only, and the
  panel says so.

## Banning

Moderators, Admins and Owners have `players.ban`.

* **Panel:** the **🚫 Moderation** tab (or **🚫 Ban…** on a player in the
  Players tab). Enter the player, choose a length (1 hour, 1 day, 7 days,
  30 days, Permanent; only the lengths your role may use are shown), type a
  reason and press **Ban**. Active bans are listed below with **Unban**.
* **Command bar:** `/admin ban <player> <30m|12h|7d|2w|perm> <reason...>`,
  `/admin unban <player|#UserId>`, `/admin bans`.
* A ban applies in **every server**. The player is removed right away
  (other servers follow within seconds) and kicked whenever they try to
  join, with the reason and the end date.
* **Offline players** can be banned by `#UserId` or by their exact Roblox
  username (looked up on the server). The confirmation dialog shows who the
  name resolved to.
* **Limits:** Moderators up to 7 days, Admins up to 30 days, Owners any length
  including permanent (`Limits.MaxBanDays`). Nobody can ban staff of equal or
  higher rank, and a ban can only be lifted by staff of at least the rank
  that issued it.
* The reason is filtered by Roblox before it is stored, because the player
  and other staff will read it.
* Bans are stored by UserId in the same server-only DataStore as staff roles
  and end automatically. In live servers they are also sent to **Roblox's
  own Ban API** (`Players:BanAsync`, `AdminConfig.Moderation.UseRobloxBanApi`),
  so Roblox blocks the player before they can even join and the ban shows up
  in the Creator Hub. If that call fails, our own ban list still applies.
  Alt-account banning is off by default (`BanAltAccounts`).
* If Roblox's data services are down when a server starts, a joining player
  is let in after `JoinCheckTimeout` seconds rather than blocking everyone.

## Adding an administrator in code

You can also write roles into the code. These roles cannot be changed from
the game.

1. **Find their UserId.** Use the number in their profile URL,
   `https://www.roblox.com/users/123456789/profile`, or run this in Studio's
   command bar:
   ```lua
   print(game:GetService("Players"):GetUserIdFromNameAsync("TheirUsername"))
   ```
2. **Add one line** to `AdminConfig.Users` in
   `ServerScriptService/Admin/AdminConfig`:
   ```lua
   AdminConfig.Users = {
   	[123456789] = "Admin",
   	[555555555] = "Moderator",
   }
   ```
3. **Publish.** New servers pick up the change. To apply it everywhere, shut
   down old servers from the Creator Dashboard.

Rules of thumb:

* Use UserIds, never names; names can change.
* Give the lowest role that is enough.
* Remove people who no longer moderate.

The owner of a **user-owned** place is Owner automatically
(`AutoOwnerForCreator`). For **group-owned** places, the group's owner is
Owner (`GroupOwnerIsOwner`, verified through `GroupService` on the server).

**Studio testing:** `AdminConfig.StudioTestUsers` applies only when
`RunService:IsStudio()` is true. In a *Local Server* test, Player1 (UserId
-1) is Owner, Player2 is Admin, Player3 is Moderator and Player4 is a normal
player. In an **unpublished** place, the solo Play tester is Owner
(`StudioOwnerWhenUnpublished`). This never applies to live servers.

## Using the panel

* **Open it:** click the **🛡️ Admin** button (top right), press **F2**, or
  type `/admin <command>` in chat. On a gamepad, select the button and press
  **A**; **B** closes the panel.
* The header shows your role badge. Controls your role cannot use are
  disabled, and the server refuses them anyway.
* Every result appears as a toast and in the command console.

| Tab | Features | Server actions |
|---|---|---|
| **Dashboard** | Online players, uptime, server presses and presses/s, memory, physics FPS, heartbeat, data status (saves, failures, last error), active events, security flags, recent admin actions and security events. Refreshes every 5 s. | `dashboard` |
| **Players** | Searchable list with staff/frozen tags. Selecting a player shows username, display name, UserId, currencies, level/XP, Skill Points, ascensions/stage, upgrades, skills, inventory, crates, statistics and security counters. Buttons: Teleport to, Bring, Freeze/Unfreeze, Respawn, Kick (reason required), Inspect inventory, Ban… and (Owners) Staff role…, which open the Moderation tab for that player. Offline lookup by UserId. | `players.list`, `players.inspect`, `players.teleportTo`, `players.bring`, `players.freeze`, `players.unfreeze`, `players.respawn`, `players.kick` |
| **Economy** | Target picker, currency selector, amount field (accepts 1.5k / 2m / 1e6), Add / Remove / Set, test rewards (500 Gems, crate bundle, Frenzy, spawn orb, level up), Grant Prisms, Reset currencies (confirmation). | `economy.add`, `economy.remove`, `economy.set`, `economy.reward`, `economy.reset` |
| **Items** | Searchable item list with rarity filters, Grant / Remove, crate grants, inventory inspection, **drop-rate test** (1k/10k/100k rolls, luck, pity; observed vs expected per rarity; *no data changes*), forced-rarity test drop. | `items.grant`, `items.remove`, `chests.grant`, `items.simulate`, `items.forceRoll` |
| **Progression** | Set upgrade levels, unlock a skill / all skills, grant ascensions, levels and Skill Points, reset skills (confirmation), reset progress by scope (confirmation; scope *all* also requires typing the player's name). | `progression.*` |
| **Server** | Announcements: *Server-wide (this server only)* or *Game-wide (all servers)*. Start/stop boost events with duration and countdown. Server statistics. | `server.announce`, `server.eventStart`, `server.eventStop`, `server.stats` |
| **Audit Logs** | Newest-first log with search and result filters (success, denied, invalid, error, rate_limited, confirm_required, duplicate). Live updates. Security view. Load the persisted log for a UTC day. | `logs.recent`, `logs.security`, `logs.persisted` |
| **Moderation** | Ban (length chips limited to your role, reason required) and the list of active bans with Unban. Owners also get **Staff roles**: give Moderator/Admin by name, @username or #UserId, and the list of roles given in the game with Remove. | `players.ban`, `players.unban`, `players.bans`, `staff.list`, `staff.setRole`, `staff.removeRole` |
| **Settings** | Your role, rank, permissions, limits, keybind and server info. Panel preferences for this session. Roles cannot be changed from the client. | `hello` |

## Command bar

Commands run from the panel's command bar, or in chat as `/admin …`. The
`/admin` prefix is optional in the command bar. Use quotes for arguments
with spaces, e.g. `kick Alice "spamming the chat"`. Numbers accept `1500`,
`1,500`, `2.5k`, `3m`, `1b`, `4t` and `1e6`.

**Player selection:** `me`, `#UserId`, `@username` (exact),
an exact username, an exact display name (if unique), or a unique prefix.
Anything ambiguous is rejected and the matching players are listed. Commands
that support offline players take `#UserId`.

| Command | Usage | What it does | Permission |
|---|---|---|---|
| `help` | `/admin help [command]` | List commands or show help for one. | `panel.open` |
| `players` | `/admin players` | List online players. | `players.view` |
| `stats` | `/admin stats <player>` | Show a player's progression (#UserId works offline). | `players.inspect` |
| `givecash` | `/admin givecash <player> <amount> [currency]` | Add Sparks (or Gems/Prisms). | `economy.grant` |
| `removecash` | `/admin removecash <player> <amount> [currency]` | Remove currency. | `economy.grant` |
| `setcash` | `/admin setcash <player> <amount> [currency]` | Set a currency to an exact amount. | `economy.grant` |
| `givegems` | `/admin givegems <player> <amount>` | Add Gems. | `economy.grant` |
| `giveprisms` | `/admin giveprisms <player> <amount>` | Add Prisms (ascension currency). | `economy.grant` |
| `reward` | `/admin reward <player> <gems_pack\|crate_bundle\|frenzy\|orb\|level_up>` | Grant a test reward. | `economy.grant` |
| `reseteconomy` | `/admin reseteconomy <player>` | Reset all currencies (asks for confirmation). | `economy.reset` |
| `giveitem` | `/admin giveitem <player> <itemId> [amount]` | Grant an item. | `items.grant` |
| `removeitem` | `/admin removeitem <player> <itemId> [amount]` | Remove copies of an item. | `items.grant` |
| `givechest` | `/admin givechest <player> <chestId> [amount]` | Grant crates. | `items.grant` |
| `finditem` | `/admin finditem [search]` | Search item ids. | `panel.open` |
| `testroll` | `/admin testroll <chestId> [count] [luck]` | Simulate crate odds without changing any data. | `items.test` |
| `forceroll` | `/admin forceroll <player> <chestId> <rarity>` | Grant a test drop of an exact rarity. | `items.test` |
| `kick` | `/admin kick <player> <reason...>` | Kick a player with a reason. | `players.kick` |
| `tp` | `/admin tp <player>` | Teleport to a player. | `players.teleport` |
| `bring` | `/admin bring <player>` | Bring a player to you. | `players.teleport` |
| `freeze` | `/admin freeze <player>` | Freeze a player. | `players.freeze` |
| `unfreeze` | `/admin unfreeze <player>` | Unfreeze a player. | `players.freeze` |
| `respawn` | `/admin respawn <player>` | Reset a player's character. | `players.respawn` |
| `ban` | `/admin ban <player> <30m\|12h\|7d\|2w\|perm> <reason...>` | Ban from every server (also offline: #UserId or exact username). Asks for confirmation. | `players.ban` |
| `unban` | `/admin unban <player\|#UserId>` | Lift a ban. | `players.ban` |
| `bans` | `/admin bans` | List active bans. | `players.ban` |
| `setrole` | `/admin setrole <player> <moderator\|admin>` | Make someone Moderator or Admin in every server (asks for confirmation). | `staff.manage` |
| `mod` | `/admin mod <player>` | Make someone Moderator (asks for confirmation). | `staff.manage` |
| `removerole` | `/admin removerole <player>` | Take away a staff role given in the game. | `staff.manage` |
| `staff` | `/admin staff` | List staff roles given in the game. | `staff.manage` |
| `announce` | `/admin announce <message...>` | Server-wide announcement (this server only). | `server.announce` |
| `gannounce` | `/admin gannounce <message...>` | Game-wide announcement (all servers). | `server.announce` + `server.announce.global` |
| `event` | `/admin event <start\|stop> <eventId> [seconds]` | Start or stop a boost event in this server. | `server.events` |
| `setupgrade` | `/admin setupgrade <player> <upgradeId> <level>` | Set a shop upgrade level. | `progression.grant` |
| `unlockskill` | `/admin unlockskill <player> <skillId\|all>` | Unlock skills for testing. | `progression.grant` |
| `resetskills` | `/admin resetskills <player>` | Reset a skill tree with refund (confirmation). | `progression.reset` |
| `giverebirth` | `/admin giverebirth <player> [count]` | Grant ascensions; resets their run (asks for confirmation). | `progression.grant` |
| `givelevel` | `/admin givelevel <player> [count]` | Grant levels. | `progression.grant` |
| `givesp` | `/admin givesp <player> <amount>` | Grant Skill Points. | `progression.grant` |
| `resetprogress` | `/admin resetprogress <player> [upgrades\|skills\|ascension\|inventory\|collection\|quests\|stats\|level\|all]` | Reset progression (asks for confirmation). | `progression.reset` |
| `logs` | `/admin logs [filter]` | Show recent audit log entries. | `logs.view` |
| `serverinfo` | `/admin serverinfo` | Server performance and player stats. | `server.stats` |

Type `help <command>` for usage. The list shown to each admin contains only
the commands their role may use.

## Destructive actions and confirmations

`economy.reset`, `progression.resetSkills`, `progression.reset`,
`progression.grantRebirth` (an ascension wipes the target's current run),
`players.ban` and `staff.setRole` return `needsConfirm` with a summary
instead of running. The panel shows a red
confirmation dialog. Resetting *all* progress also requires typing the
player's name. The token is single-use, expires after 45 s, and works only
for the admin it was issued to.

## Audit log

Each entry records:

* **Who:** admin UserId, name and role.
* **What:** the action and sanitised parameters. Tokens and request ids are
  never logged.
* **Whom:** target UserId and name.
* **When:** a unix timestamp.
* **Result:** `success`, `denied`, `invalid`, `error`, `rate_limited`,
  `confirm_required` or `duplicate`.
* A message, and the server JobId.

Entries are recorded for successful actions, refused actions (permission,
rank, limits), malformed requests, duplicates, rate limits and unauthorised
attempts.

Panel refresh requests (dashboard, lists) are not logged. Inspecting the
same player is logged at most once per minute.

**Persistence:** every 60 s, and on shutdown, each server appends its new
entries to the DataStore key `Audit_YYYY-MM-DD` in
`ButtonAscension_AdminAudit`, keeping the newest 1,500 per day. If the
DataStore is unavailable, entries are retried on the next flush and remain
visible in memory (500 per server). Owners can load any day in the Audit
Logs tab.

## Offline players

`players.inspect` with `#UserId` reads stored data without locking it
(`offline.read`). Currency, item and crate changes with `#UserId` require
`offline.write` (Owner). They are applied inside a single `UpdateAsync` that:

* refuses if the player is online in this server,
* refuses if a fresh session lock shows them playing in another server,
* migrates and sanitises the stored data first,
* applies the same `DataOps` functions as online play.

So an offline edit can never be overwritten by a live session, or overwrite
one. Other progression tools need the player online.

## Announcements and events

* **Server-wide** announcements reach everyone in the current server. The
  banner reads *"SERVER ANNOUNCEMENT (this server)"*.
* **Game-wide** announcements (Owner) are published through
  MessagingService and labelled *"GAME-WIDE ANNOUNCEMENT"*. Receiving servers
  check payload types and lengths and **re-verify that the sender is
  authorised** in their own config before showing anything.
* **Events** (Spark Surge ×2, Lucky Hour +100% luck, Golden Rush ×4 golden
  chance, Critical Frenzy +25% crit, Knowledge Storm ×2 XP) affect only the
  current server and show a banner and timer to all its players. An
  automatic scheduler also starts a 5-minute event every 30 minutes when
  nothing is running (`GameConfig.Events.AutoSchedule`).

## Adding a new admin action

1. Add a definition to `AdminActions.Definitions` with `Permission`,
   `Category`, `Target`, `Punitive`/`Destructive` flags, `Validate` and `Run`
   (and `Offline` for offline-capable actions).
2. Add the permission to the relevant roles in `AdminConfig`.
3. Optionally add a command in `AdminCommands` and a control in the panel
   (`ServerStorage/AdminClient/AdminUI/Tabs`).

The pipeline (auth, rate limits, confirmation, audit) applies automatically.
