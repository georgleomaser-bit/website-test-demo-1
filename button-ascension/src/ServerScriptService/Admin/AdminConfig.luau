--[[
	AdminConfig (ModuleScript)
	Location: ServerScriptService/Admin/AdminConfig

	SERVER-ONLY. ServerScriptService never replicates to clients, so nothing
	in this file can be read by players. Do not move it to ReplicatedStorage.

	================================================================
	HOW TO ADD AN ADMINISTRATOR SAFELY
	================================================================
	1. Find the person's Roblox UserId (a number that never changes):
	     * Open their profile on roblox.com. The URL looks like
	       https://www.roblox.com/users/123456789/profile — 123456789 is the UserId.
	     * Or, in Studio's Command Bar:
	       print(game:GetService("Players"):GetUserIdFromNameAsync("TheirUsername"))
	2. Add one line to AdminConfig.Users below, e.g.
	       [123456789] = "Admin",
	   Valid roles: "Owner", "Admin", "Moderator" (see Roles below).
	3. Publish the place. New servers use the new list; restart old servers
	   (Game Settings > ... > Shut Down All Servers) to apply it everywhere.

	EASIER: Owners can make people Moderator or Admin IN THE GAME, without
	editing this file: Admin Panel (F2) → Moderation tab, or the command
	"/admin setrole <player> moderator". Those roles are stored server-side
	by UserId (DataStore, see AdminConfig.Moderation) and apply in every
	server within seconds. Roles written in this file always win and cannot
	be changed from the game.

	Rules:
	  * Always use UserIds. Never usernames or display names — those can be
	    changed by their owner and could be taken by someone else.
	  * Give the lowest role that does the job. Moderators cannot touch the
	    economy; only Owners can reset progression or announce game-wide.
	  * Remove people who no longer help moderate.
	================================================================
]]

local AdminConfig = {}

-- [UserId] = "Owner" | "Admin" | "Moderator"
AdminConfig.Users = {
	-- [123456789] = "Owner",
	-- [987654321] = "Admin",
	-- [555555555] = "Moderator",
}

-- The Roblox user that owns the place is Owner automatically (user-owned games).
AdminConfig.AutoOwnerForCreator = true

-- For group-owned games, the owner of the group is Owner automatically.
-- (Verified server-side through the group service, never from the client.)
AdminConfig.GroupOwnerIsOwner = true

--[[
	STUDIO TESTING ONLY. Applied only when RunService:IsStudio() is true, so it
	can never grant anything in a live server. Studio's "Local Server" test
	mode creates players Player1, Player2, ... with UserIds -1, -2, ...
	This makes Player1 an Owner, Player2 an Admin, Player3 a Moderator and
	Player4+ normal players, so every permission level can be tested at once.
]]
AdminConfig.StudioTestUsers = {
	[-1] = "Owner",
	[-2] = "Admin",
	[-3] = "Moderator",
}

--[[
	STUDIO TESTING ONLY. A place opened from a file that has never been
	published has no owner (game.CreatorId is 0), so nobody would be Owner in
	Play Solo. With this on, the solo tester is Owner in that one situation.
	It never applies to published places or live servers.
]]
AdminConfig.StudioOwnerWhenUnpublished = true

