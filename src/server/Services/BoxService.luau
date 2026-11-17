--!strict
-- Секретные боксы «?» на трассе (всё решает сервер):
--  * на Active случайных точках (теги BoxSpot) стоят боксы;
--  * участник на трассе (не на рубеже) проехал сквозь бокс — получает случайный бонус только себе,
--    бокс пропадает у всех и через RespawnTime появляется в другой свободной точке;
--  * бонусы: ⚡ Турбо (то же, что за 5/5), 💥 Мега-толчок на N секунд, 🎯 Большие мишени на следующую стрельбу.
-- Боксы стоят всё время (и в лобби — видно, где они), брать можно только в гонке.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local B = Config.Boxes

local BoxService = {}

local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local StaminaService: any
local noticeRemote: RemoteEvent
local takenRemote: RemoteEvent

local spots: { BasePart } = {}
local boxes: { [BasePart]: BasePart } = {} -- точка -> бокс на ней
local reserved: { [BasePart]: boolean } = {} -- точка ждёт респауна (бокс только что взят)
local folder: Folder
local rng = Random.new()

local function log(fmt: string, ...: any)
	print("[BoxService] " .. string.format(fmt, ...))
end

---------------------------------------------------------------- боксы

local function makeBox(spot: BasePart): BasePart
	local box = Instance.new("Part")
	box.Name = "PowerBox"
	box.Size = Vector3.one * B.Size
	box.CFrame = CFrame.new(spot.Position)
	box.Color = B.Color
	box.Material = Enum.Material.Neon
	box.Transparency = 0.15
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	for _, face in Enum.NormalId:GetEnumItems() do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "?"
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = box
	end
	CollectionService:AddTag(box, B.BoxTag)
	box.Parent = folder
	return box
end

-- Свободная точка (без бокса и не только что опустевшая), случайная.
local function freeSpot(): BasePart?
	local free = {}
	for _, spot in spots do
		if not boxes[spot] and not reserved[spot] then
			table.insert(free, spot)
		end
	end
	return if #free > 0 then free[rng:NextInteger(1, #free)] else nil
end

local function spawnOne()
	local spot = freeSpot()
	if spot then
		boxes[spot] = makeBox(spot)
	end
end

---------------------------------------------------------------- бонусы

local function grant(player: Player, effect: string)
	local def = (B.Defs :: any)[effect]
	if effect == "Turbo" then
		StaminaService.grantTurbo(player, def.seconds)
	elseif effect == "MegaPush" then
		player:SetAttribute(Attributes.MegaPushUntil, workspace:GetServerTimeNow() + def.seconds)
	elseif effect == "BigTargets" then
		player:SetAttribute(Attributes.BigTargets, true)
	end
	noticeRemote:FireClient(player, string.format("%s %s!", def.icon, def.title))
end

local function take(player: Player, spot: BasePart, box: BasePart)
	boxes[spot] = nil
	reserved[spot] = true
	local position = box.Position
	box:Destroy()
	local effect = B.Effects[rng:NextInteger(1, #B.Effects)]
	grant(player, effect)
	takenRemote:FireAllClients(position, player.UserId, effect)
	log("%s took %s", player.Name, effect)
	task.delay(B.RespawnTime, function()
		spawnOne() -- сначала новая точка, потом освобождаем старую: бокс не вернётся туда же
		reserved[spot] = nil
	end)
end

local function step()
	if RaceManager.getState() ~= "Racing" then
		return
	end
	for _, player in Players:GetPlayers() do
		if not RaceManager.isParticipant(player) or not ProgressTracker.isTracked(player) or ShootingService.isShooting(player) then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		for spot, box in boxes do
			if (box.Position - root.Position).Magnitude <= B.PickupRadius then
				take(player, spot, box)
				break
			end
		end
	end
end

-- Новая гонка: бонусы прошлой не переносятся.
local function clearPlayerBonuses()
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Attributes.MegaPushUntil, nil)
		player:SetAttribute(Attributes.BigTargets, nil)
	end
end

function BoxService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	StaminaService = services.StaminaService
	noticeRemote = Remotes.get(Remotes.Names.Notice)
	takenRemote = Remotes.get(Remotes.Names.BoxTaken)
end

function BoxService.start()
	for _, spot in CollectionService:GetTagged(B.SpotTag) do
		if spot:IsA("BasePart") then
			table.insert(spots, spot)
		end
	end
	folder = Instance.new("Folder")
	folder.Name = "PowerBoxes"
	folder.Parent = workspace
	for _ = 1, math.min(B.Active, #spots) do
		spawnOne()
	end
	log("%d spot(s), %d box(es)", #spots, math.min(B.Active, #spots))

	local lastState = RaceManager.getState()
	RunService.Heartbeat:Connect(function()
		local state = RaceManager.getState()
		if state ~= lastState then
			if state == "Countdown" or state == "Results" then
				clearPlayerBonuses()
			end
			lastState = state
		end
		step()
	end)
end

return BoxService
