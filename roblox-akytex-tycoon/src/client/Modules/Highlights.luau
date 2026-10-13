-- =====================================================================
--  AKYTEX TYCOON – Zentraler Highlight-Verteiler (Client/Modules/Highlights)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.5, §C16 (Highlights ≤ 31). CC 1:1.
--
--  Roblox zeigt höchstens 31 Highlights gleichzeitig – mehr werden einfach nicht gezeichnet.
--  Darum holt sich JEDES Modul seine Highlights hier ab (Etagen-/Möbel-Auswahl im Tower, Admin-ESP ≤ 20, …).
--  Feste Vorräte: ein Highlight wird nach Release wiederverwendet, nie neu gebaut.
--
--  Öffentliche API:
--    Highlights.Acquire(owner, adornee, props): handle?    nil, wenn das Budget (31) voll ist
--        props { Outline: Color3?, Fill: Color3?, FillTransparency: number?, Depth: Enum.HighlightDepthMode? }
--    Highlights.Update(handle, props)          Farben/Tiefe eines vorhandenen Handles ändern
--    Highlights.Release(handle)                Highlights.ReleaseOwner(owner)
--    Highlights.Count(): number                Highlights.CountOwner(owner): number
--    Highlights.Pulse(owner, seconds)          alle Handles des Owners kurz auf AlwaysOnTop (z. B. "hier klicken")
--    Highlights.Init(ctx) / Highlights.Start()
--  Owner-Grenzen: "AdminESP" ≤ 20. Verschwindet das Ziel (gestreamt/zerstört), wird automatisch freigegeben.
-- =====================================================================

local Highlights = {}

type Props = {
	Outline: Color3?,
	Fill: Color3?,
	FillTransparency: number?,
	Depth: Enum.HighlightDepthMode?,
}

export type Handle = {
	Id: number,
	Owner: string,
	Highlight: Highlight,
	Adornee: Instance,
	Depth: Enum.HighlightDepthMode,
	PulseUntil: number,
	Conn: RBXScriptConnection?,
	Alive: boolean,
}

local DEFAULT_CAP = 31
local OWNER_CAPS: { [string]: number } = { AdminESP = 20 }
local WHITE = Color3.new(1, 1, 1)

local ctx: any = nil
local cap = DEFAULT_CAP
local folder: Folder? = nil
local free: { Highlight } = {}
local created = 0
local active: { [Handle]: boolean } = {}
local activeCount = 0
local ownerCount: { [string]: number } = {}
local nextId = 0
local pulseToken: { [string]: number } = {}

local function getFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "AkytexTycoonHighlights"
	newFolder.Parent = workspace
	folder = newFolder
	return newFolder
end

local function takeHighlight(): Highlight?
	local highlight = table.remove(free)
	if highlight and highlight.Parent ~= nil then
		return highlight
	end
	-- (zerstört? dann zählt es nicht mehr zum Vorrat)
	if highlight then
		created -= 1
	end
	if created >= cap then
		return nil
	end
	created += 1
	local newHighlight = Instance.new("Highlight")
	newHighlight.Name = "ATHighlight"
	newHighlight.Enabled = false
	newHighlight.Parent = getFolder()
	return newHighlight
end

local function applyProps(handle: Handle, props: Props?)
	local highlight = handle.Highlight
	local p: Props = props or {}
	highlight.OutlineColor = p.Outline or highlight.OutlineColor
	highlight.OutlineTransparency = 0
	highlight.FillColor = p.Fill or (p.Outline or WHITE)
	local fillT = p.FillTransparency
	if type(fillT) == "number" and fillT == fillT then
		highlight.FillTransparency = math.clamp(fillT, 0, 1)
	elseif props then
		highlight.FillTransparency = 1 -- Standard: nur Umriss
	end
	if p.Depth then
		handle.Depth = p.Depth
	end
	highlight.DepthMode = if os.clock() < handle.PulseUntil then Enum.HighlightDepthMode.AlwaysOnTop else handle.Depth
end

