--!strict
-- =====================================================================
--  AKYTEX TYCOON – Hybrid-Asset-Plätze (Shared/AssetSlot)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C6.1 + §C14.3 (Besitzer-Wunsch 17).
--  Alles funktioniert OHNE hochgeladene Assets: 0 = Code-Rezept. Ist eine Id gesetzt und lädt sie, wird das
--  echte MeshPart/Bild/Sound benutzt – fehlt sie oder schlägt das Laden fehl, automatisch das Rezept.
--
--  Öffentliche API:
--    AssetSlot.IsSet(slot?): boolean                      MeshId ist eine gültige Id (> 0, ganzzahlig)
--    AssetSlot.Mesh(key, slot?, recipe): Instance          Vorlage aus ReplicatedStorage.AssetCache[key] (oder gleicher
--        Inhalt unter anderem Schlüssel) -> Model mit dem MeshPart (Size × Scale, CFrame = Offset, WorldPivot = identity,
--        also dieselbe Pivot-Konvention wie ein Rezept-Model mit Ursprung im Pivot). Keine Vorlage / 0 / Fehler -> recipe().
--        YIELDET NIE: fehlt auf dem Server die Vorlage, startet das Laden im Hintergrund (CreateMeshPartAsync, pcall);
--        der nächste Bau nutzt sie. Normalfall: PreloadServer hat beim Start schon alles geladen.
--    AssetSlot.Image(id?, fallback?): string               "rbxassetid://<id>" oder fallback ("" = Code-Grafik)
--    AssetSlot.SoundId(id?): string?                       nil = Sfx-Rezept
--    AssetSlot.PreloadServer(slots)                        nur Server; lädt alle gesetzten Mesh-Plätze parallel nach
--        ReplicatedStorage.AssetCache/<Key> (Attribute MeshId/TextureId), wartet höchstens 12 s. Yieldet.
--    AssetSlot.Verify(ids, onFail)                         ContentProvider:PreloadAsync mit Status-Callback; Failure/
--        TimedOut -> onFail(id) (Bild/Sound dann auf Code-Grafik bzw. Rezept umschalten). Yieldet.
--    AssetSlot.KeyOf(child, entryKey): string              Schlüssel-Konvention "<Config-Kind>.<Eintrag>", z. B.
--        "Vehicles.LamCity", "Tower.Crane", "City.Blimp"
--    AssetSlot.CollectFromConfig(config): { [string]: AssetSlot }   alle gesetzten Mesh-Plätze aus den Config-Kindern
--        (Einträge mit Key + Asset und Assets = { Name = Slot }); Main.server lädt damit beim Start vor.
-- =====================================================================

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent:WaitForChild("Types"))

type Slot = Types.AssetSlot

local AssetSlot = {}

local CACHE_NAME = "AssetCache"
local PRELOAD_TIMEOUT = 12 -- Sekunden, die der Server-Start höchstens auf Mesh-Vorlagen wartet
local MAX_SLOTS = 512 -- Obergrenze je Vorlade-Runde / Suche
local MAX_VERIFY = 200
local MAX_DEPTH = 6
local LOG_GAP = 30

local loading: { [string]: boolean } = {} -- Schlüssel -> Laden läuft
local failed: { [string]: boolean } = {} -- Inhalts-Schlüssel -> Laden fehlgeschlagen (dieser Server versucht es nicht erneut)
local lastLog = -math.huge

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function validId(n: any): boolean
	return type(n) == "number" and n == n and n > 0 and n < 2 ^ 53 and n % 1 == 0
end

local function idText(n: number): string
	return string.format("%.0f", n)
end

local function logOnce(text: string)
	local now = os.clock()
	if now - lastLog >= LOG_GAP then
		lastLog = now
		warn("[AssetSlot] " .. text)
	end
end

function AssetSlot.IsSet(slot: Slot?): boolean
	return type(slot) == "table" and validId((slot :: any).MeshId)
end

local function textureOf(slot: Slot): number
	local tex = (slot :: any).TextureId
	return if validId(tex) then tex else 0
end

local function scaleOf(slot: Slot): number
	local s = (slot :: any).Scale
	if type(s) ~= "number" or s ~= s or s <= 0 or s == math.huge then
		return 1
	end
	return math.clamp(s, 0.01, 100)
