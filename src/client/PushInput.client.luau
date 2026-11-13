--!strict
-- Толчок: F (клавиатура), R1 (геймпад) или кнопка «Толчок» на экране (тач).
-- Клиент шлёт только намерение; кого и можно ли толкнуть — решает сервер.
-- Иконка кулдауна внизу экрана читает атрибут PushReadyAt.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local ACTION = "Push"

local player = Players.LocalPlayer
local pushRemote = Remotes.get(Remotes.Names.PushIntent)

local function onAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		pushRemote:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(ACTION, onAction, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
ContextActionService:SetTitle(ACTION, "Толчок")
ContextActionService:SetPosition(ACTION, UDim2.new(1, -240, 1, -90))

-- иконка кулдауна
local gui = Instance.new("ScreenGui")
gui.Name = "PushHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local icon = Instance.new("Frame")
icon.AnchorPoint = Vector2.new(0.5, 1)
icon.Position = UDim2.new(0.5, 0, 1, -16)
icon.Size = UDim2.fromOffset(64, 64)
icon.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
icon.Visible = false
icon.Parent = gui
Instance.new("UICorner", icon).CornerRadius = UDim.new(0.5, 0)

local fill = Instance.new("Frame") -- тёмная заливка уходит снизу вверх по мере отката
fill.AnchorPoint = Vector2.new(0, 1)
fill.Position = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.new(0, 0, 0)
fill.BackgroundTransparency = 0.45
fill.BorderSizePixel = 0
fill.Parent = icon
Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeTransparency = 0.4
label.ZIndex = 2
label.Parent = icon
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0.15, 0)
padding.PaddingRight = UDim.new(0.15, 0)
padding.Parent = label

local buttonTitle = "Толчок"
local function setButtonTitle(text: string)
	if text ~= buttonTitle then
		buttonTitle = text
		ContextActionService:SetTitle(ACTION, text)
	end
end

local cooldownStart = 0 -- server time начала текущего отката (для заливки)
local lastReadyAt: number? = nil

local function update()
	local readyAt = player:GetAttribute(Attributes.PushReadyAt) :: number?
	icon.Visible = readyAt ~= nil
	if not readyAt then
		lastReadyAt = nil
		return
	end
	local t = workspace:GetServerTimeNow()
	if readyAt ~= lastReadyAt then
		lastReadyAt = readyAt
		cooldownStart = t
	end
	local left = readyAt - t
	if left > 0 then
		local total = math.max(readyAt - cooldownStart, 0.01)
		fill.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
		label.Text = string.format("%.0f", math.ceil(left))
		setButtonTitle(label.Text)
	else
		fill.Size = UDim2.fromScale(1, 0)
		label.Text = if UserInputService.KeyboardEnabled then "F" else "✋"
		setButtonTitle("Толчок")
	end
end

RunService.Heartbeat:Connect(update)
