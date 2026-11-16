--!strict
-- Велосипед у всех клиентов (только картинка): колёса и педали крутятся по пройденному пути,
-- персонаж сидит в позе велосипедиста — корпус вперёд, руки на руле, ноги ходят за педалями.
-- Поза — через Transform суставов поверх анимации (как толчок в PushFx), каждый кадр в Stepped.
-- Модель вешает сервер (BikeService) внутрь персонажа под именем Config.Bike.ModelName.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local C = Config.Bike
local TAU = 2 * math.pi

-- Сустав с Transform: классический Motor6D или AnimationConstraint (новые аватары Roblox).
local function joint(character: Model, partName: string, jointName: string): any
	local part = character:FindFirstChild(partName)
	local j = part and part:FindFirstChild(jointName)
	if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
		return j
	end
	return nil
end

type Rig = {
	r15: boolean,
	waist: any?,
	neck: any?,
	shoulders: { { j: any, cf: CFrame } },
	hips: { any }, -- [1] правое, [2] левое
	knees: { any },
	hipSign: { number }, -- R6: ось бедра повёрнута, знак угла по сторонам
}

type State = {
	character: Model,
	bike: Model,
	rig: Rig,
	distance: number,
	front: Motor6D?,
	rear: Motor6D?,
	crank: Motor6D?,
}

local states: { [Player]: State } = {}

local function buildRig(character: Model): Rig
	local arms = math.rad(C.PoseArmsDeg)
	local rig: Rig = { r15 = character:FindFirstChild("UpperTorso") ~= nil, shoulders = {}, hips = {}, knees = {}, hipSign = {} }
	if rig.r15 then
		rig.waist = joint(character, "UpperTorso", "Waist")
		rig.neck = joint(character, "Head", "Neck")
		for _, spec in { { "RightUpperArm", "RightShoulder" }, { "LeftUpperArm", "LeftShoulder" } } do
			local j = joint(character, spec[1], spec[2])
			if j then
				table.insert(rig.shoulders, { j = j, cf = CFrame.Angles(arms, 0, 0) })
			end
		end
		rig.hips = { joint(character, "RightUpperLeg", "RightHip"), joint(character, "LeftUpperLeg", "LeftHip") }
		rig.knees = { joint(character, "RightLowerLeg", "RightKnee"), joint(character, "LeftLowerLeg", "LeftKnee") }
	else
		-- R6: суставы в Torso, вперёд — поворот вокруг Z со знаком стороны
		for _, spec in { { "Right Shoulder", 1 }, { "Left Shoulder", -1 } } do
			local j = joint(character, "Torso", spec[1] :: string)
			if j then
				table.insert(rig.shoulders, { j = j, cf = CFrame.Angles(0, 0, (spec[2] :: number) * arms) })
			end
		end
		rig.hips = { joint(character, "Torso", "Right Hip"), joint(character, "Torso", "Left Hip") }
		rig.hipSign = { 1, -1 }
	end
	return rig
end

local function motor(bike: Model, name: string): Motor6D?
	local found = bike:FindFirstChild(name, true)
	return if found and found:IsA("Motor6D") then found else nil
end

local function stateFor(player: Player): State?
	if player:GetAttribute(Attributes.Riding) ~= true then
		states[player] = nil
		return nil
	end
	local character = player.Character
	local bike = character and character:FindFirstChild(C.ModelName) :: Model?
	if not character or not bike then
		states[player] = nil
		return nil
	end
	local st = states[player]
	if st and st.character == character and st.bike == bike then
		return st
	end
	st = {
		character = character,
		bike = bike,
		rig = buildRig(character),
		distance = 0,
		front = motor(bike, "FrontWheelMotor"),
		rear = motor(bike, "RearWheelMotor"),
		crank = motor(bike, "CrankMotor"),
	}
	states[player] = st
	return st
end

local function pose(st: State)
	local rig = st.rig
	local phase = st.distance * C.CrankTurnsPerStud * TAU
	local lean = math.rad(C.PoseLeanDeg)
	if rig.waist then
		rig.waist.Transform = CFrame.Angles(-lean, 0, 0)
	end
	if rig.neck then
		rig.neck.Transform = CFrame.Angles(lean * 0.7, 0, 0) -- голова смотрит вперёд, а не в землю
	end
	for _, s in rig.shoulders do
		s.j.Transform = s.cf
	end
	for side = 1, 2 do
		-- правая педаль в начале внизу; левая — напротив. Педаль вверху — бедро выше, колено согнуто сильнее.
		local up = -math.cos(phase + (side - 1) * math.pi) -- −1 внизу … 1 вверху
		local hip = math.rad(C.PoseHipDeg + C.PoseHipSwingDeg * up)
		local knee = math.rad(C.PoseKneeDeg + C.PoseKneeSwingDeg * up)
		local hipJoint = rig.hips[side]
		if hipJoint then
			hipJoint.Transform = if rig.r15 then CFrame.Angles(hip, 0, 0) else CFrame.Angles(0, 0, rig.hipSign[side] * hip)
		end
		local kneeJoint = rig.knees[side]
		if kneeJoint then
			kneeJoint.Transform = CFrame.Angles(-knee, 0, 0)
		end
	end
end

RunService.Stepped:Connect(function(_, dt: number)
	for _, player in Players:GetPlayers() do
		local st = stateFor(player)
		if not st then
			continue
		end
		local root = st.character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			-- катимся назад редко; для простоты крутим только вперёд
			st.distance += speed * dt
		end
		local wheelAngle = st.distance / C.WheelRadius
		if st.front then
			st.front.Transform = CFrame.Angles(-wheelAngle, 0, 0)
		end
		if st.rear then
			st.rear.Transform = CFrame.Angles(-wheelAngle, 0, 0)
		end
		if st.crank then
			st.crank.Transform = CFrame.Angles(-st.distance * C.CrankTurnsPerStud * TAU, 0, 0)
		end
		pose(st)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
