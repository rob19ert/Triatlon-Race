--!strict
-- Камера на велокруге (только пока игрок на велосипеде): за спиной вдоль дороги, доворачивать не нужно.
-- Пешком (бег с препятствиями, лобби) — обычная камера Roblox, этот скрипт её не трогает.
--  * в гонке — привязана к линии трассы (CoursePath — маршрут ботов, с упреждением PathLookAhead):
--    всегда смотрит вперёд по трассе, удары и толчки её не крутят; оглянуться — потянуть камеру,
--    через LookBackTime она вернётся вперёд; после возврата на чекпоинт — сразу вперёд по трассе;
--  * далеко от линии (срезки) — по оси куска дороги BikeRoad, совсем вне трассы — по направлению бега;
--  * поворачиваем только по горизонтали вокруг точки фокуса, наклон и зум — как выставил игрок;
--  * игрок сам повернул камеру (мышь, палец, стик) — авто ждёт ResumeAfter, потом плавно возвращает;
--  * телепорт (возврат на чекпоинт, срезал круг) — сразу ставим камеру за спину;
--  * только для своей обычной камеры: прицел, подиум и режим зрителя не трогаем.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local C = Config.FollowCamera
if not C.Enabled then
	return
end

local player = Players.LocalPlayer
local FLAT = Vector3.new(1, 0, 1)
local MAX_COS = math.cos(math.rad(C.MaxAngle))

local roads: { BasePart } = {}
local function addRoad(inst: Instance)
	if inst:IsA("BasePart") and not table.find(roads, inst) then
		table.insert(roads, inst)
	end
end
local function removeRoad(inst: Instance)
	local i = table.find(roads, inst :: any)
	if i then
		table.remove(roads, i)
	end
end
for _, inst in CollectionService:GetTagged(Config.Bike.RoadTag) do
	addRoad(inst)
end
CollectionService:GetInstanceAddedSignal(Config.Bike.RoadTag):Connect(addRoad)
CollectionService:GetInstanceRemovedSignal(Config.Bike.RoadTag):Connect(removeRoad)

-- Линия трассы — только в гонке (в лобби у старта камера не разворачивается к трассе)
local racing = false
Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: any)
	racing = payload.state == "Racing"
end)

-- Линия трассы: точки по порядку (сервер кладёт их в ReplicatedStorage при старте).
local path: { Vector3 } = {}
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(C.PathFolder, 30)
	if not folder then
		return
	end
	task.wait(1) -- точки дозаливаются вместе с папкой
	local items = folder:GetChildren()
	table.sort(items, function(a, b)
		return a.Name < b.Name
	end)
	local list = {}
	for _, item in items do
		if item:IsA("Vector3Value") then
			table.insert(list, item.Value)
		end
	end
	path = list
end)

-- Направление трассы у точки pos: проекция на ближайший отрезок, затем точка на PathLookAhead дальше.
local function pathDirection(pos: Vector3): Vector3?
	if #path < 2 then
		return nil
	end
	local p = pos * FLAT
	local bestJ, bestT, bestD = 0, 0, math.huge
	for j = 1, #path - 1 do
		local a = path[j] * FLAT
		local ab = path[j + 1] * FLAT - a
		local len2 = ab:Dot(ab)
		local t = if len2 > 1e-6 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
		local d = (p - (a + ab * t)).Magnitude
		if d < bestD then
			bestJ, bestT, bestD = j, t, d
		end
	end
	if bestD > C.PathMaxDistance then
		return nil
	end
	local from = path[bestJ] * FLAT + (path[bestJ + 1] - path[bestJ]) * FLAT * bestT
	-- пройти LookAhead по линии вперёд
	local left = C.PathLookAhead
	local cur = from
	local j = bestJ
	while j < #path do
		local nextPoint = path[j + 1] * FLAT
		local seg = (nextPoint - cur).Magnitude
		if seg >= left then
			cur = cur + (nextPoint - cur).Unit * left
			left = 0
			break
		end
		left -= seg
		cur = nextPoint
		j += 1
	end
	local dir = cur - from
	return if dir.Magnitude > 1e-3 then dir.Unit else nil
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function flat(v: Vector3): Vector3?
	local f = v * FLAT
	return if f.Magnitude > 1e-3 then f.Unit else nil
end

