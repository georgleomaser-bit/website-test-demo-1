--[[
	ScreenManager (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/ScreenManager
	Depends on: ReplicatedStorage/Shared/Signal

	Keeps track of the full-screen windows (Shop, Crates, Inventory, ...).
	Only one is open at a time; opening another closes the current one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local ScreenManager = {
	Current = nil :: string?,
	Changed = Signal.new(),
}

local screens: { [string]: any } = {}

-- screen must expose Window (from UIKit.window); optional OnOpen() / OnClose().
function ScreenManager.register(id: string, screen)
	screens[id] = screen
	screen.Window.Closed.Event:Connect(function()
		if ScreenManager.Current == id then
			ScreenManager.Current = nil
			ScreenManager.Changed:Fire(nil)
		end
		if screen.OnClose then
			screen.OnClose()
		end
	end)
end

function ScreenManager.get(id: string)
	return screens[id]
end

function ScreenManager.open(id: string, ...: any)
	local screen = screens[id]
	if not screen then
		return
	end
	if ScreenManager.Current and ScreenManager.Current ~= id then
		local previous = screens[ScreenManager.Current]
		task.spawn(previous.Window.Close)
	end
	ScreenManager.Current = id
	if screen.OnOpen then
		screen.OnOpen(...)
	end
	screen.Window.Open()
	ScreenManager.Changed:Fire(id)
end

function ScreenManager.close()
	local id = ScreenManager.Current
	if id and screens[id] then
		task.spawn(screens[id].Window.Close)
	end
end

function ScreenManager.toggle(id: string)
	if ScreenManager.Current == id then
		ScreenManager.close()
	else
		ScreenManager.open(id)
	end
end

function ScreenManager.isOpen(id: string?): boolean
	if id then
		return ScreenManager.Current == id
	end
	return ScreenManager.Current ~= nil
end

return ScreenManager
