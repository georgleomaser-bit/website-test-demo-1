--[[
	AdminCommands (ModuleScript)
	Location: ServerScriptService/Admin/AdminCommands
	Depends on: Admin/AdminActions, Admin/AdminPermissions

	Parses command-bar text into an admin action + arguments. Parsing happens
	on the SERVER; the parsed action then goes through exactly the same
	permission, validation, confirmation, rate-limit and audit pipeline as
	panel buttons.

	Syntax:  [/admin] <command> <args...>
	  * Arguments are separated by spaces; use "double quotes" for spaces.
	  * Players: name / display name prefix, @username, #UserId, me.
	  * Numbers accept 1500, 1,500, 2.5k, 3m, 1b, 4t, 1e6.
	  * The last argument of kick/announce takes the rest of the line.
]]

local AdminActions = require(script.Parent.AdminActions)
local AdminPermissions = require(script.Parent.AdminPermissions)

local AdminCommands = {}

-- Argument types: player, number, integer, word, rest
local COMMANDS = {
	{ Name = "help", Usage = "help [command]", Description = "List commands or show help for one.", Local = "help" },
	{ Name = "players", Usage = "players", Description = "List online players.", Action = "players.list" },
	{ Name = "stats", Usage = "stats <player>", Description = "Show a player's progression (#UserId works offline).", Action = "players.inspect", Args = { { "Target", "player" } } },
	{ Name = "givecash", Usage = "givecash <player> <amount> [currency]", Description = "Add Sparks (or Gems/Prisms).", Action = "economy.add", Args = { { "Target", "player" }, { "Amount", "number" }, { "Currency", "word", true } } },
	{ Name = "removecash", Usage = "removecash <player> <amount> [currency]", Description = "Remove currency.", Action = "economy.remove", Args = { { "Target", "player" }, { "Amount", "number" }, { "Currency", "word", true } } },
	{ Name = "setcash", Usage = "setcash <player> <amount> [currency]", Description = "Set a currency to an exact amount.", Action = "economy.set", Args = { { "Target", "player" }, { "Amount", "number" }, { "Currency", "word", true } } },
	{ Name = "givegems", Usage = "givegems <player> <amount>", Description = "Add Gems.", Action = "economy.add", Fixed = { Currency = "Gems" }, Args = { { "Target", "player" }, { "Amount", "number" } } },
	{ Name = "giveprisms", Usage = "giveprisms <player> <amount>", Description = "Add Prisms (ascension currency).", Action = "economy.add", Fixed = { Currency = "Prisms" }, Args = { { "Target", "player" }, { "Amount", "number" } } },
	{ Name = "reward", Usage = "reward <player> <gems_pack|crate_bundle|frenzy|orb|level_up>", Description = "Grant a test reward.", Action = "economy.reward", Args = { { "Target", "player" }, { "Reward", "word" } } },
	{ Name = "reseteconomy", Usage = "reseteconomy <player>", Description = "Reset all currencies (asks for confirmation).", Action = "economy.reset", Args = { { "Target", "player" } } },
	{ Name = "giveitem", Usage = "giveitem <player> <itemId> [amount]", Description = "Grant an item.", Action = "items.grant", Args = { { "Target", "player" }, { "Item", "word" }, { "Amount", "integer", true } } },
	{ Name = "removeitem", Usage = "removeitem <player> <itemId> [amount]", Description = "Remove copies of an item.", Action = "items.remove", Args = { { "Target", "player" }, { "Item", "word" }, { "Amount", "integer", true } } },
	{ Name = "givechest", Usage = "givechest <player> <chestId> [amount]", Description = "Grant crates.", Action = "chests.grant", Args = { { "Target", "player" }, { "Chest", "word" }, { "Amount", "integer", true } } },
	{ Name = "finditem", Usage = "finditem [search]", Description = "Search item ids.", Action = "items.find", Args = { { "Query", "rest", true } } },
	{ Name = "testroll", Usage = "testroll <chestId> [count] [luck]", Description = "Simulate crate odds without changing any data.", Action = "items.simulate", Args = { { "Chest", "word" }, { "Count", "integer", true }, { "Luck", "number", true } } },
	{ Name = "forceroll", Usage = "forceroll <player> <chestId> <rarity>", Description = "Grant a test drop of an exact rarity.", Action = "items.forceRoll", Args = { { "Target", "player" }, { "Chest", "word" }, { "Rarity", "word" } } },
	{ Name = "kick", Usage = "kick <player> <reason...>", Description = "Kick a player with a reason.", Action = "players.kick", Args = { { "Target", "player" }, { "Reason", "rest" } } },
	{ Name = "tp", Usage = "tp <player>", Description = "Teleport to a player.", Action = "players.teleportTo", Args = { { "Target", "player" } } },
	{ Name = "bring", Usage = "bring <player>", Description = "Bring a player to you.", Action = "players.bring", Args = { { "Target", "player" } } },
	{ Name = "freeze", Usage = "freeze <player>", Description = "Freeze a player.", Action = "players.freeze", Args = { { "Target", "player" } } },
	{ Name = "unfreeze", Usage = "unfreeze <player>", Description = "Unfreeze a player.", Action = "players.unfreeze", Args = { { "Target", "player" } } },
	{ Name = "respawn", Usage = "respawn <player>", Description = "Reset a player's character.", Action = "players.respawn", Args = { { "Target", "player" } } },
	{ Name = "announce", Usage = "announce <message...>", Description = "Server-wide announcement (this server only).", Action = "server.announce", Fixed = { Scope = "server" }, Args = { { "Message", "rest" } } },
	{ Name = "gannounce", Usage = "gannounce <message...>", Description = "Game-wide announcement (all servers).", Action = "server.announce", Fixed = { Scope = "global" }, Args = { { "Message", "rest" } } },
	{ Name = "event", Usage = "event <start|stop> <eventId> [seconds]", Description = "Start or stop a boost event in this server.", Special = "event" },
	{ Name = "setupgrade", Usage = "setupgrade <player> <upgradeId> <level>", Description = "Set a shop upgrade level.", Action = "progression.setUpgrade", Args = { { "Target", "player" }, { "Upgrade", "word" }, { "Level", "integer" } } },
	{ Name = "unlockskill", Usage = "unlockskill <player> <skillId|all>", Description = "Unlock skills for testing.", Action = "progression.unlockSkill", Args = { { "Target", "player" }, { "Skill", "word" } } },
	{ Name = "resetskills", Usage = "resetskills <player>", Description = "Reset a skill tree with refund (confirmation).", Action = "progression.resetSkills", Args = { { "Target", "player" } } },
	{ Name = "giverebirth", Usage = "giverebirth <player> [count]", Description = "Grant ascensions.", Action = "progression.grantRebirth", Args = { { "Target", "player" }, { "Count", "integer", true } } },
	{ Name = "givelevel", Usage = "givelevel <player> [count]", Description = "Grant levels.", Action = "progression.grantLevels", Args = { { "Target", "player" }, { "Count", "integer", true } } },
	{ Name = "givesp", Usage = "givesp <player> <amount>", Description = "Grant Skill Points.", Action = "progression.grantSkillPoints", Args = { { "Target", "player" }, { "Amount", "integer" } } },
	{ Name = "resetprogress", Usage = "resetprogress <player> [upgrades|skills|ascension|inventory|collection|quests|stats|level|all]", Description = "Reset progression (asks for confirmation).", Action = "progression.reset", Args = { { "Target", "player" }, { "Scope", "word", true } } },
	{ Name = "logs", Usage = "logs [filter]", Description = "Show recent audit log entries.", Action = "logs.recent", Args = { { "Filter", "rest", true } } },
	{ Name = "serverinfo", Usage = "serverinfo", Description = "Server performance and player stats.", Action = "server.stats" },
}

