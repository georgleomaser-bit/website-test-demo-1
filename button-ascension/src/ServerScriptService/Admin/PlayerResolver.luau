--[[
	PlayerResolver (ModuleScript)
	Location: ServerScriptService/Admin/PlayerResolver

	Safely turns admin input into exactly one online player.
	Resolution order (case-insensitive):
	  me              -> the admin
	  #12345          -> online player with that UserId (or a UserId for offline tools)
	  @name           -> exact username only
	  exact username  -> that player
	  exact display name, if unique
	  unique prefix of a username or display name
	Anything matching more than one player is rejected with the candidates
	listed, so a typo can never hit the wrong person.
]]

local Players = game:GetService("Players")

local PlayerResolver = {}

local function describe(p: Player): string
	if p.DisplayName ~= p.Name then
		return `{p.DisplayName} (@{p.Name})`
	end
	return "@" .. p.Name
end

local function listCandidates(list: { Player }): string
	local names = {}
	for i, p in ipairs(list) do
		if i > 5 then
			table.insert(names, "…")
			break
		end
		table.insert(names, describe(p))
	end
	return table.concat(names, ", ")
end

-- Parses "#123" (or a bare number when allowBare) into a UserId.
function PlayerResolver.parseUserId(query: string, allowBare: boolean?): number?
	local digits = string.match(query, "^#(%-?%d+)$")
	if not digits and allowBare then
		digits = string.match(query, "^(%-?%d+)$")
	end
	local id = digits and tonumber(digits)
	if id and math.abs(id) < 2 ^ 53 then
		return id
	end
	return nil
end

-- Returns (player, nil) or (nil, errorMessage).
function PlayerResolver.resolve(query: any, requester: Player?): (Player?, string?)
	if type(query) == "number" then
		local p = Players:GetPlayerByUserId(query)
		if p then
			return p, nil
		end
		return nil, `No online player has UserId {query}.`
	end
	if type(query) ~= "string" then
		return nil, "Specify a player."
	end
	local q = string.lower((string.gsub(query, "^%s*(.-)%s*$", "%1")))
	if q == "" or #q > 50 then
		return nil, "Specify a player."
	end
	if q == "me" then
		if requester then
			return requester, nil
		end
		return nil, "'me' is not available here."
	end

	local userId = PlayerResolver.parseUserId(q, false)
	if userId then
		local p = Players:GetPlayerByUserId(userId)
		if p then
			return p, nil
		end
		return nil, `No online player has UserId {userId}.`
	end

	local exactOnly = false
	if string.sub(q, 1, 1) == "@" then
		q = string.sub(q, 2)
		exactOnly = true
	end

	local all = Players:GetPlayers()
	for _, p in ipairs(all) do
		if string.lower(p.Name) == q then
			return p, nil
		end
	end
	if exactOnly then
		return nil, `No online player is named @{q}.`
	end

	local displayMatches = {}
	for _, p in ipairs(all) do
		if string.lower(p.DisplayName) == q then
			table.insert(displayMatches, p)
		end
	end
	if #displayMatches == 1 then
		return displayMatches[1], nil
	elseif #displayMatches > 1 then
		return nil, `"{query}" matches several display names: {listCandidates(displayMatches)}. Use @username or #UserId.`
	end

	local prefixMatches = {}
	for _, p in ipairs(all) do
		local name = string.lower(p.Name)
		local display = string.lower(p.DisplayName)
		if string.sub(name, 1, #q) == q or string.sub(display, 1, #q) == q then
			table.insert(prefixMatches, p)
		end
	end
	if #prefixMatches == 1 then
		return prefixMatches[1], nil
	elseif #prefixMatches > 1 then
		return nil, `"{query}" is ambiguous: {listCandidates(prefixMatches)}. Type more of the name, @username or #UserId.`
	end
	return nil, `No online player matches "{query}".`
end

return PlayerResolver
