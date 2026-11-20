--!strict
-- Лёд на поворотах у клиента (сцепление считает сервер — IceService, атрибут IceGrip):
--  * на льду: клик ЛКМ / E / R2 / тап по экрану или кнопке «Жми!» — шлём серверу IceClick;
--  * снос наружу из поворота: после штатного управления добавляем к направлению движения
--    SlideDir льдины × (1 − сцепление);
--  * подсказка «ЖМИ!» над полосой пульса и полоска сцепления.

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local TouchButtons = require(script.Parent:WaitForChild("TouchButtons"))

local I = Config.Ice
local player = Players.LocalPlayer
local clickRemote = Remotes.get(Remotes.Names.IceClick)
local ACTION = "IceClick"

local function grip(): number?
	local g = player:GetAttribute(Attributes.IceGrip)
	return if typeof(g) == "number" then g else nil
end

---------------------------------------------------------------- клики

local lastSent = 0
local hud: TextLabel

local function click()
	if not grip() then
		return
	end
	local t = os.clock()
	if t - lastSent < 1 / I.MaxClicksPerSec then
		return
	end
	lastSent = t
	clickRemote:FireServer()
	if hud then
		hud.TextSize = 40 -- «толчок» надписи на каждый клик
	end
end

local function onAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		click()
	end
	return Enum.ContextActionResult.Pass
end

-- тап по экрану (не по кнопкам и не стиком)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.Touch then
		click()
	end
end)

local button = TouchButtons.create({
	name = "IceClick",
	title = "Press!",
	slot = 3,
	color = Color3.fromRGB(90, 190, 255),
	onDown = click,
})
if button then
	button:setVisible(false)
end

---------------------------------------------------------------- подсказка

local gui = Instance.new("ScreenGui")
gui.Name = "IceHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 1)
frame.Position = UDim2.new(0.5, 0, 1, -200)
frame.Size = UDim2.fromOffset(220, 70)
frame.BackgroundTransparency = 1
frame.Visible = false
frame.Parent = gui

hud = Instance.new("TextLabel")
hud.Size = UDim2.new(1, 0, 0, 46)
hud.BackgroundTransparency = 1
hud.Font = Enum.Font.FredokaOne
hud.Text = I.Hint
hud.TextSize = 34
hud.TextColor3 = Color3.fromRGB(200, 240, 255)
hud.TextStrokeColor3 = Color3.fromRGB(20, 60, 110)
hud.TextStrokeTransparency = 0
hud.Parent = frame

local barBack = Instance.new("Frame")
barBack.Position = UDim2.new(0, 0, 0, 52)
barBack.Size = UDim2.new(1, 0, 0, 10)
barBack.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
barBack.BackgroundTransparency = 0.3
barBack.Parent = frame
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = Color3.fromRGB(110, 210, 255)
bar.Parent = barBack
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

local bound = false
local function onGrip()
	local g = grip()
	local on = g ~= nil
	frame.Visible = on
	if button then
		button:setVisible(on)
	end
	if on ~= bound then
		bound = on
		if on then
			ContextActionService:BindAction(ACTION, onAction, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.E, Enum.KeyCode.ButtonR2)
		else
			ContextActionService:UnbindAction(ACTION)
		end
	end
	if g then
		bar.Size = UDim2.fromScale(g, 1)
	end
end
player:GetAttributeChangedSignal(Attributes.IceGrip):Connect(onGrip)
onGrip()

RunService.RenderStepped:Connect(function(dt)
	if frame.Visible then
		hud.TextSize += (34 - hud.TextSize) * math.min(1, dt * 12)
	end
end)

---------------------------------------------------------------- снос наружу

local function slideDir(position: Vector3): Vector3?
	for _, part in CollectionService:GetTagged(I.Tag) do
		if part:IsA("BasePart") then
			local p = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= -half.Y and p.Y <= half.Y + I.HeightAbove then
				local d = part:GetAttribute("SlideDir")
				return if typeof(d) == "Vector3" then d else nil
			end
		end
	end
	return nil
end

RunService:BindToRenderStep("IceSlide", Enum.RenderPriority.Input.Value + 2, function()
	local g = grip()
	if not g then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local dir = humanoid.MoveDirection
	local slide = slideDir(root.Position)
	if dir.Magnitude < 0.01 or not slide then
		return
	end
	local mixed = dir + slide * I.SlideStrength * (1 - g)
	if mixed.Magnitude > 0.01 then
		humanoid:Move(mixed.Unit, false)
	end
end)
