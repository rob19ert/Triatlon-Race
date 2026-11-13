--!strict
-- Формулы прицела, общие для сервера и клиента.
-- Сервер по ним считает реальное направление выстрела, клиент — рисует ту же картинку.

local Config = require(script.Parent.Config)

local C = Config.Shooting

local Aim = {}

export type Stance = "Prone" | "Standing"

function Aim.swayAmplitude(pulse: number, stance: Stance, holdingBreath: boolean): number
	local amp = C.SwayBaseDeg + C.SwayDegPerPulse * math.max(0, pulse - C.SwayPulseOffset)
	amp *= C.SwayMultiplier[stance] or 1
	if holdingBreath then
		amp *= C.HoldBreathSwayMultiplier
	end
	return amp
end

-- Смещение прицела (yaw, pitch в градусах) в момент t (workspace:GetServerTimeNow()).
-- Восьмёрка: по горизонтали sin(wt), по вертикали sin(2wt) с половинной амплитудой.
function Aim.swayOffset(t: number, pulse: number, stance: Stance, holdingBreath: boolean): (number, number)
	local amp = Aim.swayAmplitude(pulse, stance, holdingBreath)
	local w = 2 * math.pi * C.SwayFrequency
	return amp * math.sin(w * t), amp * 0.5 * math.sin(2 * w * t)
end

-- Ветер в градусах по горизонтали; windLevel со знаком (+ вправо от стрелка).
function Aim.windYaw(windLevel: number): number
	return windLevel * C.WindDegPerLevel
end

-- Направление от точки глаз: yaw > 0 — вправо, pitch > 0 — вверх.
function Aim.cframe(eye: CFrame, yawDeg: number, pitchDeg: number): CFrame
	return eye * CFrame.Angles(0, -math.rad(yawDeg), 0) * CFrame.Angles(math.rad(pitchDeg), 0, 0)
end

return Aim
