--[[
	SettingsService (ModuleScript)
	Location: ServerScriptService/Services/SettingsService
	Depends on: Shared/Config/GameConfig, Core/Net, Core/Guard, SyncService

	Persists player preferences (volumes, reduced motion, UI scale, ...).
	Every key and value is validated against GameConfig.Settings.

	Actions: UpdateSettings { Key, Value }, RequestState {}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Core = script.Parent.Parent.Core
local Net = require(Core.Net)
local Guard = require(Core.Guard)

local SettingsService = { Name = "SettingsService" }

function SettingsService:Init(services)
	self.Services = services
	Net.registerAction("UpdateSettings", {
		Rate = { Capacity = 20, Refill = 5 },
		Handler = function(profile, payload)
			return self:Update(profile, payload.Key, payload.Value)
		end,
	})
	-- Lets a client that connected late ask for a fresh full snapshot.
	Net.registerAction("RequestState", {
		Rate = { Capacity = 2, Refill = 0.2 },
		Handler = function(profile)
			self.Services.SyncService:SendFull(profile)
			return Net.ok()
		end,
	})
end

function SettingsService:Update(profile, rawKey: any, rawValue: any)
	local key = Guard.id(rawKey, GameConfig.Settings, 32)
	if not key then
		return Net.fail("Unknown setting.")
	end
	local def = GameConfig.Settings[key]
	local value
	if type(def.Default) == "boolean" then
		value = Guard.boolean(rawValue)
	elseif key == "AutoSell" then
		value = Guard.integer(rawValue, def.Min, def.Max)
	else
		value = Guard.number(rawValue, def.Min, def.Max)
	end
	if value == nil then
		return Net.fail("Invalid value.")
	end
	profile.Data.Settings[key] = value
	self.Services.SyncService:MarkDirty(profile, "Settings")
	return Net.ok({ Key = key, Value = value })
end

return SettingsService
