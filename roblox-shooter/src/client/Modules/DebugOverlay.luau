-- =====================================================================
--  CLUTCH CLASH – Debug-Anzeige F8 (Client/Modules/DebugOverlay)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md B25.3 (Debug), C18.
--  Nur für den Besitzer (Modul lädt nur bei IsAdmin; der Server prüft "ServerInfo" trotzdem erneut).
--  Zeigt: Server-Heartbeat Ø/max (Scheduler-Statistik) + teuerste Takte, Zustand der Arena-Slots, Bots,
--  Projektile, Spieler, Speicher, Laufzeit, Client-FPS/Ping und den letzten abgelehnten Schuss + Grund
--  (Combat "Reject" kommt für Admins immer). Abfrage 1×/s nur solange sichtbar.
--  Zusätzlich: Hitbox-Anzeige (Admin-Debug "Hitboxen zeigen" = workspace-Attribut DebugShowHitboxes):
--  Kopf-Kugel + Körper-Kasten (analytisch wie B13.2) an allen Combatants in 150 Studs, 10 Hz, ≤ 32 Paare.
--  Look (docs/STYLE-AKYTEX.md): Glas-Karte (Surface, 1-px-Rahmen, Ecke 12), Titel Michroma + Akzent-Strich,
--  Werte in Text2 (Monospace nur für die Takt-Tabelle, damit die Spalten stehen).
--
--  Öffentliche API:
--    DebugOverlay.Toggle()
--    DebugOverlay.Init(ctx) / DebugOverlay.Start()
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DebugOverlay = {}

local player = Players.LocalPlayer
local ctx: any = nil

local POLL_SECONDS = 1
local HITBOX_HZ = 10
local HITBOX_RANGE = 150
local HITBOX_MAX = 32
-- AKYTEX-Farben als Ersatz, falls das UI-Kit fehlt (sonst UI.Theme)
local FALLBACK_THEME = {
	Surface = Color3.fromRGB(18, 24, 36),
	Border = Color3.fromRGB(31, 41, 55),
	Text = Color3.fromRGB(230, 236, 245),
	Text2 = Color3.fromRGB(170, 180, 195),
	Accent = Color3.fromRGB(79, 140, 255),
	Down = Color3.fromRGB(239, 68, 68),
}

local visible = false
local hiddenByPhoto = false
local frame: Frame? = nil
local lines: TextLabel? = nil
local titleLabel: TextLabel? = nil
local pollToken = 0
local lastInfo: { [string]: any }? = nil
local lastReject: { Shot: number, Why: string, T: number }? = nil
local fps = 60
local fpsAcc, fpsFrames = 0, 0

type HitboxPair = { Head: SphereHandleAdornment, Body: BoxHandleAdornment }
local hitboxFolder: Folder? = nil
local hitboxPool: { HitboxPair } = {}
local hitboxAcc = 0

local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function formatTime(seconds: number): string
	local util = ctx and ctx.Util
	if util and type(util.FormatTime) == "function" then
		local ok, text = pcall(util.FormatTime, seconds)
		if ok and type(text) == "string" then
			return text
		end
	end
	return ("%ds"):format(math.floor(seconds))
end

local function theme(): { [string]: Color3 }
	local ui = ctx and ctx.UI
	local t = ui and ui.Theme
	return if type(t) == "table" then t else FALLBACK_THEME
end

