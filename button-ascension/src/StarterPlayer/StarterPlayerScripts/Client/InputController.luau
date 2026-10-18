--[[
	InputController (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/InputController
	Depends on: Client/ScreenManager

	Controller support on top of Roblox's built-in GUI selection:
	  R2 / L2   press the big button (when no window is open)
	  Y         jump to the navigation rail (press again to leave it)
	  B         close the open window
	D-pad / left stick move between buttons, A activates (built in).
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
	end, false, 2000, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2)

	ContextActionService:BindActionAtPriority("ButtonAscension_Back", function(_, state)
		if state ~= Enum.UserInputState.Begin or not ScreenManager.isOpen() then
			return Enum.ContextActionResult.Pass
		end
		ScreenManager.close()
		return Enum.ContextActionResult.Sink
	end, false, 2000, Enum.KeyCode.ButtonB)

	ContextActionService:BindActionAtPriority("ButtonAscension_Nav", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(ctx.Hud.Rail) then
			GuiService.SelectedObject = ctx.BigButton.Cap
		else
			GuiService:Select(ctx.Hud.Rail)
		end
		return Enum.ContextActionResult.Sink
	end, false, 2000, Enum.KeyCode.ButtonY)

	-- When a gamepad connects with nothing selected, start on the big button.
	UserInputService.GamepadConnected:Connect(function()
		if not GuiService.SelectedObject and not ScreenManager.isOpen() then
			GuiService.SelectedObject = ctx.BigButton.Cap
		end
	end)
end

return InputController
