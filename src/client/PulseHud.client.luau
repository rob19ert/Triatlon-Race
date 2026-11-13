--!strict
-- HUD пульса: шкала внизу экрана (зелёная -> жёлтая -> красная), «удары в минуту»,
-- метка красной зоны. Только отображение атрибутов, которые выставляет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local S = Config.Stamina
local player = Players.LocalPlayer

---------------------------------------------------------------- UI

local gui = Instance.new("ScreenGui")
gui.Name = "PulseHud"
gui.ResetOnSpawn = false
gui.Enabled = false

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -16)
panel.Size = UDim2.new(0.4, 0, 0, 34)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.35
panel.Parent = gui
Instance.new("UICorner", panel)
local panelLimit = Instance.new("UISizeConstraint")
panelLimit.MinSize = Vector2.new(220, 34)
panelLimit.MaxSize = Vector2.new(420, 34)
panelLimit.Parent = panel

local heart = Instance.new("TextLabel")
heart.Name = "Bpm"
heart.BackgroundTransparency = 1
heart.Position = UDim2.fromOffset(8, 0)
heart.Size = UDim2.new(0, 90, 1, 0)
heart.Font = Enum.Font.GothamBold
heart.TextSize = 18
heart.TextColor3 = Color3.new(1, 1, 1)
heart.TextXAlignment = Enum.TextXAlignment.Left
heart.Parent = panel

local barBack = Instance.new("Frame")
barBack.Name = "Bar"
barBack.AnchorPoint = Vector2.new(0, 0.5)
barBack.Position = UDim2.new(0, 100, 0.5, 0)
barBack.Size = UDim2.new(1, -110, 0, 14)
barBack.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
barBack.Parent = panel
Instance.new("UICorner", barBack)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0.5, 1)
fill.Parent = barBack
Instance.new("UICorner", fill)

-- отметка порога красной зоны
local redMark = Instance.new("Frame")
redMark.Name = "RedZoneMark"
redMark.AnchorPoint = Vector2.new(0.5, 0.5)
redMark.Position = UDim2.fromScale(S.RedZoneEnter / S.MaxPulse, 0.5)
redMark.Size = UDim2.new(0, 2, 1, 6)
redMark.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
redMark.BorderSizePixel = 0
redMark.Parent = barBack

local warning = Instance.new("TextLabel")
warning.Name = "RedZone"
warning.AnchorPoint = Vector2.new(0.5, 1)
warning.Position = UDim2.new(0.5, 0, 0, -4)
warning.Size = UDim2.new(1, 0, 0, 22)
warning.BackgroundTransparency = 1
warning.Font = Enum.Font.GothamBlack
warning.TextSize = 18
warning.TextColor3 = Color3.fromRGB(255, 70, 70)
warning.TextStrokeTransparency = 0.4
warning.Text = "КРАСНАЯ ЗОНА — отдышись!"
warning.Visible = false
warning.Parent = panel

gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- отображение

local displayed = S.StartPulse

local function pulseColor(pulse: number): Color3
	-- 40 и ниже — зелёный, к RedZoneEnter — красный
	local t = math.clamp((pulse - 40) / (S.RedZoneEnter - 40), 0, 1)
	return Color3.fromHSV(0.33 * (1 - t), 0.85, 0.95)
end

RunService.RenderStepped:Connect(function(dt)
	local pulse = player:GetAttribute(Attributes.Pulse)
	if typeof(pulse) ~= "number" then
		gui.Enabled = false
		return
	end
	gui.Enabled = true

	-- плавное догоняние значения с сервера
	displayed += (pulse - displayed) * math.min(1, dt * 10)
	local ratio = displayed / S.MaxPulse

	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = pulseColor(displayed)

	local bpm = S.BpmAtMin + (S.BpmAtMax - S.BpmAtMin) * ratio
	local beat = if player:GetAttribute(Attributes.Sprinting) then "»" else ""
	heart.Text = string.format("♥ %d%s", math.floor(bpm + 0.5), beat)

	local red = player:GetAttribute(Attributes.RedZone) == true
	warning.Visible = red
	if red then
		-- мигание
		warning.TextTransparency = 0.5 - 0.5 * math.cos(os.clock() * 8)
	end
end)
