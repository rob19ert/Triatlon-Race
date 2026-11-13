--!strict
-- Стрельбище: занятие рубежа, выстрелы, качание, ветер, задержка дыхания, итог стрельбы.
-- Всё решает сервер. Клиент присылает только «куда целился и когда нажал»;
-- качание (Shared/Aim) и ветер сервер добавляет к направлению сам.
--
-- Структура стрельбища в мире (модель с тегом Config.Shooting.RangeTag):
--   атрибуты: Order (номер стрельбы), Stance ("Prone"/"Standing")
--   Entry — невидимая зона поперёк трассы: кто в неё вошёл, тот идёт на рубеж
--   Lanes/LaneN (атрибут Index): Eye — точка глаз стрелка, Target1..5 — мишени
--   FlagPole.WindLabel.Text — подпись ветра

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local Aim = require(ReplicatedStorage.Shared.Aim)
local Types = require(ReplicatedStorage.Shared.Types)

local C = Config.Shooting

local ShootingService = {}

local StaminaService: any -- задаётся в init

local stageFinishedEvent = Instance.new("BindableEvent")
-- (player: Player, rangeOrder: number, hits: number, misses: number) — игрок отстрелялся и ушёл с рубежа
ShootingService.StageFinished = stageFinishedEvent.Event

type Lane = {
	index: number,
	eye: BasePart,
	targets: { BasePart },
}

type Range = {
	model: Model,
	order: number,
	stance: Aim.Stance,
	entry: BasePart,
	lanes: { Lane },
	wind: number, -- уровень со знаком на текущую гонку
}

type Session = {
	range: Range,
	lane: Lane,
	shotsLeft: number,
	hits: { boolean },
	lastShotAt: number,
	holdUntil: number,
	holdReadyAt: number,
	finishing: boolean,
}

export type StageResult = { hits: number, misses: number }

local ranges: { Range } = {}
local racers: { [Player]: number } = {} -- игрок -> стартовый номер (определяет «свой» рубеж)
local sessions: { [Player]: Session } = {}
local laneOccupant: { [Lane]: Player } = {}
local results: { [Player]: { [number]: StageResult } } = {} -- по Order стрельбища

local remoteStarted: RemoteEvent
local remoteShotResult: RemoteEvent
local remoteFinished: RemoteEvent

local function log(fmt: string, ...: any)
	print("[ShootingService] " .. string.format(fmt, ...))
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isInside(zone: BasePart, position: Vector3): boolean
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function isFiniteNumber(v: unknown): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---------------------------------------------------------------- загрузка стрельбищ из мира

local function loadRange(model: Model): Range?
	local entry = model:FindFirstChild("Entry")
	local lanesFolder = model:FindFirstChild("Lanes")
	if not (entry and entry:IsA("BasePart") and lanesFolder) then
		warn("[ShootingService] bad range model: " .. model:GetFullName())
		return nil
	end

	local lanes: { Lane } = {}
	for _, laneModel in lanesFolder:GetChildren() do
		local eye = laneModel:FindFirstChild("Eye")
		if eye and eye:IsA("BasePart") then
			local targets: { BasePart } = {}
			for i = 1, C.ShotsPerStage do
				local target = laneModel:FindFirstChild("Target" .. i)
				if target and target:IsA("BasePart") then
					table.insert(targets, target)
				end
			end
			table.insert(lanes, {
				index = (laneModel:GetAttribute("Index") :: number?) or #lanes + 1,
				eye = eye,
				targets = targets,
			})
		end
	end
	table.sort(lanes, function(a, b)
		return a.index < b.index
	end)
	-- проверка мира: скопированные рубежи часто остаются с тем же Index или на том же месте
	for i = 2, #lanes do
		for j = 1, i - 1 do
			if lanes[i].index == lanes[j].index then
				warn(string.format("[ShootingService] %s: duplicate lane Index %d", model.Name, lanes[i].index))
			end
			if (lanes[i].eye.Position - lanes[j].eye.Position).Magnitude < 1 then
				warn(string.format("[ShootingService] %s: lanes %d and %d have Eye at the same spot", model.Name, lanes[j].index, lanes[i].index))
			end
		end
	end

	local stance = model:GetAttribute("Stance")
	return {
		model = model,
		order = (model:GetAttribute("Order") :: number?) or 1,
		stance = if stance == "Standing" then "Standing" else "Prone",
		entry = entry,
		lanes = lanes,
		wind = 0,
	}
