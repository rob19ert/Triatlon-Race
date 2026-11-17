--!strict
-- Проверки «игрок в зоне» по позиции (без Touched).
--  * inside — строго внутри детали;
--  * inColumn — внутри по горизонтали и не ниже дна, сверху — до Track.ZoneColumnHeight над зоной:
--    перепрыгнуть зону (низкая гравитация, пружина, трамплин) нельзя, она всё равно засчитается.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Zone = {}

function Zone.inside(zone: BasePart, position: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

function Zone.inColumn(zone: BasePart, position: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X
		and math.abs(p.Z) <= half.Z
		and p.Y >= -half.Y
		and p.Y <= half.Y + Config.Track.ZoneColumnHeight
end

return Zone
