--!strict
-- Боты-соперники: NPC (Humanoid R15), проходят трассу по точкам Track/BotPath.
--  * бег: Humanoid:MoveTo к следующей точке; прыжок — с точек Jump и перед низким препятствием впереди;
--    застрял — прыжок, совсем застрял — перенос на точку;
--  * упал в воду (FallZone) или ниже KillY — назад к последней точке Spawn;
--  * рубеж (Action = Range): занимает полосу через ShootingService, 5 выстрелов с паузами,
--    попадание по точности профиля закрывает мишень, промах — штрафные секунды;
--  * велосипед: Mount — модель велосипеда (BikeService) и скорость езды, Dismount — снова пешком;
--  * финиш — пересечение плоскости FinishLine (как у игроков, с долей кадра).
-- Модель бота — тег Config.Bots.Tag, атрибут Riding (клиенты крутят колёса и ставят позу).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local Types = require(ReplicatedStorage.Shared.Types)
local Zone = require(script.Parent.Parent.Lib.Zone)

local B = Config.Bots

local BotService = {}

local ShootingService: any
local BikeService: any
local ProgressTracker: any

local finishedEvent = Instance.new("BindableEvent")
-- (bot: Bot, finishClock: number) — бот пересёк финиш (os.clock() момента пересечения)
BotService.Finished = finishedEvent.Event

type Waypoint = {
	pos: Vector3,
	jump: boolean,
	spawn: boolean,
	bike: boolean,
	action: string?,
	range: number?,
}

export type Bot = {
	id: number, -- отрицательный: не пересекается с UserId игроков
	name: string,
	slot: number, -- стартовый номер (своя полоса на рубеже)
	profile: { run: number, bike: number, accuracy: number, shotGap: { number }, dodge: number },
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	state: "Waiting" | "Run" | "Shooting" | "Finished",
	index: number, -- следующая точка маршрута
	spawnIndex: number,
	falls: number, -- падений в воду с текущей точки Spawn
	riding: boolean,
	stages: number, -- завершённые стрельбы
	penalty: number,
	hits: number,
	shots: number,
	stageShots: number, -- выстрелов на текущем рубеже (для таблицы позиций)
	startClock: number,
	bestDist: number,
	progressAt: number,
	jumpAt: number,
	moveIssuedAt: number,
	knockedUntil: number, -- сбит препятствием: лежит до этого os.clock()
	lastLineDist: number?,
	lastClock: number,
	tracks: { [string]: AnimationTrack },
	playing: string?,
}

local waypoints: { Waypoint } = {}
local bots: { Bot } = {}
local nextId = -1
local folder: Folder
local finishLine: BasePart
local finishZone: BasePart
local rng = Random.new()
local probeParams = RaycastParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = true

local function log(fmt: string, ...: any)
	print("[BotService] " .. string.format(fmt, ...))
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

---------------------------------------------------------------- маршрут

local function loadPath()
	local track = workspace:WaitForChild(Config.Track.FolderName)
	local pathFolder = track:FindFirstChild(B.PathFolder)
	if not pathFolder then
		warn("[BotService] no Track/" .. B.PathFolder .. " — bots disabled")
		return
	end
	local parts = {}
	for _, p in pathFolder:GetChildren() do
		if p:IsA("BasePart") and typeof(p:GetAttribute("Order")) == "number" then
			table.insert(parts, p)
		end
	end
	table.sort(parts, function(a, b)
		return (a:GetAttribute("Order") :: number) < (b:GetAttribute("Order") :: number)
	end)
	for _, p in parts do
		local action = p:GetAttribute("Action")
		local range = p:GetAttribute("Range")
		table.insert(waypoints, {
			pos = p.Position,
			jump = p:GetAttribute("Jump") == true,
			spawn = p:GetAttribute("Spawn") == true,
			bike = p:GetAttribute("Bike") == true,
			action = if typeof(action) == "string" then action else nil,
			range = if typeof(range) == "number" then range else nil,
		})
	end
end

---------------------------------------------------------------- модель

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function addBib(model: Model, number: number)
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Bib"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(100, 100)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.6, 0.55)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.TextColor3 = Color3.new(0.1, 0.1, 0.1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = tostring(number)
	label.Parent = gui
	gui.Parent = torso
end