local BY_NAME = {}
for _, cmd in ipairs(COMMANDS) do
	BY_NAME[cmd.Name] = cmd
end
AdminCommands.List = COMMANDS

local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }

function AdminCommands.parseNumber(text: string): number?
	local s = string.lower((string.gsub(text, ",", "")))
	local direct = tonumber(s)
	if direct then
		return direct
	end
	local num, suffix = string.match(s, "^(%-?[%d%.]+)(%a+)$")
	if num and SUFFIX[suffix] then
		local n = tonumber(num)
		if n then
			return n * SUFFIX[suffix]
		end
	end
	return nil
end

-- Splits text into tokens, honouring "double quotes". Returns tokens and the
-- raw remainder after each token (used for "rest" arguments).
function AdminCommands.tokenize(text: string): ({ string }, { string })
	local tokens, rests = {}, {}
	local i = 1
	local len = #text
	while i <= len do
		local c = string.sub(text, i, i)
		if string.match(c, "%s") then
			i += 1
		else
			table.insert(rests, string.sub(text, i))
			if c == '"' then
				local close = string.find(text, '"', i + 1, true)
				if close then
					table.insert(tokens, string.sub(text, i + 1, close - 1))
					i = close + 1
				else
					table.insert(tokens, string.sub(text, i + 1))
					i = len + 1
				end
			else
				local stop = string.find(text, "%s", i) or (len + 1)
				table.insert(tokens, string.sub(text, i, stop - 1))
				i = stop
			end
		end
	end
	return tokens, rests
