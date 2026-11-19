--!strict
-- Камера за спиной вдоль дороги: доворачивать её на поворотах не нужно.
--  * на велокруге — по оси куска дороги (BikeRoad) под игроком, вне дороги — по направлению бега;
--  * поворачиваем только по горизонтали вокруг точки фокуса, наклон и зум — как выставил игрок;
--  * игрок сам повернул камеру (мышь, палец, стик) — авто ждёт ResumeAfter, потом плавно возвращает;
--  * телепорт (возврат на чекпоинт, срезал круг) — сразу ставим камеру за спину;
--  * только для своей обычной камеры: прицел, подиум и режим зрителя не трогаем.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

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

	local now = os.clock()
	local look = flat(camera.CFrame.LookVector)
	if not look then
		return
	end
	local yaw = yawOf(look)
	if lastYaw and math.abs(wrap(yaw - lastYaw)) > C.ManualEps then
		manualUntil = now + C.ResumeAfter
	end

	local pos = root.Position
	local teleported = lastPos ~= nil and (pos - (lastPos :: Vector3)).Magnitude > C.SnapDistance
	lastPos = pos

	if teleported then
		local forward = flat(root.CFrame.LookVector)
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
	if now >= manualUntil and speed >= C.MinSpeed and velocity then
		-- дорога чуть впереди (поворот начинаем заранее), иначе под ногами
		local axis = roadAxis(pos + velocity * C.LookAhead, look) or roadAxis(pos, look)
		local intent = flat(humanoid.MoveDirection)
		if axis then
			-- ось без знака: берём сторону, куда уже смотрит камера (едешь назад — не разворачиваем)
			target = if axis:Dot(look) >= 0 then axis else -axis
		elseif intent and velocity:Dot(intent) >= C.IntentCos and velocity:Dot(look) >= MAX_COS then
			-- вне дороги — за бегом, но только если бежим куда жмём (толчок и маятник камеру не крутят)
			target = velocity
		end
	end

	if target then
		local alpha = 1 - math.exp(-C.TurnSpeed * dt)
		local delta = wrap(yawOf(target) - yaw) * alpha
		rotate(camera, delta)
		lastYaw = yaw + delta
	else
		lastYaw = yaw
	end
end)
