--!strict
-- Лужи и кольца у клиента (только картинка; что считается — решает MudRingService):
--  * кольца крутятся, при пролёте (RingPassed) вспыхивают у всех; у себя — вспышка экрана;
--  * InMud у себя — кляксы грязи на экране (сходят через SplatSeconds после выезда);
--  * InMud у любого гонщика — комья грязи из-под колёс.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local M = Config.Mud
local R = Config.Rings
local player = Players.LocalPlayer
local MUD = Color3.fromRGB(110, 72, 40)

local gui = Instance.new("ScreenGui")
gui.Name = "MudRingFx"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2
gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- кольца

-- Сегменты кольца лежат рядом с центром (тот же родитель), крутим их вокруг оси.
type Ring = { center: BasePart, parts: { [BasePart]: CFrame } }
local rings: { [BasePart]: Ring } = {}

local function addRing(center: Instance)
	if not center:IsA("BasePart") or rings[center] or not center.Parent then
		return
	end
	local parts = {}
	for _, part in center.Parent:GetDescendants() do
		if part:IsA("BasePart") and part ~= center then
			parts[part] = center.CFrame:ToObjectSpace(part.CFrame)
		end
	end
	rings[center] = { center = center, parts = parts }
end

for _, center in CollectionService:GetTagged(R.Tag) do
	addRing(center)
end
CollectionService:GetInstanceAddedSignal(R.Tag):Connect(addRing)
CollectionService:GetInstanceRemovedSignal(R.Tag):Connect(function(center)
	rings[center :: BasePart] = nil
end)

local angle = 0
RunService.RenderStepped:Connect(function(dt)
	angle += R.SpinSpeed * dt
	local spin = CFrame.Angles(0, 0, angle)
	for _, ring in rings do
		local base = ring.center.CFrame * spin
		for part, offset in ring.parts do
			part.CFrame = base * offset
		end
	end
end)

local flash = Instance.new("Frame")
flash.Name = "RingFlash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = R.Color
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = gui

local boostText = Instance.new("TextLabel")
boostText.Name = "RingText"
boostText.AnchorPoint = Vector2.new(0.5, 0.5)
boostText.Position = UDim2.fromScale(0.5, 0.3)
boostText.Size = UDim2.fromOffset(320, 60)
boostText.BackgroundTransparency = 1
boostText.Font = Enum.Font.GothamBlack
boostText.TextSize = 40
boostText.TextColor3 = R.Color
boostText.TextStrokeTransparency = 0.2
boostText.TextTransparency = 1
boostText.TextStrokeColor3 = Color3.fromRGB(60, 35, 0)
boostText.Text = "⚡ КОЛЬЦО!"
boostText.Parent = gui

Remotes.get(Remotes.Names.RingPassed).OnClientEvent:Connect(function(center: BasePart, userId: number)
	local ring = rings[center]
	if ring then
		for part in ring.parts do
			local color = part.Color
			part.Color = R.FlashColor
			TweenService:Create(part, TweenInfo.new(0.5), { Color = color }):Play()
		end
	end
	if userId == player.UserId then
		flash.BackgroundTransparency = 0.55
		TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		boostText.TextTransparency = 0
		boostText.TextStrokeTransparency = 0.2
		boostText.TextSize = 54
		TweenService:Create(boostText, TweenInfo.new(0.25, Enum.EasingStyle.Back), { TextSize = 40 }):Play()
		TweenService:Create(boostText, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end
end)

---------------------------------------------------------------- грязь на экране

local splat = Instance.new("Frame")
splat.Name = "Mud"
splat.Size = UDim2.fromScale(1, 1)
splat.BackgroundTransparency = 1
splat.Parent = gui
local splatGroup = Instance.new("CanvasGroup")
splatGroup.Size = UDim2.fromScale(1, 1)
splatGroup.BackgroundTransparency = 1
splatGroup.GroupTransparency = 1
splatGroup.Parent = splat
local fade: Tween? = nil

-- Клякса: крупный круг и пара мелких брызг рядом.
local function blob(x: number, y: number, size: number)
	local function dot(dx: number, dy: number, s: number)
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.new(x, dx, y, dy)
		d.Size = UDim2.fromOffset(s, s * (0.8 + math.random() * 0.4))
		d.Rotation = math.random(0, 180)
		d.BackgroundColor3 = MUD:Lerp(Color3.new(0, 0, 0), math.random() * 0.25)
		d.BackgroundTransparency = 0.1
		d.Parent = splatGroup
		Instance.new("UICorner", d).CornerRadius = UDim.new(0.5, 0)
	end
	dot(0, 0, size)
	for _ = 1, 3 do
		local a = math.random() * math.pi * 2
		local r = size * (0.55 + math.random() * 0.4)
		dot(math.cos(a) * r, math.sin(a) * r, size * (0.12 + math.random() * 0.18))
	end
end

local function splatOn()
	if fade then
		fade:Cancel()
		fade = nil
	end
	for _, child in splatGroup:GetChildren() do
		child:Destroy()
	end
	for _ = 1, M.SplatBlobs do
		-- по краям экрана, середину (дорогу) почти не закрываем
		local x = if math.random() < 0.5 then math.random() * 0.3 else 0.7 + math.random() * 0.3
		blob(x, 0.1 + math.random() * 0.85, math.random(50, 130))
	end
	splatGroup.GroupTransparency = 0
end

local function splatOff()
	fade = TweenService:Create(splatGroup, TweenInfo.new(M.SplatSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
	;(fade :: Tween):Play()
end

player:GetAttributeChangedSignal(Attributes.InMud):Connect(function()
	if player:GetAttribute(Attributes.InMud) then
		splatOn()
	else
		splatOff()
	end
end)

---------------------------------------------------------------- комья из-под колёс (у всех)

local EMITTER = "MudSpray"

local function spray(other: Player)
	local on = other:GetAttribute(Attributes.InMud) == true
	local character = other.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local holder = root:FindFirstChild(EMITTER) :: Attachment?
	if on and not holder then
		-- у заднего колеса, у земли
		local at = Instance.new("Attachment")
		at.Name = EMITTER
		at.Position = Vector3.new(0, -2.5, 1.6)
		local e = Instance.new("ParticleEmitter")
		e.Name = EMITTER
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(MUD)
		e.LightEmission = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.4, 0.7)
		e.Rate = 60
		e.Speed = NumberRange.new(10, 18)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Acceleration = Vector3.new(0, -60, 0)
		e.EmissionDirection = Enum.NormalId.Back
		e.Parent = at
		at.Parent = root
	elseif not on and holder then
		holder.Name = EMITTER .. "Old"
		local e = holder:FindFirstChildOfClass("ParticleEmitter")
		if e then
			e.Enabled = false
		end
		task.delay(1, function()
			holder:Destroy()
		end)
	end
end

local function watch(other: Player)
	other:GetAttributeChangedSignal(Attributes.InMud):Connect(function()
		spray(other)
	end)
end
for _, other in Players:GetPlayers() do
	watch(other)
end
Players.PlayerAdded:Connect(watch)