-- Ось дороги под игроком, или nil. На развилке, где куски перекрываются, — тот, что ближе
-- к своей центральной линии и меньше расходится с камерой (не дёргаемся на соседнюю ветку).
local function roadAxis(pos: Vector3, look: Vector3): Vector3?
	local best: Vector3? = nil
	local bestScore = math.huge
	for _, seg in roads do
		local p = seg.CFrame:PointToObjectSpace(pos)
		local halfX = seg.Size.X / 2
		if
			math.abs(p.X) <= halfX + C.RoadMargin
			and math.abs(p.Z) <= seg.Size.Z / 2 + C.RoadMargin
			and p.Y > -4
			and p.Y < 20
		then
			local axis = flat(seg.CFrame.LookVector)
			if axis then
				local score = math.abs(p.X) / halfX + (1 - math.abs(axis:Dot(look)))
				if score < bestScore then
					best = axis
					bestScore = score
				end
			end
		end
	end
	return best
end

local lastYaw: number? = nil -- куда смотрела камера после нашего доворота в прошлом кадре
local lastPos: Vector3? = nil
local manualUntil = 0

local function reset()
	lastYaw = nil
	lastPos = nil
end

local function rotate(camera: Camera, delta: number)
	local focus = camera.Focus.Position
	camera.CFrame = CFrame.new(focus) * CFrame.Angles(0, delta, 0) * CFrame.new(-focus) * camera.CFrame
end

-- После стандартного модуля камеры (он строит кадр от текущего LookVector, так что доворот сохраняется).
RunService:BindToRenderStep("FollowCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if
		not camera
		or not humanoid
		or not root
		or humanoid.Health <= 0
		or camera.CameraType ~= Enum.CameraType.Custom
		or camera.CameraSubject ~= humanoid
	then
		reset()
		return
	end

	-- только на велосипеде: пешком (бег с препятствиями, лобби, финиш) камера целиком у игрока —
	-- никаких доворотов, они мешают управлению
	if player:GetAttribute(Attributes.Riding) ~= true then
		reset()
		return
	end

	local now = os.clock()
	local look = flat(camera.CFrame.LookVector)
	if not look then
		return
	end
	local yaw = yawOf(look)
	local pos = root.Position
	-- в гонке на трассе — камера привязана к трассе
	local course = if racing then pathDirection(pos) else nil
	if lastYaw and math.abs(wrap(yaw - lastYaw)) > C.ManualEps then
		-- игрок сам повернул камеру: оглянуться можно, потом — назад вперёд
		manualUntil = now + (if course then C.LookBackTime else C.ResumeAfter)
	end

	local teleported = lastPos ~= nil and (pos - (lastPos :: Vector3)).Magnitude > C.SnapDistance
	lastPos = pos

	if teleported then
		-- вернули на чекпоинт: вперёд по трассе (персонаж в этот момент может ещё кувыркаться после удара)
		local forward = course or flat(root.CFrame.LookVector)
		if forward then
			manualUntil = 0
			rotate(camera, wrap(yawOf(forward) - yaw))
			lastYaw = yawOf(forward)
			return
		end
	end

	local target: Vector3? = nil
	local velocity = flat(root.AssemblyLinearVelocity)
	local speed = (root.AssemblyLinearVelocity * FLAT).Magnitude
	local intent = flat(humanoid.MoveDirection)
	local turnSpeed = C.TurnSpeed
	if course then
		-- привязка к трассе: всегда (стоит, бежит, сбили), кроме момента, когда игрок сам оглядывается
		if now >= manualUntil then
			target = course
			turnSpeed = C.LockTurnSpeed
		end
	elseif now >= manualUntil and speed >= C.MinSpeed and velocity then
		-- срезка — ось дороги, иначе — бег
		local axis = roadAxis(pos + velocity * C.LookAhead, look) or roadAxis(pos, look)
		if axis then
			-- ось без знака: берём сторону, куда уже смотрит камера (едешь назад — не разворачиваем)
			target = if axis:Dot(look) >= 0 then axis else -axis
		elseif intent and velocity:Dot(intent) >= C.IntentCos and velocity:Dot(look) >= MAX_COS then
			-- вне дороги — за бегом, но только если бежим куда жмём (толчок и маятник камеру не крутят)
			target = velocity
		end
	end

	if target then
		local alpha = 1 - math.exp(-turnSpeed * dt)
		local delta = wrap(yawOf(target) - yaw) * alpha
		rotate(camera, delta)
		lastYaw = yaw + delta
	else
		lastYaw = yaw
	end
end)
