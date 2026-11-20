--!strict
-- Толчок: игрок жмёт F / тач-кнопку, сервер ищет ближайшего соперника в конусе впереди
-- и толкает его в сторону от толкающего и чуть вверх.
-- Соперник отлетает и падает на KnockdownTime. Нельзя толкать и быть толкнутым на рубеже
-- после толчка цель TargetImmunity секунд неуязвима (против спама). На финишной прямой — можно.
-- Импульс — общий модуль Lib/Knockback. Боты (BotService) толкаются и толкаемы так же;
-- сами толкают с шансом Bots.PushChance, когда соперник рядом.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local Knockback = require(script.Parent.Parent.Lib.Knockback)
local Protection = require(script.Parent.Parent.Lib.Protection)

local C = Config.Push
local MEGA = Config.Boxes.Defs.MegaPush
local CONE_COS = math.cos(math.rad(C.ConeAngleDeg))

local PushService = {}

-- задаются в init
local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local BotService: any
local noticeRemote: RemoteEvent
local pushFxRemote: RemoteEvent
local knockedRemote: RemoteEvent

local B = Config.Bots
local racers: { [Player]: boolean } = {}
local readyAt: { [Player]: number } = {}
local botReadyAt: { [any]: number } = {}
local immuneUntil: { [any]: number } = {} -- игрок или бот
local nextBotCheck = 0
local rng = Random.new()

local function log(fmt: string, ...: any)
	print("[PushService] " .. string.format(fmt, ...))
end

local function now(): number
	return workspace:GetServerTimeNow()
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

-- Игрок на трассе (не финишировал) и не на рубеже.
local function canPushOrBePushed(player: Player): boolean
	if not racers[player] or not ProgressTracker.isTracked(player) then
		return false
	end
	if ShootingService.isShooting(player) then
		return false
	end
	return true -- на финишной прямой толкаться можно (решено 14.11.2026)
end

local function setReadyAt(player: Player, t: number?)
	readyAt[player] = t
	player:SetAttribute(Attributes.PushReadyAt, t)
end

-- Участник гонки: игрок или бот (BotService). id — UserId или BotId (< 0).
local function idOf(racer: any): number
	return if typeof(racer) == "Instance" then (racer :: Player).UserId else racer.id
end

local function nameOf(racer: any): string
	return if typeof(racer) == "Instance" then (racer :: Player).DisplayName else racer.name
end

-- Ближайший соперник (игрок или бот) впереди или сбоку (конус ±ConeAngleDeg).
local function findTarget(pusher: any, root: BasePart): (any, BasePart?)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		return nil, nil
	end
	look = look.Unit
	local t = now()
	local best: any, bestRoot: BasePart?, bestDist = nil, nil, math.huge
	local function consider(other: any, otherRoot: BasePart?)
		if not otherRoot or other == pusher or t < (immuneUntil[other] or 0) then
			return
		end
		local offset = otherRoot.Position - root.Position
		local dist = offset.Magnitude
		local flat = offset * Vector3.new(1, 0, 1)
		if dist > C.Range or flat.Magnitude < 1e-3 then
			return
		end
		if look:Dot(flat.Unit) >= CONE_COS and dist < bestDist then
			best, bestRoot, bestDist = other, otherRoot, dist
		end
	end
	for other in racers do
		if canPushOrBePushed(other) and not Protection.isGhost(other) then
			consider(other, getRoot(other))
		end
	end
	for _, bot in BotService.getBots() do
		if BotService.isRunning(bot) and not BotService.isKnocked(bot) then
			consider(bot, bot.root)
		end
	end
	return best, bestRoot
end

