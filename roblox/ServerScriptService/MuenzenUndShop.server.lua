--[[
	MuenzenUndShop  ·  Script  →  ServerScriptService

	  • Rangliste oben rechts mit "Münzen" (die typischen leaderstats)
	  • Münzen zum Einsammeln: Jedes Teil mit dem Tag "Muenze" ist eine Münze.
	    (Teil auswählen → Eigenschaften → ganz unten bei "Tags" auf + → Muenze)
	    Gibt es noch keine, legt das Script ein paar Beispiel-Münzen um den Spawn.
	    Attribut "Wert" an einer Münze = so viele Münzen gibt sie (Standard: 1).
	  • Shop: Gekauft wird auf dem Server, damit niemand schummeln kann.
	    Was der Shop anbietet, steht unten in SHOP – einfach erweitern.

	Die Oberfläche dazu macht der LocalScript "RobloxUI".
	Hinweis: Münzen werden nicht gespeichert – nach dem Verlassen fängst du bei 0 an.
]]

local MUENZ_NAME = "Münzen" -- so heißt die Spalte in der Rangliste
local MUENZ_TAG = "Muenze"
local MUENZE_KOMMT_ZURUECK_NACH = 8 -- Sekunden
local BEISPIEL_MUENZEN = 12

-- Id: nur Buchstaben, keine Leerzeichen oder Umlaute
-- Icon: ein Emoji für die Karte im Shop
-- Wirkung: was mit deinem Avatar passiert (auch nach jedem Respawn)
local SHOP = {
	{
		Id = "TurboSchuhe",
		Titel = "Turbo-Schuhe",
		Text = "Du rennst schneller",
		Icon = "👟",
		Preis = 10,
		Farbe = Color3.fromRGB(0, 153, 255),
		Wirkung = function(_figur: Model, humanoid: Humanoid)
			humanoid.WalkSpeed += 10
		end,
	},
	{
		Id = "Sprungfedern",
		Titel = "Sprungfedern",
		Text = "Du springst höher",
		Icon = "🦘",
		Preis = 25,
		Farbe = Color3.fromRGB(46, 204, 64),
		Wirkung = function(_figur: Model, humanoid: Humanoid)
			if humanoid.UseJumpPower then
				humanoid.JumpPower *= 1.5
			else
				humanoid.JumpHeight *= 2
			end
		end,
	},
	{
		Id = "Glitzer",
		Titel = "Glitzer",
		Text = "Du funkelst",
		Icon = "✨",
		Preis = 50,
		Farbe = Color3.fromRGB(155, 89, 255),
		Wirkung = function(figur: Model, _humanoid: Humanoid)
			local wurzel = figur:FindFirstChild("HumanoidRootPart")
			if wurzel then
				Instance.new("Sparkles").Parent = wurzel
			end
		end,
	},
}

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local artikelNachId = {}
for _, artikel in SHOP do
	artikelNachId[artikel.Id] = artikel
end

local function muenzenVon(spieler: Player): IntValue?
	local leaderstats = spieler:FindFirstChild("leaderstats")
	local muenzen = leaderstats and leaderstats:FindFirstChild(MUENZ_NAME)
	if muenzen and muenzen:IsA("IntValue") then
		return muenzen
	end
	return nil
end

--------------------------------------------------------------------------------
-- Rangliste (leaderstats) und gekaufte Sachen
--------------------------------------------------------------------------------

local function gekauftesAnwenden(spieler: Player, figur: Model)
	local humanoid = figur:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	for _, artikel in SHOP do
		if spieler:GetAttribute("Gekauft_" .. artikel.Id) then
			artikel.Wirkung(figur, humanoid)
		end
	end
end

