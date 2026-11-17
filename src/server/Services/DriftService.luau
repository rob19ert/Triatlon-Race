--!strict
-- Дрифт на велосипеде (всё решает сервер, клиент шлёт только «зажал / отпустил»):
--  * держишь дрифт и поворачиваешь в одну сторону — копится заряд (время в повороте);
--  * уровни заряда — искры синие → оранжевые → фиолетовые (атрибут DriftTier);
--  * отпустил — ускорение по уровню (StaminaService.grantBoost);
--  * заряд сгорает: прямая дольше StraightGrace, смена стороны поворота (вилять на прямой бесполезно),
--    обочина, слишком медленно. В воздухе — пауза (не копим и не сгораем).
-- Пока держишь дрифт, скорость чуть ниже (Drift.SpeedMultiplier).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local D = Config.Drift

local DriftService = {}

local RaceManager: any
local StaminaService: any

type State = {
	charge: number, -- с в повороте
	sign: number, -- сторона поворота (+1/−1), 0 — ещё не поворачивал
	tier: number,
	lastTurnAt: number,
	heading: Vector3?, -- направление скорости на прошлом замере
	sampleAt: number,
}

local states: { [Player]: State } = {}

local function log(fmt: string, ...: any)
	print("[DriftService] " .. string.format(fmt, ...))
end

local function tierFor(charge: number): number
	local tier = 0
	for i, t in D.Tiers do
		if charge >= t.time then
			tier = i
		end
	end
	return tier
end

local function setTier(player: Player, st: State, tier: number)
	if st.tier ~= tier then
		st.tier = tier
		player:SetAttribute(Attributes.DriftTier, tier)
	end
end

local function lose(player: Player, st: State)
	st.charge = 0
	st.sign = 0
	setTier(player, st, 0)
end

local function canDrift(player: Player): boolean
	return RaceManager.getState() == "Racing" and player:GetAttribute(Attributes.Riding) == true
end

local function start(player: Player)
	if states[player] or not canDrift(player) then
		return
	end
	local t = os.clock()
	states[player] = { charge = 0, sign = 0, tier = 0, lastTurnAt = t, heading = nil, sampleAt = t }
	player:SetAttribute(Attributes.DriftTier, 0)
	StaminaService.setDrift(player, D.SpeedMultiplier)
end

-- Отпустил (boost = true) или дрифт прервался (слез с велосипеда, конец гонки).
local function stop(player: Player, boost: boolean)
	local st = states[player]
	if not st then
		return
	end
	states[player] = nil
	player:SetAttribute(Attributes.DriftTier, nil)
	StaminaService.setDrift(player, 1)
	local tier = D.Tiers[st.tier]
	if boost and tier then
		StaminaService.grantBoost(player, tier.boost, tier.seconds)
		player:SetAttribute(Attributes.DriftBoostUntil, workspace:GetServerTimeNow() + tier.seconds)
		log("%s drift tier %d (%.1fs) -> x%.2f for %.1fs", player.Name, st.tier, st.charge, tier.boost, tier.seconds)
	end
end

local function onIntent(player: Player, holding: unknown)
	if typeof(holding) ~= "boolean" then
		return
	end
	if holding then
		start(player)
	else
		stop(player, true)
	end
end

local function update(player: Player, st: State, t: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		st.lastTurnAt = t -- в воздухе пауза
		return
	end
	if StaminaService.getTerrainMultiplier(player) < 1 then
		lose(player, st)
		return
	end
	local elapsed = t - st.sampleAt
	if elapsed < D.SampleTime then
		return
	end
	st.sampleAt = t
	local v = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	if v.Magnitude < D.MinSpeed then
		lose(player, st)
		st.heading = nil
		return
	end
	local heading = v.Unit
	local prev = st.heading
	st.heading = heading
	if not prev then
		return
	end
	-- угол поворота за замер со знаком (+ — влево, − — вправо)
	local angle = math.deg(math.atan2(prev:Cross(heading).Y, prev:Dot(heading)))
	local rate = angle / elapsed
	if math.abs(rate) >= D.MinYawRate then
		local sign = if rate > 0 then 1 else -1
		if st.sign ~= 0 and sign ~= st.sign then
			lose(player, st) -- сменил сторону — виляние, заряд сгорел
		end
		st.sign = sign
		st.charge += elapsed
		st.lastTurnAt = t
		setTier(player, st, tierFor(st.charge))
	elseif t - st.lastTurnAt > D.StraightGrace then
		lose(player, st)
	end
end

function DriftService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	StaminaService = services.StaminaService
end

function DriftService.start()
	Remotes.get(Remotes.Names.DriftIntent).OnServerEvent:Connect(onIntent)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for player, st in states do
			if not canDrift(player) then
				stop(player, false)
			else
				update(player, st, t)
			end
		end
	end)
end

return DriftService
