--!strict
-- Вертикальная петля у клиента: сервер закрепил велосипедиста и прислал «поехал по петле» —
-- плавно ведём его корень по формуле Shared/LoopPath (у всех игроков одинаково).
-- Сервер потом сам ставит на выходе, так что к концу клиент и сервер совпадают.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local LoopPath = require(Shared:WaitForChild("LoopPath"))

local player = Players.LocalPlayer

type Ride = { startedAt: number, duration: number, origin: CFrame }
local rides: { [number]: Ride } = {}

-- Свой персонаж: на время петли гуманоид в PlatformStand и без «падения» — иначе он решит,
-- что падает вверх ногами, и рассыплется на выходе.
local function prepareOwn(on: boolean)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not on)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not on)
	humanoid.PlatformStand = on
	if not on then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

Remotes.get(Remotes.Names.LoopRide).OnClientEvent:Connect(function(userId: number, startedAt: number, duration: number, origin: CFrame)
	rides[userId] = { startedAt = startedAt, duration = duration, origin = origin }
	if userId == player.UserId then
		prepareOwn(true)
	end
end)

-- Конец поездки: ставим на выходе; свой персонаж снова в обычном режиме и со скоростью вперёд.
local function finishRide(userId: number, character: Model, ride: Ride)
	local exit = LoopPath.rider(ride.origin, 2 * math.pi)
	character:PivotTo(exit)
	if userId == player.UserId then
		prepareOwn(false)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not root.Anchored then
			root.AssemblyLinearVelocity = exit.LookVector * Config.Bike.LoopExitSpeed
		end
	end
end

-- PreSimulation: идёт и без фокуса окна, поза готова до шага физики
RunService.PreSimulation:Connect(function()
	local now = workspace:GetServerTimeNow()
	for userId, ride in rides do
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local t = now - ride.startedAt
		if not character then
			rides[userId] = nil
		elseif t >= ride.duration then
			finishRide(userId, character, ride)
			rides[userId] = nil
		else
			character:PivotTo(LoopPath.rider(ride.origin, 2 * math.pi * math.max(t, 0) / ride.duration))
		end
	end
end)
