-- 3D previews of animals and eggs inside the UI (ViewportFrames), slowly turning.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AnimalModel = require(Shared.AnimalModel)
local EggModel = require(Shared.EggModel)

local Kit = require(script.Parent.Kit)

local Preview = {}

local spinning = {} -- [viewport] = { Model, Camera, Distance, Center, Angle }

local function fit(viewport: ViewportFrame, model: Model, angle: number?)
	local camera = viewport.CurrentCamera or Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local entry = { Model = model, Camera = camera, Distance = distance, Center = cf.Position, Angle = angle or math.rad(200) }
	spinning[viewport] = entry
	local function place()
		local a = entry.Angle
		local offset = Vector3.new(math.sin(a), 0.35, math.cos(a)).Unit * distance
		camera.CFrame = CFrame.lookAt(entry.Center + offset, entry.Center)
	end
	place()
	entry.Place = place
end

function Preview.new(parent: Instance, size: UDim2, position: UDim2?, z: number?)
	local viewport = Kit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = size,
		Position = position or UDim2.new(),
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1.5, -1),
		ZIndex = z or 22,
		Parent = parent,
	})
	viewport.Destroying:Connect(function()
		spinning[viewport] = nil
	end)
	return viewport
end

local function clear(viewport: ViewportFrame)
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("Model") or child:IsA("WorldModel") then
			child:Destroy()
		end
	end
	spinning[viewport] = nil
end

-- silhouette = true shows an undiscovered animal as a dark shape
-- static = true renders once without turning (used for grid tiles)
function Preview.showAnimal(viewport: ViewportFrame, species: string, options, silhouette: boolean?, static: boolean?)
	clear(viewport)
	local model = AnimalModel.build(species, options or {})
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("Fire") or d:IsA("PointLight") then
			d:Destroy()
		elseif silhouette and d:IsA("BasePart") then
			d.Color = Color3.fromRGB(20, 20, 30)
			d.Material = Enum.Material.SmoothPlastic
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	fit(viewport, model)
	if static then
		spinning[viewport] = nil
	end
	return model
end

function Preview.showEgg(viewport: ViewportFrame, species: string, rarity: number)
	clear(viewport)
	local model = EggModel.build({ Species = species, Rarity = rarity })
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	fit(viewport, model, math.rad(180))
	return model
end

function Preview.clear(viewport: ViewportFrame)
	clear(viewport)
end

RunService.RenderStepped:Connect(function(dt)
	for viewport, entry in pairs(spinning) do
		if viewport.Visible and viewport.Parent then
			entry.Angle += dt * 0.6
			entry.Place()
		end
	end
end)

return Preview
