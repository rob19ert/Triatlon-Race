--!strict
-- Велосипед (аркадный): посадка и высадка, всё на сервере.
--  * въехал в зону BikeMount на велоэтапе (отстрелял первый рубеж) — сел на велосипед;
--  * круг: невидимые ворота BikeGate (атрибут Order 1..N) надо пройти по порядку;
--  * въехал в зону BikeDismount, пройдя все ворота, — слез; не пройдя — назад к последним
--    пройденным воротам (или к началу круга, Order 0) и сообщение SkipNotice. Срезать круг нельзя.
--  * на велосипеде: свои скорости и пульс (StaminaService.setBike), прыгать можно;
--    модель (клон ServerStorage/BikeTemplate) приварена к HumanoidRootPart, колёса и позу крутят клиенты.
-- Состояние для клиентов — атрибут Riding на Player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Zone = require(script.Parent.Parent.Lib.Zone)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local C = Config.Bike

local BikeService = {}

local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local StaminaService: any

local riding: { [Player]: boolean } = {}
local noticeRemote: RemoteEvent

-- ворота круга по порядку; gates[0] — начало круга (куда возвращать, если ни одни не пройдены)
local gates: { [number]: BasePart } = {}
local lastGateOrder = 0
-- прогресс по кругу на велоэтапе: следующий номер ворот (lastGateOrder + 1 = круг пройден)
local nextGate: { [Player]: number } = {}

local function log(fmt: string, ...: any)
	print("[BikeService] " .. string.format(fmt, ...))
end

-- зоны и ворота — «колонной»: перепрыгнуть нельзя
local isInside = Zone.inColumn

local function inTagged(tag: string, position: Vector3): boolean
	for _, zone in CollectionService:GetTagged(tag) do
		if zone:IsA("BasePart") and isInside(zone, position) then
			return true
		end
	end
	return false
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

---------------------------------------------------------------- модель

local template = ServerStorage:FindFirstChild(C.TemplateName) :: Model?

local function detachBike(character: Model?)
	local bike = character and character:FindFirstChild(C.ModelName)
	if bike then
		bike:Destroy()
	end
end

-- Велосипед под персонажем: Root шаблона — у земли, поэтому опускаем на высоту бёдер + половину корня.
local function attachBike(player: Player, character: Model)
	if not template or character:FindFirstChild(C.ModelName) then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local bike = template:Clone()
	bike.Name = C.ModelName
	local color = C.Colors[player.UserId % #C.Colors + 1]
	for _, part in bike:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") == true then
			part.Color = color
		end
	end
	local bikeRoot = bike.PrimaryPart :: BasePart
	local offset = CFrame.new(0, -(humanoid.HipHeight + root.Size.Y / 2), 0)
	bike:PivotTo(root.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = bikeRoot
	weld.C0 = offset
	weld.Parent = bikeRoot
	bike.Parent = character
end

local function setRiding(player: Player, on: boolean, reason: string)
	if (riding[player] == true) == on then
		return
	end
	riding[player] = if on then true else nil
	player:SetAttribute(Attributes.Riding, if on then true else nil)
	StaminaService.setBike(player, on)
	if on and player.Character then
		attachBike(player, player.Character)
	else
		detachBike(player.Character)
	end
	log("%s %s (%s)", player.Name, if on then "mounted" else "dismounted", reason)
	if on then
		noticeRemote:FireClient(player, Config.Drift.MountHint)
	end
end

---------------------------------------------------------------- круг

local function loadGates()
	for _, part in CollectionService:GetTagged(C.GateTag) do
		local order = part:GetAttribute("Order")
		if part:IsA("BasePart") and typeof(order) == "number" then
			if gates[order] then
				warn(string.format("[BikeService] duplicate BikeGate Order %d", order))
			end
			gates[order] = part
			lastGateOrder = math.max(lastGateOrder, order)
		end
	end
	for order = 0, lastGateOrder do
		if not gates[order] then
			warn(string.format("[BikeService] BikeGate Order %d missing", order))
		end
	end
end

local function updateGates(player: Player, position: Vector3)
	local order = nextGate[player] or 1
	local gate = gates[order]
	if gate and isInside(gate, position) then
		nextGate[player] = order + 1
		log("%s passed gate %d/%d", player.Name, order, lastGateOrder)
	end
end

local function loopDone(player: Player): boolean
	return (nextGate[player] or 1) > lastGateOrder
end

-- Срезал круг: назад к последним пройденным воротам, лицом по ходу.
local function sendBack(player: Player, character: Model, root: BasePart)
	local gate = gates[(nextGate[player] or 1) - 1] or gates[0]
	if not gate then
		return
	end
	local forward = gate.CFrame.LookVector * Vector3.new(1, 0, 1)
	local base = gate.Position - Vector3.new(0, gate.Size.Y / 2, 0)
	local pos = Vector3.new(base.X, base.Y + Config.Track.RespawnHeight, base.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(pos, pos + forward.Unit))
	noticeRemote:FireClient(player, C.SkipNotice)
	log("%s skipped the loop -> back to gate %d", player.Name, (nextGate[player] or 1) - 1)
end

local function step()
	local racing = RaceManager.getState() == "Racing"
	for _, player in Players:GetPlayers() do
		local tracked = racing and RaceManager.isParticipant(player) and ProgressTracker.isTracked(player)
		local stages = if tracked then ShootingService.getCompletedStages(player) else 0
		if not tracked or stages ~= 1 then
			nextGate[player] = nil
		end
		if riding[player] and (not tracked or stages >= 2) then
			setRiding(player, false, if not tracked then "not racing" else "stage done")
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = getHumanoid(player)
		if not tracked or not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		if stages ~= 1 or ShootingService.isShooting(player) then
			continue
		end
		updateGates(player, root.Position)
		if inTagged(C.DismountTag, root.Position) then
			-- и пешком без круга (как-то обошёл посадку) дальше не пускаем
			if not loopDone(player) then
				sendBack(player, character :: Model, root)
			elseif riding[player] then
				setRiding(player, false, "dismount zone")
			end
		elseif riding[player] then
			-- новый персонаж (респавн) — снова с велосипедом
			attachBike(player, character :: Model)
		elseif inTagged(C.MountTag, root.Position) and not loopDone(player) then
			nextGate[player] = 1
			setRiding(player, true, "mount zone")
		end
	end
end

function BikeService.isRiding(player: Player): boolean
	return riding[player] == true
end

function BikeService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	StaminaService = services.StaminaService
	noticeRemote = Remotes.get(Remotes.Names.Notice)
end

function BikeService.start()
	if not template then
		warn("[BikeService] ServerStorage." .. C.TemplateName .. " not found — riding without a bike model")
	end
	loadGates()
	log("%d loop gate(s)", lastGateOrder)
	Players.PlayerRemoving:Connect(function(player)
		riding[player] = nil
		nextGate[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return BikeService
