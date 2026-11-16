--!strict
-- Траектория вертикальной петли: окружность в вертикальной плоскости, выход смещён вбок от входа
-- (полосы заезда и выезда идут рядом, как у настоящей петли).
-- Одна формула для сервера (конец заезда), клиентов (плавное ведение велосипедиста) и постройки кольца.
--
-- origin — основание петли на полотне: LookVector = направление движения, Position — центр дороги.
-- theta от 0 до 2π: 0 — вход (внизу, слева), π — верхняя точка (вниз головой), 2π — выход (внизу, справа).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local B = Config.Bike
local TAU = 2 * math.pi

local LoopPath = {}

-- Смещение вбок: плавно от −S/2 до +S/2, у входа и выхода боковой скорости нет.
function LoopPath.lateral(theta: number): number
	return B.LoopSideShift * ((theta - math.sin(theta)) / TAU - 0.5)
end

-- Точка на полотне и ориентация: Look = касательная, Up = внутрь кольца (туда, где «пол» велосипедиста).
function LoopPath.surface(origin: CFrame, theta: number): CFrame
	local r = B.LoopRadius
	local pos = origin:PointToWorldSpace(Vector3.new(LoopPath.lateral(theta), r * (1 - math.cos(theta)), -r * math.sin(theta)))
	local sideRate = B.LoopSideShift * (1 - math.cos(theta)) / TAU
	local tangent = origin:VectorToWorldSpace(Vector3.new(sideRate, r * math.sin(theta), -r * math.cos(theta)))
	local inward = origin:VectorToWorldSpace(Vector3.new(0, math.cos(theta), math.sin(theta)))
	return CFrame.lookAt(pos, pos + tangent, inward)
end

-- Положение корня персонажа (HumanoidRootPart) на параметре theta.
function LoopPath.rider(origin: CFrame, theta: number): CFrame
	return LoopPath.surface(origin, theta) * CFrame.new(0, B.LoopRiderHeight, 0)
end

return LoopPath
