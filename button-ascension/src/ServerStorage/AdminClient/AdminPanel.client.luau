--[[
	AdminPanel (LocalScript)
	Location: ServerStorage/AdminClient/AdminPanel
	Runs from: PlayerGui/AdminPanelGui/AdminPanel — AdminService clones the contents of
	           ServerStorage/AdminClient into that ScreenGui ONLY for authorised staff,
	           so normal players never receive this code.
	Depends on: AdminUI/AdminNet, AdminUI/Panel (and through them ReplicatedStorage/UI/*,
	            ReplicatedStorage/Shared/*)

	Asks the server who we are ("hello"), then builds the panel with exactly
	the tabs and controls that role may use. If the server says we are not
	authorised (for example the role was removed), the panel removes itself.
	Security never depends on this script: the server checks every request.
]]

local gui = script.Parent
local AdminUI = gui:WaitForChild("AdminUI")
local AdminNet = require(AdminUI:WaitForChild("AdminNet"))
local Panel = require(AdminUI:WaitForChild("Panel"))

local hello = nil
for attempt = 1, 6 do
	local response = AdminNet.request("hello")
	if response.ok and type(response.data) == "table" then
		hello = response.data
		break
	end
	if response.err == "Not authorized." then
		break
	end
	task.wait(1.5 * attempt)
end

if not hello then
	warn("[AdminPanel] The server did not authorise this client; removing the panel.")
	gui:Destroy()
	return
end

Panel.build(gui, hello)
