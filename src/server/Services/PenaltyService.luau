--!strict
-- Штрафные круги: за каждый промах — круг по штрафной петле.
-- Круг = ближняя зона -> дальняя зона (за островом) -> ближняя зона; считает сервер.
-- Пока штраф не отработан, зона Check на трассе возвращает игрока ко входу в петлю.
-- Петель может быть несколько (PenaltyLoop, PenaltyLoop2 …, атрибут Order = Order стрельбища):
-- штраф со стрельбы N отрабатывается на петле N.
-- Над игроком висит счётчик «Штраф: 1/3», видимый всем.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)

local P = Config.Penalty

local PenaltyService = {}

local ShootingService: any -- задаётся в init

local COUNTER_NAME = "PenaltyCounter"

type Loop = {
	near: BasePart,
	far: BasePart,
	check: BasePart,
	returnPoint: BasePart,
}

type PenaltyState = {
	loop: Loop,
	owed: number,
	done: number,
	reachedFar: boolean, -- половина круга пройдена
	lapStartedAt: number,
}

local racers: { [Player]: boolean } = {}
local states: { [Player]: PenaltyState } = {}

local loops: { [number]: Loop } = {} -- по Order
local noticeRemote: RemoteEvent

local function log(fmt: string, ...: any)
	print("[PenaltyService] " .. string.format(fmt, ...))
end

local function isInside(zone: BasePart, position: Vector3): boolean
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

---------------------------------------------------------------- счётчик над головой

local function removeCounter(player: Player)
	local character = player.Character
	local counter = character and character:FindFirstChild(COUNTER_NAME, true)
	if counter then
		counter:Destroy()
	end
end

local function updateCounter(player: Player, st: PenaltyState?)
	if not st or st.done >= st.owed then
		removeCounter(player)
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild(COUNTER_NAME) :: BillboardGui?
	if not gui then
		local newGui = Instance.new("BillboardGui")
		newGui.Name = COUNTER_NAME
		newGui.Size = UDim2.fromOffset(140, 36)
		newGui.StudsOffset = Vector3.new(0, P.CounterOffsetY, 0)
		newGui.AlwaysOnTop = true
		newGui.MaxDistance = 150
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Parent = newGui
		Instance.new("UICorner", label)
		newGui.Parent = head
		gui = newGui
	end
	local label = (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel
	label.Text = string.format("Штраф: %d/%d", st.done, st.owed)
end

local function publish(player: Player, st: PenaltyState?)
	player:SetAttribute(Attributes.PenaltyOwed, if st then st.owed else nil)
	player:SetAttribute(Attributes.PenaltyDone, if st then st.done else nil)
	updateCounter(player, st)
end

---------------------------------------------------------------- логика

local function onStageFinished(player: Player, rangeOrder: number, _hits: number, misses: number)
	if not racers[player] or misses <= 0 then
		return
	end
	local loop = loops[rangeOrder] or loops[1]
	if not loop then
		warn(string.format("[PenaltyService] no penalty loop for range %d", rangeOrder))
		return
	end
	local st = states[player]
	if st and st.loop == loop and st.done < st.owed then
		st.owed += misses * P.LapsPerMiss
	else
		-- новая стрельба — новый счёт на своей петле
		st = { loop = loop, owed = misses * P.LapsPerMiss, done = 0, reachedFar = false, lapStartedAt = os.clock() }
		states[player] = st
	end
	publish(player, st)
	log("%s owes %d lap(s)", player.Name, st.owed - st.done)
end

local function sendBack(player: Player, st: PenaltyState)
	local character = player.Character
	local root = getRoot(player)
	if not character or not root then
		return
	end
	local pos = st.loop.returnPoint.Position + Vector3.new(0, Config.Track.RespawnHeight, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0)))
	noticeRemote:FireClient(player, string.format("Сначала штрафные круги: осталось %d", st.owed - st.done))
	log("%s tried to skip penalty -> back to loop", player.Name)
end

local function step()
	for player, st in states do
		if st.done >= st.owed then
			continue
		end
		local root = getRoot(player)
		if not root then
			continue
		end
		local pos = root.Position
		local loop = st.loop

		if not st.reachedFar then
			if isInside(loop.far, pos) then
				st.reachedFar = true
			end
		elseif isInside(loop.near, pos) then
			st.reachedFar = false
			st.done += 1
			log("%s lap %d/%d (%.1fs)", player.Name, st.done, st.owed, os.clock() - st.lapStartedAt)
			st.lapStartedAt = os.clock()
			publish(player, st)
			if st.done >= st.owed then
				noticeRemote:FireClient(player, "Штраф отработан — вперёд!")
			end
		end

		if st.done < st.owed and isInside(loop.check, pos) then
			sendBack(player, st)
		end
	end
end

---------------------------------------------------------------- API

function PenaltyService.beginRace(players: { Player })
	PenaltyService.endRace()
	for _, player in players do
		racers[player] = true
	end
end

function PenaltyService.endRace()
	for player in states do
		publish(player, nil)
	end
	table.clear(states)
	table.clear(racers)
end

function PenaltyService.getOutstanding(player: Player): number
	local st = states[player]
	return if st then st.owed - st.done else 0
end

function PenaltyService.init(services: { [string]: any })
	ShootingService = services.ShootingService
	noticeRemote = Remotes.get(Remotes.Names.Notice)
end

function PenaltyService.start()
	local track = workspace:WaitForChild(Config.Track.FolderName)
	track:WaitForChild(P.LoopName) -- хотя бы первая петля должна быть
	for _, model in track:GetChildren() do
		if model:IsA("Model") and string.sub(model.Name, 1, #P.LoopName) == P.LoopName then
			local order = (model:GetAttribute("Order") :: number?) or 1
			if loops[order] then
				warn(string.format("[PenaltyService] duplicate penalty loop Order %d (%s)", order, model.Name))
			end
			loops[order] = {
				near = model:WaitForChild("Near") :: BasePart,
				far = model:WaitForChild("Far") :: BasePart,
				check = model:WaitForChild("Check") :: BasePart,
				returnPoint = model:WaitForChild("Return") :: BasePart,
			}
		end
	end
	local count = 0
	for _ in loops do
		count += 1
	end
	log("%d penalty loop(s) loaded", count)

	ShootingService.StageFinished:Connect(onStageFinished)

	local function hookPlayer(player: Player)
		-- после респауна вернуть счётчик над головой
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 5)
			updateCounter(player, states[player])
		end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		racers[player] = nil
	end)

	RunService.Heartbeat:Connect(step)
end

return PenaltyService
