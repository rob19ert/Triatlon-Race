--!strict
-- Режим прицела на рубеже: камера из глаз стрелка с оптикой, визуальное качание,
-- ввод выстрела и задержки дыхания, HUD патронов/ветра/дыхания.
-- Клиент шлёт только «куда целился и когда»; попадание считает сервер по той же формуле (Shared/Aim).

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local Aim = require(Shared:WaitForChild("Aim"))
local Types = require(Shared:WaitForChild("Types"))
local TouchButtons = require(script.Parent:WaitForChild("TouchButtons"))

local C = Config.Shooting
local player = Players.LocalPlayer

local ACTION_FIRE = "ShootFire"
local ACTION_BREATH = "ShootHoldBreath"
local RENDER_STEP = "ShootingCamera"

type AimState = {
	eye: CFrame,
	stance: Aim.Stance,
	wind: number,
	targetSpacingDeg: number,
	shotsLeft: number,
	shotsFired: number,
	yaw: number,
	pitch: number,
	lastShotAt: number,
	savedFov: number,
}

local aim: AimState? = nil
local fireButton: TouchButtons.Handle? = nil
local breathButton: TouchButtons.Handle? = nil

local fireRemote = Remotes.get(Remotes.Names.FireShot)
local breathRemote = Remotes.get(Remotes.Names.HoldBreath)

---------------------------------------------------------------- UI

local gui = Instance.new("ScreenGui")
gui.Name = "ShootingHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false

-- перекрестие в центре экрана
local cross = Instance.new("Frame")
cross.Name = "Crosshair"
cross.AnchorPoint = Vector2.new(0.5, 0.5)
cross.Position = UDim2.fromScale(0.5, 0.5)
cross.Size = UDim2.fromOffset(28, 28)
cross.BackgroundTransparency = 1
cross.Parent = gui
local ring = Instance.new("UIStroke")
ring.Color = Color3.fromRGB(255, 60, 60)
ring.Thickness = 2
ring.Parent = cross
Instance.new("UICorner", cross).CornerRadius = UDim.new(1, 0)
for _, spec in { { 2, 60 }, { 60, 2 } } do
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.5)
	line.Size = UDim2.fromOffset(spec[1], spec[2])
	line.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	line.BackgroundTransparency = 0.3
	line.BorderSizePixel = 0
	line.Parent = cross
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -64)
panel.Size = UDim2.fromOffset(360, 104)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.3
panel.Parent = gui
Instance.new("UICorner", panel)

local dotsRow = Instance.new("Frame")
dotsRow.BackgroundTransparency = 1
dotsRow.Position = UDim2.fromOffset(12, 8)
dotsRow.Size = UDim2.new(1, -24, 0, 24)
dotsRow.Parent = panel
local dotsLayout = Instance.new("UIListLayout")
dotsLayout.FillDirection = Enum.FillDirection.Horizontal
dotsLayout.Padding = UDim.new(0, 8)
dotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dotsLayout.Parent = dotsRow

local DOT_EMPTY = Color3.fromRGB(70, 70, 80)
local DOT_HIT = Color3.fromRGB(255, 255, 255)
local DOT_MISS = Color3.fromRGB(230, 60, 60)
local dots: { Frame } = {}
for i = 1, C.ShotsPerStage do
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(22, 22)
	dot.BackgroundColor3 = DOT_EMPTY
	dot.LayoutOrder = i
	dot.Parent = dotsRow
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	dots[i] = dot
end

local windLabel = Instance.new("TextLabel")
windLabel.BackgroundTransparency = 1
windLabel.AnchorPoint = Vector2.new(1, 0)
windLabel.Position = UDim2.new(1, -12, 0, 8)
windLabel.Size = UDim2.fromOffset(140, 24)
windLabel.Font = Enum.Font.GothamBold
windLabel.TextSize = 18
windLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
windLabel.TextXAlignment = Enum.TextXAlignment.Right
windLabel.Parent = panel

-- подсказка: куда сносит пулю и куда целиться
local windHint = Instance.new("TextLabel")
windHint.BackgroundTransparency = 1
windHint.Position = UDim2.fromOffset(12, 38)
windHint.Size = UDim2.new(1, -24, 0, 26)
windHint.Font = Enum.Font.GothamMedium
windHint.TextSize = 15
windHint.TextColor3 = Color3.fromRGB(255, 200, 80)
windHint.TextXAlignment = Enum.TextXAlignment.Left
windHint.TextWrapped = true
windHint.Parent = panel

