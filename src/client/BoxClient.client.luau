--!strict
-- Секретные боксы у клиента (только картинка, всё решает сервер — BoxService):
--  * боксы на трассе крутятся и покачиваются;
--  * бокс взяли — вспышка конфетти у всех;
--  * свои бонусы — плашки под таймером: «💥 МЕГА-ТОЛЧОК 4.2» и «🎯 Большие мишени — на стрельбу».
-- Турбо из бокса показывает TurboFx (то же турбо, что за 5/5).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local B = Config.Boxes
local SPIN = 1.6 -- рад/с
local BOB = 0.5 -- стад вверх-вниз
local player = Players.LocalPlayer

---------------------------------------------------------------- вращение

-- исходное положение каждого бокса (сервер ставит, клиент только крутит вокруг него)
local homes: { [BasePart]: CFrame } = {}

local function track(box: Instance)
	if box:IsA("BasePart") then
		homes[box] = box.CFrame
	end
end
for _, box in CollectionService:GetTagged(B.BoxTag) do
	track(box)
end
CollectionService:GetInstanceAddedSignal(B.BoxTag):Connect(track)
CollectionService:GetInstanceRemovedSignal(B.BoxTag):Connect(function(box)
	homes[box :: BasePart] = nil
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for box, home in homes do
		local phase = home.Position.X * 0.1 + home.Position.Z * 0.1 -- соседи не в такт
		box.CFrame = home * CFrame.new(0, math.sin(t * 2 + phase) * BOB, 0) * CFrame.Angles(0.3, t * SPIN + phase, 0.3)
	end
end)

Remotes.get(Remotes.Names.BoxTaken).OnClientEvent:Connect(function(position: Vector3)
	Fx.burst("Confetti", position)
end)

---------------------------------------------------------------- плашки своих бонусов

local gui = Instance.new("ScreenGui")
gui.Name = "BoxHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function pill(y: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, y)
	label.Size = UDim2.fromOffset(0, 30)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = color
	label.BackgroundTransparency = 0.1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 20
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Visible = false
	label.Parent = gui
	Instance.new("UICorner", label).CornerRadius = UDim.new(0.4, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = label
	return label
end

local mega = pill(140, Color3.fromRGB(220, 60, 60))
local big = pill(176, Color3.fromRGB(40, 140, 220))
local megaDef = B.Defs.MegaPush
local bigDef = B.Defs.BigTargets

RunService.Heartbeat:Connect(function()
	local untilT = player:GetAttribute(Attributes.MegaPushUntil)
	local left = if typeof(untilT) == "number" then untilT - workspace:GetServerTimeNow() else 0
	mega.Visible = left > 0
	if left > 0 then
		mega.Text = string.format("%s МЕГА-ТОЛЧОК %.1f", megaDef.icon, left)
	end
	big.Visible = player:GetAttribute(Attributes.BigTargets) == true
	if big.Visible then
		big.Text = bigDef.icon .. " Большие мишени — на стрельбу"
	end
end)