end

local function setWindLabel(range: Range)
	local label = range.model:FindFirstChild("WindLabel", true)
	local text = label and label:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		local level = math.abs(range.wind)
		local arrow = if range.wind > 0 then string.rep("▶", level) elseif range.wind < 0 then string.rep("◀", level) else "—"
		text.Text = string.format("Ветер %s %d", arrow, level)
	end
	-- флажок: длина по силе ветра, развевается по направлению (+Z — вправо от стрелка)
	local flag = range.model:FindFirstChild("Flag")
	local pole = range.model:FindFirstChild("FlagPole")
	if flag and flag:IsA("BasePart") and pole and pole:IsA("BasePart") then
		local length = 0.5 + math.abs(range.wind) * 1.2
		local dir = if range.wind >= 0 then 1 else -1
		local top = pole.Position + Vector3.new(0, pole.Size.Y / 2 - 1, 0)
		flag.Size = Vector3.new(0.1, 1.5, length)
		flag.CFrame = CFrame.new(top + Vector3.new(0, 0, dir * length / 2))
	end
end

local function resetLaneTargets(lane: Lane)
	for _, target in lane.targets do
		target.Color = C.TargetOpenColor
	end
end

local function resetRange(range: Range)
	for _, lane in range.lanes do
		resetLaneTargets(lane)
	end
	local level = math.random(0, C.WindMaxLevel)
	range.wind = if math.random() < 0.5 then -level else level
	setWindLabel(range)
end

---------------------------------------------------------------- рубеж

local function setHoldAttributes(player: Player, session: Session?)
	player:SetAttribute(Attributes.HoldBreathUntil, if session then session.holdUntil else nil)
	player:SetAttribute(Attributes.HoldBreathReadyAt, if session then session.holdReadyAt else nil)
end

local function nearestFreeLane(range: Range, position: Vector3): Lane?
	local best: Lane? = nil
	local bestDist = math.huge
	for _, lane in range.lanes do
		if not laneOccupant[lane] then
			local d = (lane.eye.Position - position).Magnitude
			if d < bestDist then
				best, bestDist = lane, d
			end
		end
	end
	return best
end

