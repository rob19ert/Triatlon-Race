--!strict
-- Движение подвижных препятствий: чистая функция от серверного времени.
-- Одна и та же формула на клиенте (рисует) и на сервере (ловит попадания),
-- поэтому у всех игроков препятствия в одном и том же положении.
--
-- Виды:
--  * Pendulum — качание вокруг локальной оси Z детали Pivot (атрибуты Period, AmplitudeDeg, Phase 0–1);
--  * Windmill — вращение вокруг оси Z Pivot (Rpm, Phase);
--  * Shuttle  — поезд: раз в Period секунд, начиная с Delay, едет вперёд (−Z Pivot) на Distance
--               со скоростью Speed, остальное время стоит в начале (спрятан в депо/тоннеле);
--  * Gate     — шлагбаум: опущен (поворот на −90° вокруг Z Pivot), пока по расписанию закрыто
--               (Period, ClosedFrom, ClosedTo — секунды внутри периода).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local H = Config.Hazards

export type Kind = "Pendulum" | "Windmill" | "Shuttle" | "Gate"

export type MovingPart = {
	part: BasePart,
	offset: CFrame, -- положение относительно Pivot в покое
	hits: boolean,
}

export type Hazard = {
	model: Model,
	kind: Kind,
	pivot: CFrame, -- положение Pivot в покое
	parts: { MovingPart },
	period: number,
	amplitude: number, -- рад
	angularSpeed: number, -- рад/с (мельница)
	phase: number, -- 0–1
	-- поезд
	delay: number, -- с от начала периода до старта
	distance: number, -- стад
	speed: number, -- стад/с
	-- шлагбаум
	closedFrom: number,
	closedTo: number,
}

local HazardMotion = {}

local GATE_MOVE_TIME = 0.6 -- с, шлагбаум опускается/поднимается

local function numberAttr(model: Instance, name: string, default: number): number
	local v = model:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

-- Снять «позу покоя» с модели. Вызывать до того, как её начали двигать.
function HazardMotion.load(model: Model, kind: Kind): Hazard?
	local pivotPart = model:FindFirstChild(H.PivotName)
	if not pivotPart or not pivotPart:IsA("BasePart") then
		warn("[HazardMotion] " .. model:GetFullName() .. " has no Pivot part")
		return nil
	end
	local pivot = pivotPart.CFrame
	local parts: { MovingPart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= pivotPart then
			table.insert(parts, {
				part = d,
				offset = pivot:ToObjectSpace(d.CFrame),
				hits = d:GetAttribute(H.HitsAttribute) == true,
			})
		end
	end
	local rpm = numberAttr(model, "Rpm", H.WindmillRpm)
	return {
		model = model,
		kind = kind,
		pivot = pivot,
		parts = parts,
		period = numberAttr(model, "Period", H.PendulumPeriod),
		amplitude = math.rad(numberAttr(model, "AmplitudeDeg", H.PendulumAmplitudeDeg)),
		angularSpeed = rpm * 2 * math.pi / 60,
		phase = numberAttr(model, "Phase", 0),
		delay = numberAttr(model, "Delay", 0),
		distance = numberAttr(model, "Distance", 0),
		speed = numberAttr(model, "Speed", 40),
		closedFrom = numberAttr(model, "ClosedFrom", 0),
		closedTo = numberAttr(model, "ClosedTo", 0),
	}
end

-- Расписание по периоду: закрыт ли переезд в момент t (для шлагбаумов, огней и твёрдой стенки).
function HazardMotion.isClosed(period: number, closedFrom: number, closedTo: number, t: number): boolean
	local local_ = t % period
	return local_ >= closedFrom and local_ < closedTo
end

-- «Положение» препятствия в момент t: угол (маятник, мельница, шлагбаум) или пройденный путь (поезд).
function HazardMotion.angleAt(h: Hazard, t: number): number
	if h.kind == "Pendulum" then
		return h.amplitude * math.sin(2 * math.pi * (t / h.period + h.phase))
	elseif h.kind == "Shuttle" then
		local local_ = (t % h.period) - h.delay
		if local_ <= 0 then
			return 0
		end
		return math.min(h.distance, local_ * h.speed)
	elseif h.kind == "Gate" then
		-- 0 — поднят, 1 — опущен; плавно за GATE_MOVE_TIME
		local local_ = t % h.period
		local k
		if local_ < h.closedFrom then
			k = 0 -- до закрытия поднят
		elseif local_ < h.closedFrom + GATE_MOVE_TIME then
			k = (local_ - h.closedFrom) / GATE_MOVE_TIME
		elseif local_ < h.closedTo then
			k = 1
		elseif local_ < h.closedTo + GATE_MOVE_TIME then
			k = 1 - (local_ - h.closedTo) / GATE_MOVE_TIME
		else
			k = 0
		end
		return -math.rad(90) * k
	else
		-- остаток от деления держит угол небольшим (точность float)
		local turn = if h.angularSpeed ~= 0 then 2 * math.pi / math.abs(h.angularSpeed) else 1
		return h.angularSpeed * ((t + h.phase * turn) % turn)
	end
end

function HazardMotion.partCFrame(h: Hazard, mp: MovingPart, value: number): CFrame
	if h.kind == "Shuttle" then
		return h.pivot * CFrame.new(0, 0, -value) * mp.offset
	end
	return h.pivot * CFrame.Angles(0, 0, value) * mp.offset
end

return HazardMotion