local function buildModel(name: string, slot: number): Model
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(B.SkinTones)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = pick(B.ShirtColors)
	local pants = pick(B.PantsColors)
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = "Bot_" .. name
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = B.NamePrefix .. name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	addBib(model, slot)
	CollectionService:AddTag(model, B.Tag)
	return model
end

local function loadTracks(humanoid: Humanoid): { [string]: AnimationTrack }
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}
	for key, id in B.Animations do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			track.Looped = key ~= "Jump"
			tracks[key] = track
		end
	end
	return tracks
end

local function play(bot: Bot, key: string, speed: number?)
	if bot.playing ~= key then
		if bot.playing and bot.tracks[bot.playing] then
			bot.tracks[bot.playing]:Stop(0.15)
		end
		bot.playing = key
		local track = bot.tracks[key]
		if track then
			track:Play(0.15)
		end
	end
	local track = bot.tracks[key]
	if track and speed then
		track:AdjustSpeed(speed)
	end
end

local function animate(bot: Bot)
	local state = bot.humanoid:GetState()
	local speed = flat(bot.root.AssemblyLinearVelocity).Magnitude
	if bot.riding or bot.state == "Shooting" then
		play(bot, "Idle")
	elseif state == Enum.HumanoidStateType.Jumping then
		play(bot, "Jump")
	elseif state == Enum.HumanoidStateType.Freefall then
		play(bot, "Fall")
	elseif speed > 1 then
		play(bot, "Run", speed / Config.Movement.WalkSpeed)
	else
		play(bot, "Idle")
	end
end

---------------------------------------------------------------- движение

-- Разморозить и оставить физику серверу: у замороженной детали владельца не задать,
-- а без этого бота подхватывает клиент ближайшего игрока и MoveTo идёт рывками.
local function release(bot: Bot)
	bot.root.Anchored = false
	pcall(function()
		bot.root:SetNetworkOwner(nil)
	end)
end

local function setRiding(bot: Bot, on: boolean)
	bot.riding = on
	bot.model:SetAttribute("Riding", if on then true else nil)
	bot.humanoid.WalkSpeed = if on then bot.profile.bike else bot.profile.run
	if on then
		BikeService.attachToModel(bot.model, pick(Config.Cosmetics.BikeSkins).id)
	else
		BikeService.detachFromModel(bot.model)
	end
end

local function resetProgress(bot: Bot)
	bot.bestDist = math.huge
	bot.progressAt = os.clock()
	bot.moveIssuedAt = 0
end

local function teleportTo(bot: Bot, index: number)
	local wp = waypoints[index]
	local nextWp = waypoints[index + 1]
	local pos = wp.pos + Vector3.new(0, 3, 0)
	local look = if nextWp then flat(nextWp.pos - wp.pos) else Vector3.new(0, 0, -1)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	bot.root.AssemblyLinearVelocity = Vector3.zero
	bot.model:PivotTo(CFrame.lookAt(pos, pos + look.Unit))
	resetProgress(bot)
end

local function inFallZone(position: Vector3): boolean
	if position.Y < Config.Track.KillY then
		return true
	end
	for _, zone in CollectionService:GetTagged(Config.Track.FallZoneTag) do
		if zone:IsA("BasePart") and Zone.inside(zone, position) then
			return true
		end
	end
	return false
end

