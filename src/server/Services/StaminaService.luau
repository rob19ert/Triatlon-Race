--!strict
-- Пульс игроков (0–100, общий на всю гонку), спринт и красная зона.
-- Всё считает сервер: клиент присылает только намерение «хочу спринт».
-- Скорость (WalkSpeed) во время гонки выставляет тоже этот сервис.
-- Клиентам состояние уходит через атрибуты Player (см. Shared/Attributes).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local S = Config.Stamina

local StaminaService = {}

type PlayerStamina = {
	pulse: number,
	redZone: boolean,
	wantsSprint: boolean, -- намерение с клиента
	sprinting: boolean, -- спринт реально работает
	ignoreRedZonePenalty: boolean, -- финишная прямая: красная зона не замедляет
	recoveryMultiplier: number, -- догонялка: >1 у отстающих
	turboUntil: number, -- os.clock() конца турбо (5/5 на рубеже)
	speedOverride: number?, -- базовая скорость вместо бега (велосипед; в Studio — режим велосипеда)
	boostUntil: number, -- os.clock() конца ускорителя
	boostMultiplier: number,
	lastVelY: number,
	publishedPulse: number?,
}

local active: { [Player]: PlayerStamina } = {}
local publishAccumulator = 0

local function getHumanoidAndRoot(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function publish(player: Player, st: PlayerStamina, force: boolean)
	local rounded = math.floor(st.pulse + 0.5)
	if force or st.publishedPulse ~= rounded then
		st.publishedPulse = rounded
		player:SetAttribute(Attributes.Pulse, rounded)
	end
	if player:GetAttribute(Attributes.RedZone) ~= st.redZone then
		player:SetAttribute(Attributes.RedZone, st.redZone)
	end
	if player:GetAttribute(Attributes.Sprinting) ~= st.sprinting then
		player:SetAttribute(Attributes.Sprinting, st.sprinting)
	end
end

local function clearAttributes(player: Player)
	player:SetAttribute(Attributes.Pulse, nil)
	player:SetAttribute(Attributes.RedZone, nil)
	player:SetAttribute(Attributes.Sprinting, nil)
	player:SetAttribute(Attributes.TurboUntil, nil)
end

local function addPulse(st: PlayerStamina, delta: number)
	st.pulse = math.clamp(st.pulse + delta, S.MinPulse, S.MaxPulse)
end

-- Обычный бег тянет пульс к RunPulse с обеих сторон.
local function driftToward(current: number, target: number, maxStep: number): number
	if current < target then
		return math.min(current + maxStep, target)
	end
	return math.max(current - maxStep, target)
end

local function updatePlayer(player: Player, st: PlayerStamina, dt: number)
	local humanoid, root = getHumanoidAndRoot(player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if root.Anchored then
		-- закреплён на рубеже: стоит и дышит
		st.sprinting = false
		st.lastVelY = 0
		addPulse(st, -S.RestRecoveryPerSec * st.recoveryMultiplier * dt)
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = horizontalSpeed > S.MovingSpeedThreshold

	-- прыжок: вертикальная скорость пересекла порог снизу вверх
	if st.lastVelY < S.JumpVelocityThreshold and velocity.Y >= S.JumpVelocityThreshold then
		addPulse(st, S.JumpCost)
	end
	st.lastVelY = velocity.Y

	-- красная зона с гистерезисом: вход на RedZoneEnter, выход ниже RedZoneExit
	if not st.redZone and st.pulse >= S.RedZoneEnter then
		st.redZone = true
		print(string.format("[StaminaService] %s entered red zone", player.Name))
	elseif st.redZone and st.pulse < S.RedZoneExit then
		st.redZone = false
		print(string.format("[StaminaService] %s left red zone", player.Name))
	end

	st.sprinting = st.wantsSprint and moving and not st.redZone

	if st.sprinting then
		addPulse(st, S.SprintGainPerSec * dt)
	elseif moving then
		-- снижение пульса к RunPulse — это восстановление, оно ускоряется догонялкой
		local rate = if st.pulse > S.RunPulse then S.RunDriftPerSec * st.recoveryMultiplier else S.RunDriftPerSec
		st.pulse = driftToward(st.pulse, S.RunPulse, rate * dt)
	else
		addPulse(st, -S.RestRecoveryPerSec * st.recoveryMultiplier * dt)
	end

	local speed = if st.sprinting then Config.Movement.SprintSpeed else Config.Movement.WalkSpeed
	if st.speedOverride then
		speed = st.speedOverride
	end
	if st.redZone and not st.ignoreRedZonePenalty then
		speed *= S.RedZoneSpeedMultiplier
	end
	if os.clock() < st.turboUntil then
		speed *= Config.Reward.TurboSpeedMultiplier
	end
	if os.clock() < st.boostUntil then
		speed *= st.boostMultiplier
	end
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

local function step(dt: number)
	for player, st in active do
		updatePlayer(player, st, dt)
	end

	publishAccumulator += dt
	if publishAccumulator >= S.PublishInterval then
		publishAccumulator = 0
		for player, st in active do
			publish(player, st, false)
		end
	end
end

local function onSprintIntent(player: Player, wantsSprint: unknown)
	if typeof(wantsSprint) ~= "boolean" then
		return
	end
	local st = active[player]
	if not st then
		return -- не в гонке — игнорируем
	end
	st.wantsSprint = wantsSprint
end

---------------------------------------------------------------- API

function StaminaService.beginRace(players: { Player })
	StaminaService.endRace()
	for _, player in players do
		local st: PlayerStamina = {
			pulse = S.StartPulse,
			redZone = false,
			wantsSprint = false,
			sprinting = false,
			ignoreRedZonePenalty = false,
			recoveryMultiplier = 1,
			turboUntil = 0,
			boostUntil = 0,
			boostMultiplier = 1,
			lastVelY = 0,
			publishedPulse = nil,
		}
		active[player] = st
		publish(player, st, true)
	end
end

function StaminaService.endRace()
	for player in active do
		clearAttributes(player)
	end
	table.clear(active)
end

function StaminaService.getPulse(player: Player): number?
	local st = active[player]
	return if st then st.pulse else nil
end

function StaminaService.addPulse(player: Player, delta: number)
	local st = active[player]
	if st then
		addPulse(st, delta)
	end
end

function StaminaService.isRedZone(player: Player): boolean
	local st = active[player]
	return st ~= nil and st.redZone
end

-- Базовая скорость вместо бега (nil — обычный бег). Множители красной зоны и турбо действуют поверх.
function StaminaService.setSpeedOverride(player: Player, speed: number?)
	local st = active[player]
	if st then
		st.speedOverride = speed
	end
end

function StaminaService.getSpeedOverride(player: Player): number?
	local st = active[player]
	return st and st.speedOverride
end

-- Ускоритель на дороге: скорость ×multiplier на seconds (продлевается при повторном заезде).
function StaminaService.grantBoost(player: Player, multiplier: number, seconds: number)
	local st = active[player]
	if st then
		st.boostUntil = os.clock() + seconds
		st.boostMultiplier = multiplier
	end
end

-- Турбо: скорость ×TurboSpeedMultiplier на seconds секунд (награда за 5/5).
function StaminaService.grantTurbo(player: Player, seconds: number)
	local st = active[player]
	if not st then
		return
	end
	st.turboUntil = os.clock() + seconds
	player:SetAttribute(Attributes.TurboUntil, workspace:GetServerTimeNow() + seconds)
	print(string.format("[StaminaService] %s TURBO %ds", player.Name, seconds))
end

-- Догонялка: отстающие (последняя треть таблицы) восстанавливают пульс быстрее.
function StaminaService.setCatchUp(player: Player, enabled: boolean)
	local st = active[player]
	if st then
		st.recoveryMultiplier = if enabled then 1 + S.CatchUpRecoveryBonus else 1
	end
end

-- Финишная прямая: красная зона не замедляет.
function StaminaService.setIgnoreRedZonePenalty(player: Player, ignore: boolean)
	local st = active[player]
	if st then
		st.ignoreRedZonePenalty = ignore
	end
end

function StaminaService.start()
	Remotes.get(Remotes.Names.SprintIntent).OnServerEvent:Connect(onSprintIntent)
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return StaminaService
