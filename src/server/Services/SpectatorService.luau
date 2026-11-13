--!strict
-- Режим зрителя, серверная часть: камеру двигает клиент, а сервер переносит
-- ReplicationFocus зрителя на гонщика — иначе при StreamingEnabled далёкий персонаж
-- и мир вокруг него у зрителя не загрузятся.
-- Зрителем может быть только тот, кто сейчас не на трассе (финишировал или не участвует).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SpectatorService = {}

local RaceManager: any
local ProgressTracker: any

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function onSpectateFocus(player: Player, targetUserId: unknown)
	if typeof(targetUserId) ~= "number" then
		return
	end
	local target = if targetUserId ~= 0 then Players:GetPlayerByUserId(targetUserId) else nil
	local allowed = RaceManager.getState() == "Racing"
		and not ProgressTracker.isTracked(player)
		and target ~= nil
		and target ~= player
		and ProgressTracker.isTracked(target)
	player.ReplicationFocus = if allowed and target then getRoot(target) else nil
end

-- Конец гонки: всем вернуть фокус на своего персонажа.
function SpectatorService.reset()
	for _, player in Players:GetPlayers() do
		player.ReplicationFocus = nil
	end
end

function SpectatorService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
end

function SpectatorService.start()
	Remotes.get(Remotes.Names.SpectateFocus).OnServerEvent:Connect(onSpectateFocus)
end

return SpectatorService
