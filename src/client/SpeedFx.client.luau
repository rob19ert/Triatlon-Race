--!strict
-- Ощущение скорости — только картинка (скорость считает сервер):
--  * у себя: обзор шире по скорости (в турбо и на ускорителе — заметно), полосы ветра по краям экрана;
--  * у всех велосипедистов: пыль из-под заднего колеса (на льду — снег).
-- Обзор трогаем только при обычной камере (прицел и подиум управляют им сами).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local S = Config.SpeedFx
local player = Players.LocalPlayer

local function ramp(v: number, from: number, to: number): number
	return math.clamp((v - from) / (to - from), 0, 1)
end

local function flatSpeed(character: Model?): number
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end
	local v = root.AssemblyLinearVelocity
	return Vector2.new(v.X, v.Z).Magnitude
end

---------------------------------------------------------------- обзор

local baseFov: number? = nil
local fovBoost = 0

local function updateFov(speed: number, dt: number)
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Custom then
		baseFov = nil
		fovBoost = 0
		return
	end
	local target = S.FovMax * ramp(speed, S.FovFrom, S.FovTo)
	fovBoost += (target - fovBoost) * math.clamp(dt * S.FovLerp, 0, 1)
	if not baseFov then
		if target == 0 then
			return -- в покое FOV не трогаем
		end
		baseFov = camera.FieldOfView
	end
	if target == 0 and fovBoost < 0.05 then
		camera.FieldOfView = baseFov :: number
		baseFov = nil
		fovBoost = 0
		return
	end
	camera.FieldOfView = (baseFov :: number) + fovBoost
end

---------------------------------------------------------------- полосы ветра

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedLines"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = -1 -- под остальным HUD
gui.Parent = player:WaitForChild("PlayerGui")

type Line = { frame: Frame, dir: Vector2, r: number, speed: number, age: number, life: number }
local lines: { Line } = {}
local pool: { Frame } = {}
local spawnAcc = 0
local rng = Random.new()

local function takeFrame(): Frame
	local f = table.remove(pool)
	if f then
		f.Visible = true
		return f
	end
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Parent = gui
	return frame
end

local function spawnLine()
	local angle = rng:NextNumber(0, 2 * math.pi)
	local frame = takeFrame()
	frame.Size = UDim2.fromOffset(rng:NextInteger(90, 220), 3)
	frame.Rotation = math.deg(angle)
	table.insert(lines, {
		frame = frame,
		dir = Vector2.new(math.cos(angle), math.sin(angle)),
		r = rng:NextNumber(0.45, 0.75), -- доля от полудиагонали: только края, центр не трогаем
		speed = rng:NextNumber(1.2, 1.8),
		age = 0,
		life = rng:NextNumber(0.3, 0.45),
	})
end

local function updateLines(speed: number, dt: number)
	local k = ramp(speed, S.LinesFrom, S.LinesTo)
	if k > 0 then
		spawnAcc += S.LinesPerSec * k * dt
		while spawnAcc >= 1 do
			spawnAcc -= 1
			spawnLine()
		end
	else
		spawnAcc = 0
	end
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local center = size / 2
	local half = center.Magnitude
	for i = #lines, 1, -1 do
		local line = lines[i]
		line.age += dt
		line.r += line.speed * dt
		if line.age >= line.life then
			line.frame.Visible = false
			table.insert(pool, line.frame)
			table.remove(lines, i)
			continue
		end
		local pos = center + line.dir * line.r * half
		line.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
		local t = line.age / line.life
		line.frame.BackgroundTransparency = 0.2 + 0.8 * math.abs(t * 2 - 1) -- появилась — исчезла
	end
end

---------------------------------------------------------------- пыль у всех велосипедистов

local DUST = "SpeedDust"

local function dustFor(character: Model): ParticleEmitter?
	local bike = character:FindFirstChild(Config.Bike.ModelName)
	local root = bike and bike:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local existing = root:FindFirstChild(DUST, true)
	if existing and existing:IsA("ParticleEmitter") then
		return existing
	end
	local att = Instance.new("Attachment")
	att.Name = DUST .. "At"
	att.Position = Vector3.new(0, 0.3, 2.1) -- за задним колесом, у земли
	att.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Name = DUST
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(40, 20)
	e.EmissionDirection = Enum.NormalId.Back
	e.Acceleration = Vector3.new(0, 4, 0)
	e.Drag = 2
	e.LightInfluence = 0.6
	e.Rate = 0
	e.Parent = att
	return e
end

local function updateDust()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if not character then
			continue
		end
		local riding = p:GetAttribute(Attributes.Riding) == true
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local e = if riding then dustFor(character) else nil
		if not e then
			continue
		end
		local speed = flatSpeed(character)
		local grounded = humanoid and humanoid.FloorMaterial ~= Enum.Material.Air
		e.Rate = if grounded then math.max(0, speed - S.DustFrom) * S.DustPerStud else 0
		local onIce = typeof(p:GetAttribute(Attributes.IceGrip)) == "number"
		e.Color = ColorSequence.new(if onIce then S.SnowColor else S.DustColor)
	end
end

---------------------------------------------------------------- каждый кадр

RunService.RenderStepped:Connect(function(dt)
	local speed = flatSpeed(player.Character)
	updateFov(speed, dt)
	updateLines(speed, dt)
	updateDust()
end)
