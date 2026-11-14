--!strict
-- Толчок: игрок жмёт F / тач-кнопку, сервер ищет ближайшего соперника в конусе впереди
-- и толкает его в сторону от толкающего и чуть вверх.
-- Соперник отлетает и падает на KnockdownTime. Нельзя толкать и быть толкнутым на рубеже
-- после толчка цель TargetImmunity секунд неуязвима (против спама). На финишной прямой — можно.
-- Импульс — общий модуль Lib/Knockback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local Knockback = require(script.Parent.Parent.Lib.Knockback)

local C = Config.Push
local CONE_COS = math.cos(math.rad(C.ConeAngleDeg))

local PushService = {}

-- задаются в init
local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local noticeRemote: RemoteEvent
local pushFxRemote: RemoteEvent
local knockedRemote: RemoteEvent

local racers: { [Player]: boolean } = {}
local readyAt: { [Player]: number } = {}
local immuneUntil: { [Player]: number } = {}

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

-- Ближайший соперник впереди или сбоку (конус ±ConeAngleDeg).
local function findTarget(pusher: Player, root: BasePart): (Player?, BasePart?)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		return nil, nil
	end
	look = look.Unit

	local best: Player?, bestRoot: BasePart?, bestDist = nil, nil, math.huge
	for other in racers do
		if other == pusher or not canPushOrBePushed(other) or now() < (immuneUntil[other] or 0) then
			continue
		end
		local otherRoot = getRoot(other)
		if not otherRoot then
			continue
		end
		local offset = otherRoot.Position - root.Position
		local dist = offset.Magnitude
		local flat = offset * Vector3.new(1, 0, 1)
		if dist > C.Range or flat.Magnitude < 1e-3 then
			continue
		end
		if look:Dot(flat.Unit) >= CONE_COS and dist < bestDist then
			best, bestRoot, bestDist = other, otherRoot, dist
		end
	end
	return best, bestRoot
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

	local away = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	Knockback.apply(targetRoot, away, C.Speed, C.UpSpeed, C.Duration)
	knockedRemote:FireClient(target, C.KnockdownTime)
	immuneUntil[target] = t + C.TargetImmunity
	setReadyAt(player, t + C.Cooldown)
	pushFxRemote:FireAllClients(player.UserId, target.UserId)
	noticeRemote:FireClient(target, string.format("%s толкнул тебя!", player.DisplayName))
	log("%s pushed %s", player.Name, target.Name)
end

function PushService.beginRace(players: { Player })
	table.clear(racers)
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
end

function PushService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	noticeRemote = Remotes.get(Remotes.Names.Notice)
	pushFxRemote = Remotes.get(Remotes.Names.PushFx)
	knockedRemote = Remotes.get(Remotes.Names.KnockedDown)
end

function PushService.start()
	Remotes.get(Remotes.Names.PushIntent).OnServerEvent:Connect(onPushIntent)
	Players.PlayerRemoving:Connect(function(player)
		racers[player] = nil
		readyAt[player] = nil
		immuneUntil[player] = nil
	end)
end

return PushService
