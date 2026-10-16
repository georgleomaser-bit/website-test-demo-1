--[[
	Reagiert auf Nachrichten und Effekte vom Server:
	Kauf-Funken, goldene Zitronen, Rebirth-Blitz, Offline-Geld, Hebel …
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sound = require(script.Parent.Sound)
local Ui = require(script.Parent.UI.Ui)
local Popups = require(script.Parent.UI.Popups)
local Windows = require(script.Parent.UI.Windows)
local Conveyors = require(script.Parent.World.Conveyors)
local PlotVisuals = require(script.Parent.World.PlotVisuals)

local Effects = {}

local function burst(position: Vector3, color: Color3, amount: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.7
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(10, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(amount)
	Debris:AddItem(part, 1.5)
end

local handlers = {}

function handlers.Purchase(position: Vector3?)
	Sound.Play("Buy", 0.6)
	if typeof(position) == "Vector3" then
		burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(120, 255, 120), 40)
	end
end

function handlers.Error()
	Sound.Play("Error", 0.5, 0.7, 0.3)
end

function handlers.Press(laneIndex: number)
	Sound.Play("Click", 0.5, 1.1)
	PlotVisuals.PressAnimation(laneIndex)
end

function handlers.LevelUp()
	Sound.Play("Click", 0.35, 1.5, 0.05)
end

function handlers.Milestone(data)
	Sound.Play("Golden", 0.7, 1.2)
	Popups.Confetti(30)
	local laneCfg = Config.Lanes[data.Lane]
	if laneCfg then
		Popups.Big("🏁 MEILENSTEIN!", Ui.Colors.Gold, laneCfg.Emoji .. " " .. laneCfg.Name .. " · Level " .. data.Level)
	end
end

function handlers.Golden(data)
	Sound.Play("Golden", 0.6, 1.3, 0.15)
	local position = Conveyors.SellerPosition(data.Lane)
	if position then
		Conveyors.Popup(position + Vector3.new(0, 2, 0), "✨ GOLDEN! +" .. Format.Cash(data.Amount), Color3.fromRGB(255, 215, 0))
		burst(position, Color3.fromRGB(255, 215, 0), 25)
	end
end

function handlers.Rebirth(data)
	Sound.Play("Rebirth", 0.8, 0.8)
	Popups.Flash(Color3.fromRGB(120, 255, 120), 0.8)
	Popups.Confetti(70)
	Popups.Big("🛸 REBIRTH!", Color3.fromRGB(150, 255, 120), "+" .. Format.Number(data.Investors) .. " Alien-Investoren · Bonus ×" .. Format.Number(data.Bonus))
	Windows.Close()
end

function handlers.Evolve(data)
	Sound.Play("Rebirth", 0.9, 0.6)
	Popups.Flash(Color3.fromRGB(190, 90, 255), 0.9)
	Popups.Confetti(90)
	Popups.Big("🌀 EVOLUTION!", Color3.fromRGB(220, 150, 255), "Deine Früchte sind jetzt: " .. data.Emoji .. " " .. data.Fruit)
	Windows.Close()
end

function handlers.Offline(data)
	Sound.Play("Golden", 0.6)
	Popups.Modal(
		"💤 Willkommen zurück!",
		"Deine Manager haben in " .. Format.Time(data.Seconds) .. " fleißig gearbeitet:\n\n+" .. Format.Cash(data.Amount),
		"Super! 💰",
		Ui.Colors.Green
	)
end

function handlers.Reward(data)
	Sound.Play("Golden", 0.7)
	Popups.Confetti(40)
	if data.Amount and data.Amount > 0 then
		Popups.Big("+" .. Format.Cash(data.Amount), Ui.Colors.Gold, data.Title)
	else
		Popups.Big(data.Title or "🎉", Ui.Colors.Gold)
	end
end

function handlers.Pickup(data)
	Sound.Play("Pickup", 0.6, 1.4, 0.05)
	if typeof(data.Position) == "Vector3" then
		Conveyors.Popup(data.Position, "🍋 +" .. Format.Cash(data.Amount), Color3.fromRGB(255, 215, 0))
	end
end

function handlers.Event(data)
	Sound.Play("Golden", 0.8, 0.9)
	Popups.Big(data.Emoji .. " " .. data.Name .. "!", Color3.fromRGB(220, 150, 255))
end

function handlers.OpenWindow(name: string)
	Windows.Open(name)
end

function handlers.Lever(data)
	Sound.Play("Lever", 0.8, data.Correct and 1.2 or 0.6)
	if not data.Correct then
		Popups.Flash(Color3.fromRGB(255, 0, 0), 0.3)
	end
end

function handlers.VaultOpen()
	Sound.Play("Rebirth", 0.7, 0.5)
	PlotVisuals.OpenVault()
end

function handlers.UfoKey()
	Popups.Flash(Color3.fromRGB(120, 255, 120), 0.6)
	Popups.Confetti(80)
	Popups.Big("👽 DANKE, ERDLING!", Color3.fromRGB(140, 255, 120), "Investoren sind jetzt 50 % stärker!")
end

function Effects.Start()
	Remotes.Get("Notify").OnClientEvent:Connect(function(text: string, style: string?)
		if type(text) == "string" then
			Popups.Toast(text, style)
		end
	end)
	Remotes.Get("Effect").OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler then
			local ok, err = pcall(handler, data)
			if not ok then
				warn("[ZitronenFabrik] Effekt " .. tostring(kind) .. ": " .. tostring(err))
			end
		end
	end)
end

return Effects
