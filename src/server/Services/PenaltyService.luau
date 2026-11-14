--!strict
-- Штрафное время: каждый промах сразу прибавляет Config.Penalty.SecondsPerMiss,
-- попадание в золотую мишень — вычитает Config.Reward.GoldenBonusSeconds
-- к индивидуальному времени игрока. Итоговое время = время до финишной линии + штраф.
-- Накопленный штраф — в атрибуте PenaltyTime на игроке: его видят все клиенты
-- (всплывающее «+3 с» над головой, таймер, таблица позиций, табло).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local P = Config.Penalty

local PenaltyService = {}

local ShootingService: any -- задаётся в init

local seconds: { [Player]: number } = {}

local function publish(player: Player)
	player:SetAttribute(Attributes.PenaltyTime, seconds[player])
end

local function onShotMissed(player: Player)
	local current = seconds[player]
	if not current then
		return -- не участник гонки
	end
	seconds[player] = current + P.SecondsPerMiss
	publish(player)
	print(string.format("[PenaltyService] %s +%ds (total %ds)", player.Name, P.SecondsPerMiss, seconds[player]))
end

-- Золотая мишень: бонус — время уменьшается (штраф может уйти в минус).
local function onGoldenHit(player: Player)
	local current = seconds[player]
	if not current then
		return
	end
	seconds[player] = current - Config.Reward.GoldenBonusSeconds
	publish(player)
	print(string.format("[PenaltyService] %s golden -%ds (total %ds)", player.Name, Config.Reward.GoldenBonusSeconds, seconds[player]))
end

function PenaltyService.beginRace(players: { Player })
	PenaltyService.endRace()
	for _, player in players do
		seconds[player] = 0
		publish(player)
	end
end

function PenaltyService.endRace()
	for player in seconds do
		player:SetAttribute(Attributes.PenaltyTime, nil)
	end
	table.clear(seconds)
end

-- Накопленное штрафное время игрока, с.
function PenaltyService.getSeconds(player: Player): number
	return seconds[player] or 0
end

function PenaltyService.init(services: { [string]: any })
	ShootingService = services.ShootingService
end

function PenaltyService.start()
	ShootingService.ShotMissed:Connect(onShotMissed)
	ShootingService.GoldenHit:Connect(onGoldenHit)
	Players.PlayerRemoving:Connect(function(player)
		seconds[player] = nil
	end)
end

return PenaltyService
