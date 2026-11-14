--!strict
-- Анимация толчка у всех клиентов: толкающий резко выбрасывает руки вперёд
-- (Transform плечевых суставов поверх анимации, без загружаемых анимаций), у цели — облачко пыли.
-- Сервер шлёт PushFx(pusherUserId, targetUserId) после проверки толчка; target 0 — мимо.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local C = Config.Push

-- Сустав с Transform: классический Motor6D или AnimationConstraint (новые аватары Roblox).
type Joint = Motor6D | AnimationConstraint
local function isJoint(x: Instance?): boolean
	return x ~= nil and (x:IsA("Motor6D") or x:IsA("AnimationConstraint"))
end

-- плечи: R15 (RightUpperArm.RightShoulder) или R6 (Torso["Right Shoulder"])
local function shoulders(character: Model): { { motor: Joint, raise: CFrame } }
	local list = {}
	local angle = math.rad(C.AnimArmDeg)
	for _, spec in { { "RightUpperArm", "RightShoulder" }, { "LeftUpperArm", "LeftShoulder" } } do
		local arm = character:FindFirstChild(spec[1])
		local motor = arm and arm:FindFirstChild(spec[2])
		if motor and isJoint(motor) then
			-- R15: рука висит вдоль -Y, поворот вокруг X вперёд
			table.insert(list, { motor = motor :: any, raise = CFrame.Angles(angle, 0, 0) })
		end
	end
	if #list == 0 then
		local torso = character:FindFirstChild("Torso")
		for _, spec in { { "Right Shoulder", 1 }, { "Left Shoulder", -1 } } do
			local motor = torso and torso:FindFirstChild(spec[1] :: string)
			if motor and isJoint(motor) then
				-- R6: ось плеча повёрнута, руку вперёд поднимает поворот вокруг Z
				table.insert(list, { motor = motor :: any, raise = CFrame.Angles(0, 0, (spec[2] :: number) * angle) })
			end
		end
	end
	return list
end

-- Активные толчки: руки поднимаются через Transform сустава поверх анимации
-- (C0 у персонажа менять нельзя). Каждый кадр после аниматора — в RunService.Stepped.
type Active = { list: { { motor: Joint, raise: CFrame } }, startedAt: number }
local active: { [Model]: Active } = {}

-- 0 -> 1 быстро (выброс), держим, плавно назад к 0
local function strength(t: number): number
	local outEnd = C.AnimTime * 0.25
	local holdEnd = C.AnimTime * 0.55
	if t < outEnd then
		return t / outEnd
	elseif t < holdEnd then
		return 1
	elseif t < C.AnimTime then
		return 1 - (t - holdEnd) / (C.AnimTime - holdEnd)
	end
	return 0
end

RunService.Stepped:Connect(function()
	local now = os.clock()
	for character, a in active do
		local t = now - a.startedAt
		if t >= C.AnimTime or not character.Parent then
			active[character] = nil
			continue
		end
		local k = strength(t)
		for _, s in a.list do
			local joint = s.motor :: any
			joint.Transform = joint.Transform * CFrame.new():Lerp(s.raise, k)
		end
	end
end)

local function playArms(character: Model)
	local list = shoulders(character)
	if #list > 0 then
		active[character] = { list = list, startedAt = os.clock() }
	end
end

Remotes.get(Remotes.Names.PushFx).OnClientEvent:Connect(function(pusherUserId: number, targetUserId: number)
	local pusher = Players:GetPlayerByUserId(pusherUserId)
	local character = pusher and pusher.Character
	if character then
		playArms(character)
	end
	-- у самой цели пыль рисует обработчик падения (HazardClient), здесь — для остальных
	local target = if targetUserId ~= 0 and targetUserId ~= Players.LocalPlayer.UserId then Players:GetPlayerByUserId(targetUserId) else nil
	local targetChar = target and target.Character
	local root = targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Fx.burst("Dust", root.Position)
	end
end)
