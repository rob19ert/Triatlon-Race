--!strict
-- Усталость на экране: чем выше пульс, тем сильнее (только картинка, на игру не влияет).
--  * камера «дышит» — ритмично приседает и покачивается, ритм учащается с пульсом;
--  * края экрана темнеют и пульсируют в такт дыханию, в красной зоне — краснеют;
--  * в красной зоне — лёгкое размытие и выцветание.
-- На рубеже (камера прицела Scriptable) эффекты камеры не трогаем.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local F = Config.Fatigue
local S = Config.Stamina
local player = Players.LocalPlayer

---------------------------------------------------------------- виньетка (4 края с градиентом, без картинок)

local gui = Instance.new("ScreenGui")
gui.Name = "FatigueVignette"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = -1 -- под остальным HUD
gui.Parent = player:WaitForChild("PlayerGui")

local DARK = Color3.fromRGB(10, 0, 0)
local RED = Color3.fromRGB(150, 0, 0)

type Edge = { frame: Frame, gradient: UIGradient }
local edges: { Edge } = {}

-- rotation: куда смотрит градиент (непрозрачный край -> прозрачная середина)
local function edge(position: UDim2, size: UDim2, rotation: number)
	local f = Instance.new("Frame")
	f.Position = position
	f.Size = size
	f.BorderSizePixel = 0
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = 1
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	table.insert(edges, { frame = f, gradient = g })
end
edge(UDim2.fromScale(0, 0), UDim2.fromScale(0.28, 1), 0) -- слева
edge(UDim2.fromScale(0.72, 0), UDim2.fromScale(0.28, 1), 180) -- справа
edge(UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.3), 90) -- сверху
edge(UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.3), -90) -- снизу

---------------------------------------------------------------- размытие и цвет (локальные эффекты)

local blur = Instance.new("BlurEffect")
blur.Name = "FatigueBlur"
blur.Size = 0
blur.Parent = Lighting

local color = Instance.new("ColorCorrectionEffect")
color.Name = "FatigueColor"
color.Saturation = 0
color.Parent = Lighting

---------------------------------------------------------------- каждый кадр

local breathPhase = 0
local level = 0 -- сглаженная сила эффекта 0..1
local red = 0 -- сглаженная красная зона 0..1

local function pulseNow(): number?
	local v = player:GetAttribute(Attributes.Pulse)
	return if typeof(v) == "number" then v else nil
end

RunService:BindToRenderStep("FatigueFx", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local pulse = pulseNow()
	local target = if pulse then math.clamp((pulse - F.StartPulse) / (S.MaxPulse - F.StartPulse), 0, 1) else 0
	local redTarget = if player:GetAttribute(Attributes.RedZone) == true then 1 else 0
	local k = math.clamp(dt * 3, 0, 1)
	level += (target - level) * k
	red += (redTarget - red) * k

	-- ритм дыхания: чем выше пульс, тем чаще
	local period = F.BreathPeriodSlow + (F.BreathPeriodFast - F.BreathPeriodSlow) * level
	breathPhase = (breathPhase + dt / period * 2 * math.pi) % (2 * math.pi)
	local breath = math.sin(breathPhase) -- -1 выдох .. 1 вдох

	-- виньетка: темнее с усталостью, пульсирует в такт, в красной зоне — краснеет
	local alpha = F.VignetteMaxAlpha * level * (0.75 + 0.25 * breath)
	for _, e in edges do
		e.frame.BackgroundTransparency = 1 - alpha
		e.frame.BackgroundColor3 = DARK:Lerp(RED, red)
	end

	blur.Size = F.RedZoneBlur * red
	color.Saturation = F.RedZoneSaturation * red

	-- камера «дышит» (только обычная камера, не прицел и не подиум)
	local camera = workspace.CurrentCamera
	if level > 0.01 and camera.CameraType == Enum.CameraType.Custom then
		local bob = math.rad(F.CameraBobDeg * level) * breath
		local roll = math.rad(F.CameraRollDeg * level) * math.sin(breathPhase * 0.5)
		camera.CFrame = camera.CFrame * CFrame.Angles(bob, 0, roll)
	end
end)
