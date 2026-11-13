--!strict
-- Живые болельщики на трибунах. Целиком на клиенте: детали создаются локально
-- (не реплицируются), сервер о них не знает.
--  * рассаживаются по рядам с тегом StandRow (атрибут Facing — куда смотреть);
--  * в покое слегка покачиваются;
--  * прыгают и машут, когда рядом пробегает гонщик или кто-то финишировал;
--  * дальше AnimateRadius от камеры замирают — экономим кадр на телефонах.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local C = Config.Crowd

local SHIRTS = {
	Color3.fromRGB(235, 60, 60), Color3.fromRGB(60, 140, 255), Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(60, 190, 90), Color3.fromRGB(255, 130, 200), Color3.fromRGB(150, 90, 230),
	Color3.fromRGB(255, 150, 40), Color3.fromRGB(245, 245, 245),
}
local SKINS = {
	Color3.fromRGB(255, 220, 180), Color3.fromRGB(235, 190, 140), Color3.fromRGB(200, 150, 100),
	Color3.fromRGB(150, 100, 65), Color3.fromRGB(100, 70, 45),
}
local FLAGS = { Color3.fromRGB(255, 60, 60), Color3.fromRGB(60, 140, 255), Color3.fromRGB(255, 210, 40) }

type Fan = {
	parts: { BasePart },
	offsets: { CFrame }, -- от базовой точки фаната
	base: CFrame, -- стоит на сиденье, смотрит на трассу
	phase: number,
	speedJitter: number,
	cheer: number, -- 0..1, сглаженное возбуждение
	cheerTarget: number,
}

local folder = Instance.new("Folder")
folder.Name = "CrowdLocal"
folder.Parent = workspace

local fansByRow: { [Instance]: { Fan } } = {}
local rng = Random.new()

local function newPart(size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	if shape then
		p.Shape = shape
	end
	return p
end

local function makeFan(base: CFrame): Fan
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function add(p: BasePart, offset: CFrame)
		p.CFrame = base * offset
		p.Parent = folder
		table.insert(parts, p)
		table.insert(offsets, offset)
	end
	add(newPart(Vector3.new(1.3, 1.6, 0.9), SHIRTS[rng:NextInteger(1, #SHIRTS)]), CFrame.new(0, 0.8, 0))
	add(newPart(Vector3.new(1.1, 1.1, 1.1), SKINS[rng:NextInteger(1, #SKINS)], Enum.PartType.Ball), CFrame.new(0, 2.15, 0))
	if rng:NextNumber() < C.PropChance then
		-- флажок на палке в поднятой руке
		add(newPart(Vector3.new(0.15, 2.2, 0.15), Color3.fromRGB(90, 60, 40)), CFrame.new(0.75, 2.2, 0))
		add(newPart(Vector3.new(0.1, 0.9, 1.4), FLAGS[rng:NextInteger(1, #FLAGS)]), CFrame.new(0.75, 2.85, 0.7))
	end
	return {
		parts = parts,
		offsets = offsets,
		base = base,
		phase = rng:NextNumber(0, math.pi * 2),
		speedJitter = rng:NextNumber(0.85, 1.15),
		cheer = 0,
		cheerTarget = 0,
	}
end

local function fillRow(row: Instance)
	if fansByRow[row] or not row:IsA("BasePart") then
		return
	end
	local facing = row:GetAttribute("Facing")
	local dir = Vector3.new(if typeof(facing) == "number" then facing else 1, 0, 0)
	local fans: { Fan } = {}
	local length = row.Size.Z
	local top = row.Position.Y + row.Size.Y / 2
	local z = -length / 2 + C.SeatSpacing / 2
	while z <= length / 2 - C.SeatSpacing / 2 do
		if rng:NextNumber() < C.FillChance then
			local pos = row.CFrame:PointToWorldSpace(Vector3.new(0, 0, z))
			local basePos = Vector3.new(pos.X, top, pos.Z)
			table.insert(fans, makeFan(CFrame.lookAt(basePos, basePos + dir)))
		end
		z += C.SeatSpacing
	end
	fansByRow[row] = fans
end

local function clearRow(row: Instance)
	local fans = fansByRow[row]
	if not fans then
		return
	end
	for _, fan in fans do
		for _, p in fan.parts do
			p:Destroy()
		end
	end
	fansByRow[row] = nil
end

for _, row in CollectionService:GetTagged(C.RowTag) do
	fillRow(row)
end
-- при стриминге ряды приходят и уходят
CollectionService:GetInstanceAddedSignal(C.RowTag):Connect(fillRow)
CollectionService:GetInstanceRemovedSignal(C.RowTag):Connect(clearRow)

---------------------------------------------------------------- кто ликует

local raceState: Types.RaceState = "Lobby"
local cheerAllUntil = 0

Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	if payload.state == "Racing" and raceState ~= "Racing" then
		cheerAllUntil = os.clock() + C.CheerOnFinishTime -- старт!
	end
	raceState = payload.state
end)
Remotes.get(Remotes.Names.PlayerFinished).OnClientEvent:Connect(function()
	cheerAllUntil = os.clock() + C.CheerOnFinishTime
end)

local function racerPositions(): { Vector3 }
	local list = {}
	if raceState ~= "Racing" then
		return list
	end
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(list, root.Position)
		end
	end
	return list
end

local function updateTargets()
	local all = os.clock() < cheerAllUntil
	local racers = racerPositions()
	local r2 = C.CheerRadius * C.CheerRadius
	for _, fans in fansByRow do
		for _, fan in fans do
			local target = 0
			if all then
				target = 1
			else
				local p = fan.base.Position
				for _, rp in racers do
					local dx, dz = rp.X - p.X, rp.Z - p.Z
					if dx * dx + dz * dz < r2 then
						target = 1
						break
					end
				end
			end
			fan.cheerTarget = target
		end
	end
end

---------------------------------------------------------------- анимация

local updateAccumulator = 0
local movedParts: { BasePart } = {}
local movedCFrames: { CFrame } = {}

RunService.Heartbeat:Connect(function(dt)
	updateAccumulator += dt
	if updateAccumulator >= C.UpdateInterval then
		updateAccumulator = 0
		updateTargets()
	end

	local camPos = workspace.CurrentCamera.CFrame.Position
	local radius2 = C.AnimateRadius * C.AnimateRadius
	local t = os.clock()
	local blend = math.clamp(dt * 4, 0, 1)
	table.clear(movedParts)
	table.clear(movedCFrames)

	for _, fans in fansByRow do
		for _, fan in fans do
			local d = fan.base.Position - camPos
			if d.X * d.X + d.Z * d.Z > radius2 then
				continue -- далеко: стоит как стоял
			end
			fan.cheer += (fan.cheerTarget - fan.cheer) * blend
			local idle = math.sin(t * C.IdleSpeed * fan.speedJitter + fan.phase) * C.IdleBob
			local jump = math.abs(math.sin(t * C.CheerSpeed * fan.speedJitter + fan.phase)) * C.CheerJump
			local y = idle * (1 - fan.cheer) + jump * fan.cheer
			-- при ликовании ещё и покачиваются из стороны в сторону
			local sway = math.sin(t * C.CheerSpeed * 0.5 + fan.phase) * 0.25 * fan.cheer
			local root = fan.base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, sway)
			for i, p in fan.parts do
				table.insert(movedParts, p)
				table.insert(movedCFrames, root * fan.offsets[i])
			end
		end
	end
	if #movedParts > 0 then
		workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