local function shoot(bot: Bot, order: number)
	local cf, lane, targets
	while bot.state == "Shooting" do
		cf, lane, targets = ShootingService.botClaimLane(order, bot.slot, bot, bot.root.Position)
		if cf then
			break
		end
		task.wait(0.5)
	end
	if bot.state ~= "Shooting" or not cf then
		return
	end
	bot.humanoid:Move(Vector3.zero)
	bot.humanoid:MoveTo(bot.root.Position)
	bot.root.AssemblyLinearVelocity = Vector3.zero
	bot.model:PivotTo(cf)
	bot.root.Anchored = true
	bot.stageShots = 0
	-- как у игроков: точки над головой и строка в «трансляции» (RangeRivals, ShootingBroadcast)
	bot.model:SetAttribute(Attributes.RangeOrder, order)
	bot.model:SetAttribute(Attributes.RangeMarks, "")
	task.wait(B.AimTime)
	local closed = 0
	local hits = 0
	for _ = 1, Config.Shooting.ShotsPerStage do
		local gap = bot.profile.shotGap
		task.wait(math.max(Config.Shooting.MinShotInterval, rng:NextNumber(gap[1], gap[2])))
		if bot.state ~= "Shooting" then
			return
		end
		bot.shots += 1
		bot.stageShots += 1
		local hit = rng:NextNumber() < bot.profile.accuracy and closed < targets
		if hit then
			closed += 1
			hits += 1
			bot.hits += 1
			ShootingService.botCloseTarget(order, lane, closed)
		else
			bot.penalty += Config.Penalty.SecondsPerMiss
			bot.model:SetAttribute(Attributes.PenaltyTime, bot.penalty)
		end
		bot.model:SetAttribute(Attributes.RangeMarks, (bot.model:GetAttribute(Attributes.RangeMarks) or "") .. (if hit then "H" else "M"))
	end
	task.wait(Config.Shooting.FinishDelay)
	ShootingService.botReleaseLane(order, lane, bot)
	bot.model:SetAttribute(Attributes.RangeOrder, nil)
	bot.model:SetAttribute(Attributes.RangeMarks, nil)
	bot.stageShots = 0
	if bot.state ~= "Shooting" then
		return
	end
	release(bot)
	bot.stages += 1
	bot.state = "Run"
	resetProgress(bot)
	log("%s range %d done, hits %d of %d", bot.name, order, hits, Config.Shooting.ShotsPerStage)
end

local function finish(bot: Bot, finishClock: number)
	bot.state = "Finished"
	bot.model:SetAttribute("Finished", true)
	local elapsed = finishClock - bot.startClock + bot.penalty
	log("%s finished in %.2fs (penalty %ds, shooting %d/%d)", bot.name, elapsed, bot.penalty, bot.hits, bot.shots)
	-- пробежать чуть дальше линии и остановиться
	bot.humanoid:Move(Vector3.zero)
	bot.humanoid:MoveTo(bot.root.Position + Vector3.new(0, 0, -4))
	finishedEvent:Fire(bot, finishClock)
end

local function arrive(bot: Bot, wp: Waypoint)
	if wp.spawn then
		bot.spawnIndex = bot.index
		bot.falls = 0
	end
	if wp.jump then
		bot.humanoid.Jump = true
		bot.jumpAt = os.clock()
	end
	bot.index += 1
	resetProgress(bot)
	if wp.action then
		log("%s %s at %.1fs", bot.name, wp.action .. (if wp.range then tostring(wp.range) else ""), os.clock() - bot.startClock)
	end
	if wp.action == "Range" and wp.range then
		bot.state = "Shooting"
		task.spawn(shoot, bot, wp.range)
	elseif wp.action == "Mount" then
		setRiding(bot, true)
	elseif wp.action == "Dismount" then
		setRiding(bot, false)
	end
end

-- Прыжковый участок: к точке прыжка и от неё. Там — точный MoveTo (останавливается в точке,
-- в том числе в воздухе, — приземляется на платформу) и скорость не выше CarefulSpeed;
-- на остальной трассе — непрерывный Move по направлению (без торможения у каждой точки).
local function isCareful(index: number): boolean
	local wp = waypoints[index]
	local prev = waypoints[index - 1]
	return (wp ~= nil and wp.jump) or (prev ~= nil and prev.jump)
end

local function lineDistance(position: Vector3): number
	return finishLine.CFrame:PointToObjectSpace(position).Z
end