local function build()
	if frame then
		return
	end
	local parent = ctx and ctx.Gui
	if typeof(parent) ~= "Instance" then
		return
	end
	local th = theme()
	local box = Instance.new("Frame")
	box.Name = "CC_DebugOverlay"
	box.Position = UDim2.fromOffset(12, 120)
	box.Size = UDim2.fromOffset(430, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = th.Surface or FALLBACK_THEME.Surface
	box.BackgroundTransparency = 0.12
	box.BorderSizePixel = 0
	box.ZIndex = 50
	box.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = th.Border or FALLBACK_THEME.Border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = box
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = box
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.Michroma
	title.TextSize = 13
	title.TextColor3 = th.Text or FALLBACK_THEME.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = T("admin.dbgTitle")
	title.LayoutOrder = 1
	title.ZIndex = 51
	title.Parent = box
	local underline = Instance.new("Frame")
	underline.Name = "Underline"
	underline.Size = UDim2.fromOffset(24, 2)
	underline.BackgroundColor3 = th.Accent or FALLBACK_THEME.Accent
	underline.BorderSizePixel = 0
	underline.LayoutOrder = 2
	underline.ZIndex = 51
	underline.Parent = box
	local label = Instance.new("TextLabel")
	label.Name = "Lines"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.RobotoMono
	label.TextSize = 13
	label.LineHeight = 1.1
	label.TextColor3 = th.Text2 or FALLBACK_THEME.Text2
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = false
	label.Text = ""
	label.LayoutOrder = 3
	label.ZIndex = 51
	label.Parent = box
	box.Parent = parent
	frame = box
	lines = label
	titleLabel = title
end

local function render()
	if not lines then
		return
	end
	local out: { string } = {}
	if titleLabel then
		titleLabel.Text = T("admin.dbgTitle")
	end
	local info = lastInfo
	if info then
		table.insert(out, T("admin.dbgHeartbeat", tonumber(info.HeartbeatMs) or 0, tonumber(info.HeartbeatMaxMs) or 0))
		if type(info.Jobs) == "table" then
			for _, job in ipairs(info.Jobs) do
				if type(job) == "table" then
					table.insert(
						out,
						("  %-22s %5.2f / %5.2f ms"):format(
							string.sub(tostring(job.Name), 1, 22),
							tonumber(job.AvgMs) or 0,
							tonumber(job.MaxMs) or 0
						)
					)
				end
			end
		end
		table.insert(
			out,
			T("admin.dbgCounts", tonumber(info.Players) or 0, tonumber(info.Bots) or 0, tonumber(info.Projectiles) or 0)
		)
		local slots: { string } = {}
		if type(info.Slots) == "table" then
			for _, s in ipairs(info.Slots) do
				if type(s) == "table" then
					table.insert(
						slots,
						("%s:%s%s"):format(
							tostring(s.Slot),
							tostring(s.State),
							if s.MapKey then "(" .. tostring(s.MapKey) .. ")" else ""
						)
					)
				end
			end
		end
		table.insert(out, T("admin.dbgSlots", if #slots > 0 then table.concat(slots, "  ") else "-"))
		table.insert(out, T("admin.dbgMem", tonumber(info.MemoryMb) or 0, formatTime(tonumber(info.Uptime) or 0)))
	else
		table.insert(out, T("core.loading"))
	end
	table.insert(out, T("admin.dbgClient", math.floor(fps + 0.5), tonumber(player:GetAttribute("PingMs")) or 0))
	local reject = lastReject
	if reject then
		table.insert(out, T("admin.dbgReject", reject.Shot, reject.Why, math.floor(os.clock() - reject.T)))
	else
		table.insert(out, T("admin.dbgNoReject"))
	end
	lines.Text = table.concat(out, "\n")
end

local function poll(token: number)
	while visible and token == pollToken do
		local remotes = ctx and ctx.Remotes
		local admin = remotes and remotes.Admin
		if admin and admin:IsA("RemoteFunction") then
			local ok, result = pcall(function()
				return admin:InvokeServer("ServerInfo", {})
			end)
			if ok and type(result) == "table" and result.Ok and type(result.Data) == "table" then
				lastInfo = result.Data
			end
		end
		if not visible or token ~= pollToken then
			break
		end
		render()
		task.wait(POLL_SECONDS)
	end
end

local function applyVisible()
	build()
	if frame then
		frame.Visible = visible and not hiddenByPhoto
	end
end

function DebugOverlay.Toggle()
	visible = not visible
	pollToken += 1
	applyVisible()
	if visible then
		render()
		task.spawn(poll, pollToken)
	end
end

-- ---------------------------------------------------------------------
-- HITBOXEN (rein lokal, CanQuery-frei: Adornments sind keine Parts)
-- ---------------------------------------------------------------------
local function pairAt(index: number): HitboxPair?
	local existing = hitboxPool[index]
	if existing then
		return existing
	end
	if index > HITBOX_MAX then
		return nil
	end
	if not hitboxFolder then
		local folder = Instance.new("Folder")
		folder.Name = "CC_DebugHitboxes"
		folder.Parent = workspace.CurrentCamera
		hitboxFolder = folder
	end
	local head = Instance.new("SphereHandleAdornment")
	head.Color3 = FALLBACK_THEME.Down -- AKYTEX Down: Kopf
	head.Transparency = 0.6
	head.AlwaysOnTop = true
	head.ZIndex = 1
	head.Visible = false
	head.Parent = hitboxFolder
	local body = Instance.new("BoxHandleAdornment")
	body.Color3 = FALLBACK_THEME.Accent -- AKYTEX Accent: Körper
	body.Transparency = 0.75
	body.AlwaysOnTop = true
	body.ZIndex = 0
	body.Visible = false
	body.Parent = hitboxFolder
	local pair: HitboxPair = { Head = head, Body = body }
	hitboxPool[index] = pair
	return pair
end

local function hideHitboxes(from: number)
	for i = from, #hitboxPool do
		local pair = hitboxPool[i]
		pair.Head.Visible = false
		pair.Body.Visible = false
		pair.Head.Adornee = nil
		pair.Body.Adornee = nil
	end
end

local function updateHitboxes()
	if workspace:GetAttribute("DebugShowHitboxes") ~= true or hiddenByPhoto then
		hideHitboxes(1)
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local combat = ctx and ctx.Config and ctx.Config.Combat or {}
	local headRadius = tonumber(combat.HeadRadius) or 0.8
	local bodyOffset: Vector3 = if typeof(combat.BodyOffset) == "Vector3"
		then combat.BodyOffset
		else Vector3.new(0, -1, 0)
	local bodyHalf: Vector3 = if typeof(combat.BodyHalf) == "Vector3" then combat.BodyHalf else Vector3.new(1.5, 2, 0.8)
	local camPos = camera.CFrame.Position
	local index = 0
	local candidates: { Model } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		if character then
			table.insert(candidates, character)
		end
	end
	for _, tagged in ipairs(game:GetService("CollectionService"):GetTagged("Bot")) do
		if tagged:IsA("Model") then
			table.insert(candidates, tagged)
		end
	end
	for _, model in ipairs(candidates) do
		if index >= HITBOX_MAX then
			break
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		local head = model:FindFirstChild("Head")
		if
			root
			and head
			and root:IsA("BasePart")
			and head:IsA("BasePart")
			and model:GetAttribute("CombatantId") ~= nil
			and (root.Position - camPos).Magnitude <= HITBOX_RANGE
		then
			index += 1
			local pair = pairAt(index)
			if not pair then
				break
			end
			local mult = if model:GetAttribute("BigHead") then 1.6 else 1
			pair.Head.Adornee = head
			pair.Head.Radius = headRadius * mult
			pair.Head.CFrame = CFrame.new()
			pair.Head.Visible = true
			pair.Body.Adornee = root
			pair.Body.Size = bodyHalf * 2
			pair.Body.CFrame = CFrame.new(bodyOffset)
			pair.Body.Visible = true
		end
	end
	hideHitboxes(index + 1)
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function DebugOverlay.Init(context: any)
	ctx = context
end

function DebugOverlay.Start()
	local key = Enum.KeyCode.F8
	local keys = ctx and ctx.Config and ctx.Config.Client and ctx.Config.Client.Keys
	if keys and type(keys.Debug) == "table" and type(keys.Debug[1]) == "string" then
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[keys.Debug[1]]
		end)
		if ok and typeof(code) == "EnumItem" then
			key = code
		end
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		-- F8 wird nie von Roblox-Menüs "verbraucht"; andere Tasten nur, wenn kein Textfeld/Menü sie nimmt
		if input.KeyCode ~= key or UserInputService:GetFocusedTextBox() then
			return
		end
		if processed and key ~= Enum.KeyCode.F8 then
			return
		end
		DebugOverlay.Toggle()
	end)
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Combat:Reject", function(data: any)
			if type(data) == "table" then
				lastReject = {
					Shot = tonumber(data.Shot) or 0,
					Why = string.sub(tostring(data.Why or "?"), 1, 24),
					T = os.clock(),
				}
				if visible then
					render()
				end
			end
		end)
		hooks.On("PhotoMode", function(on: any)
			hiddenByPhoto = on == true
			applyVisible()
			if hiddenByPhoto then
				hideHitboxes(1)
			end
		end)
	end
	RunService.PreRender:Connect(function(dt)
		fpsAcc += dt
		fpsFrames += 1
		if fpsAcc >= 0.5 then
			fps = fpsFrames / fpsAcc
			fpsAcc, fpsFrames = 0, 0
		end
		hitboxAcc += dt
		if hitboxAcc >= 1 / HITBOX_HZ then
			hitboxAcc = 0
			if #hitboxPool > 0 or workspace:GetAttribute("DebugShowHitboxes") == true then
				updateHitboxes()
			end
		end
	end)
end

return DebugOverlay
