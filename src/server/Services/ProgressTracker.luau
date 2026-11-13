--!strict
-- Прогресс игроков по трассе. Пока только финиш:
-- каждый кадр проверяем, что HumanoidRootPart отслеживаемого игрока внутри невидимой FinishZone.
-- Проверка идёт на сервере по позиции, а не по Touched — так надёжнее.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ProgressTracker = {}

local finishedEvent = Instance.new("BindableEvent")
-- (player: Player) — игрок пересёк финиш. Срабатывает один раз, потом игрок снимается с трекинга.
ProgressTracker.Finished = finishedEvent.Event

local tracked: { [Player]: boolean } = {}
local finishZone: BasePart

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

function ProgressTracker.beginTracking(players: { Player })
	table.clear(tracked)
	for _, player in players do
		tracked[player] = true
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

	RunService.Heartbeat:Connect(function()
		for player in tracked do
			local root = getRoot(player)
			if root and isInside(finishZone, root.Position) then
				tracked[player] = nil
				finishedEvent:Fire(player)
			end
		end
	end)
end

return ProgressTracker
