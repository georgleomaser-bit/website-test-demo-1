-- =====================================================================
--  FOTO-MODUS (Taste H, nur Admins) – für schöne Thumbnail-Screenshots.
--  Rein clientseitig: blendet die eigene UI, die Roblox-Oberfläche, fliegende Zahlen,
--  Admin-Ansagen, das "!" der Parade-Aliens und alle Prompts aus. Nochmal H = alles wieder an.
-- =====================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local PhotoMode = {}

local player = Players.LocalPlayer
local ctx: any = nil

local photoMode = false
local photoPending = false -- Toast wird gezeigt, gleich wird ausgeblendet
local photoToken = 0
local photoHidden: { [ProximityPrompt]: boolean } = {} -- Prompts, die der Foto-Modus ausgeschaltet hat
local photoConnections: { RBXScriptConnection } = {}
local savedCoreGui: { [Enum.CoreGuiType]: boolean } = {}

local function hidePrompt(prompt: ProximityPrompt)
	local function off()
		if photoMode and prompt.Enabled then
			photoHidden[prompt] = true
			prompt.Enabled = false
		end
	end
	off()
	-- Der Server schaltet Prompts evtl. wieder ein -> sofort wieder aus
	table.insert(photoConnections, prompt:GetPropertyChangedSignal("Enabled"):Connect(off))
end

local function startPhotoMode()
	photoMode = true
	UI.CloseAll() -- offene Fenster zu, damit sie nach dem Foto nicht im Weg sind
	ctx.Gui.Enabled = false
	ctx.Prompts.SetPhotoMode(true)
	ctx.Effects.SetHidden(true)
	if ctx.Parade then
		ctx.Parade.SetHidden(true) -- "!" über erschrockenen Parade-Aliens aus
	end
	-- Roblox-Oberfläche (Chat, Spielerliste, Rucksack ...) merken und ausblenden
	savedCoreGui = {}
	for _, item in ipairs(Enum.CoreGuiType:GetEnumItems()) do
		if item ~= Enum.CoreGuiType.All then
			local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, item)
			-- Nicht lesbar -> beim Beenden trotzdem wieder einschalten (sonst bliebe es für immer aus)
			savedCoreGui[item] = not ok or enabled == true
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			hidePrompt(inst)
		end
	end
	table.insert(
		photoConnections,
		workspace.DescendantAdded:Connect(function(inst)
			if inst:IsA("ProximityPrompt") then
				hidePrompt(inst)
			end
		end)
	)
end

local function stopPhotoMode()
	photoMode = false
	for _, connection in ipairs(photoConnections) do
		connection:Disconnect()
	end
	photoConnections = {}
	ctx.Gui.Enabled = true
	ctx.Effects.SetHidden(false)
	if ctx.Parade then
		ctx.Parade.SetHidden(false)
	end
	for item, enabled in pairs(savedCoreGui) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, enabled)
	end
	-- Kaufen-Prompts wieder an (der Server prüft beim Kaufen ohnehin alles),
	-- Klauen/Verkaufen stellt das Prompts-Modul wieder richtig ein.
	for prompt in pairs(photoHidden) do
		if prompt.Parent and not ctx.Prompts.IsTracked(prompt) then
			prompt.Enabled = true
		end
	end
	photoHidden = {}
	ctx.Prompts.SetPhotoMode(false)
end

function PhotoMode.Toggle()
	if photoMode or photoPending then
		photoToken += 1
		photoPending = false
		if photoMode then
			stopPhotoMode()
			ctx.Toast("📸 Foto-Modus aus", "Info")
		end
		return
	end
	if player:GetAttribute("IsAdmin") ~= true then
		return
	end
	photoPending = true
	photoToken += 1
	local token = photoToken
	ctx.Toast("📸 Foto-Modus: H drücken zum Beenden", "Info")
	task.delay(1.5, function()
		if photoPending and photoToken == token then
			photoPending = false
			startPhotoMode()
		end
	end)
end

function PhotoMode.Init(context: any)
	ctx = context
	-- Funktioniert auch bei versteckter UI, aber nicht beim Tippen in einer TextBox
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.H or UserInputService:GetFocusedTextBox() then
			return
		end
		PhotoMode.Toggle()
	end)
end

return PhotoMode
