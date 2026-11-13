--!strict
-- Прогресс игроков по трассе (всё на сервере, по позиции HumanoidRootPart, без Touched):
--  * чекпоинты — начало каждого препятствия (тег Checkpoint, атрибут Order);
--  * падение в зону FallZone или ниже KillY — возврат на последний чекпоинт;
--  * пересёк FinishZone — событие Finished.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ProgressTracker = {}

local finishedEvent = Instance.new("BindableEvent")
-- (player: Player) — игрок пересёк финиш. Срабатывает один раз, потом игрок снимается с трекинга.
ProgressTracker.Finished = finishedEvent.Event

type PlayerProgress = {
	checkpoint: BasePart?, -- nil = ещё не прошёл ни одного, возвращаем на старт
	checkpointOrder: number,
	respawning: boolean, -- уже упал, ждём FallRespawnDelay
}

local tracked: { [Player]: PlayerProgress } = {}
local finishZone: BasePart
local startGrid: BasePart

local function isInside(zone: BasePart, position: Vector3): boolean
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Точка возврата: низ зоны чекпоинта (или стартовой решётки) + RespawnHeight, лицом к финишу (-Z).
local function respawnCFrame(progress: PlayerProgress): CFrame
	local zone = progress.checkpoint or startGrid
	local floor = zone.Position - Vector3.new(0, zone.Size.Y / 2, 0)
	local pos = floor + Vector3.new(0, Config.Track.RespawnHeight, 0)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
end

local function returnToCheckpoint(player: Player, progress: PlayerProgress)
	local character = player.Character
	local root = getRoot(player)
	if not character or not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(respawnCFrame(progress))
end

local function inAnyFallZone(position: Vector3): boolean
	if position.Y < Config.Track.KillY then
		return true
	end
	for _, zone in CollectionService:GetTagged(Config.Track.FallZoneTag) do
		if zone:IsA("BasePart") and isInside(zone, position) then
			return true
		end
	end
	return false
end

local function updateCheckpoint(player: Player, progress: PlayerProgress, position: Vector3)
	for _, zone in CollectionService:GetTagged(Config.Track.CheckpointTag) do
		if zone:IsA("BasePart") then
			local order = zone:GetAttribute("Order")
			-- только вперёд: вернувшись назад, чекпоинт не откатываем
			if typeof(order) == "number" and order > progress.checkpointOrder and isInside(zone, position) then
				progress.checkpoint = zone
				progress.checkpointOrder = order
				print(string.format("[ProgressTracker] %s reached checkpoint %d", player.Name, order))
			end
		end
	end
end

local function step()
	for player, progress in tracked do
		local root = getRoot(player)
		if not root then
			continue
		end
		local position = root.Position

		if isInside(finishZone, position) then
			tracked[player] = nil
			finishedEvent:Fire(player)
			continue
		end

		updateCheckpoint(player, progress, position)

		if not progress.respawning and inAnyFallZone(position) then
			progress.respawning = true
			print(string.format("[ProgressTracker] %s fell -> checkpoint %d", player.Name, progress.checkpointOrder))
			task.delay(Config.Track.FallRespawnDelay, function()
				if tracked[player] == progress then
					returnToCheckpoint(player, progress)
				end
				progress.respawning = false
			end)
		end
	end
end

-- Если персонаж погиб во время гонки — новый появится в лобби; переносим его на чекпоинт.
local function onCharacterAdded(player: Player, character: Model)
	local progress = tracked[player]
	if not progress then
		return
	end
	character:WaitForChild("HumanoidRootPart", 5)
	if tracked[player] == progress then
		returnToCheckpoint(player, progress)
	end
end

function ProgressTracker.beginTracking(players: { Player })
	table.clear(tracked)
	for _, player in players do
		tracked[player] = { checkpoint = nil, checkpointOrder = 0, respawning = false }
	end
end

function ProgressTracker.stopTracking(player: Player)
	tracked[player] = nil
end

function ProgressTracker.reset()
	table.clear(tracked)
end

function ProgressTracker.start()
	local track = workspace:WaitForChild(Config.Track.FolderName)
	finishZone = track:WaitForChild(Config.Track.FinishZoneName) :: BasePart
	startGrid = track:WaitForChild(Config.Track.StartGridName) :: BasePart

	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	RunService.Heartbeat:Connect(step)
end

return ProgressTracker
