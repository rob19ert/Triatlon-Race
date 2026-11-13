--!strict
-- Формулы мушки, общие для сервера и клиента.
-- Мушка — маятник: сама ходит слева направо через все мишени и дрожит по вертикали.
-- Игрок не целится, только жмёт «Огонь» вовремя. Сервер по этим же формулам считает,
-- куда ушла пуля в момент выстрела, клиент — рисует мушку.
--
-- Углы в градусах от направления глаз стрелка (на центральную мишень): yaw > 0 — вправо, pitch > 0 — вверх.

local Config = require(script.Parent.Config)

local C = Config.Shooting

local Aim = {}

export type Stance = "Prone" | "Standing"

-- Параметры маятника на одну стрельбу (сервер выбирает при выходе на рубеж и шлёт клиенту).
export type Track = {
	t0: number, -- серверное время старта
	phase0: number, -- начальная фаза, рад
	speed: number, -- рад/с
	hAmp: number, -- размах по горизонтали, градусы
	tremorSeed: number, -- фаза вертикальной дрожи
}

-- Задержки дыхания за эту стрельбу (серверное время).
export type Hold = { start: number, finish: number }

-- Угловая скорость маятника по пульсу на входе (рад/с).
function Aim.pendulumSpeed(pulse: number, stance: Stance): number
	local k = math.clamp((pulse - C.PendulumCalmPulse) / (C.PendulumTiredPulse - C.PendulumCalmPulse), 0, 1)
	local period = C.PendulumPeriodCalm + (C.PendulumPeriodTired - C.PendulumPeriodCalm) * k
	return 2 * math.pi / period * (C.StanceSpeedMultiplier[stance] or 1)
end

function Aim.isHolding(holds: { Hold }, t: number): boolean
	for _, h in holds do
		if t >= h.start and t < h.finish then
			return true
		end
	end
	return false
end

-- Сколько секунд из [a, b] пришлось на задержки дыхания.
local function holdOverlap(holds: { Hold }, a: number, b: number): number
	local total = 0
	for _, h in holds do
		local s, e = math.max(a, h.start), math.min(b, h.finish)
		if e > s then
			total += e - s
		end
	end
	return total
end

-- Фаза маятника: во время задержки дыхания он идёт медленнее (интеграл скорости по времени).
function Aim.phase(track: Track, t: number, holds: { Hold }): number
	local elapsed = math.max(0, t - track.t0)
	local slowed = holdOverlap(holds, track.t0, t)
	return track.phase0 + track.speed * (elapsed - slowed * (1 - C.HoldBreathSpeedMultiplier))
end

-- Размах вертикальной дрожи по текущему пульсу.
function Aim.tremorAmplitude(pulse: number, stance: Stance, holding: boolean): number
	local amp = C.TremorBaseDeg + C.TremorDegPerPulse * math.max(0, pulse - C.PendulumCalmPulse)
	amp *= C.TremorMultiplier[stance] or 1
	if holding then
		amp *= C.HoldBreathTremorMultiplier
	end
	return amp
end

-- Положение мушки (yaw, pitch) в момент t.
function Aim.crosshair(track: Track, t: number, holds: { Hold }, pulse: number, stance: Stance): (number, number)
	local yaw = track.hAmp * math.sin(Aim.phase(track, t, holds))
	local amp = Aim.tremorAmplitude(pulse, stance, Aim.isHolding(holds, t))
	local pitch = amp * math.sin(2 * math.pi * C.TremorFrequency * t + track.tremorSeed)
	return yaw, pitch
end

-- Направление от точки глаз.
function Aim.cframe(eye: CFrame, yawDeg: number, pitchDeg: number): CFrame
	return eye * CFrame.Angles(0, -math.rad(yawDeg), 0) * CFrame.Angles(math.rad(pitchDeg), 0, 0)
end

return Aim
