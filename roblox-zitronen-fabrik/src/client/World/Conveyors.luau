--[[
	Die Förderbänder zum Leben erwecken (nur Anzeige auf dem Client):
	- Früchte fallen aus der Maschine, fahren übers Band, verwandeln sich unter
	  jedem Maschinen-Bogen und plumpsen in den Verkaufs-Trichter (+$ Anzeige).
	- Die Band-Lamellen der eigenen Fabrik bewegen sich, solange die Linie läuft.
	Die Zeiten kommen aus den Attributen, die der Server setzt – so passt der
	Verkauf genau zum Moment, in dem das Geld gutgeschrieben wird.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.Sound)

local Conveyors = {}

local player = Players.LocalPlayer
local L = Config.Layout
local V = Config.Visual

local folder: Folder
local lanesVis: { [string]: any } = {}
local pools: { [string]: { BasePart } } = {}
local items: { any } = {}
local popupPool: { BasePart } = {}

local BELT_LENGTH = L.BeltStartZ - L.BeltEndZ
local BELT_SHARE = 0.86 -- Anteil der Fahrzeit auf dem Band, der Rest ist der Fall in den Trichter
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local GEM_TILT = CFrame.Angles(math.rad(45), 0, math.rad(45))

--------------------------------------------------------------------------
-- Teile-Pool
--------------------------------------------------------------------------
local function newPart(kind: string): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif kind == "Cylinder" or kind == "Coin" then
		part.Shape = Enum.PartType.Cylinder
	elseif kind == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part:SetAttribute("Kind", kind)
	return part
end

local function acquire(kind: string): BasePart
	local pool = pools[kind]
	if pool and #pool > 0 then
		local part = table.remove(pool) :: BasePart
		return part
	end
	local part = newPart(kind)
	part.Parent = folder
	return part
end

local function release(part: BasePart)
	local kind = part:GetAttribute("Kind") :: string
	part.CFrame = CFrame.new(0, -5000, 0)
	pools[kind] = pools[kind] or {}
	table.insert(pools[kind], part)
end

local function skin(part: BasePart, stage, fruit)
	local size = stage.Size
	if stage.Kind == "Ball" then
		size = Vector3.new(size.X, size.X, size.X)
	end
	part.Size = size
	if stage.Color == "Fruit" then
		part.Color = fruit.Color
		part.Material = stage.Material == Enum.Material.SmoothPlastic and fruit.Material or stage.Material
	else
		part.Color = stage.Color
		part.Material = stage.Material
	end
	part.Transparency = stage.Material == Enum.Material.Glass and 0.15 or 0
end

--------------------------------------------------------------------------
-- "+$"-Anzeige am Verkauf
--------------------------------------------------------------------------
local function popup(position: Vector3, text: string, color: Color3)
	local anchor = table.remove(popupPool)
	if not anchor then
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		local gui = Instance.new("BillboardGui")
		gui.Name = "Gui"
		gui.Size = UDim2.fromScale(8, 2)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 120
		gui.LightInfluence = 0
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.SourceSansBold
		label.TextScaled = true
		label.TextStrokeTransparency = 0
		label.Parent = gui
		part.Parent = folder
		anchor = part
	end
	local part = anchor :: BasePart
	local gui = part:FindFirstChild("Gui") :: BillboardGui
	local label = gui:FindFirstChild("Label") :: TextLabel
	part.CFrame = CFrame.new(position)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.Enabled = true
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0
	TweenService:Create(gui, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 7, 0) }):Play()
	local fade = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.6), { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade:Play()
	task.delay(1.2, function()
		gui.Enabled = false
		table.insert(popupPool, part)
	end)
end
Conveyors.Popup = popup

--------------------------------------------------------------------------
-- Linien verwalten
--------------------------------------------------------------------------
local function laneKey(plot: Model, index: number): string
	return plot.Name .. "_" .. index
end

local function getLane(plot: Model, index: number)
	local key = laneKey(plot, index)
	local vis = lanesVis[key]
	if vis then
		return vis
	end
	local states = plot:FindFirstChild("LaneState")
	local state = states and states:FindFirstChild("Lane" .. index)
	if not state then
		return nil
	end
	vis = {
		Plot = plot,
		Index = index,
		State = state,
		Key = nil :: number?,
		LastN = 0,
		ManualItem = nil :: any,
		Slats = nil :: { BasePart }?,
		SlatPhase = 0,
		LastPopup = 0,
		PendingPopup = 0,
	}
	lanesVis[key] = vis
	return vis
end

local function travelFor(cycle: number, manager: boolean): number
	if manager then
		return math.clamp(cycle, V.MinTravel, V.MaxTravel)
	end
	return math.min(cycle, V.MaxTravel)
end

local function stageFor(z: number, owned: number): number
	local stage = 0
	for j = 1, owned do
		if z < L.UpgraderZ[j] then
			stage = j
		end
	end
	return stage
end

-- Position einer Frucht auf ihrem Weg (0..1) im Linien-Koordinatensystem
local function pathPoint(progress: number, halfHeight: number): Vector3
	local beltTop = L.BeltY + halfHeight
	if progress <= BELT_SHARE then
		local t = progress / BELT_SHARE
		local z = (L.BeltStartZ - 1) - t * (BELT_LENGTH - 1.5)
		return Vector3.new(0, beltTop, z)
	end
	local t = (progress - BELT_SHARE) / (1 - BELT_SHARE)
	local z = (L.BeltEndZ + 0.5) - t * ((L.BeltEndZ + 0.5) - (L.SellerZ + 1.5))
	local y = beltTop + 0.8 * math.sin(t * math.pi) - t * (beltTop - 1.2 - halfHeight * 0.3)
	return Vector3.new(0, y, z)
end

local function spawnItem(vis, laneCFrame: CFrame, laneCfg, fruit, spawnTime: number, saleTime: number, value: number, isOwn: boolean)
	local item = {
		Vis = vis,
		LaneCFrame = laneCFrame,
		LaneCfg = laneCfg,
		Fruit = fruit,
		SpawnTime = spawnTime,
		SaleTime = saleTime,
		Value = value,
		IsOwn = isOwn,
		Stage = -1,
		Part = nil :: BasePart?,
		Spin = math.random() * math.pi * 2,
	}
	table.insert(items, item)
	return item
end

local function sell(item)
	local vis = item.Vis
	if item.IsOwn then
		vis.PendingPopup += item.Value
		local now = os.clock()
		if now - vis.LastPopup > 0.3 then
			vis.LastPopup = now
			local pos = (item.LaneCFrame * CFrame.new(0, 3, L.SellerZ)).Position
			popup(pos, "+" .. Format.Cash(vis.PendingPopup), Color3.fromRGB(120, 255, 120))
			vis.PendingPopup = 0
			Sound.Play("Sell", 0.15, 1.4 + math.random() * 0.2, 0.12)
		end
	end
end

--------------------------------------------------------------------------
-- Band-Lamellen (nur eigene Fabrik)
--------------------------------------------------------------------------
local SLAT_SPACING = 4

local function ensureSlats(vis, laneCFrame: CFrame)
	if vis.Slats then
		return
	end
	local slats = {}
	for k = 1, math.floor((BELT_LENGTH - SLAT_SPACING) / SLAT_SPACING) do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Size = Vector3.new(5.6, 0.1, 0.7)
		part.Color = Color3.fromRGB(70, 70, 76)
		part.Material = Enum.Material.Metal
		part.TopSurface = Enum.SurfaceType.Smooth
		part.CFrame = laneCFrame * CFrame.new(0, L.BeltY + 0.05, L.BeltStartZ - k * SLAT_SPACING)
		part.Parent = folder
		slats[k] = part
	end
	vis.Slats = slats
end

local function removeSlats(vis)
	if vis.Slats then
		for _, part in ipairs(vis.Slats) do
			part:Destroy()
		end
		vis.Slats = nil
	end
end

--------------------------------------------------------------------------
-- Haupt-Schleife
--------------------------------------------------------------------------
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function update(dt: number)
	local world = workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	if not plots then
		return
	end
	local now = workspace:GetServerTimeNow()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local myPos = root and root.Position or Vector3.zero
	local showOthers = State.Setting("OtherItems")
	local active: { [string]: boolean } = {}

	for _, plot in ipairs(plots:GetChildren()) do
		local ownerId = plot:GetAttribute("OwnerId")
		if not plot:IsA("Model") or not ownerId or ownerId == 0 then
			continue
		end
		local isOwn = ownerId == player.UserId
		local origin = plot:GetAttribute("Origin") :: CFrame
		if not origin then
			continue
		end
		if not isOwn then
			if not showOthers or (origin.Position - myPos).Magnitude > V.OtherRenderDistance + L.PlotSize then
				continue
			end
		end
		local fruit = Config.Fruits[plot:GetAttribute("Fruit") or 1] or Config.Fruits[1]
		local minInterval = isOwn and V.OwnMinInterval or V.OtherMinInterval

		for i, laneCfg in ipairs(Config.Lanes) do
			local vis = getLane(plot, i)
			if not vis then
				continue
			end
			local state = vis.State
			local laneCFrame = origin * CFrame.new(Config.LaneX(i), 0, 0)
			local unlocked = state:GetAttribute("Unlocked")
			local running = state:GetAttribute("Running")
			local manager = state:GetAttribute("Manager") == true
			local cycle = state:GetAttribute("CycleTime") or 1
			local start = state:GetAttribute("CycleStart") or 0
			local revenue = state:GetAttribute("Revenue") or 0
			active[laneKey(plot, i)] = true

			-- Lamellen
			if isOwn and unlocked then
				ensureSlats(vis, laneCFrame)
				if running then
					local speed = (BELT_LENGTH * BELT_SHARE) / travelFor(cycle, manager)
					vis.SlatPhase = (vis.SlatPhase + speed * dt) % SLAT_SPACING
				end
				for k, part in ipairs(vis.Slats) do
					table.insert(moveParts, part)
					table.insert(moveCFrames, laneCFrame * CFrame.new(0, L.BeltY + 0.05, L.BeltStartZ - 1 - ((k - 1) * SLAT_SPACING + vis.SlatPhase)))
				end
			elseif vis.Slats then
				removeSlats(vis)
			end

			if not unlocked or not running or cycle <= 0 then
				vis.Key = nil
				continue
			end

			-- Neue Früchte planen
			local travel = travelFor(cycle, manager)
			if vis.Key ~= start then
				local firstLook = vis.Key == nil
				vis.Key = start
				if manager then
					-- Früchte, die schon fahren, gehören zum alten Takt: keine doppelten erzeugen.
					-- Beim allerersten Blick (Beitritt) das Band dagegen gleich füllen.
					vis.LastN = firstLook and math.floor((now - start) / cycle) or math.floor((now + travel - start) / cycle)
				else
					local current = vis.ManualItem
					if current and now < current.SaleTime and start < current.SaleTime - 0.05 and table.find(items, current) then
						-- Zyklus wurde nur umgerechnet (z. B. Level gekauft): vorhandene Frucht neu takten
						current.SaleTime = start + cycle
						current.SpawnTime = current.SaleTime - travel
						current.Value = revenue
						vis.LastN = 1
					else
						vis.LastN = 0
					end
				end
			end
			if manager then
				local nNow = math.floor((now + travel - start) / cycle)
				if nNow > vis.LastN then
					local step = math.max(1, math.ceil(minInterval / cycle))
					local first = math.max(vis.LastN + 1, nNow - math.ceil(travel / cycle) - 1)
					for n = first, nNow do
						if n % step == 0 then
							local saleTime = start + n * cycle
							if saleTime > now then
								spawnItem(vis, laneCFrame, laneCfg, fruit, saleTime - travel, saleTime, revenue * step, isOwn)
							end
						end
					end
					vis.LastN = nNow
				end
			elseif vis.LastN < 1 and now >= start + cycle - travel then
				vis.LastN = 1
				local saleTime = start + cycle
				if saleTime > now then
					vis.ManualItem = spawnItem(vis, laneCFrame, laneCfg, fruit, saleTime - travel, saleTime, revenue, isOwn)
				end
			end
		end
	end

	-- Linien aufräumen, die es nicht mehr gibt (Spieler weg / Rebirth)
	for key, vis in pairs(lanesVis) do
		if not active[key] then
			removeSlats(vis)
			lanesVis[key] = nil
		end
	end

	-- Früchte bewegen
	local i = 1
	while i <= #items do
		local item = items[i]
		local travel = item.SaleTime - item.SpawnTime
		local progress = travel > 0 and (now - item.SpawnTime) / travel or 1
		local vis = item.Vis
		if progress >= 1 or lanesVis[laneKey(vis.Plot, vis.Index)] ~= vis then
			if progress >= 1 then
				sell(item)
			end
			if item.Part then
				release(item.Part)
			end
			items[i] = items[#items]
			items[#items] = nil
		else
			if progress < 0 then
				progress = 0
			end
			local owned = vis.State:GetAttribute("Upgraders") or 0
			local laneCfg = item.LaneCfg
			-- Höhe der aktuellen Stufe bestimmt die Bahn
			local stageIndex = item.Stage >= 0 and item.Stage or 0
			local stageCfg = laneCfg.Items[stageIndex + 1] or laneCfg.Items[1]
			local half = (stageCfg.Kind == "Cylinder" or stageCfg.Kind == "Coin") and stageCfg.Size.X / 2 or stageCfg.Size.Y / 2
			local localPos = pathPoint(progress, half)
			local newStage = math.min(stageFor(localPos.Z, owned), #laneCfg.Items - 1)
			if newStage ~= item.Stage then
				item.Stage = newStage
				stageCfg = laneCfg.Items[newStage + 1]
				if item.Part then
					release(item.Part)
				end
				local part = acquire(stageCfg.Kind)
				skin(part, stageCfg, item.Fruit)
				item.Part = part
			end
			local cf = item.LaneCFrame * CFrame.new(localPos)
			local kind = stageCfg.Kind
			if kind == "Cylinder" or kind == "Coin" then
				cf *= UPRIGHT
			elseif kind == "Gem" then
				cf *= CFrame.Angles(0, item.Spin + now * 2, 0) * GEM_TILT
			else
				cf *= CFrame.Angles(0, item.Spin, 0)
			end
			table.insert(moveParts, item.Part :: BasePart)
			table.insert(moveCFrames, cf)
			i += 1
		end
	end

	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(moveParts)
		table.clear(moveCFrames)
	end
end

function Conveyors.Start()
	folder = Instance.new("Folder")
	folder.Name = "ClientConveyorItems"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			warn("[ZitronenFabrik] Förderband-Anzeige: " .. tostring(err))
		end
	end)
end

-- Position der Verkaufsstelle einer eigenen Linie (für Effekte)
function Conveyors.SellerPosition(laneIndex: number): Vector3?
	local plot = State.Plot()
	local origin = plot and plot:GetAttribute("Origin") :: CFrame?
	if not origin then
		return nil
	end
	return (origin * CFrame.new(Config.LaneX(laneIndex), 4, L.SellerZ)).Position
end

return Conveyors
