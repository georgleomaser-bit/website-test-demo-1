-- =====================================================================
--  PROMPTS passend ein-/ausblenden:
--   in den Basen:
--     "Klauen" (StealPrompt)     nur bei FREMDEN Basen, die nicht gesperrt sind
--     "Verkaufen" (SellPrompt)   nur in deiner EIGENEN Base
--   am Förderband / am Boden (Ordner BeltMeteors, GroundMeteors):
--     "Klauen"/"Schnappen" (GrabPrompt)  aus, solange du schon etwas trägst
--     "Kaufen" (BuyPrompt)               immer an (wird automatisch geliefert)
--  Dazu: Hinweis unten im HUD, solange ein Förderband-/Boden-Prompt sichtbar ist
--  (E = Klauen gratis, F = Kaufen). Der Server prüft beim Auslösen trotzdem alles.
--  Halte-Sperre: Wer E an einem Band-Meteor hält, dem springt der Prompt nicht zum nächsten Meteor.
--  Eingefroren (Falle / Admin): Klauen und Schnappen sind aus.
-- =====================================================================

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Prompts = {}

local player = Players.LocalPlayer
local UPDATE_INTERVAL = 0.3

local ctx: any = nil

-- Prompt -> Base-Model (oder false, wenn keine Base gefunden wurde)
local tracked: { [ProximityPrompt]: Instance | false } = {}
-- GrabPrompts an Förderband-Meteoren und Eiern am Boden -> true = von UNS ausgeschaltet
-- (nur die schalten wir später wieder ein; sonst gilt, was der Server eingestellt hat)
local grabPrompts: { [ProximityPrompt]: boolean } = {}
-- Gerade sichtbare Förderband-/Boden-Prompts -> Art ("Belt", "Ground", "Free")
local shownPrompts: { [ProximityPrompt]: string } = {}
local photoMode = false
local carrying = false
local frozen = false -- eigener HumanoidRootPart verankert (Falle / Admin-Freeze)
local tipShown = false

-- Klauen am Förderband: Während E gehalten wird (Config.BeltGrabHold), fährt das Band weiter.
-- Roblox könnte dann zum nächsten Meteor wechseln und das Halten abbrechen -> solange die
-- ANDEREN GrabPrompts lokal aus. Spätestens nach HOLD_SAFETY Sekunden ist alles wieder normal.
local HOLD_SAFETY = 3
local HOLD_RELEASE_AFTER_TRIGGER = 0.8 -- bis der Server "trägt" meldet (dann bleiben sie sowieso aus)
local HOLD_RELEASE_AFTER_CANCEL = 0.1
local holdPrompt: ProximityPrompt? = nil
local holdTriggered = false
local holdDisabled: { [ProximityPrompt]: boolean } = {}
local holdToken = 0

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
		setEnabled(prompt, not isMine and not locked and not carrying and not frozen)
	end
end

