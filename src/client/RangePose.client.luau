--!strict
-- Стрелок на рубеже (у всех клиентов, только картинка): винтовка и поза рук.
--  * кто стреляет — атрибут RangeOrder у игрока (Player) или у модели бота;
--  * лёжа (сервер кладёт корень лицом вниз) — руки вытянуты вперёд к винтовке, винтовка перед головой у земли;
--  * стоя — винтовка у плеча, руки к ней;
--  * свою винтовку не рисуем: стрелок смотрит в прицел, его тело скрыто (ShootingClient).
-- Поза — Transform суставов поверх анимации (как велосипед в BikeClient), каждый кадр в Stepped.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local R = Config.Shooting.Rifle
local player = Players.LocalPlayer

local folder = Instance.new("Folder")
folder.Name = "Rifles"
folder.Parent = workspace

-- Сустав с Transform: Motor6D или AnimationConstraint (новые аватары Roblox).
local function joint(character: Model, partName: string, jointName: string): any
	local part = character:FindFirstChild(partName)
	local j = part and part:FindFirstChild(jointName)
	if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
		return j
	end
	return nil
end

local function piece(model: Model, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("Offset", offset)
	p.Parent = model
	return p
end

-- Винтовка в своих координатах: ствол вдоль -Z (вперёд), начало — приклад у плеча.
local function buildRifle(): Model
	local model = Instance.new("Model")
	model.Name = "Rifle"
	local wood, metal, accent = R.WoodColor, R.MetalColor, R.AccentColor
	piece(model, Vector3.new(0.32, 0.5, 1.5), CFrame.new(0, -0.08, -0.55), wood, Enum.Material.Wood) -- ложа
	piece(model, Vector3.new(0.3, 0.32, 0.9), CFrame.new(0, -0.02, -1.6), wood, Enum.Material.Wood) -- цевьё
	piece(model, Vector3.new(2.6, 0.16, 0.16), CFrame.new(0, 0.1, -2.2) * CFrame.Angles(0, math.pi / 2, 0), metal, Enum.Material.Metal, Enum.PartType.Cylinder) -- ствол
	piece(model, Vector3.new(0.9, 0.24, 0.24), CFrame.new(0, 0.38, -1.25) * CFrame.Angles(0, math.pi / 2, 0), metal, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder) -- прицел
	piece(model, Vector3.new(0.2, 0.36, 0.3), CFrame.new(0, -0.38, -1.05), accent, Enum.Material.SmoothPlastic) -- магазин
	return model
end

type Shooter = {
	character: Model,
	rifle: Model,
	rightShoulder: any,
	leftShoulder: any,
	rightElbow: any,
	leftElbow: any,
	neck: any,
}

local shooters: { [Instance]: Shooter } = {}

local function clear(key: Instance)
	local s = shooters[key]
	if s then
		s.rifle:Destroy()
		shooters[key] = nil
	end
end

local function shooterFor(key: Instance, character: Model?): Shooter?
	if not character then
		clear(key)
		return nil
	end
	local s = shooters[key]
	if s and s.character == character then
		return s
	end
	clear(key)
	local rifle = buildRifle()
	rifle.Parent = folder
	s = {
		character = character,
		rifle = rifle,
		rightShoulder = joint(character, "RightUpperArm", "RightShoulder"),
		leftShoulder = joint(character, "LeftUpperArm", "LeftShoulder"),
		rightElbow = joint(character, "RightLowerArm", "RightElbow"),
		leftElbow = joint(character, "LeftLowerArm", "LeftElbow"),
		neck = joint(character, "Head", "Neck"),
	}
	shooters[key] = s
	return s
end

-- Кто сейчас на рубеже: игроки (кроме себя) и боты.
local function active(): { [Instance]: Model }
	local list: { [Instance]: Model } = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and typeof(p:GetAttribute(Attributes.RangeOrder)) == "number" and p.Character then
			list[p] = p.Character
		end
	end
	for _, model in CollectionService:GetTagged(Config.Bots.Tag) do
		if model:IsA("Model") and typeof(model:GetAttribute(Attributes.RangeOrder)) == "number" then
			list[model] = model
		end
	end
	return list
end

local function pose(s: Shooter)
	local root = s.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local prone = root.CFrame.UpVector.Y < 0.5 -- сервер кладёт лёжа: «верх» корня смотрит на мишени
	-- «прицельная» рамка: вперёд — на мишени, вверх — вверх (лёжа снимаем наклон корня)
	local aim = if prone then root.CFrame * CFrame.Angles(math.pi / 2, 0, 0) else root.CFrame
	local at = if prone then R.ProneOffset else R.StandingOffset
	local base = aim * at
	for _, p in s.rifle:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = base * (p:GetAttribute("Offset") :: CFrame)
		end
	end
	local P = if prone then R.ProneArms else R.StandingArms
	if s.rightShoulder then
		s.rightShoulder.Transform = CFrame.Angles(math.rad(P.rightShoulder[1]), math.rad(P.rightShoulder[2]), math.rad(P.rightShoulder[3]))
	end
	if s.leftShoulder then
		s.leftShoulder.Transform = CFrame.Angles(math.rad(P.leftShoulder[1]), math.rad(P.leftShoulder[2]), math.rad(P.leftShoulder[3]))
	end
	if s.rightElbow then
		s.rightElbow.Transform = CFrame.Angles(math.rad(P.elbow), 0, 0)
	end
	if s.leftElbow then
		s.leftElbow.Transform = CFrame.Angles(math.rad(P.elbow), 0, 0)
	end
	if s.neck and prone then
		s.neck.Transform = CFrame.Angles(math.rad(R.ProneNeckDeg), 0, 0) -- лёжа — голова поднята к прицелу
	end
end

RunService.Stepped:Connect(function()
	local now = active()
	for key in shooters do
		if not now[key] then
			clear(key)
		end
	end
	for key, character in now do
		local s = shooterFor(key, character)
		if s then
			pose(s)
		end
	end
end)

Players.PlayerRemoving:Connect(clear)
CollectionService:GetInstanceRemovedSignal(Config.Bots.Tag):Connect(clear)
