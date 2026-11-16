--!strict
-- Вертикальная петля: влетел в зону LoopEntry на скорости >= LoopMinSpeed — сервер закрепляет велосипедиста,
-- рассылает всем клиентам «поехал по петле» (они плавно ведут его по формуле Shared/LoopPath),
-- через LoopDuration ставит на выходе и отпускает со скоростью LoopExitSpeed.
-- Медленнее — зона не срабатывает, игрок проезжает под кольцом по обычной дороге.
-- Работает на велоэтапе (между первым и вторым рубежом).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local LoopPath = require(ReplicatedStorage.Shared.LoopPath)

local B = Config.Bike

local LoopRideService = {}

local RaceManager: any
local ProgressTracker: any
local ShootingService: any

local rideRemote: RemoteEvent
local riding: { [Player]: boolean } = {}
local cooldownUntil: { [Player]: number } = {}

local function log(fmt: string, ...: any)
	print("[LoopRideService] " .. string.format(fmt, ...))
end

local function isInside(zone: BasePart, position: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function onBikeStage(player: Player): boolean
	if not RaceManager.isParticipant(player) or not ProgressTracker.isTracked(player) then
		return false
	end
	if ShootingService.isShooting(player) then
		return false
	end
	return ShootingService.getCompletedStages(player) == 1
end

local function finish(player: Player, character: Model, origin: CFrame)
	riding[player] = nil
	player:SetAttribute(Attributes.LoopRiding, nil)
	cooldownUntil[player] = os.clock() + B.LoopCooldown
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or player.Character ~= character then
		return
	end
	local exit = LoopPath.rider(origin, 2 * math.pi)
	character:PivotTo(exit)
	root.Anchored = false
	root.AssemblyLinearVelocity = exit.LookVector * B.LoopExitSpeed
end

local function start(player: Player, character: Model, root: BasePart, zone: BasePart)
	riding[player] = true
	player:SetAttribute(Attributes.LoopRiding, true)
	local surfaceY = (zone:GetAttribute("SurfaceY") :: number?) or 0.05
	local flat = Vector3.new(zone.CFrame.LookVector.X, 0, zone.CFrame.LookVector.Z).Unit
	local origin = CFrame.lookAt(Vector3.new(zone.Position.X, surfaceY, zone.Position.Z), Vector3.new(zone.Position.X, surfaceY, zone.Position.Z) + flat)
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	character:PivotTo(LoopPath.rider(origin, 0))
	rideRemote:FireAllClients(player.UserId, workspace:GetServerTimeNow(), B.LoopDuration, origin)
	log("%s rides the loop", player.Name)
	task.delay(B.LoopDuration, function()
		if riding[player] then
			finish(player, character, origin)
		end
	end)
end

local function step()
	if RaceManager.getState() ~= "Racing" then
		return
	end
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if riding[player] or now < (cooldownUntil[player] or 0) or not onBikeStage(player) then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		local flatSpeed = (velocity * Vector3.new(1, 0, 1)).Magnitude
		if flatSpeed < B.LoopMinSpeed then
			continue
		end
		for _, zone in CollectionService:GetTagged(B.LoopEntryTag) do
			if zone:IsA("BasePart") and isInside(zone, root.Position) and velocity:Dot(zone.CFrame.LookVector) > 0 then
				start(player, character, root, zone)
				break
			end
		end
	end
end

function LoopRideService.isRiding(player: Player): boolean
	return riding[player] == true
end

function LoopRideService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	rideRemote = Remotes.get(Remotes.Names.LoopRide)
end

function LoopRideService.start()
	Players.PlayerRemoving:Connect(function(player)
		riding[player] = nil
		cooldownUntil[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return LoopRideService