--[[
	Permissions
	  panel.open               open the panel, dashboard, command bar, help
	  players.view             list online players and basic stats
	  players.inspect          full progression/inventory of a player
	  players.teleport         teleport to a player / bring a player
	  players.kick             kick with a reason
	  players.freeze           freeze / unfreeze
	  players.respawn          reset a character
	  economy.grant            add / remove / set currencies, test rewards
	  economy.reset            reset a player's currencies (destructive)
	  items.grant              grant / remove items and crates
	  items.test               simulate crate odds, forced-rarity test drops
	  progression.grant        upgrade levels, skills, ascensions, levels, skill points
	  progression.reset        reset progression sections (destructive)
	  server.announce          server-wide announcements
	  server.announce.global   game-wide announcements (all servers)
	  server.events            start / stop boost events
	  server.stats             server performance statistics
	  logs.view                audit and security logs of this server
	  logs.persisted           audit logs saved by all servers
	  offline.read             inspect players who are offline
	  offline.write            change data of offline players (verified, lock-checked)
	  players.ban              ban / unban players in every server (up to Limits.MaxBanDays)
	  staff.manage             make players Moderator or Admin in the game (Owner)
]]
AdminConfig.Roles = {
	Owner = {
		Rank = 3,
		Color = Color3.fromRGB(255, 196, 60),
		Permissions = { "*" },
		Limits = {
			MaxCurrency = 1e100,
			MaxItems = 1000,
			MaxChests = 1000,
			MaxRebirths = 100,
			MaxLevels = 500,
			MaxSkillPoints = 1000,
			-- math.huge = no limit; permanent bans allowed.
			MaxBanDays = math.huge,
		},
	},
	Admin = {
		Rank = 2,
		Color = Color3.fromRGB(0, 245, 160),
		Permissions = {
			"panel.open",
			"players.view",
			"players.inspect",
			"players.teleport",
			"players.kick",
			"players.freeze",
			"players.respawn",
			"players.ban",
			"economy.grant",
			"economy.reset",
			"items.grant",
			"items.test",
			"progression.grant",
			"server.announce",
			"server.events",
			"server.stats",
			"logs.view",
			"offline.read",
		},
		Limits = {
			MaxCurrency = 1e15,
			MaxItems = 100,
			MaxChests = 100,
			MaxRebirths = 5,
			MaxLevels = 50,
			MaxSkillPoints = 50,
			MaxBanDays = 30,
		},
	},
	Moderator = {
		Rank = 1,
		Color = Color3.fromRGB(80, 170, 255),
		Permissions = {
			"panel.open",
			"players.view",
			"players.inspect",
			"players.teleport",
			"players.kick",
			"players.freeze",
			"players.respawn",
			"players.ban",
			"server.announce",
			"server.stats",
			"logs.view",
		},
		Limits = {
			MaxCurrency = 0,
			MaxItems = 0,
			MaxChests = 0,
			MaxRebirths = 0,
			MaxLevels = 0,
			MaxSkillPoints = 0,
			MaxBanDays = 7,
		},
	},
}

-- Token buckets per admin. Capacity = burst size, Refill = tokens per second.
AdminConfig.RateLimits = {
	Global = { Capacity = 30, Refill = 3 },
	Categories = {
		read = { Capacity = 20, Refill = 4 },
		player = { Capacity = 10, Refill = 1 },
		punish = { Capacity = 5, Refill = 0.2 },
		economy = { Capacity = 10, Refill = 1 },
		items = { Capacity = 10, Refill = 1 },
		progression = { Capacity = 8, Refill = 0.5 },
		destructive = { Capacity = 3, Refill = 0.05 },
		announce = { Capacity = 3, Refill = 0.1 },
		events = { Capacity = 4, Refill = 0.1 },
		test = { Capacity = 5, Refill = 0.25 },
		staff = { Capacity = 5, Refill = 0.1 },
	},
}

-- Destructive actions must be confirmed with a single-use token within this time.
AdminConfig.ConfirmTokenSeconds = 45

AdminConfig.Text = {
	MaxAnnouncement = 200,
	MaxReason = 200,
	MaxCommand = 300,
}

AdminConfig.Audit = {
	Persist = true,
	StoreName = "ButtonAscension_AdminAudit",
	FlushInterval = 60,
	MaxEntriesPerDay = 1500,
	MemoryLimit = 500,
	-- Unauthorised attempts are logged at most this often per player (seconds).
	DeniedLogCooldown = 10,
}

-- Game-wide announcements use MessagingService. Only Owners have the
-- permission by default; receiving servers re-verify the sender's role.
AdminConfig.CrossServerAnnouncements = {
	Enabled = true,
	Topic = "ButtonAscension_Announce",
}

--[[
	In-game staff roles and bans. Both are stored by UserId in a server-only
	DataStore; servers tell each other about changes over MessagingService and
	then re-read the DataStore (message contents are never trusted).
]]
AdminConfig.Moderation = {
	StoreName = "ButtonAscension_Moderation",
	Topic = "ButtonAscension_Moderation",
	-- Every server also re-reads the lists this often, in case a message was lost.
	RefreshSeconds = 60,
	-- Roles an Owner can hand out in the game. "Owner" is deliberately not here.
	GrantableRoles = { "Moderator", "Admin" },
	MaxStaff = 100,
	MaxBans = 3000,
	-- How long a joining player waits for the ban list after a server starts.
	JoinCheckTimeout = 10,
	-- Also ban through Roblox's own Ban API (Players:BanAsync) in live servers.
	-- Roblox then blocks the player before they can even join, in every server,
	-- and the bans show up in the Creator Hub. Our own list stays the source of truth.
	UseRobloxBanApi = true,
	-- Let Roblox's Ban API also ban suspected alt accounts of the banned player.
	BanAltAccounts = false,
}

-- Key that toggles the panel on keyboards (the panel also has an on-screen button).
AdminConfig.PanelKey = "F2"

return AdminConfig
