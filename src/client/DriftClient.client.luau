--!strict
-- Дрифт на велосипеде у клиента:
--  * ввод: зажать E (клавиатура), L2 (геймпад) или кнопку «Дрифт» (тач, видна только на велосипеде) —
--    шлём серверу только «зажал / отпустил», заряд и ускорение считает DriftService;
--  * искры из-под заднего колеса у всех дрифтящих: цвет по уровню (атрибут DriftTier),
--    отпустил с зарядом (DriftBoostUntil) — сноп искр.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local TouchButtons = require(script.Parent:WaitForChild("TouchButtons"))

local D = Config.Drift
local player = Players.LocalPlayer
local driftRemote = Remotes.get(Remotes.Names.DriftIntent)

---------------------------------------------------------------- ввод

local holding = false

local function riding(): boolean
	return player:GetAttribute(Attributes.Riding) == true
end

local function setHolding(value: boolean)
	if value and not riding() then
		return
	end
	if value ~= holding then
		holding = value
		driftRemote:FireServer(value)
	end
end

ContextActionService:BindAction("Drift", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setHolding(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setHolding(false)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonL2)

local button = TouchButtons.create({
	name = "Drift",
	title = "Дрифт",
	slot = 3,
	color = Color3.fromRGB(200, 80, 255),
	onDown = function()
		setHolding(true)
	end,
	onUp = function()
		setHolding(false)
	end,
})

local function onRiding()
	if button then
		button:setVisible(riding())
	end
	if not riding() then
		holding = false -- сервер сам прервал дрифт
	end
end
player:GetAttributeChangedSignal(Attributes.Riding):Connect(onRiding)
onRiding()

---------------------------------------------------------------- искры у всех

local EMITTER = "DriftSparks"

local function emitterFor(character: Model): ParticleEmitter?
	local bike = character:FindFirstChild(Config.Bike.ModelName)
	local root = bike and bike:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local existing = root:FindFirstChild(EMITTER, true)
	if existing and existing:IsA("ParticleEmitter") then
		return existing
	end
	local att = Instance.new("Attachment")
	att.Name = "DriftSparksAt"
	att.Position = Vector3.new(0, 0.2, 1.9) -- под задним колесом
	att.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Name = EMITTER
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.LightEmission = 0.3 -- сильнее — днём искры белеют и цвет уровня не виден
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0.1) })
	e.Lifetime = NumberRange.new(0.35, 0.6)
	e.Speed = NumberRange.new(10, 16)
	e.SpreadAngle = Vector2.new(30, 45)
	e.EmissionDirection = Enum.NormalId.Top -- фонтаном вверх-назад: видно из-за спины
	e.Acceleration = Vector3.new(0, -45, 0)
	e.Rate = 0
	e.Parent = att
	return e
end

local boostSeen: { [Player]: number } = {}

-- своя плашка над колонкой бонусов: «ДРИФТ ●●○» цветом уровня
local hud = Instance.new("ScreenGui")
hud.Name = "DriftHud"
hud.ResetOnSpawn = false
hud.Parent = player:WaitForChild("PlayerGui")
local pill = Instance.new("TextLabel")
pill.AnchorPoint = Vector2.new(0, 0.5)
pill.Position = UDim2.new(0, 16, 0.4, -96)
pill.Size = UDim2.fromOffset(0, 28)
pill.AutomaticSize = Enum.AutomaticSize.X
pill.Font = Enum.Font.FredokaOne
pill.TextSize = 18
pill.TextColor3 = Color3.new(1, 1, 1)
pill.TextStrokeTransparency = 0.4
pill.BackgroundTransparency = 0.1
pill.Visible = false
pill.Parent = hud
Instance.new("UICorner", pill).CornerRadius = UDim.new(0.4, 0)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.Parent = pill

local function updatePill()
	local tier = player:GetAttribute(Attributes.DriftTier)
	pill.Visible = typeof(tier) == "number"
	if typeof(tier) ~= "number" then
		return
	end
	local dots = string.rep("●", tier) .. string.rep("○", #D.Tiers - tier)
	pill.Text = "ДРИФТ " .. dots
	pill.BackgroundColor3 = if tier > 0 then D.Tiers[tier].color else Color3.fromRGB(40, 40, 50)
end
player:GetAttributeChangedSignal(Attributes.DriftTier):Connect(updatePill)
updatePill()

RunService.Heartbeat:Connect(function()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if not character then
			continue
		end
		local tier = p:GetAttribute(Attributes.DriftTier)
		local boost = p:GetAttribute(Attributes.DriftBoostUntil)
		local newBoost = typeof(boost) == "number" and boost ~= boostSeen[p]
		if not (typeof(tier) == "number" and tier > 0) and not newBoost then
			local e = character:FindFirstChild(EMITTER, true)
			if e and e:IsA("ParticleEmitter") then
				e.Rate = 0
			end
			continue
		end
		local e = emitterFor(character)
		if not e then
			continue
		end
		if typeof(tier) == "number" and tier > 0 then
			e.Color = ColorSequence.new(D.Tiers[tier].color)
			e.Rate = 60 + 40 * tier
		else
			e.Rate = 0
		end
		if newBoost then
			boostSeen[p] = boost :: number
			e:Emit(80)
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	boostSeen[p] = nil
end)
