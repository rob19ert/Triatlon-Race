--!strict
-- Маятники и мельницы: сервер ловит попадания по той же формуле, по которой клиент
-- рисует движение (Shared/HazardMotion), и сбивает игрока: отбрасывает и роняет на KnockdownTime.
-- Сами детали на сервере не двигаются (стоят в позе покоя) — анимирует клиент.
-- Сбивает только участников на трассе, не во время стрельбы.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HazardMotion = require(ReplicatedStorage.Shared.HazardMotion)
local Knockback = require(script.Parent.Parent.Lib.Knockback)

local H = Config.Hazards
local VELOCITY_DT = 1 / 30 -- шаг для оценки скорости детали (направление удара)

local HazardService = {}

-- задаются в init
local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local knockedRemote: RemoteEvent

local hazards: { HazardMotion.Hazard } = {}
local immuneUntil: { [Player]: number } = {}

local function log(fmt: string, ...: any)
	print("[HazardService] " .. string.format(fmt, ...))
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function insideBox(cf: CFrame, size: Vector3, point: Vector3, pad: number): boolean
	local p = cf:PointToObjectSpace(point)
	local half = size / 2
	return math.abs(p.X) <= half.X + pad and math.abs(p.Y) <= half.Y + pad and math.abs(p.Z) <= half.Z + pad
end

-- Первое попадание по игроку: направление отлёта (или nil).
local function findHit(position: Vector3, t: number): Vector3?
	for _, h in hazards do
		local angle = HazardMotion.angleAt(h, t)
		for _, mp in h.parts do
			if not mp.hits then
				continue
			end
			local cf = HazardMotion.partCFrame(h, mp, angle)
			if insideBox(cf, mp.part.Size, position, H.HitPadding) then
				-- по ходу движения детали; если она почти стоит — от её центра
				local nextCf = HazardMotion.partCFrame(h, mp, HazardMotion.angleAt(h, t + VELOCITY_DT))
				local move = (nextCf.Position - cf.Position) * Vector3.new(1, 0, 1)
				if move.Magnitude > 0.05 then
					return move
				end
				return (position - cf.Position) * Vector3.new(1, 0, 1)
			end
		end
	end
	return nil
end

local function step()
	if RaceManager.getState() ~= "Racing" or #hazards == 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local t = now - H.HitTimeLag
	for _, player in Players:GetPlayers() do
		if not RaceManager.isParticipant(player) or not ProgressTracker.isTracked(player) then
			continue
		end
		if ShootingService.isShooting(player) or now < (immuneUntil[player] or 0) then
			continue
		end
		local root = getRoot(player)
		if not root then
			continue
		end
		local direction = findHit(root.Position, t)
		if direction then
			immuneUntil[player] = now + H.HitImmunity
			Knockback.apply(root, direction, H.KnockSpeed, H.KnockUpSpeed, H.KnockImpulseTime)
			knockedRemote:FireClient(player, H.KnockdownTime)
			log("%s knocked down", player.Name)
		end
	end
end

local function loadTagged(tag: string, kind: HazardMotion.Kind)
	for _, model in CollectionService:GetTagged(tag) do
		if model:IsA("Model") then
			local h = HazardMotion.load(model, kind)
			if h then
				table.insert(hazards, h)
			end
		end
	end
end

function HazardService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	knockedRemote = Remotes.get(Remotes.Names.KnockedDown)
end

function HazardService.start()
	loadTagged(H.PendulumTag, "Pendulum")
	loadTagged(H.WindmillTag, "Windmill")
	log("%d hazard(s) loaded", #hazards)

	Players.PlayerRemoving:Connect(function(player)
		immuneUntil[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return HazardService