local function isFrozen(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and root.Anchored
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

-- Liegt der Prompt an einem Meteor auf dem Förderband / am Boden? -> "Belt" / "Ground" / nil
local function meteorFolderKind(prompt: Instance): string?
	local part = prompt.Parent
	local folder = part and part.Parent
	if not folder then
		return nil
	end
	if folder.Name == "BeltMeteors" then
		return "Belt"
	elseif folder.Name == "GroundMeteors" then
		return "Ground"
	end
	return nil
end

-- Art des Hinweises: Förderband, Ei am Boden (tragen) oder Gratis-Zone (automatische Lieferung)
local function hintKind(prompt: ProximityPrompt): string?
	local kind = meteorFolderKind(prompt)
	if kind == "Ground" and prompt.Name == "BuyPrompt" then
		return "Free"
	end
	if kind and (prompt.Name == "GrabPrompt" or prompt.Name == "BuyPrompt") then
		return kind
	end
	return nil
end

local function updateGrab(prompt: ProximityPrompt)
	if photoMode or carrying or frozen then
		-- auch merken, wenn er schon aus war (z.B. vom Foto-Modus) -> später sicher wieder an
		grabPrompts[prompt] = true
		setEnabled(prompt, false)
	elseif grabPrompts[prompt] then
		grabPrompts[prompt] = false
		if not holdDisabled[prompt] then
			setEnabled(prompt, true)
		end
	end
end

-- Halte-Sperre aufheben: nur wieder einschalten, was WIR wegen des Haltens ausgeschaltet haben
-- (und was nicht inzwischen wegen Tragen/Foto-Modus aus sein soll)
local function releaseHold()
	holdPrompt = nil
	holdTriggered = false
	holdToken += 1
	for prompt in pairs(holdDisabled) do
		holdDisabled[prompt] = nil
		if
			prompt:IsDescendantOf(workspace)
			and not photoMode
			and not carrying
			and not frozen
			and grabPrompts[prompt] == false
		then
			setEnabled(prompt, true)
		end
	end
end

local function scheduleRelease(delay: number)
	holdToken += 1
	local token = holdToken
	task.delay(delay, function()
		if holdToken == token then
			releaseHold()
		end
	end)
end

-- Einen GrabPrompt wegen des Haltens ausschalten (nur wenn er gerade an ist)
local function holdOff(prompt: ProximityPrompt)
	if prompt ~= holdPrompt and prompt.Enabled then
		holdDisabled[prompt] = true
		prompt.Enabled = false
	end
end

-- Förderband-Meteore werden lokal bewegt (der Server lässt sie am Bandstart stehen) ->
-- echte Reichweite steht im Attribut "ClientMaxDistance" und wird hier lokal eingestellt.
-- Der Server setzt das Attribut schon, bevor der Meteor in die Map kommt -> einmal lesen reicht
-- (keine Verbindung pro Meteor = kein Speicherleck).
local function watchReach(inst: Instance)
	if not inst:IsA("ProximityPrompt") or inst.Name == "SellPrompt" or inst.Name == "StealPrompt" then
		return
	end
	local reach = tonumber(inst:GetAttribute("ClientMaxDistance"))
	if reach and reach > 0 and inst.MaxActivationDistance ~= reach then
		inst.MaxActivationDistance = reach
	end
	if inst.Name == "GrabPrompt" and grabPrompts[inst] == nil and meteorFolderKind(inst) then
		grabPrompts[inst] = false
		updateGrab(inst)
		if holdPrompt then
			holdOff(inst) -- neuer Meteor während des Haltens -> auch aus
		end
	end
end

-- Welcher Hinweis gilt gerade? Förderband vor Boden vor Gratis-Zone
local HINT_PRIORITY: { [string]: number } = { Belt = 3, Ground = 2, Free = 1 }

local function refreshHint()
	if not ctx then
		return
	end
	local best: string? = nil
	for prompt, kind in pairs(shownPrompts) do
		if not prompt.Enabled or not prompt:IsDescendantOf(workspace) then
			shownPrompts[prompt] = nil
		elseif not best or HINT_PRIORITY[kind] > HINT_PRIORITY[best] then
			best = kind
		end
	end
	ctx.Hud.SetPromptHint(if photoMode then nil else best)
end

function Prompts.UpdateAll()
	table.clear(mineCache)
	table.clear(lockedCache)
	frozen = isFrozen()
	-- Sicherheitsnetz für die Halte-Sperre: der gehaltene Meteor ist weg (geklaut, gekauft, Bandende)
	-- und Roblox hat kein "losgelassen" mehr gemeldet -> sofort freigeben statt erst nach HOLD_SAFETY
	local held = holdPrompt
	if held and not holdTriggered and not held:IsDescendantOf(workspace) then
		releaseHold()
	end
	for prompt, plot in pairs(tracked) do
		-- IsDescendantOf statt Parent: wird nur das Alien-Model zerstört, behält der Prompt
		-- (je nach Destroy-Replikation) seinen Parent – er hängt dann aber nicht mehr in der Welt.
		if prompt:IsDescendantOf(workspace) then
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
	for prompt in pairs(grabPrompts) do
		if prompt:IsDescendantOf(workspace) then
			-- Der Server schaltet Prompts beim Landen ein -> beim Tragen hier wieder aus
			updateGrab(prompt)
		else
			grabPrompts[prompt] = nil
		end
	end
	refreshHint()
end

-- Gehört dieser Prompt zu den Prompts, die dieses Modul ein-/ausschaltet? (für den Foto-Modus)
function Prompts.IsTracked(prompt: ProximityPrompt): boolean
	return tracked[prompt] ~= nil or grabPrompts[prompt] ~= nil
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

function Prompts.Init(map: Instance, context: any)
	ctx = context
	for _, inst in ipairs(map:GetDescendants()) do
		watchReach(inst)
	end
	map.DescendantAdded:Connect(watchReach)

	-- Hinweis im HUD, solange ein Förderband-/Boden-Prompt in Reichweite angezeigt wird
	ProximityPromptService.PromptShown:Connect(function(prompt)
		local kind = hintKind(prompt)
		if kind then
			shownPrompts[prompt] = kind
			refreshHint()
			if kind == "Belt" and not tipShown and ctx then
				tipShown = true
				ctx.Toast(
					"💡 Klauen ist GRATIS – aber du musst das Ei selbst heimtragen! Kaufen = Lieferung.",
					"Info"
				)
			end
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if shownPrompts[prompt] then
			shownPrompts[prompt] = nil
			refreshHint()
		end
		-- Der gehaltene Prompt verschwindet (Meteor geklaut/gekauft/am Bandende, außer Reichweite):
		-- Halte-Sperre gleich aufheben, sonst kann man bis zu HOLD_SAFETY Sekunden nichts schnappen
		if prompt == holdPrompt and not holdTriggered then
			scheduleRelease(HOLD_RELEASE_AFTER_CANCEL)
		end
	end)

	-- Halte-Sperre am Förderband (siehe oben): E auf einem Band-Meteor halten -> andere GrabPrompts aus
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt.Name ~= "GrabPrompt" or meteorFolderKind(prompt) ~= "Belt" or photoMode or carrying or frozen then
			return
		end
		releaseHold()
		holdPrompt = prompt
		for other in pairs(grabPrompts) do
			holdOff(other)
		end
		scheduleRelease(HOLD_SAFETY)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt == holdPrompt then
			holdTriggered = true
			scheduleRelease(HOLD_RELEASE_AFTER_TRIGGER)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		-- losgelassen (oder fertig): kurz warten – kommt gleich noch "Triggered", gilt dessen Zeit
		if prompt == holdPrompt and not holdTriggered then
			scheduleRelease(HOLD_RELEASE_AFTER_CANCEL)
		end
	end)

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
