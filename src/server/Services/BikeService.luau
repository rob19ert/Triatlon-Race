--!strict
-- Велосипед (аркадный): посадка и высадка, всё на сервере.
--  * въехал в зону BikeMount на велоэтапе (отстрелял первый рубеж) — сел на велосипед;
--    на всякий случай садим и западнее стадиона, если зону как-то проскочил;
--  * въехал в зону BikeDismount — слез;
--  * на велосипеде: свои скорости и пульс (StaminaService.setBike), прыжок выключен.
-- Состояние для клиентов — атрибут Riding на Player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local C = Config.Bike

local BikeService = {}

local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local StaminaService: any

local riding: { [Player]: boolean } = {}
-- прыжок до посадки, чтобы вернуть после высадки
local savedJump: { [Humanoid]: { power: number, height: number } } = setmetatable({}, { __mode = "k" }) :: any

local function log(fmt: string, ...: any)
	print("[BikeService] " .. string.format(fmt, ...))
end

local function isInside(zone: BasePart, position: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

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

local function setJumpEnabled(humanoid: Humanoid, enabled: boolean)
	if enabled then
		local saved = savedJump[humanoid]
		if saved then
			humanoid.JumpPower = saved.power
			humanoid.JumpHeight = saved.height
			savedJump[humanoid] = nil
		end
	elseif not savedJump[humanoid] then
		savedJump[humanoid] = { power = humanoid.JumpPower, height = humanoid.JumpHeight }
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end

local function setRiding(player: Player, on: boolean)
	if (riding[player] == true) == on then
		return
	end
	riding[player] = if on then true else nil
	player:SetAttribute(Attributes.Riding, if on then true else nil)
	StaminaService.setBike(player, on)
	local humanoid = getHumanoid(player)
	if humanoid then
		setJumpEnabled(humanoid, not on)
	end
	log("%s %s", player.Name, if on then "mounted" else "dismounted")
end

local function step()
	local racing = RaceManager.getState() == "Racing"
	for _, player in Players:GetPlayers() do
		local tracked = racing and RaceManager.isParticipant(player) and ProgressTracker.isTracked(player)
		local stages = if tracked then ShootingService.getCompletedStages(player) else 0
		if riding[player] and (not tracked or stages >= 2) then
			setRiding(player, false)
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = getHumanoid(player)
		if not tracked or not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		if riding[player] then
			-- новый персонаж (респавн) — снова без прыжка
			setJumpEnabled(humanoid, false)
			if inTagged(C.DismountTag, root.Position) then
				setRiding(player, false)
			end
		elseif stages == 1 and not ShootingService.isShooting(player) then
			if inTagged(C.MountTag, root.Position) or root.Position.X < C.StadiumEdgeX then
				setRiding(player, true)
			end
		end
	end
end

function BikeService.isRiding(player: Player): boolean
	return riding[player] == true
end

-- Только для дев-команды: сесть / слезть вне зон.
function BikeService.toggle(player: Player): boolean
	setRiding(player, not riding[player])
	return riding[player] == true
end

function BikeService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	StaminaService = services.StaminaService
end

function BikeService.start()
	Players.PlayerRemoving:Connect(function(player)
		riding[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return BikeService
