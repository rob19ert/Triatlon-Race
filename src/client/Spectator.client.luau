--!strict
-- Режим зрителя: финишировал (или зашёл посреди гонки) — камера следует за гонщиком,
-- который ещё на трассе. По умолчанию за лидером; ← / → или экранные стрелки — переключение.
-- Порядок гонщиков берём из таблицы позиций (Standings). Сервер переносит ReplicationFocus
-- на выбранного гонщика (SpectatorService), чтобы его персонаж подгрузился при стриминге.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local player = Players.LocalPlayer
local focusRemote = Remotes.get(Remotes.Names.SpectateFocus)

local raceState: Types.RaceState = "Lobby"
local standings: { Types.StandingEntry } = {}
local targetUserId = 0 -- за кем смотрим; 0 — ни за кем
local sentUserId = 0
local spectating = false

local PHASE_TEXT: { [string]: string } = {
	Run = "трасса",
	Shooting = "стрельба",
}

---------------------------------------------------------------- UI

local gui = Instance.new("ScreenGui")
gui.Name = "SpectatorHud"
gui.ResetOnSpawn = false
gui.Enabled = false

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -120) -- выше панели пульса и иконки толчка
bar.Size = UDim2.fromOffset(340, 44)
bar.BackgroundTransparency = 1
bar.Parent = gui

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.new(1, -104, 1, 0)
label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
label.BackgroundTransparency = 0.3
label.Font = Enum.Font.GothamBold
label.TextSize = 16
label.TextColor3 = Color3.new(1, 1, 1)
label.TextTruncate = Enum.TextTruncate.AtEnd
label.Parent = bar
Instance.new("UICorner", label)

local function arrowButton(text: string, anchorX: number): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(anchorX, 0.5)
	b.Position = UDim2.fromScale(anchorX, 0.5)
	b.Size = UDim2.fromOffset(44, 44)
	b.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 26
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = bar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0.5, 0)
	return b
end
local prevButton = arrowButton("◀", 0)
local nextButton = arrowButton("▶", 1)

gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- логика

-- Кто ещё на трассе, по местам (без себя).
local function candidates(): { Types.StandingEntry }
	local list = {}
	for _, entry in standings do
		if entry.phase ~= "Finished" and entry.userId ~= player.UserId then
			table.insert(list, entry)
		end
	end
	return list
end

local function shouldSpectate(): boolean
	if raceState ~= "Racing" then
		return false
	end
	for _, entry in standings do
		if entry.userId == player.UserId then
			return entry.phase == "Finished"
		end
	end
	return #standings > 0 -- не участник: зашёл посреди гонки
end

local function indexOf(list: { Types.StandingEntry }, userId: number): number?
	for i, entry in list do
		if entry.userId == userId then
			return i
		end
	end
	return nil
end

local function ownHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function cycle(step: number)
	local list = candidates()
	if not spectating or #list == 0 then
		return
	end
	local i = indexOf(list, targetUserId) or 1
	targetUserId = list[(i - 1 + step) % #list + 1].userId
end

local function sendFocus(userId: number)
	if userId ~= sentUserId then
		sentUserId = userId
		focusRemote:FireServer(userId)
	end
end

local function update()
	local camera = workspace.CurrentCamera
	local was = spectating
	spectating = shouldSpectate()
	local list = if spectating then candidates() else {}

	if not spectating or #list == 0 then
		targetUserId = 0
		gui.Enabled = false
		sendFocus(0)
		if was then -- вышли из режима зрителя — камера снова на себя
			local own = ownHumanoid()
			if own then
				camera.CameraSubject = own
			end
		end
		return
	end

	-- по умолчанию (и когда тот, за кем смотрели, финишировал) — лидер среди бегущих
	local i = indexOf(list, targetUserId)
	if not i then
		i = 1
		targetUserId = list[1].userId
	end
	local entry = list[i]
	sendFocus(targetUserId)

	local target = Players:GetPlayerByUserId(targetUserId)
	local character = target and target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and camera.CameraSubject ~= humanoid then
		camera.CameraSubject = humanoid
	end

	gui.Enabled = true
	local phase = PHASE_TEXT[entry.phase] or ""
	local penalty = if entry.penalty > 0 then string.format(" • +%d с", entry.penalty) else ""
	label.Text = string.format("👀 %s • %d место • %s%s", entry.name, entry.place, phase, penalty)
	prevButton.Visible = #list > 1
	nextButton.Visible = #list > 1
end

Remotes.get(Remotes.Names.Standings).OnClientEvent:Connect(function(list: { Types.StandingEntry })
	standings = list
end)

Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	raceState = payload.state
	if raceState ~= "Racing" then
		standings = {}
	end
end)

prevButton.Activated:Connect(function()
	cycle(-1)
end)
nextButton.Activated:Connect(function()
	cycle(1)
end)

ContextActionService:BindAction("SpectatePrev", function(_, state)
	if state == Enum.UserInputState.Begin and spectating then
		cycle(-1)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Config.Spectator.PrevKey)
ContextActionService:BindAction("SpectateNext", function(_, state)
	if state == Enum.UserInputState.Begin and spectating then
		cycle(1)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Config.Spectator.NextKey)

RunService.Heartbeat:Connect(update)
