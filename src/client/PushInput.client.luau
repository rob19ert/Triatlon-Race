--!strict
-- Толчок: F (клавиатура), R1 (геймпад) или кнопка «Толчок» на экране (тач, модуль TouchButtons).
-- Клиент шлёт только намерение; кого и можно ли толкнуть — решает сервер.
-- Кулдаун читаем из атрибута PushReadyAt: на тач-кнопке — затемнение и цифра,
-- для клавиатуры — круглая иконка над панелью пульса.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local TouchButtons = require(script.Parent:WaitForChild("TouchButtons"))

local ACTION = "Push"
local TITLE = "Толчок"

local player = Players.LocalPlayer
local pushRemote = Remotes.get(Remotes.Names.PushIntent)

local function push()
	pushRemote:FireServer()
end

ContextActionService:BindAction(ACTION, function(_, state)
	if state == Enum.UserInputState.Begin then
		push()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)

local touchButton = TouchButtons.create({
	name = "Push",
	title = TITLE,
	slot = 2,
	group = "run",
	onDown = push,
})

---------------------------------------------------------------- иконка для клавиатуры

local showIcon = UserInputService.KeyboardEnabled

local gui = Instance.new("ScreenGui")
gui.Name = "PushHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local icon = Instance.new("Frame")
icon.AnchorPoint = Vector2.new(0.5, 1)
icon.Position = UDim2.new(0.5, 0, 1, -58) -- над панелью пульса (она внизу, высота 34)
icon.Size = UDim2.fromOffset(52, 52)
icon.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
icon.Visible = false
icon.Parent = gui
Instance.new("UICorner", icon).CornerRadius = UDim.new(0.5, 0)

local fill = Instance.new("Frame") -- тёмная заливка уходит вниз по мере отката
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
padding.PaddingLeft = UDim.new(0.2, 0)
padding.PaddingRight = UDim.new(0.2, 0)
padding.Parent = label

---------------------------------------------------------------- кулдаун

local cooldownStart = 0 -- server time начала текущего отката (для заливки)
local lastReadyAt: number? = nil

local function update()
	local readyAt = player:GetAttribute(Attributes.PushReadyAt) :: number?
	icon.Visible = showIcon and readyAt ~= nil
	if touchButton then
		touchButton:setVisible(readyAt ~= nil) -- кнопка только во время гонки
	end
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
	local fraction = if left > 0 then left / math.max(readyAt - cooldownStart, 0.01) else 0
	local text = if left > 0 then string.format("%d", math.ceil(left)) else nil

	fill.Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1))
	label.Text = text or "F"
	if touchButton then
		touchButton:setCooldown(fraction)
		touchButton:setTitle(text or TITLE)
	end
end

RunService.Heartbeat:Connect(update)