local breathLabel = Instance.new("TextLabel")
breathLabel.BackgroundTransparency = 1
breathLabel.Position = UDim2.fromOffset(12, 68)
breathLabel.Size = UDim2.new(1, -24, 0, 28)
breathLabel.Font = Enum.Font.GothamMedium
breathLabel.TextSize = 16
breathLabel.TextColor3 = Color3.new(1, 1, 1)
breathLabel.TextXAlignment = Enum.TextXAlignment.Left
breathLabel.TextWrapped = true
breathLabel.Parent = panel

gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- прицел

local function now(): number
	return workspace:GetServerTimeNow()
end

local function numberAttr(name: string, default: number): number
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local function setCharacterHidden(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function windText(wind: number): string
	local level = math.abs(wind)
	local arrow = if wind > 0 then string.rep("▶", level) elseif wind < 0 then string.rep("◀", level) else "—"
	return string.format("Ветер %s %d", arrow, level)
end

local function windHintText(wind: number, spacingDeg: number): string
	if wind == 0 then
		return "Ветра нет — целься прямо в мишень"
	end
	local side = if wind > 0 then "вправо" else "влево"
	local aimSide = if wind > 0 then "левее" else "правее"
	local inTargets = if spacingDeg > 0 then math.abs(Aim.windYaw(wind)) / spacingDeg else 0
	return string.format("Пулю сносит %s ≈ на %.1f мишени — целься %s", side, inTargets, aimSide)
end

-- след пули на щите: виден только стрелку, сразу показывает поправку на ветер
local function showImpact(state: AimState, point: Vector3, hit: boolean)
	local mark = Instance.new("Part")
	mark.Name = "ImpactMark"
	mark.Shape = Enum.PartType.Ball
	mark.Size = Vector3.one * C.ImpactMarkSize
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.Material = Enum.Material.Neon
	mark.Color = if hit then Color3.fromRGB(80, 255, 120) else Color3.fromRGB(255, 60, 60)
	-- чуть ближе к стрелку, чтобы не утонуть в мишени
	mark.Position = point - state.eye.LookVector * 0.15
	mark.Parent = workspace
	Debris:AddItem(mark, C.ImpactMarkSeconds)
end

local function updateBreathLabel(t: number)
	local holdUntil = numberAttr(Attributes.HoldBreathUntil, 0)
	local readyAt = numberAttr(Attributes.HoldBreathReadyAt, 0)
	if t < holdUntil then
		breathLabel.Text = string.format("Дыхание задержано: %.1f с", holdUntil - t)
	elseif t < readyAt then
		breathLabel.Text = string.format("Дыхание: снова через %.1f с", readyAt - t)
	elseif TouchButtons.isTouch() then
		breathLabel.Text = "«Дыхание» — задержать, «Огонь» — выстрел"
	else
		breathLabel.Text = "ЛКМ — выстрел, ПКМ — задержать дыхание"
	end
end

-- Откат на тач-кнопках: затвор и задержка дыхания.
local function updateTouchButtons(state: AimState, t: number)
	if fireButton then
		local left = state.lastShotAt + C.MinShotInterval - t
		fireButton:setCooldown(if left > 0 then left / C.MinShotInterval else 0)
		fireButton:setTitle(if state.shotsLeft > 0 then string.format("Огонь\n%d", state.shotsLeft) else "—")
	end
	if breathButton then
		local holdUntil = numberAttr(Attributes.HoldBreathUntil, 0)
		local readyAt = numberAttr(Attributes.HoldBreathReadyAt, 0)
		if t < holdUntil then
			breathButton:setCooldown(0)
			breathButton:setTitle(string.format("%.1f", holdUntil - t))
		elseif t < readyAt then
			breathButton:setCooldown((readyAt - t) / C.HoldBreathCooldown)
			breathButton:setTitle(string.format("%d", math.ceil(readyAt - t)))
		else
			breathButton:setCooldown(0)
			breathButton:setTitle("Дыхание")
		end
	end
end

local function renderAim()
	local state = aim
	if not state then
		return
	end
	local t = now()
	local pulse = numberAttr(Attributes.Pulse, Config.Stamina.StartPulse)
	local holding = t < numberAttr(Attributes.HoldBreathUntil, 0)
	local swayYaw, swayPitch = Aim.swayOffset(t, pulse, state.stance, holding)

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = C.ScopeFov
	camera.CFrame = Aim.cframe(state.eye, state.yaw + swayYaw, state.pitch + swayPitch)

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	setCharacterHidden(true)
	updateBreathLabel(t)
	updateTouchButtons(state, t)
end

local function fire(): Enum.ContextActionResult
	local state = aim
	if not state or state.shotsLeft <= 0 then
		return Enum.ContextActionResult.Sink
	end
	local t = now()
	if t - state.lastShotAt < C.MinShotInterval then
		return Enum.ContextActionResult.Sink
	end
	state.lastShotAt = t
	fireRemote:FireServer(state.yaw, state.pitch, t)
	return Enum.ContextActionResult.Sink
end

local function onFireAction(_: string, inputState: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		return fire()
	end
	return Enum.ContextActionResult.Sink
end

local function onBreathAction(_: string, inputState: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and aim then
		breathRemote:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

local function enterAim(payload: Types.ShootingStartPayload)
	local camera = workspace.CurrentCamera
	aim = {
		eye = payload.eye,
		stance = payload.stance,
		wind = payload.wind,
		targetSpacingDeg = payload.targetSpacingDeg,
		shotsLeft = payload.shots,
		shotsFired = 0,
		yaw = 0,
		pitch = 0,
		lastShotAt = -math.huge,
		savedFov = camera.FieldOfView,
	}
	for _, dot in dots do
		dot.BackgroundColor3 = DOT_EMPTY
	end
	windLabel.Text = windText(payload.wind)
	windHint.Text = windHintText(payload.wind, payload.targetSpacingDeg)
	gui.Enabled = true

	ContextActionService:BindAction(ACTION_FIRE, onFireAction, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction(ACTION_BREATH, onBreathAction, false, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)

	-- тач: на месте кнопок бега — «Огонь» (крупная) и «Дыхание»
	TouchButtons.setGroupHidden("run", true)
	fireButton = TouchButtons.create({
		name = "Fire",
		title = "Огонь",
		slot = 1,
		big = true,
		color = Color3.fromRGB(235, 70, 70),
		onDown = function()
			fire()
		end,
	})
	breathButton = TouchButtons.create({
		name = "Breath",
		title = "Дыхание",
		slot = 2,
		color = Color3.fromRGB(70, 170, 255),
		onDown = function()
			if aim then
				breathRemote:FireServer()
			end
		end,
	})

	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, renderAim)
end

local function exitAim()
	local state = aim
	if not state then
		return
	end
	aim = nil
	RunService:UnbindFromRenderStep(RENDER_STEP)
	ContextActionService:UnbindAction(ACTION_FIRE)
	ContextActionService:UnbindAction(ACTION_BREATH)
	if fireButton then
		fireButton:destroy()
		fireButton = nil
	end
	if breathButton then
		breathButton:destroy()
		breathButton = nil
	end
	TouchButtons.setGroupHidden("run", false)
	gui.Enabled = false

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = state.savedFov
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	setCharacterHidden(false)
end

---------------------------------------------------------------- ввод прицела

local function addAim(dx: number, dy: number, sensitivity: number)
	local state = aim
	if not state then
		return
	end
	state.yaw = math.clamp(state.yaw + dx * sensitivity, -C.AimLimitDeg, C.AimLimitDeg)
	state.pitch = math.clamp(state.pitch - dy * sensitivity, -C.AimLimitDeg, C.AimLimitDeg)
end

UserInputService.InputChanged:Connect(function(input, _)
	if aim and input.UserInputType == Enum.UserInputType.MouseMovement then
		addAim(input.Delta.X, input.Delta.Y, C.MouseSensitivity)
	end
end)

UserInputService.TouchMoved:Connect(function(touch, processed)
	if aim and not processed then
		addAim(touch.Delta.X, touch.Delta.Y, C.TouchSensitivity)
	end
end)

---------------------------------------------------------------- события сервера

Remotes.get(Remotes.Names.ShootingStarted).OnClientEvent:Connect(function(payload: Types.ShootingStartPayload)
	exitAim()
	enterAim(payload)
end)

Remotes.get(Remotes.Names.ShotResult).OnClientEvent:Connect(function(result: Types.ShotResultPayload)
	local state = aim
	if not state then
		return
	end
	state.shotsFired += 1
	state.shotsLeft = result.shotsLeft
	local dot = dots[state.shotsFired]
	if dot then
		dot.BackgroundColor3 = if result.hit then DOT_HIT else DOT_MISS
	end
	if result.impact then
		showImpact(state, result.impact, result.hit)
	end
end)

Remotes.get(Remotes.Names.ShootingFinished).OnClientEvent:Connect(function(summary: Types.ShootingSummary)
	if summary.userId == player.UserId then
		exitAim()
	end
end)

Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	if payload.state ~= "Racing" then
		exitAim()
	end
end)

player.CharacterAdded:Connect(function()
	exitAim()
end)
