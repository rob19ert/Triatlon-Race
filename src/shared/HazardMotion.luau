--!strict
-- Движение маятников и мельниц: чистая функция от серверного времени.
-- Одна и та же формула на клиенте (рисует) и на сервере (ловит попадания),
-- поэтому у всех игроков препятствия в одном и том же положении.
-- Вращение — вокруг локальной оси Z детали Pivot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local H = Config.Hazards

export type Kind = "Pendulum" | "Windmill"

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
}

local HazardMotion = {}

local function numberAttr(model: Model, name: string, default: number): number
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
	}
end

-- Угол поворота вокруг оси Pivot в момент серверного времени t.
function HazardMotion.angleAt(h: Hazard, t: number): number
	if h.kind == "Pendulum" then
		return h.amplitude * math.sin(2 * math.pi * (t / h.period + h.phase))
	else
		-- остаток от деления держит угол небольшим (точность float)
		local turn = if h.angularSpeed ~= 0 then 2 * math.pi / math.abs(h.angularSpeed) else 1
		return h.angularSpeed * ((t + h.phase * turn) % turn)
	end
end

function HazardMotion.partCFrame(h: Hazard, mp: MovingPart, angle: number): CFrame
	return h.pivot * CFrame.Angles(0, 0, angle) * mp.offset
end

return HazardMotion