end

local function offsetOf(slot: Slot): CFrame
	local o = (slot :: any).Offset
	return if typeof(o) == "CFrame" then o else CFrame.identity
end

local function contentKey(slot: Slot): string
	return "M" .. idText((slot :: any).MeshId) .. "_T" .. idText(textureOf(slot))
end

local function cacheFolder(create: boolean): Folder?
	local existing = ReplicatedStorage:FindFirstChild(CACHE_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if not create then
		return nil
	end
	if existing then
		existing.Name = CACHE_NAME .. "_Alt" -- falsches Objekt mit dem Namen -> umbenennen statt Fehler
	end
	local folder = Instance.new("Folder")
	folder.Name = CACHE_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function matches(template: Instance, slot: Slot): boolean
	return template:IsA("MeshPart")
		and template:GetAttribute("MeshId") == (slot :: any).MeshId
		and (template:GetAttribute("TextureId") or 0) == textureOf(slot)
end

-- Vorlage unter dem Schlüssel – oder (Schlüssel anders geschrieben) mit gleichem Inhalt
local function findTemplate(key: string, slot: Slot): MeshPart?
	local folder = cacheFolder(false)
	if not folder then
		return nil
	end
	local byKey = folder:FindFirstChild(key)
	if byKey and matches(byKey, slot) then
		return byKey :: MeshPart
	end
	local children = folder:GetChildren()
	for i = 1, math.min(#children, MAX_SLOTS) do
		local child = children[i]
		if matches(child, slot) then
			return child :: MeshPart
		end
	end
	return nil
end

local function buildFromTemplate(key: string, template: MeshPart, slot: Slot): Model
	local model = Instance.new("Model")
	model.Name = key
	local part = template:Clone()
	part.Size = part.Size * scaleOf(slot)
	part.CFrame = offsetOf(slot)
	part.Parent = model
	model.WorldPivot = CFrame.identity
	model:SetAttribute("AssetSlot", true)
	return model
end

-- ---------------------------------------------------------------------
-- 2) LADEN (nur Server; yieldet)
-- ---------------------------------------------------------------------
local function loadTemplate(key: string, slot: Slot): boolean
	local content = contentKey(slot)
	if failed[content] then
		return false
	end
	local meshId = (slot :: any).MeshId :: number
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync("rbxassetid://" .. idText(meshId))
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("MeshPart") then
		failed[content] = true
		logOnce(
			("Mesh %s (%s) konnte nicht geladen werden – Code-Rezept bleibt: %s"):format(
				idText(meshId),
				key,
				tostring(result)
			)
		)
		return false
	end
	local part = result :: MeshPart
	local texture = textureOf(slot)
	if texture > 0 then
		part.TextureID = "rbxassetid://" .. idText(texture)
	end
	part.Name = key
	part.Anchored = true
	part:SetAttribute("MeshId", meshId)
	part:SetAttribute("TextureId", texture)
	local folder = cacheFolder(true) :: Folder
	local old = folder:FindFirstChild(key)
	if old then
		old:Destroy() -- alte Vorlage (Config geändert) ersetzen
	end
	part.Parent = folder
	return true
end

local function startBackgroundLoad(key: string, slot: Slot)
	if loading[key] or failed[contentKey(slot)] then
		return
	end
	loading[key] = true
	task.spawn(function()
		local ok, err = pcall(loadTemplate, key, slot)
		if not ok then
			logOnce("Laden fehlgeschlagen (" .. key .. "): " .. tostring(err))
		end
		loading[key] = nil
	end)
end

-- ---------------------------------------------------------------------
-- 3) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function AssetSlot.KeyOf(child: string, entryKey: string): string
	return tostring(child) .. "." .. tostring(entryKey)
end

function AssetSlot.Mesh(key: string, slot: Slot?, recipe: () -> Instance): Instance
	if type(key) == "string" and slot ~= nil and AssetSlot.IsSet(slot) then
		local template = findTemplate(key, slot)
		if template then
			local ok, model = pcall(buildFromTemplate, key, template, slot)
			if ok then
				return model
			end
			logOnce("Vorlage " .. key .. " nicht nutzbar: " .. tostring(model))
		elseif RunService:IsServer() then
			startBackgroundLoad(key, slot)
		end
	end
	return recipe()
