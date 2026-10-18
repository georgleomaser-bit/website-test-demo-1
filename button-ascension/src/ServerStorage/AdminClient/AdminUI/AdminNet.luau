--[[
	AdminNet (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/AdminNet
	          (runs from PlayerGui/AdminPanelGui/AdminUI/AdminNet for authorised staff)
	Depends on: ReplicatedStorage/Shared/Remotes, ReplicatedStorage/UI/UIKit, ReplicatedStorage/UI/Theme

	Client wrapper around the "Admin" RemoteFunction.
	  * Every request carries a fresh RequestId (the server rejects replays).
	  * InvokeServer is always wrapped in pcall; failures become
	    { ok = false, err = "Connection problem..." } instead of errors.
	  * Destructive actions come back with needsConfirm + a single-use token;
	    run() shows a confirmation dialog and sends "confirm" or "cancel".

	Nothing here grants anything: the server checks permissions, limits,
	targets and confirmations on every call. The client only mirrors those
	rules to hide controls the role cannot use.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UIKit"))
local Theme = require(UIFolder:WaitForChild("Theme"))

export type Response = {
	ok: boolean,
	message: string?,
	err: string?,
	data: any,
	needsConfirm: boolean?,
	token: string?,
	summary: string?,
	expires: number?,
	cancelled: boolean?,
}

local AdminNet = {}

local adminRemote = Remotes.func("Admin")
local pushRemote = Remotes.event("AdminPush")
local reporter: ((response: Response, label: string?) -> ())? = nil

-- Sends one request. Never throws.
function AdminNet.request(action: string, args: { [string]: any }?): Response
	local ok, response = pcall(function()
		return adminRemote:InvokeServer({
			Action = action,
			Args = args or {},
			RequestId = HttpService:GenerateGUID(false),
		})
	end)
	if not ok then
		return { ok = false, err = "Connection problem. Please try again." }
	end
	if type(response) ~= "table" then
		return { ok = false, err = "Unexpected response from the server." }
	end
	return response :: Response
end

-- The panel installs a reporter that writes results to the console and toasts.
function AdminNet.setReporter(fn: (response: Response, label: string?) -> ())
	reporter = fn
end

--[[
	Runs an action and handles the confirmation flow.
	opts: {
	  Label: string?          short name shown in the console ("Kick", "Add Sparks", ...)
	  Silent: boolean?        do not report the result
	  RequireText: string?    the admin must type this text to confirm
	  ConfirmTitle: string?
	}
]]
function AdminNet.run(action: string, args: { [string]: any }?, opts: { [string]: any }?): Response
	local options = opts or {}
	local response = AdminNet.request(action, args)
	if response.needsConfirm and response.token then
		local message = (response.summary or "Confirm this action?")
			.. `\nThis confirmation expires in {response.expires or 45} seconds.`
		if options.RequireText then
			message ..= `\nType "{options.RequireText}" to confirm.`
		end
		local confirmed = UI.confirm({
			Title = options.ConfirmTitle or "Confirm destructive action",
			Message = message,
			ConfirmText = "Confirm",
			CancelText = "Cancel",
			Danger = true,
			Palette = Theme.Admin,
			RequireText = options.RequireText,
			Placeholder = if options.RequireText then options.RequireText else nil,
		})
		if not confirmed then
			AdminNet.request("cancel", { Token = response.token })
			response = { ok = false, cancelled = true, err = "Cancelled." }
		else
			response = AdminNet.request("confirm", { Token = response.token })
		end
	end
	if reporter and not options.Silent then
		reporter(response, options.Label)
	end
	return response
end

-- Sends a command-bar line ("/admin givecash me 100" or "givecash me 100").
function AdminNet.command(text: string): Response
	return AdminNet.run("command", { Text = text }, { Label = "Command" })
end

function AdminNet.onPush(fn: (kind: string, payload: any) -> ()): RBXScriptConnection
	return pushRemote.OnClientEvent:Connect(fn)
end

return AdminNet
