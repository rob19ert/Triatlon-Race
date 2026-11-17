--!strict
-- Лёд на поворотах велокруга (всё решает сервер, клиент шлёт только клики):
--  * въехал на лёд (деталь с тегом Ice.Tag) — сцепление StartGrip, атрибут IceGrip;
--  * сцепление само уходит (GripDecayPerSec), каждый клик/тап — +GripPerClick (не чаще MaxClicksPerSec);
--  * скорость велосипеда × MinSpeed..1 по сцеплению (StaminaService.setIce);
--  * снос наружу рисует клиент (IceClient) по тому же IceGrip — физика персонажа у клиента.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local I = Config.Ice

local IceService = {}

local RaceManager: any
local StaminaService: any

type State = { grip: number, lastClick: number }
local onIce: { [Player]: State } = {}

local function log(fmt: string, ...: any)
	print("[IceService] " .. string.format(fmt, ...))
end

-- Над какой-нибудь льдиной (по горизонтали внутри, по высоте — от низа до HeightAbove над верхом).
local function iceUnder(position: Vector3): boolean
	for _, part in CollectionService:GetTagged(I.Tag) do
		if part:IsA("BasePart") then
			local p = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= -half.Y and p.Y <= half.Y + I.HeightAbove then
				return true
			end
		end
	end
	return false
end

local function leave(player: Player)
	if onIce[player] then
		onIce[player] = nil
		player:SetAttribute(Attributes.IceGrip, nil)
		StaminaService.setIce(player, 1)
	end
end

local function apply(player: Player, st: State)
	-- шаг 0,05: не гоняем атрибут каждый кадр
	player:SetAttribute(Attributes.IceGrip, math.floor(st.grip * 20 + 0.5) / 20)
	StaminaService.setIce(player, I.MinSpeed + (1 - I.MinSpeed) * st.grip)
end

local function onClick(player: Player)
	local st = onIce[player]
	if not st then
		return
	end
	local t = os.clock()
	if t - st.lastClick < 1 / I.MaxClicksPerSec then
		return
	end
	st.lastClick = t
	st.grip = math.min(1, st.grip + I.GripPerClick)
	apply(player, st)
end

local function step(dt: number)
	local racing = RaceManager.getState() == "Racing"
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local riding = racing and player:GetAttribute(Attributes.Riding) == true
		if not riding or not root or not iceUnder(root.Position) then
			leave(player)
			continue
		end
		local st = onIce[player]
		if not st then
			st = { grip = I.StartGrip, lastClick = 0 }
			onIce[player] = st
			log("%s on ice", player.Name)
		else
			st.grip = math.max(0, st.grip - I.GripDecayPerSec * dt)
		end
		apply(player, st)
	end
end

function IceService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	StaminaService = services.StaminaService
end

function IceService.start()
	log("%d ice part(s)", #CollectionService:GetTagged(I.Tag))
	Remotes.get(Remotes.Names.IceClick).OnServerEvent:Connect(onClick)
	Players.PlayerRemoving:Connect(function(player)
		onIce[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return IceService