-- Толчок состоялся: цель отлетает и падает. Возвращает false, если цель закрылась щитом.
local function applyPush(pusher: any, root: BasePart, target: any, targetRoot: BasePart, mega: any?): boolean
	local t = now()
	immuneUntil[target] = t + C.TargetImmunity
	local isPlayer = typeof(target) == "Instance"
	if isPlayer and Protection.absorb(target) then
		pushFxRemote:FireAllClients(idOf(pusher), 0)
		if typeof(pusher) == "Instance" then
			noticeRemote:FireClient(pusher, string.format("%s закрылся щитом!", nameOf(target)))
		end
		return false
	end
	local away = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	Knockback.apply(targetRoot, away, C.Speed * (if mega then mega.force else 1), C.UpSpeed * (if mega then mega.up else 1), C.Duration)
	if isPlayer then
		knockedRemote:FireClient(target, C.KnockdownTime)
		noticeRemote:FireClient(target, string.format("%s толкнул тебя!", nameOf(pusher)))
	else
		BotService.knockDown(target, C.KnockdownTime)
	end
	pushFxRemote:FireAllClients(idOf(pusher), idOf(target))
	log("%s pushed %s", nameOf(pusher), nameOf(target))
	return true
end

local function onPushIntent(player: Player)
	if RaceManager.getState() ~= "Racing" then
		return
	end
	local t = now()
	local ready = readyAt[player]
	if not ready or t < ready then
		return -- не в гонке или кулдаун
	end
	if not canPushOrBePushed(player) then
		return
	end
	local root = getRoot(player)
	if not root then
		return
	end

	local target, targetRoot = findTarget(player, root)
	if not target or not targetRoot then
		setReadyAt(player, t + C.MissCooldown)
		pushFxRemote:FireAllClients(player.UserId, 0) -- руки вперёд и мимо
		return
	end
	-- бонус «Мега-толчок» из бокса
	local megaUntil = player:GetAttribute(Attributes.MegaPushUntil)
	local mega = if typeof(megaUntil) == "number" and megaUntil > t then MEGA else nil
	local pushed = applyPush(player, root, target, targetRoot, mega)
	setReadyAt(player, t + (if pushed and mega then mega.cooldown else C.Cooldown))
end

-- Боты толкаются сами: соперник рядом в конусе — с шансом PushChance, потом PushCooldown.
local function stepBots()
	if RaceManager.getState() ~= "Racing" then
		return
	end
	local t = now()
	if t < nextBotCheck then
		return
	end
	nextBotCheck = t + B.PushCheckInterval
	for _, bot in BotService.getBots() do
		if not botReadyAt[bot] then
			botReadyAt[bot] = t + B.PushStartDelay -- на старте все вплотную
		end
		if not BotService.isRunning(bot) or BotService.isKnocked(bot) or t < botReadyAt[bot] then
			continue
		end
		local target, targetRoot = findTarget(bot, bot.root)
		if target and targetRoot and rng:NextNumber() < B.PushChance then
			applyPush(bot, bot.root, target, targetRoot, nil)
			botReadyAt[bot] = t + B.PushCooldown
		end
	end
end

function PushService.beginRace(players: { Player })
	table.clear(racers)
	table.clear(botReadyAt)
	local t = now()
	for _, player in players do
		racers[player] = true
		setReadyAt(player, t)
	end
end

function PushService.endRace()
	for player in racers do
		setReadyAt(player, nil)
	end
	table.clear(racers)
	table.clear(botReadyAt)
	table.clear(immuneUntil)
end

function PushService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	BotService = services.BotService
	noticeRemote = Remotes.get(Remotes.Names.Notice)
	pushFxRemote = Remotes.get(Remotes.Names.PushFx)
	knockedRemote = Remotes.get(Remotes.Names.KnockedDown)
end

function PushService.start()
	Remotes.get(Remotes.Names.PushIntent).OnServerEvent:Connect(onPushIntent)
	game:GetService("RunService").Heartbeat:Connect(stepBots)
	Players.PlayerRemoving:Connect(function(player)
		racers[player] = nil
		readyAt[player] = nil
		immuneUntil[player] = nil
	end)
end

return PushService
