--!strict
-- Лужи грязи и кольца-ускорители на велокруге (всё решает сервер):
--  * лужа (тег Mud.Tag, плоская деталь): велосипед над ней (до HeightAbove) — скорость ×SpeedMultiplier,
--    атрибут InMud (клиент рисует брызги на экране и комья из-под колёс);
--  * кольцо (тег Rings.Tag, невидимый центр, LookVector — ось, атрибут Radius): корень персонажа
--    в плоскости кольца (±PassDepth) и внутри радиуса — ускорение, всем вспышка RingPassed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local M = Config.Mud
local R = Config.Rings

local MudRingService = {}

local RaceManager: any
local StaminaService: any

local inMud: { [Player]: boolean } = {}
local ringReadyAt: { [Player]: { [BasePart]: number } } = {}

local function log(fmt: string, ...: any)
	print("[MudRingService] " .. string.format(fmt, ...))
end

local function mudUnder(position: Vector3): boolean
	for _, part in CollectionService:GetTagged(M.Tag) do
		if part:IsA("BasePart") then
			local p = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= -half.Y and p.Y <= half.Y + M.HeightAbove then
				return true
			end
		end
	end
	return false
end

local function setMud(player: Player, on: boolean)
	if (inMud[player] == true) == on then
		return
	end
	inMud[player] = if on then true else nil
	player:SetAttribute(Attributes.InMud, if on then true else nil)
	StaminaService.setMud(player, if on then M.SpeedMultiplier else 1)
end

local function checkRings(player: Player, position: Vector3, now: number)
	for _, ring in CollectionService:GetTagged(R.Tag) do
		if not ring:IsA("BasePart") then
			continue
		end
		local p = ring.CFrame:PointToObjectSpace(position)
		local radius = (ring:GetAttribute("Radius") :: number?) or 6
		if math.abs(p.Z) <= R.PassDepth and p.X * p.X + p.Y * p.Y <= radius * radius then
			local ready = ringReadyAt[player]
			if not ready then
				ready = {}
				ringReadyAt[player] = ready
			end
			if now >= (ready[ring] or 0) then
				ready[ring] = now + R.Cooldown
				StaminaService.grantBoost(player, R.Multiplier, R.Seconds)
				Remotes.get(Remotes.Names.RingPassed):FireAllClients(ring, player.UserId)
				log("%s through %s", player.Name, ring:GetFullName())
			end
		end
	end
end

local function step()
	local racing = RaceManager.getState() == "Racing"
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local riding = racing and player:GetAttribute(Attributes.Riding) == true
		if not riding or not root then
			setMud(player, false)
			continue
		end
		setMud(player, mudUnder(root.Position))
		checkRings(player, root.Position, now)
	end
end

function MudRingService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	StaminaService = services.StaminaService
end

function MudRingService.start()
	log("%d puddle(s), %d ring(s)", #CollectionService:GetTagged(M.Tag), #CollectionService:GetTagged(R.Tag))
	Players.PlayerRemoving:Connect(function(player)
		inMud[player] = nil
		ringReadyAt[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return MudRingService
