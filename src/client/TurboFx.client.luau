--!strict
-- Турбо после чистой стрельбы (5/5) — только картинка, скорость даёт сервер:
--  * у себя: надпись «🔥 ТУРБО 5.2»;
--  * у всех, кто в турбо (видно всем): огненный шлейф за персонажем.
-- Данные — атрибут TurboUntil (server time) на игроке.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attributes = require(Shared:WaitForChild("Attributes"))

local player = Players.LocalPlayer

local function turboLeft(p: Player): number
	local v = p:GetAttribute(Attributes.TurboUntil)
	return if typeof(v) == "number" then v - workspace:GetServerTimeNow() else 0
end

---------------------------------------------------------------- надпись

local gui = Instance.new("ScreenGui")
gui.Name = "TurboHud"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 96)
label.Size = UDim2.fromOffset(220, 36)
label.BackgroundColor3 = Color3.fromRGB(255, 120, 30)
label.BackgroundTransparency = 0.1
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeTransparency = 0.4
label.Parent = gui
Instance.new("UICorner", label).CornerRadius = UDim.new(0.4, 0)

---------------------------------------------------------------- шлейф (у всех, кто в турбо)

local TRAIL_NAME = "TurboTrail"

local function trailFor(p: Player): Trail?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local existing = root:FindFirstChild(TRAIL_NAME)
	if existing and existing:IsA("Trail") then
		return existing
	end
	local a0 = Instance.new("Attachment")
	a0.Name = TRAIL_NAME .. "Top"
	a0.Position = Vector3.new(0, 1.2, 0.6)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = TRAIL_NAME .. "Bottom"
	a1.Position = Vector3.new(0, -1.6, 0.6)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 80, 20))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = root
	return trail
end

---------------------------------------------------------------- каждый кадр
-- (обзор шире на скорости — SpeedFx, в турбо он расширяется сам)

RunService.RenderStepped:Connect(function()
	-- шлейфы
	for _, p in Players:GetPlayers() do
		local active = turboLeft(p) > 0
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local trail = if active then trailFor(p) else (root and root:FindFirstChild(TRAIL_NAME) :: Trail?)
		if trail then
			trail.Enabled = active
		end
	end

	-- своё турбо: надпись
	local left = turboLeft(player)
	gui.Enabled = left > 0
	if left > 0 then
		label.Text = string.format("🔥 ТУРБО %.1f", left)
	end
end)