end

function AssetSlot.Image(id: number?, fallback: string?): string
	if validId(id) then
		return "rbxassetid://" .. idText(id :: number)
	end
	return if type(fallback) == "string" then fallback else ""
end

function AssetSlot.SoundId(id: number?): string?
	if validId(id) then
		return "rbxassetid://" .. idText(id :: number)
	end
	return nil
end

function AssetSlot.PreloadServer(slots: { [string]: Slot })
	if not RunService:IsServer() or type(slots) ~= "table" then
		return
	end
	local pending = 0
	local count = 0
	for key, slot in pairs(slots) do
		if count >= MAX_SLOTS then
			logOnce("zu viele Asset-Plätze – Rest wird bei Bedarf geladen")
			break
		end
		if type(key) == "string" and AssetSlot.IsSet(slot) and not findTemplate(key, slot) and not loading[key] then
			count += 1
			pending += 1
			loading[key] = true
			task.spawn(function()
				local ok, err = pcall(loadTemplate, key, slot)
				if not ok then
					logOnce("Vorladen fehlgeschlagen (" .. key .. "): " .. tostring(err))
				end
				loading[key] = nil
				pending -= 1
			end)
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < PRELOAD_TIMEOUT do
		task.wait(0.1)
	end
	if pending > 0 then
		logOnce(
			("%d Mesh-Vorlage(n) nach %d s noch nicht fertig – werden nachgereicht"):format(pending, PRELOAD_TIMEOUT)
		)
	end
end

function AssetSlot.Verify(ids: { string }, onFail: (id: string) -> ())
	if type(ids) ~= "table" or type(onFail) ~= "function" then
		return
	end
	local list: { string } = {}
	for i, id in ipairs(ids) do
		if i > MAX_VERIFY then
			break
		end
		if type(id) == "string" and id ~= "" then
			table.insert(list, id)
		end
	end
	if #list == 0 then
		return
	end
	local reported: { [string]: boolean } = {}
	local function report(id: string)
		if reported[id] then
			return
		end
		reported[id] = true
		task.spawn(function()
			local ok, err = pcall(onFail :: (string) -> any, id)
			if not ok then
				logOnce("onFail-Fehler: " .. tostring(err))
			end
		end)
	end
	local ok = pcall(function()
		ContentProvider:PreloadAsync(list, function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
				report(contentId)
			end
		end)
	end)
	if not ok then
		-- ContentProvider nicht erreichbar -> sicher auf Code-Grafik/Rezept
		for _, id in ipairs(list) do
			report(id)
		end
	end
end

-- Sammelt alle gesetzten Mesh-Plätze aus den Config-Kindern (Schlüssel siehe KeyOf).
function AssetSlot.CollectFromConfig(config: { [string]: any }): { [string]: Slot }
	local out: { [string]: Slot } = {}
	if type(config) ~= "table" then
		return out
	end
	local visited: { [any]: boolean } = {}
	local count = 0
	local function add(key: string, slot: any)
		if count < MAX_SLOTS and out[key] == nil and AssetSlot.IsSet(slot) then
			out[key] = slot
			count += 1
		end
	end
	local function walk(child: string, t: { [any]: any }, depth: number)
		if depth > MAX_DEPTH or visited[t] then
			return
		end
		visited[t] = true
		if type(t.Key) == "string" and type(t.Asset) == "table" then
			add(AssetSlot.KeyOf(child, t.Key), t.Asset)
		end
		if type(t.Assets) == "table" then
			for name, slot in pairs(t.Assets) do
				if type(name) == "string" and type(slot) == "table" then
					add(AssetSlot.KeyOf(child, name), slot)
				end
			end
		end
		for _, value in pairs(t) do
			if type(value) == "table" then
				walk(child, value, depth + 1)
			end
		end
	end
	for name, value in pairs(config) do
		if type(name) == "string" and type(value) == "table" then
			walk(name, value, 1)
		end
	end
	return out
end

return AssetSlot
