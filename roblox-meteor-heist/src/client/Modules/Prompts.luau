-- =====================================================================
--  PROMPTS an Meteoren/Aliens in den Basen:
--   "Klauen" (StealPrompt)   nur bei FREMDEN Basen, die nicht gesperrt sind
--   "Verkaufen" (SellPrompt) nur in deiner EIGENEN Base
--  Der Server prüft beim Auslösen trotzdem alles – das hier ist nur für die Übersicht.
-- =====================================================================

local Players = game:GetService("Players")

local Prompts = {}

local player = Players.LocalPlayer
local UPDATE_INTERVAL = 0.3

-- Prompt -> Base-Model (oder false, wenn keine Base gefunden wurde)
local tracked: { [ProximityPrompt]: Instance | false } = {}
local photoMode = false
local carrying = false

-- Base finden: das Base-Model hat die Attribute PlotIndex, OwnerUserId und LockedUntil.
-- (Meteore/Aliens im Slot tragen auch PlotIndex + OwnerUserId, aber NICHT LockedUntil –
--  deshalb zuerst nach LockedUntil suchen, sonst wüssten wir nicht, ob die Base gesperrt ist.)
local function findPlot(inst: Instance): Instance?
	local fallback: Instance? = nil
	local current = inst.Parent
	while current and current ~= workspace do
		if current:GetAttribute("LockedUntil") ~= nil then
			return current
		end
		if not fallback and current:GetAttribute("PlotIndex") ~= nil then
			fallback = current
		end
		current = current.Parent
	end
	return fallback
end

local function setEnabled(prompt: ProximityPrompt, enabled: boolean)
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

-- Pro Durchlauf merken wir uns je Base "gehört mir?" und "gesperrt?" (statt pro Prompt neu zu fragen)
local mineCache: { [Instance]: boolean } = {}
local lockedCache: { [Instance]: boolean } = {}

local function plotStatus(plot: Instance): (boolean, boolean)
	local isMine = mineCache[plot]
	local locked = lockedCache[plot]
	if isMine == nil or locked == nil then
		isMine = plot:GetAttribute("OwnerUserId") == player.UserId
		local lockedUntil = tonumber(plot:GetAttribute("LockedUntil")) or 0
		locked = lockedUntil > workspace:GetServerTimeNow()
		mineCache[plot] = isMine
		lockedCache[plot] = locked
	end
	return isMine == true, locked == true
end

local function updatePrompt(prompt: ProximityPrompt, plot: Instance | false)
	if photoMode then
		setEnabled(prompt, false)
		return
	end
	if not plot then
		return
	end
	local isMine, locked = plotStatus(plot)
	if prompt.Name == "SellPrompt" then
		setEnabled(prompt, isMine)
	elseif prompt.Name == "StealPrompt" then
		setEnabled(prompt, not isMine and not locked and not carrying)
	end
end

local function track(inst: Instance)
	if inst:IsA("ProximityPrompt") and (inst.Name == "SellPrompt" or inst.Name == "StealPrompt") then
		if tracked[inst] ~= nil then
			return
		end
		local plot = findPlot(inst) or false
		tracked[inst] = plot
		-- frisch nachsehen (der Zwischenspeicher könnte vom letzten Durchlauf sein)
		table.clear(mineCache)
		table.clear(lockedCache)
		updatePrompt(inst, plot)
	end
end

-- Kaufen-Prompts am Laufband: Der Meteor steht auf dem Server am Bandstart (nur wir bewegen ihn
-- lokal), deshalb ist die Server-Reichweite riesig. Die echte Reichweite steht im Attribut
-- "ClientMaxDistance" und wird hier lokal eingestellt.
local function applyClientReach(prompt: ProximityPrompt)
	local reach = tonumber(prompt:GetAttribute("ClientMaxDistance"))
	if reach and reach > 0 and prompt.MaxActivationDistance ~= reach then
		prompt.MaxActivationDistance = reach
	end
end

local function watchReach(inst: Instance)
	if not inst:IsA("ProximityPrompt") or inst.Name == "SellPrompt" or inst.Name == "StealPrompt" then
		return
	end
	applyClientReach(inst)
	inst:GetAttributeChangedSignal("ClientMaxDistance"):Connect(function()
		applyClientReach(inst)
	end)
end

function Prompts.UpdateAll()
	table.clear(mineCache)
	table.clear(lockedCache)
	for prompt, plot in pairs(tracked) do
		if prompt.Parent then
			-- Base noch unbekannt (Prompt kam vor der Base an)? Nochmal suchen
			if not plot then
				plot = findPlot(prompt) or false
				tracked[prompt] = plot
			end
			updatePrompt(prompt, plot)
		else
			tracked[prompt] = nil
		end
	end
end

-- Gehört dieser Prompt zu den Klauen/Verkaufen-Prompts? (für den Foto-Modus)
function Prompts.IsTracked(prompt: ProximityPrompt): boolean
	return tracked[prompt] ~= nil
end

function Prompts.SetPhotoMode(enabled: boolean)
	photoMode = enabled
	Prompts.UpdateAll()
end

function Prompts.OnState(state: any)
	local now = state ~= nil and state.Carrying == true
	if now ~= carrying then
		carrying = now
		Prompts.UpdateAll()
	end
end

function Prompts.Init(map: Instance)
	for _, inst in ipairs(map:GetDescendants()) do
		watchReach(inst)
	end
	map.DescendantAdded:Connect(watchReach)
	task.spawn(function()
		-- Basen liegen im Ordner "Plots"; falls es ihn nicht gibt, die ganze Map beobachten
		local container: Instance = map:WaitForChild("Plots", 15) or map
		for _, inst in ipairs(container:GetDescendants()) do
			track(inst)
		end
		container.DescendantAdded:Connect(track)
		while true do
			task.wait(UPDATE_INTERVAL)
			local ok, err = pcall(Prompts.UpdateAll)
			if not ok then
				warn("[Prompts] " .. tostring(err))
			end
		end
	end)
end

return Prompts
