--!strict
-- Аналитика Roblox (дашборд Creator Hub → Analytics). Только сервер, только наблюдение:
-- на игру не влияет, любая ошибка AnalyticsService глотается.
--  * воронка Race — своя сессия на каждую гонку: старт → 1-я стрельба → велосипед → 2-я стрельба → финиш;
--  * воронка Onboarding (Roblox считает каждый шаг один раз на игрока): зашёл → 1-я гонка → 1-й финиш;
--  * события: RaceFinished, RaceDNF, RangeHits, BoxTaken, BikeSelected, BikePurchased.
-- Удержание (D1/D7) и длину сессии Roblox считает сам.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local A = Config.Analytics
local FIELD1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local FIELD2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name
local FIELD3 = Enum.AnalyticsCustomFieldKeys.CustomField03.Name

local AnalyticsTracker = {}

local ShootingService: any
local ModifierService: any

type RaceSession = { id: string, step: number }
local sessions: { [Player]: RaceSession } = {}
local playersInRace = 0

local debugLog = RunService:IsStudio() and A.StudioLog

local function log(fmt: string, ...: any)
	if debugLog then
		print("[Analytics] " .. string.format(fmt, ...))
	end
end

local function fields(a: any?, b: any?, c: any?): { [string]: string }?
	if a == nil and b == nil and c == nil then
		return nil
	end
	local t = {}
	if a ~= nil then
		t[FIELD1] = tostring(a)
	end
	if b ~= nil then
		t[FIELD2] = tostring(b)
	end
	if c ~= nil then
		t[FIELD3] = tostring(c)
	end
	return t
end

local function safe(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		log("%s failed: %s", name, tostring(err))
	end
end

local function onboarding(player: Player, step: number)
	local name = A.OnboardingSteps[step]
	log("%s onboarding %d %s", player.Name, step, name)
	safe("onboarding", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- Шаги воронки гонки идут только вперёд: повтор или откат не пишем.
local function raceStep(player: Player, step: number)
	local s = sessions[player]
	if not s or step <= s.step then
		return
	end
	s.step = step
	local name = A.RaceSteps[step]
	log("%s race step %d %s", player.Name, step, name)
	safe("funnel", function()
		AnalyticsService:LogFunnelStepEvent(player, A.RaceFunnel, s.id, step, name)
	end)
end

local function custom(player: Player, event: string, value: number?, f: { [string]: string }?)
	log("%s %s = %s %s", player.Name, event, tostring(value), if f then HttpService:JSONEncode(f) else "")
	safe(event, function()
		AnalyticsService:LogCustomEvent(player, event, value or 1, f)
	end)
end

local function modifier(): string
	return ModifierService.getActive() or "None"
end

---------------------------------------------------------------- вызовы из сервисов

function AnalyticsTracker.raceStarted(list: { Player })
	table.clear(sessions)
	playersInRace = #list
	for _, player in list do
		sessions[player] = { id = HttpService:GenerateGUID(false), step = 0 }
		raceStep(player, 1)
		onboarding(player, 2)
	end
end

function AnalyticsTracker.bikeMounted(player: Player)
	raceStep(player, 3)
end

function AnalyticsTracker.finished(player: Player, place: number, seconds: number)
	raceStep(player, 5)
	onboarding(player, 3)
	custom(player, "RaceFinished", math.floor(seconds * 10 + 0.5) / 10, fields(place, modifier(), playersInRace))
end

function AnalyticsTracker.dnf(player: Player)
	local s = sessions[player]
	custom(player, "RaceDNF", if s then s.step else 0, fields(modifier(), playersInRace))
end

function AnalyticsTracker.boxTaken(player: Player, effect: string, rolled: string?)
	custom(player, "BoxTaken", 1, fields(effect, rolled))
end

function AnalyticsTracker.bikeSelected(player: Player, id: string)
	custom(player, "BikeSelected", 1, fields(id))
end

function AnalyticsTracker.bikePurchased(player: Player, id: string, robux: number)
	custom(player, "BikePurchased", robux, fields(id))
end

---------------------------------------------------------------- жизненный цикл

function AnalyticsTracker.init(services: { [string]: any })
	ShootingService = services.ShootingService
	ModifierService = services.ModifierService
end

function AnalyticsTracker.start()
	-- стрельбы: 1-я → шаг 2, 2-я → шаг 4; плюс попадания на каждом рубеже
	ShootingService.StageFinished:Connect(function(player: Player, order: number, hits: number, misses: number)
		raceStep(player, if order == 1 then 2 else 4)
		custom(player, "RangeHits", hits, fields(order, modifier()))
	end)
	local function joined(player: Player)
		onboarding(player, 1)
	end
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerAdded:Connect(joined)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return AnalyticsTracker
