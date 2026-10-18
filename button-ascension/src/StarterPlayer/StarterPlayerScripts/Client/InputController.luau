--[[
	InputController (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/InputController
	Depends on: Client/ScreenManager

	Pressing works everywhere, also while running around or doing the obby:
	  E (keyboard), R2 / L2 (controller)   press the PRESS button
	Controller menus on top of Roblox's built-in GUI selection:
	  Y         jump into the bottom menu (press again, or B, to leave it)
	  B         close the open window
	D-pad / left stick move between buttons while the menu is selected, A activates.
	Nothing is selected by default, so the left stick and A move and jump the character.
	Mouse and touch work directly on the UI; nothing extra is bound for them.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local ScreenManager = require(script.Parent.ScreenManager)

local InputController = {}

function InputController.init(ctx)
	ContextActionService:BindActionAtPriority("ButtonAscension_Press", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if ScreenManager.isOpen() or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		ctx.BigButton:Press()
		return Enum.ContextActionResult.Sink
	end, false, 2000, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2, Enum.KeyCode.E)

	local function inMenu(): boolean
		local selected = GuiService.SelectedObject
		return selected ~= nil and selected:IsDescendantOf(ctx.Hud.Dock)
	end

	ContextActionService:BindActionAtPriority("ButtonAscension_Back", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if ScreenManager.isOpen() then
			ScreenManager.close()
			return Enum.ContextActionResult.Sink
		end
		if inMenu() then
			GuiService.SelectedObject = nil
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 2000, Enum.KeyCode.ButtonB)

	ContextActionService:BindActionAtPriority("ButtonAscension_Nav", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if inMenu() then
			GuiService.SelectedObject = nil
		else
			GuiService:Select(ctx.Hud.Rail)
		end
		return Enum.ContextActionResult.Sink
	end, false, 2000, Enum.KeyCode.ButtonY)
end

return InputController
