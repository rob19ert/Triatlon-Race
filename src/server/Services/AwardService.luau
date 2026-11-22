--!strict
-- Значки Roblox (BadgeService): за вход, первый финиш, чистую стрельбу, победу и быстрый финиш.
-- ID — в Config.Badges (0 — значок ещё не создан, пропускаем). Повторно не выдаём (кэш на игрока).

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local B = Config.Badges

local AwardService = {}

local owned: { [Player]: { [number]: boolean } } = {}

local function log(fmt: string, ...: any)
	print("[AwardService] " .. string.format(fmt, ...))
end

-- Выдать значок key (имя поля в Config.Badges). Не блокирует вызывающего.
function AwardService.award(player: Player, key: string)
	local id = (B :: any)[key]
	if typeof(id) ~= "number" or id <= 0 then
		return
	end
	owned[player] = owned[player] or {}
	if owned[player][id] then
		return
	end
	owned[player][id] = true
	task.spawn(function()
		local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
		if ok and has then
			return
		end
		local awarded, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
		if awarded then
			log("%s earned %s", player.Name, key)
		else
			owned[player][id] = nil -- попробуем в следующий раз
			warn("[AwardService] award failed", key, err)
		end
	end)
end

-- Игрок финишировал: place — место, seconds — итоговое время, racers — всего участников (с ботами).
function AwardService.finished(player: Player, place: number, seconds: number, hits: number, shots: number, racers: number)
	if RunService:IsStudio() then
		-- в Studio финиш бывает «читерский» (клавиша G) — значки за гонку не выдаём, только пишем в лог
		log("(Studio) %s finish badges skipped: place %d, %.1fs, %d/%d", player.Name, place, seconds, hits, shots)
		return
	end
	AwardService.award(player, "FirstFinish")
	if shots > 0 and hits == shots then
		AwardService.award(player, "CleanShooter")
	end
	if place == 1 and racers >= 2 then
		AwardService.award(player, "Champion")
	end
	if seconds <= B.SpeedsterSeconds then
		AwardService.award(player, "Speedster")
	end
end

function AwardService.start()
	local function joined(player: Player)
		AwardService.award(player, "Welcome")
	end
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerAdded:Connect(joined)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

return AwardService