local function spielerEinrichten(spieler: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local muenzen = Instance.new("IntValue")
	muenzen.Name = MUENZ_NAME
	muenzen.Value = 0
	muenzen.Parent = leaderstats

	leaderstats.Parent = spieler

	spieler.CharacterAdded:Connect(function(figur)
		gekauftesAnwenden(spieler, figur)
	end)
end

Players.PlayerAdded:Connect(spielerEinrichten)
for _, spieler in Players:GetPlayers() do
	spielerEinrichten(spieler)
end

--------------------------------------------------------------------------------
-- Münzen einsammeln
--------------------------------------------------------------------------------

local function muenzeEinrichten(muenze: Instance)
	if not muenze:IsA("BasePart") then
		return
	end

	local bereit = true
	muenze.Touched:Connect(function(treffer)
		if not bereit or not treffer.Parent then
			return
		end
		local spieler = Players:GetPlayerFromCharacter(treffer.Parent)
		local humanoid = treffer.Parent:FindFirstChildOfClass("Humanoid")
		local muenzen = spieler and muenzenVon(spieler)
		if not (muenzen and humanoid and humanoid.Health > 0) then
			return
		end

		bereit = false
		local wert = muenze:GetAttribute("Wert")
		muenzen.Value += if type(wert) == "number" then wert else 1

		local sichtbar = muenze.Transparency
		muenze.Transparency = 1
		task.delay(MUENZE_KOMMT_ZURUECK_NACH, function()
			muenze.Transparency = sichtbar
			bereit = true
		end)
	end)
end

local function beispielMuenzen()
	local ordner = Instance.new("Folder")
	ordner.Name = "Muenzen"

	for nummer = 1, BEISPIEL_MUENZEN do
		local winkel = nummer / BEISPIEL_MUENZEN * math.pi * 2
		local muenze = Instance.new("Part")
		muenze.Name = "Muenze"
		muenze.Shape = Enum.PartType.Cylinder
		muenze.Size = Vector3.new(0.6, 3, 3)
		-- im Kreis um den Spawn, hochkant wie ein Rad
		muenze.CFrame = CFrame.new(math.cos(winkel) * 30, 3, math.sin(winkel) * 30) * CFrame.Angles(0, -winkel, 0)
		muenze.Color = Color3.fromRGB(255, 196, 0)
		muenze.Material = Enum.Material.SmoothPlastic
		muenze.Anchored = true
		muenze.CanCollide = false
		muenze:AddTag(MUENZ_TAG)
		muenze.Parent = ordner
	end

	ordner.Parent = workspace
end

CollectionService:GetInstanceAddedSignal(MUENZ_TAG):Connect(muenzeEinrichten)
local vorhandene = CollectionService:GetTagged(MUENZ_TAG)
for _, muenze in vorhandene do
	muenzeEinrichten(muenze)
end
if #vorhandene == 0 then
	beispielMuenzen()
end

--------------------------------------------------------------------------------
-- Shop
--------------------------------------------------------------------------------

-- Was im Shop steht, landet in ReplicatedStorage › Shop, damit die Oberfläche es lesen kann
local shopOrdner = Instance.new("Folder")
shopOrdner.Name = "Shop"

for nummer, artikel in SHOP do
	local eintrag = Instance.new("Configuration")
	eintrag.Name = artikel.Id
	eintrag:SetAttribute("Titel", artikel.Titel)
	eintrag:SetAttribute("Text", artikel.Text)
	eintrag:SetAttribute("Icon", artikel.Icon)
	eintrag:SetAttribute("Preis", artikel.Preis)
	eintrag:SetAttribute("Farbe", artikel.Farbe)
	eintrag:SetAttribute("Reihenfolge", nummer)
	eintrag.Parent = shopOrdner
end

local kaufen = Instance.new("RemoteFunction")
kaufen.Name = "Kaufen"
kaufen.Parent = shopOrdner

kaufen.OnServerInvoke = function(spieler: Player, id: unknown)
	local artikel = if type(id) == "string" then artikelNachId[id] else nil
	if not artikel then
		return false, "Das gibt es nicht."
	end
	if spieler:GetAttribute("Gekauft_" .. artikel.Id) then
		return false, "Hast du schon!"
	end

	local muenzen = muenzenVon(spieler)
	if not muenzen or muenzen.Value < artikel.Preis then
		return false, "Zu wenig Münzen!"
	end

	muenzen.Value -= artikel.Preis
	spieler:SetAttribute("Gekauft_" .. artikel.Id, true)

	local figur = spieler.Character
	local humanoid = figur and figur:FindFirstChildOfClass("Humanoid")
	if figur and humanoid then
		artikel.Wirkung(figur, humanoid)
	end
	return true, artikel.Titel .. " gekauft!"
end

shopOrdner.Parent = ReplicatedStorage
