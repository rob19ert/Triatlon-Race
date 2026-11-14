--!strict
-- Велопетля (фаза 2), всё на сервере:
--  * съезд с дороги: игрок на земле дальше OffRoadMargin от края дороги дольше OffRoadGrace —
--    мгновенно ставим в ближайшую точку центральной линии той же дороги, лицом по ходу движения
--    (не к чекпоинту!). В ямах под разрывами не трогаем — там зона падения (ProgressTracker);
--  * трамплины (тег LaunchPad): въехал на скорости — бросок вперёд и вверх;
--  * ускорители (тег BoostPad): скорость ×BoostMultiplier на BoostSeconds.
-- Работает для участников, которые сейчас на велоэтапе: отстреляли первый рубеж, ещё не второй.
--
-- Дорога: детали с тегом BikeRoad. Отрезки «Seg» — прямые куски по центральной линии
-- (направление построения = направление движения, ширина — атрибут Width); клинья (склоны холма) —
-- по их верхней грани. Остальные (кочки, трамплины, крыши) — просто поверхность, на центральную линию не влияют.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Knockback = require(script.Parent.Parent.Lib.Knockback)

local C = Config.Bike

local BikeTrackService = {}

local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local StaminaService: any

type Segment = { a: Vector3, b: Vector3, halfWidth: number }
local segments: { Segment } = {}

local offRoadSince: { [Player]: number } = {}
local launchReadyAt: { [Player]: number } = {}

local function log(fmt: string, ...: any)
	print("[BikeTrackService] " .. string.format(fmt, ...))
end

local function isInside(zone: BasePart, position: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

---------------------------------------------------------------- центральные линии

local function addSegmentFrom(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	if part.Name == "Seg" then
		local len = part.Size.Z
		local top = part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
		-- CFrame.lookAt(середина, конец): -Z локальная = вперёд
		table.insert(segments, {
			a = (top * CFrame.new(0, 0, len / 2)).Position,
			b = (top * CFrame.new(0, 0, -len / 2)).Position,
			halfWidth = ((part:GetAttribute("Width") :: number?) or part.Size.X) / 2,
		})
	elseif part:IsA("WedgePart") and part.Name == "Wedge" then
		-- склон: низ спереди (-Z), верх сзади (+Z); центральная линия по верхней грани
		local s = part.Size
		local low = (part.CFrame * CFrame.new(0, -s.Y / 2, -s.Z / 2)).Position
		local high = (part.CFrame * CFrame.new(0, s.Y / 2, s.Z / 2)).Position
		-- Reverse: едем сверху вниз (спуск)
		local reverse = part:GetAttribute("Reverse") == true
		table.insert(segments, {
			a = if reverse then high else low,
			b = if reverse then low else high,
			halfWidth = s.X / 2,
		})
	end
end

-- Ближайшая точка на центральных линиях (по горизонтали, с поправкой на высоту), её отрезок и расстояние.
local function nearest(position: Vector3): (Vector3?, Segment?, number)
	local best: Vector3?, bestSeg: Segment?, bestScore = nil, nil, math.huge
	for _, seg in segments do
		local ab = seg.b - seg.a
		local flat = Vector3.new(ab.X, 0, ab.Z)
		local len2 = flat:Dot(flat)
		local t = if len2 > 0 then math.clamp(Vector3.new(position.X - seg.a.X, 0, position.Z - seg.a.Z):Dot(flat) / len2, 0, 1) else 0
		local point = seg.a + ab * t
		local horiz = Vector3.new(position.X - point.X, 0, position.Z - point.Z).Magnitude
		-- высота важна: туннель под вершиной, дорога над дорогой
		local score = horiz + math.max(0, math.abs(position.Y - point.Y) - 6) * 2
		if score < bestScore then
			best, bestSeg, bestScore = point, seg, score
		end
	end
	return best, bestSeg, bestScore
end

---------------------------------------------------------------- проверки игрока

local function onBikeStage(player: Player): boolean
	if not RaceManager.isParticipant(player) or not ProgressTracker.isTracked(player) then
		return false
	end
	if ShootingService.isShooting(player) then
		return false
	end
	return ShootingService.getCompletedStages(player) == 1
end

local function inAnyFallZone(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged(Config.Track.FallZoneTag) do
		if zone:IsA("BasePart") and isInside(zone, position) then
			return true
		end
	end
	return false
end

local function checkOffRoad(player: Player, character: Model, humanoid: Humanoid, root: BasePart, now: number)
	if root.Position.X > C.StadiumEdgeX or humanoid.FloorMaterial == Enum.Material.Air or inAnyFallZone(root.Position) then
		offRoadSince[player] = nil
		return
	end
	local point, seg, score = nearest(root.Position)
	if not point or not seg then
		return
	end
	if score <= seg.halfWidth + C.OffRoadMargin then
		offRoadSince[player] = nil
		return
	end
	local since = offRoadSince[player]
	if not since then
		offRoadSince[player] = now
		return
	end
	if now - since < C.OffRoadGrace then
		return
	end
	-- на центр дороги в ближайшей точке, лицом по ходу движения
	offRoadSince[player] = nil
	local forward = (seg.b - seg.a) * Vector3.new(1, 0, 1)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else root.CFrame.LookVector
	local pos = point + Vector3.new(0, Config.Track.RespawnHeight, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(pos, pos + forward))
	log("%s off-road -> back on road at (%.0f, %.0f)", player.Name, point.X, point.Z)
end

local function checkPads(player: Player, root: BasePart, now: number)
	local position = root.Position
	for _, pad in CollectionService:GetTagged(C.BoostTag) do
		if pad:IsA("BasePart") then
			-- полоса тонкая: проверяем с запасом по высоте
			local p = pad.CFrame:PointToObjectSpace(position)
			if math.abs(p.X) <= pad.Size.X / 2 and math.abs(p.Z) <= pad.Size.Z / 2 + 1 and p.Y > -1 and p.Y < 6 then
				StaminaService.grantBoost(player, C.BoostMultiplier, C.BoostSeconds)
			end
		end
	end
	if now < (launchReadyAt[player] or 0) then
		return
	end
	local speed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	if speed < C.LaunchMinSpeed then
		return
	end
	for _, zone in CollectionService:GetTagged(C.LaunchTag) do
		if zone:IsA("BasePart") and isInside(zone, position) then
			launchReadyAt[player] = now + C.LaunchCooldown
			Knockback.apply(root, zone.CFrame.LookVector, math.max(speed, C.LaunchForwardSpeed), C.LaunchUpSpeed, C.LaunchTime)
			return
		end
	end
end

local function step()
	if RaceManager.getState() ~= "Racing" or #segments == 0 then
		return
	end
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if not onBikeStage(player) then
			offRoadSince[player] = nil
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and humanoid and root and humanoid.Health > 0 then
			checkPads(player, root, now)
			checkOffRoad(player, character, humanoid, root, now)
		end
	end
end

function BikeTrackService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	StaminaService = services.StaminaService
end

function BikeTrackService.start()
	for _, part in CollectionService:GetTagged(C.RoadTag) do
		addSegmentFrom(part)
	end
	log("%d road segment(s) loaded", #segments)
	Players.PlayerRemoving:Connect(function(player)
		offRoadSince[player] = nil
		launchReadyAt[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return BikeTrackService