end

function AdminCommands.available(role: string?)
	local out = {}
	for _, cmd in ipairs(COMMANDS) do
		local permission = "panel.open"
		if cmd.Action then
			permission = AdminActions.Definitions[cmd.Action].Permission
		elseif cmd.Special == "event" then
			permission = "server.events"
		end
		if AdminPermissions.has(role, permission) then
			table.insert(out, { Name = cmd.Name, Usage = cmd.Usage, Description = cmd.Description })
		end
	end
	return out
end

local function helpText(role: string?, name: string?): string
	if name then
		local cmd = BY_NAME[string.lower(name)]
		if not cmd then
			return `Unknown command "{name}". Type help for a list.`
		end
		return `{cmd.Usage}\n{cmd.Description}`
	end
	local lines = { "Commands available to your role (prefix /admin is optional):" }
	for _, cmd in ipairs(AdminCommands.available(role)) do
		table.insert(lines, "  " .. cmd.Usage)
	end
	return table.concat(lines, "\n")
end

--[[
	Parses a command line. Returns one of:
	  { Kind = "text", Text = "..." }                 (help output, no action)
	  { Kind = "action", Action = name, Args = {...} }
	  { Kind = "error", Text = "..." }
]]
function AdminCommands.parse(text: string, role: string?)
	local trimmed = string.gsub(text, "^%s*(.-)%s*$", "%1")
	trimmed = string.gsub(trimmed, "^/admin%s*", "")
	trimmed = string.gsub(trimmed, "^[/;:]", "")
	if trimmed == "" then
		return { Kind = "text", Text = helpText(role, nil) }
	end
	local tokens, rests = AdminCommands.tokenize(trimmed)
	local name = string.lower(tokens[1])
	local cmd = BY_NAME[name]
	if not cmd then
		return { Kind = "error", Text = `Unknown command "{tokens[1]}". Type help for a list.` }
	end
	if cmd.Local == "help" then
		return { Kind = "text", Text = helpText(role, tokens[2]) }
	end

	if cmd.Special == "event" then
		local verb = tokens[2] and string.lower(tokens[2])
		if (verb ~= "start" and verb ~= "stop") or not tokens[3] then
			return { Kind = "error", Text = "Usage: " .. cmd.Usage }
		end
		local args = { Event = tokens[3] }
		if verb == "start" and tokens[4] then
			local seconds = AdminCommands.parseNumber(tokens[4])
			if not seconds then
				return { Kind = "error", Text = `"{tokens[4]}" is not a number of seconds.` }
			end
			args.Duration = math.floor(seconds)
		end
		return { Kind = "action", Action = if verb == "start" then "server.eventStart" else "server.eventStop", Args = args }
	end

	local args = {}
	for key, value in pairs(cmd.Fixed or {}) do
		args[key] = value
	end
	local specs = cmd.Args or {}
	for index, spec in ipairs(specs) do
		local key, kind, optional = spec[1], spec[2], spec[3]
		local tokenIndex = index + 1
		local token = tokens[tokenIndex]
		if kind == "rest" then
			local rest = rests[tokenIndex]
			if rest == nil or rest == "" then
				if not optional then
					return { Kind = "error", Text = "Usage: " .. cmd.Usage }
				end
			else
				args[key] = rest
			end
			break
		end
		if token == nil then
			if not optional then
				return { Kind = "error", Text = "Usage: " .. cmd.Usage }
			end
		elseif kind == "number" or kind == "integer" then
			local n = AdminCommands.parseNumber(token)
			if not n then
				return { Kind = "error", Text = `"{token}" is not a valid number. Usage: {cmd.Usage}` }
			end
			if kind == "integer" and n ~= math.floor(n) then
				return { Kind = "error", Text = `"{token}" must be a whole number.` }
			end
			args[key] = n
		else
			args[key] = token
		end
	end
	if #tokens > #specs + 1 and (#specs == 0 or specs[#specs][2] ~= "rest") then
		return { Kind = "error", Text = "Too many arguments. Usage: " .. cmd.Usage }
	end
	return { Kind = "action", Action = cmd.Action, Args = args }
end

return AdminCommands