function Highlights.Release(handle: any)
	if type(handle) ~= "table" or not active[handle] then
		return
	end
	local h: Handle = handle
	active[h] = nil
	h.Alive = false
	activeCount -= 1
	ownerCount[h.Owner] = math.max(0, (ownerCount[h.Owner] or 1) - 1)
	if h.Conn then
		h.Conn:Disconnect()
		h.Conn = nil
	end
	local highlight = h.Highlight
	if highlight.Parent ~= nil then
		highlight.Enabled = false
		highlight.Adornee = nil
		table.insert(free, highlight)
	else
		created -= 1
	end
end

function Highlights.Acquire(owner: string, adornee: Instance, props: Props?): any?
	if type(owner) ~= "string" or typeof(adornee) ~= "Instance" or not adornee:IsDescendantOf(workspace) then
		return nil
	end
	-- dasselbe Ziel vom selben Owner: vorhandenes Handle wiederverwenden
	for handle in pairs(active) do
		if handle.Owner == owner and handle.Adornee == adornee then
			applyProps(handle, props)
			return handle
		end
	end
	if activeCount >= cap then
		return nil
	end
	local ownerCap = OWNER_CAPS[owner]
	if ownerCap and (ownerCount[owner] or 0) >= ownerCap then
		return nil
	end
	local highlight = takeHighlight()
	if not highlight then
		return nil
	end
	nextId += 1
	local handle: Handle = {
		Id = nextId,
		Owner = owner,
		Highlight = highlight,
		Adornee = adornee,
		Depth = Enum.HighlightDepthMode.Occluded,
		PulseUntil = 0,
		Conn = nil,
		Alive = true,
	}
	active[handle] = true
	activeCount += 1
	ownerCount[owner] = (ownerCount[owner] or 0) + 1
	highlight.Adornee = adornee
	applyProps(handle, props or {})
	highlight.Enabled = true
	-- Ziel verschwindet (Streaming, Tower-Umbau, Character weg): automatisch freigeben
	handle.Conn = adornee.AncestryChanged:Connect(function()
		if not adornee:IsDescendantOf(workspace) then
			Highlights.Release(handle)
		end
	end)
	return handle
end

function Highlights.Update(handle: any, props: Props)
	if type(handle) == "table" and active[handle] and type(props) == "table" then
		applyProps(handle, props)
	end
end

function Highlights.ReleaseOwner(owner: string)
	local list: { Handle } = {}
	for handle in pairs(active) do
		if handle.Owner == owner then
			table.insert(list, handle)
		end
	end
	for _, handle in ipairs(list) do
		Highlights.Release(handle)
	end
end

function Highlights.Count(): number
	return activeCount
end

function Highlights.CountOwner(owner: string): number
	return ownerCount[owner] or 0
end

-- Kurzer Puls: dieselben Handles kurz durch Wände sichtbar, danach zurück zur eigenen Tiefe
function Highlights.Pulse(owner: string, seconds: number)
	if type(owner) ~= "string" or type(seconds) ~= "number" or seconds ~= seconds then
		return
	end
	seconds = math.clamp(seconds, 0.05, 10)
	local untilT = os.clock() + seconds
	for handle in pairs(active) do
		if handle.Owner == owner then
			handle.PulseUntil = untilT
			handle.Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		end
	end
	pulseToken[owner] = (pulseToken[owner] or 0) + 1
	local token = pulseToken[owner]
	task.delay(seconds, function()
		if pulseToken[owner] ~= token then
			return
		end
		for handle in pairs(active) do
			if handle.Owner == owner and os.clock() >= handle.PulseUntil then
				handle.Highlight.DepthMode = handle.Depth
			end
		end
	end)
end

function Highlights.Init(context: any)
	ctx = context
	local config = ctx and ctx.Config
	local value = config and config.Client and config.Client.HighlightCap
	if type(value) == "number" and value >= 1 then
		cap = math.clamp(math.floor(value), 1, DEFAULT_CAP)
	end
	getFolder()
end

function Highlights.Start() end

return Highlights
