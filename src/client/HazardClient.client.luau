--!strict
-- Маятники и мельницы: локально двигаем детали по формуле от серверного времени
-- (Shared/HazardMotion), поэтому у всех игроков они синхронны и плавные.
-- Плюс падение после удара: сервер шлёт KnockedDown — персонаж валится и встаёт.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local HazardMotion = require(Shared:WaitForChild("HazardMotion"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local H = Config.Hazards
local player = Players.LocalPlayer

---------------------------------------------------------------- движение

local hazards: { [Model]: HazardMotion.Hazard } = {}

local function add(model: Instance, kind: HazardMotion.Kind)
	if not model:IsA("Model") or hazards[model] then
		return
	end
	-- модели Persistent, но на всякий случай ждём ось
	task.spawn(function()
		if not model:WaitForChild(H.PivotName, 10) then
			return
		end
		local h = HazardMotion.load(model, kind)
		if h then
			hazards[model] = h
		end
	end)
end

local function watch(tag: string, kind: HazardMotion.Kind)
	for _, model in CollectionService:GetTagged(tag) do
		add(model, kind)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		add(model, kind)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(model)
		hazards[model :: Model] = nil
	end)
end

watch(H.PendulumTag, "Pendulum")
watch(H.WindmillTag, "Windmill")
watch(H.TrainTag, "Shuttle")
watch(H.GateTag, "Gate")

-- мигающие фонари переезда: пока закрыто — попеременно красные
local LIGHT_ON = Color3.fromRGB(255, 40, 40)
local LIGHT_OFF = Color3.fromRGB(70, 20, 20)
local function updateLights(t: number)
	local blink = math.floor(t * 3) % 2 == 0
	for _, light in CollectionService:GetTagged(H.RailLightTag) do
		if light:IsA("BasePart") then
			local closed = HazardMotion.isClosed(
				(light:GetAttribute("Period") :: number?) or 18,
				(light:GetAttribute("ClosedFrom") :: number?) or 0,
				(light:GetAttribute("ClosedTo") :: number?) or 0,
				t
			)
			local on = closed and (blink == ((light:GetAttribute("Side") :: number?) == 1))
			light.Color = if on then LIGHT_ON else LIGHT_OFF
			light.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- PreSimulation: детали на месте до шага физики (Heartbeat идёт и без фокуса окна)
RunService.PreSimulation:Connect(function()
	local t = workspace:GetServerTimeNow()
	updateLights(t)
	for _, h in hazards do
		local angle = HazardMotion.angleAt(h, t)
		for _, mp in h.parts do
			mp.part.CFrame = HazardMotion.partCFrame(h, mp, angle)
		end
	end
end)

---------------------------------------------------------------- падение

local knockToken = 0

Remotes.get(Remotes.Names.KnockedDown).OnClientEvent:Connect(function(duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	knockToken += 1
	local token = knockToken
	Fx.play("Bonk")
	Fx.burst("Dust", root.Position)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- без управления, падает как тело
	local spin = H.TumbleSpin
	root.AssemblyAngularVelocity = Vector3.new((math.random() - 0.5) * 2 * spin, 0, (math.random() - 0.5) * 2 * spin)
	task.delay(duration, function()
		if token == knockToken and humanoid.Parent and humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end)