local function stepBot(bot: Bot, now: number)
	if bot.state ~= "Run" then
		return
	end
	local pos = bot.root.Position

	-- финиш: пересёк плоскость линии внутри зоны, отстреляв все рубежи
	local dist = lineDistance(pos)
	local prevDist, prevClock = bot.lastLineDist, bot.lastClock
	bot.lastLineDist, bot.lastClock = dist, now
	if dist <= 0 and Zone.inColumn(finishZone, pos) and bot.stages >= ShootingService.getRangeCount() then
		local finishClock = now
		if prevDist and prevDist > 0 then
			finishClock = prevClock + (now - prevClock) * prevDist / (prevDist - dist)
		end
		finish(bot, finishClock)
		return
	end

	if inFallZone(pos) then
		bot.falls += 1
		local target = bot.spawnIndex
		if bot.falls >= B.MaxFalls then
			-- не мучаем: «доплыл» до следующей точки Spawn
			for i = bot.spawnIndex + 1, #waypoints do
				if waypoints[i].spawn then
					target = i
					break
				end
			end
			bot.spawnIndex = target
			bot.falls = 0
		end
		log("%s fell -> point %d", bot.name, target)
		teleportTo(bot, target)
		bot.index = target + 1
		return
	end

	-- сбит: лежит, потом встаёт и бежит дальше
	if bot.knockedUntil > 0 then
		if now < bot.knockedUntil then
			return
		end
		bot.knockedUntil = 0
		bot.humanoid.PlatformStand = false
		resetProgress(bot)
	end

	local wp = waypoints[bot.index]
	if not wp then
		return
	end
	local toWp = flat(wp.pos - pos)
	local d = toWp.Magnitude
	-- проскочил точку (например, приземлился за ней) — тоже засчитываем
	local prev = waypoints[bot.index - 1]
	local passed = false
	if prev and d < B.ArriveDistance * 3 then
		local seg = flat(wp.pos - prev.pos)
		passed = seg.Magnitude > 1e-3 and seg:Dot(-toWp) > 0
	end
	if d <= B.ArriveDistance or passed then
		arrive(bot, wp)
		return
	end

	local speed = if bot.riding then bot.profile.bike else bot.profile.run
	local careful = isCareful(bot.index)
	if careful then
		speed = math.min(speed, B.CarefulSpeed)
	end
	if bot.humanoid.WalkSpeed ~= speed then
		bot.humanoid.WalkSpeed = speed
	end
	if careful then
		if now - bot.moveIssuedAt > 0.5 then
			bot.humanoid:MoveTo(wp.pos)
			bot.moveIssuedAt = now
		end
	else
		bot.humanoid:Move(toWp.Unit)
	end

	-- низкое препятствие прямо по курсу (бревно, стенка) — прыжок
	if d > 1 and now - bot.jumpAt > 0.6 and bot.humanoid.FloorMaterial ~= Enum.Material.Air then
		local dir = toWp.Unit
		local origin = pos - Vector3.new(0, 1.5, 0)
		local hit = workspace:Raycast(origin, dir * B.ProbeDistance, probeParams)
		if hit and hit.Instance:IsA("BasePart") then
			local part = hit.Instance :: BasePart
			local top = part.Position.Y + part.Size.Y / 2
			local feet = pos.Y - bot.humanoid.HipHeight - bot.root.Size.Y / 2
			if top - feet <= B.MaxStepUp and math.abs(hit.Normal.Y) < 0.5 then
				bot.humanoid.Jump = true
				bot.jumpAt = now
			end
		end
	end

	-- застрял
	if d < bot.bestDist - B.MinProgress then
		bot.bestDist = d
		bot.progressAt = now
	elseif now - bot.progressAt > B.StuckSkipAfter then
		log("%s stuck -> point %d", bot.name, bot.index)
		teleportTo(bot, bot.index)
	elseif now - bot.progressAt > B.StuckJumpAfter and now - bot.jumpAt > 1 then
		bot.humanoid.Jump = true
		bot.jumpAt = now
	end
end

local function step()
	if #bots == 0 then
		return
	end
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	probeParams.FilterDescendantsInstances = exclude
	local now = os.clock()
	for _, bot in bots do
		if bot.model.Parent then
			stepBot(bot, now)
			animate(bot)
		end
	end
end

---------------------------------------------------------------- API