-- Свой рубеж по стартовому номеру (как в биатлоне); если занят — ближайший свободный.
local function pickLane(player: Player, range: Range, position: Vector3): Lane?
	local slot = racers[player]
	if slot and #range.lanes > 0 then
		local own = range.lanes[(slot - 1) % #range.lanes + 1]
		if not laneOccupant[own] then
			return own
		end
	end
	return nearestFreeLane(range, position)
end

local function startSession(player: Player, range: Range, root: BasePart)
	local lane = pickLane(player, range, root.Position)
	if not lane then
		return -- все рубежи заняты: игрок ждёт в зоне, попробуем в следующем кадре
	end
	local character = player.Character :: Model

	laneOccupant[lane] = player
	resetLaneTargets(lane) -- после предыдущего стрелка мишени могли остаться закрытыми
	local session: Session = {
		range = range,
		lane = lane,
		shotsLeft = C.ShotsPerStage,
		hits = table.create(C.ShotsPerStage, false),
		lastShotAt = -math.huge,
		holdUntil = 0,
		holdReadyAt = 0,
		finishing = false,
	}
	sessions[player] = session

	-- ставим на рубеж лицом к мишеням и фиксируем
	local eye = lane.eye.CFrame
	local look = Vector3.new(eye.LookVector.X, 0, eye.LookVector.Z).Unit
	local rootPos = eye.Position - Vector3.new(0, C.EyeAboveRoot, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(rootPos, rootPos + look))
	root.Anchored = true
	setHoldAttributes(player, session)

	local spacingDeg = 0
	if #lane.targets >= 2 then
		local a = (lane.targets[1].Position - eye.Position).Unit
		local b = (lane.targets[2].Position - eye.Position).Unit
		spacingDeg = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
	end
	local payload: Types.ShootingStartPayload = {
		eye = eye,
		stance = range.stance,
		wind = range.wind,
		shots = C.ShotsPerStage,
		lane = lane.index,
		targetSpacingDeg = spacingDeg,
	}
	remoteStarted:FireClient(player, payload)
	log("%s -> range %d lane %d (%s, wind %d)", player.Name, range.order, lane.index, range.stance, range.wind)
end

local function endSession(player: Player, session: Session)
	sessions[player] = nil
	if laneOccupant[session.lane] == player then
		laneOccupant[session.lane] = nil
	end
	setHoldAttributes(player, nil)
	local root = getRoot(player)
	if root then
		root.Anchored = false
	end
end

local function finishSession(player: Player, session: Session)
	local hits = 0
	for _, hit in session.hits do
		if hit then
			hits += 1
		end
	end
	local misses = C.ShotsPerStage - hits
	results[player] = results[player] or {}
	results[player][session.range.order] = { hits = hits, misses = misses }

	endSession(player, session)

	local summary: Types.ShootingSummary = {
		userId = player.UserId,
		name = player.Name,
		rangeOrder = session.range.order,
		hits = hits,
		shots = C.ShotsPerStage,
	}
	remoteFinished:FireAllClients(summary)
	log("%s — %d/%d (%d miss)", player.Name, hits, C.ShotsPerStage, misses)
	stageFinishedEvent:Fire(player, session.range.order, hits, misses)
end

-- Точка, где луч пересекает плоскость мишени (ось цилиндра смотрит на стрелка).
local function rayPlanePoint(origin: Vector3, dir: Vector3, target: BasePart): Vector3?
	local normal = target.CFrame.RightVector
	local denom = dir:Dot(normal)
	if math.abs(denom) < 1e-6 then
		return nil
	end
	local s = (target.Position - origin):Dot(normal) / denom
	if s <= 0 then
		return nil
	end
	return origin + dir * s
end

local function rayHitsTarget(origin: Vector3, dir: Vector3, target: BasePart, radius: number): boolean
	local point = rayPlanePoint(origin, dir, target)
	return point ~= nil and (point - target.Position).Magnitude <= radius
end

local function onFireShot(player: Player, aimYaw: unknown, aimPitch: unknown, shotTime: unknown)
	local session = sessions[player]
	if not session or session.finishing or session.shotsLeft <= 0 then
		return
	end
	if not (isFiniteNumber(aimYaw) and isFiniteNumber(aimPitch) and isFiniteNumber(shotTime)) then
		return
	end
	local t = now()
	if t - session.lastShotAt < C.MinShotInterval then
		return -- затвор ещё не перезаряжен
	end
	local yaw = math.clamp(aimYaw :: number, -C.AimLimitDeg, C.AimLimitDeg)
	local pitch = math.clamp(aimPitch :: number, -C.AimLimitDeg, C.AimLimitDeg)
	-- метка времени с клиента нужна, чтобы качание совпало с тем, что он видел;
	-- принимаем только в узком окне назад от серверного «сейчас»
	local swayTime = math.clamp(shotTime :: number, t - C.ShotTimeTolerance, t)

	session.lastShotAt = t
	session.shotsLeft -= 1

	local range = session.range
	local pulse = StaminaService.getPulse(player) or Config.Stamina.StartPulse
	local holding = swayTime < session.holdUntil
	local swayYaw, swayPitch = Aim.swayOffset(swayTime, pulse, range.stance, holding)
	local shot = Aim.cframe(session.lane.eye.CFrame, yaw + swayYaw + Aim.windYaw(range.wind), pitch + swayPitch)

	local radius = C.TargetDiameter[range.stance] / 2
	local hitIndex: number? = nil
	local hitClosed = false
	for i, target in session.lane.targets do
		if rayHitsTarget(shot.Position, shot.LookVector, target, radius) then
			if session.hits[i] then
				hitClosed = true -- попал в уже закрытую — это промах
			else
				hitIndex = i
			end
			break
		end
	end

	if hitIndex then
		session.hits[hitIndex] = true
		session.lane.targets[hitIndex].Color = C.TargetClosedColor
	end
	log(
		"%s shot %d: %s (pulse %d, sway %.2f/%.2f, wind %d%s)",
		player.Name,
		C.ShotsPerStage - session.shotsLeft,
		if hitIndex then "HIT #" .. hitIndex else (if hitClosed then "miss (closed target)" else "miss"),
		math.floor(pulse + 0.5),
		swayYaw,
		swayPitch,
		range.wind,
		if holding then ", breath held" else ""
	)

	local firstTarget = session.lane.targets[1]
	local result: Types.ShotResultPayload = {
		hit = hitIndex ~= nil,
		targetIndex = hitIndex,
		shotsLeft = session.shotsLeft,
		impact = if firstTarget then rayPlanePoint(shot.Position, shot.LookVector, firstTarget) else nil,
	}
	remoteShotResult:FireClient(player, result)

	if session.shotsLeft == 0 then
		session.finishing = true
		task.delay(C.FinishDelay, function()
			if sessions[player] == session then
				finishSession(player, session)
			end
		end)
	end
end

local function onHoldBreath(player: Player)
	local session = sessions[player]
	if not session or session.finishing then
		return
	end
	local t = now()
	if t < session.holdReadyAt then
		return
	end
	session.holdUntil = t + C.HoldBreathDuration
	session.holdReadyAt = session.holdUntil + C.HoldBreathCooldown
	setHoldAttributes(player, session)
	task.delay(C.HoldBreathDuration, function()
		StaminaService.addPulse(player, C.HoldBreathPulseCost)
	end)
end

local function step()
	for player in racers do
		if sessions[player] then
			continue
		end
		local root = getRoot(player)
		if not root then
			continue
		end
		for _, range in ranges do
			local done = results[player] and results[player][range.order]
			if not done and isInside(range.entry, root.Position) then
				startSession(player, range, root)
				break
			end
		end
	end
end

---------------------------------------------------------------- API

function ShootingService.beginRace(players: { Player })
	ShootingService.endRace()
	for slot, player in players do
		racers[player] = slot
	end
	for _, range in ranges do
		resetRange(range)
	end
end

function ShootingService.endRace()
	for player, session in sessions do
		endSession(player, session)
	end
	table.clear(racers)
	table.clear(results)
end

-- Итог стрельбы игрока на стрельбище с данным Order (nil — ещё не стрелял).
function ShootingService.getResult(player: Player, rangeOrder: number): StageResult?
	return results[player] and results[player][rangeOrder]
end

function ShootingService.isShooting(player: Player): boolean
	return sessions[player] ~= nil
end

-- Сколько выстрелов сделано на текущем рубеже (0, если не стреляет).
function ShootingService.getShotsFired(player: Player): number
	local session = sessions[player]
	return if session then C.ShotsPerStage - session.shotsLeft else 0
end

-- Сколько стрельб игрок уже завершил.
function ShootingService.getCompletedStages(player: Player): number
	local n = 0
	for _ in results[player] or {} do
		n += 1
	end
	return n
end

-- Сколько стрельбищ на трассе.
function ShootingService.getRangeCount(): number
	return #ranges
end

-- Попадания и выстрелы за всю гонку.
function ShootingService.getTotals(player: Player): (number, number)
	local hits, shots = 0, 0
	for _, r in results[player] or {} do
		hits += r.hits
		shots += r.hits + r.misses
	end
	return hits, shots
end

function ShootingService.init(services: { [string]: any })
	StaminaService = services.StaminaService
	remoteStarted = Remotes.get(Remotes.Names.ShootingStarted)
	remoteShotResult = Remotes.get(Remotes.Names.ShotResult)
	remoteFinished = Remotes.get(Remotes.Names.ShootingFinished)
end

function ShootingService.start()
	for _, model in CollectionService:GetTagged(C.RangeTag) do
		if model:IsA("Model") then
			local range = loadRange(model)
			if range then
				table.insert(ranges, range)
			end
		end
	end
	table.sort(ranges, function(a, b)
		return a.order < b.order
	end)
	log("%d range(s) loaded", #ranges)

	Remotes.get(Remotes.Names.FireShot).OnServerEvent:Connect(onFireShot)
	Remotes.get(Remotes.Names.HoldBreath).OnServerEvent:Connect(onHoldBreath)
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			endSession(player, session)
		end
		racers[player] = nil
		results[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return ShootingService
