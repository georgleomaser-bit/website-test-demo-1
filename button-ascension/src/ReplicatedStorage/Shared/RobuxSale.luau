--[[
	RobuxSale (ModuleScript)
	Location: ReplicatedStorage/Shared/RobuxSale
	Depends on: Shared/Remotes (ServerState folder name)

	How a store entry (Config/GamePasses or Config/DevProducts) is sold on Roblox:
	  "pass"     a game pass: bought once, owned forever
	  "product"  a developer product: can be bought again and again

	The config holds the ID in GamePassId or ProductId. When an entry also has
	a HubName (its exact name in the Creator Hub), the server asks Roblox at
	start which kind that ID really is, so an ID pasted into the "wrong" field
	still works. The answer is published as the ServerState attribute
	"Sale_<key>" = "pass:<id>" / "product:<id>" so clients prompt the right
	purchase. Until then (and in tests without a server) the config decides.
	Nothing here grants anything: purchases are granted by the server only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent.Remotes)

local RobuxSale = {}

local function stateFolder(): Instance?
	return ReplicatedStorage:FindFirstChild(Remotes.StateFolderName)
end

-- The configured kind and ID, ignoring the server's check.
function RobuxSale.configured(entry): (string?, number)
	if type(entry.GamePassId) == "number" and entry.GamePassId > 0 then
		return "pass", entry.GamePassId
	end
	if type(entry.ProductId) == "number" and entry.ProductId > 0 then
		return "product", entry.ProductId
	end
	return nil, 0
end

-- ("pass" | "product" | nil, id): how this entry is sold right now. The
-- server's answer only decides the kind, and only for the ID it checked: if
-- the config now holds another ID, the config wins.
function RobuxSale.of(entry): (string?, number)
	local configuredKind, configuredId = RobuxSale.configured(entry)
	if not configuredKind then
		return nil, 0
	end
	local folder = stateFolder()
	local value = folder and folder:GetAttribute("Sale_" .. entry.Key)
	if type(value) == "string" then
		local kind, id = string.match(value, "^(%a+):(%d+)$")
		if (kind == "pass" or kind == "product") and tonumber(id) == configuredId then
			return kind, configuredId
		end
	end
	return configuredKind, configuredId
end

-- Server only: records the kind confirmed with Roblox.
function RobuxSale.publish(entry, kind: string, id: number)
	local folder = stateFolder()
	if folder then
		folder:SetAttribute("Sale_" .. entry.Key, `{kind}:{math.floor(id)}`)
	end
end

-- Server only: marks that every entry has been checked (ownership checks wait for it).
function RobuxSale.markResolved()
	local folder = stateFolder()
	if folder then
		folder:SetAttribute("SalesResolved", true)
	end
end

function RobuxSale.isResolved(): boolean
	local folder = stateFolder()
	return folder ~= nil and folder:GetAttribute("SalesResolved") == true
end

return RobuxSale