-- Создать бота на месте cf (заморожен до go). Ждёт загрузки модели.
function BotService.spawn(slot: number, profileName: string, cf: CFrame): Bot?
	if #waypoints == 0 then
		return nil
	end
	local name = B.Names[(slot - 1) % #B.Names + 1]
	local model = buildModel(name, slot)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local profile = (B.Profiles :: any)[profileName] or B.Profiles.Medium
	humanoid.WalkSpeed = profile.run
	model:PivotTo(cf)
	root.Anchored = true
	model:SetAttribute("BotId", nextId)
	model.Parent = folder
	local bot: Bot = {
		id = nextId,
		name = B.NamePrefix .. name,
		slot = slot,
		profile = profile,
		model = model,
		humanoid = humanoid,
		root = root,
		state = "Waiting",
		index = 1,
		spawnIndex = 1,
		falls = 0,
		riding = false,
		stages = 0,
		penalty = 0,
		hits = 0,
		shots = 0,
		stageShots = 0,
		startClock = 0,
		bestDist = math.huge,
		progressAt = 0,
		jumpAt = 0,
		moveIssuedAt = 0,
		knockedUntil = 0,
		lastLineDist = nil,
		lastClock = 0,
		tracks = loadTracks(humanoid),
		playing = nil,
	}
	nextId -= 1
	table.insert(bots, bot)
	log("spawned %s (#%d, %s)", bot.name, slot, profileName)
	return bot
end

-- Старт: все ожидающие боты бегут.
function BotService.go(startClock: number)
	for _, bot in bots do
		if bot.state == "Waiting" then
			bot.state = "Run"
			bot.startClock = startClock
			release(bot)
			resetProgress(bot)
		end
	end
end

function BotService.getBots(): { Bot }
	return bots
end

function BotService.getById(id: number): Bot?
	for _, bot in bots do
		if bot.id == id then
			return bot
		end
	end
	return nil
end

-- Для таблицы позиций — та же шкала, что у игроков (ProgressTracker).
function BotService.getProgress(bot: Bot): (Types.RacePhase, number)
	return ProgressTracker.scoreFor(bot.stages, bot.state == "Shooting", bot.stageShots, bot.root.Position)
end

-- Бот бежит по трассе (не на рубеже, не финишировал) — его могут сбить препятствия и толкнуть.
function BotService.isRunning(bot: Bot): boolean
	return bot.state == "Run" and bot.model.Parent ~= nil
end

-- Попал под препятствие: увернулся ли (шанс по профилю — боты не ловят тайминг, как игрок).
function BotService.dodges(bot: Bot): boolean
	return rng:NextNumber() < bot.profile.dodge
end

-- Сбит (маятник, мельница, поезд, толчок): падает на seconds, отлёт задаёт вызывающий (Knockback).
function BotService.knockDown(bot: Bot, seconds: number)
	bot.knockedUntil = os.clock() + seconds
	bot.humanoid.PlatformStand = true
	bot.humanoid:Move(Vector3.zero)
	bot.humanoid:MoveTo(bot.root.Position)
end

-- Гонка кончилась: кто ещё бежит — останавливается (на подиум и в итоги — как есть).
function BotService.stopAll()
	for _, bot in bots do
		if bot.state ~= "Finished" then
			bot.state = "Finished"
			bot.humanoid:Move(Vector3.zero)
			bot.humanoid:MoveTo(bot.root.Position)
		end
	end
end

function BotService.clear()
	for _, bot in bots do
		bot.state = "Finished"
		bot.model:Destroy()
	end
	table.clear(bots)
end

function BotService.init(services: { [string]: any })
	ShootingService = services.ShootingService
	BikeService = services.BikeService
	ProgressTracker = services.ProgressTracker
end

function BotService.start()
	folder = Instance.new("Folder")
	folder.Name = B.FolderName
	folder.Parent = workspace
	local track = workspace:WaitForChild(Config.Track.FolderName)
	finishLine = track:WaitForChild(Config.Track.FinishLineName) :: BasePart
	finishZone = track:WaitForChild(Config.Track.FinishZoneName) :: BasePart
	loadPath()
	log("%d path point(s)", #waypoints)
	RunService.Heartbeat:Connect(step)

	-- Studio: N — выпустить тестового бота со старта (профили по кругу)
	if RunService:IsStudio() then
		local profiles = { "Fast", "Medium", "Slow" }
		local count = 0
		Remotes.get(Remotes.Names.DevSpawnBot).OnServerEvent:Connect(function()
			count += 1
			local grid = track:FindFirstChild(Config.Track.StartGridName) :: BasePart?
			local base = if grid then grid.Position else Vector3.new(0, 0, -20)
			local pos = base + Vector3.new(((count - 1) % 5 - 2) * 4, 3, 0)
			task.spawn(function()
				local bot = BotService.spawn(count + B.FillTo, profiles[(count - 1) % 3 + 1], CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
				if bot then
					bot.state = "Run"
					bot.startClock = os.clock()
					release(bot)
					resetProgress(bot)
				end
			end)
		end)
	end
end

return BotService
