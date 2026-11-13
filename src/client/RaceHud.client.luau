--!strict
-- Простой HUD гонки: статус/отсчёт/таймер сверху и таблица результатов.
-- Только отображение — все цифры приходят с сервера.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Types = require(ReplicatedStorage.Shared:WaitForChild("Types"))
local Attributes = require(ReplicatedStorage.Shared:WaitForChild("Attributes"))

local player = Players.LocalPlayer

local current: Types.RaceStatePayload = { state = "Lobby", endsAt = 0, raceStartedAt = 0 }
local myTime: number? = nil

---------------------------------------------------------------- UI

local gui = Instance.new("ScreenGui")
gui.Name = "RaceHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.new(0.5, 0, 0, 8)
status.Size = UDim2.new(0.6, 0, 0, 48)
status.BackgroundTransparency = 0.35
status.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
status.TextColor3 = Color3.new(1, 1, 1)
status.Font = Enum.Font.GothamBold
status.TextScaled = true
status.Text = ""
status.Parent = gui
Instance.new("UICorner", status)
local statusLimit = Instance.new("UISizeConstraint")
statusLimit.MaxSize = Vector2.new(360, 48)
statusLimit.Parent = status

-- лента событий (итоги стрельбы)
local feed = Instance.new("TextLabel")
feed.Name = "Feed"
feed.AnchorPoint = Vector2.new(0.5, 0)
feed.Position = UDim2.new(0.5, 0, 0, 62)
feed.Size = UDim2.new(0.6, 0, 0, 26)
feed.BackgroundTransparency = 1
feed.TextColor3 = Color3.new(1, 1, 1)
feed.TextStrokeTransparency = 0.4
feed.Font = Enum.Font.GothamBold
feed.TextSize = 18
feed.Text = ""
feed.Parent = gui
local FEED_SECONDS = 4
local feedUntil = 0

local function showFeed(text: string)
	feed.Text = text
	feedUntil = os.clock() + FEED_SECONDS
end

-- постоянная подсказка, пока не отработан штраф
local penaltyLabel = Instance.new("TextLabel")
penaltyLabel.Name = "Penalty"
penaltyLabel.AnchorPoint = Vector2.new(0.5, 0)
penaltyLabel.Position = UDim2.new(0.5, 0, 0, 92)
penaltyLabel.Size = UDim2.new(0.6, 0, 0, 30)
penaltyLabel.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
penaltyLabel.BackgroundTransparency = 0.15
penaltyLabel.TextColor3 = Color3.new(1, 1, 1)
penaltyLabel.Font = Enum.Font.GothamBlack
penaltyLabel.TextScaled = true
penaltyLabel.Visible = false
penaltyLabel.Parent = gui
Instance.new("UICorner", penaltyLabel)
local penaltyLimit = Instance.new("UISizeConstraint")
penaltyLimit.MaxSize = Vector2.new(460, 30)
penaltyLimit.Parent = penaltyLabel

local resultsFrame = Instance.new("Frame")
resultsFrame.Name = "Results"
resultsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
resultsFrame.Position = UDim2.fromScale(0.5, 0.5)
resultsFrame.Size = UDim2.new(0.5, 0, 0.6, 0)
resultsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
resultsFrame.BackgroundTransparency = 0.2
resultsFrame.Visible = false
resultsFrame.Parent = gui
Instance.new("UICorner", resultsFrame)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(280, 200)
sizeLimit.Parent = resultsFrame

local resultsText = Instance.new("TextLabel")
resultsText.BackgroundTransparency = 1
resultsText.Position = UDim2.fromOffset(16, 12)
resultsText.Size = UDim2.new(1, -32, 1, -24)
resultsText.TextColor3 = Color3.new(1, 1, 1)
resultsText.Font = Enum.Font.GothamMedium
resultsText.TextSize = 22
resultsText.TextXAlignment = Enum.TextXAlignment.Left
resultsText.TextYAlignment = Enum.TextYAlignment.Top
resultsText.TextWrapped = true
resultsText.Parent = resultsFrame

gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- логика отображения

local function formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	return string.format("%d:%05.2f", m, s)
end

local function remaining(): number
	if current.endsAt == 0 then
		return 0
	end
	return math.max(0, current.endsAt - workspace:GetServerTimeNow())
end

local function render()
	local s = current.state
	if s == "Lobby" then
		if current.endsAt > 0 then
			status.Text = string.format("Старт через %d", math.ceil(remaining()))
		else
			status.Text = "Ожидание игроков…"
		end
	elseif s == "Countdown" then
		status.Text = tostring(math.max(1, math.ceil(remaining())))
	elseif s == "Racing" then
		if myTime then
			status.Text = "Финиш! " .. formatTime(myTime)
		else
			status.Text = formatTime(workspace:GetServerTimeNow() - current.raceStartedAt)
		end
	elseif s == "Results" then
		status.Text = string.format("Результаты • лобби через %d", math.ceil(remaining()))
	end
end

Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	current = payload
	if payload.state == "Lobby" or payload.state == "Countdown" then
		myTime = nil
		resultsFrame.Visible = false
	end
end)

Remotes.get(Remotes.Names.PlayerFinished).OnClientEvent:Connect(function(entry: Types.ResultEntry)
	if entry.userId == player.UserId then
		myTime = entry.time
	end
end)

Remotes.get(Remotes.Names.RaceResults).OnClientEvent:Connect(function(results: { Types.ResultEntry })
	local lines = { "РЕЗУЛЬТАТЫ", "" }
	for _, entry in results do
		local accuracy = if entry.shots and entry.shots > 0 then string.format("   🎯 %d/%d", entry.hits or 0, entry.shots) else ""
		if entry.dnf then
			table.insert(lines, string.format("DNF   %s%s", entry.name, accuracy))
		else
			table.insert(lines, string.format("%d.   %s   %s%s", entry.place :: number, entry.name, formatTime(entry.time :: number), accuracy))
		end
	end
	resultsText.Text = table.concat(lines, "\n")
	resultsFrame.Visible = true
end)

Remotes.get(Remotes.Names.ShootingFinished).OnClientEvent:Connect(function(summary: Types.ShootingSummary)
	local misses = summary.shots - summary.hits
	showFeed(if misses == 0
		then string.format("%s — %d/%d", summary.name, summary.hits, summary.shots)
		else string.format("%s — %d/%d, штрафных: %d", summary.name, summary.hits, summary.shots, misses))
end)

Remotes.get(Remotes.Names.Notice).OnClientEvent:Connect(function(text: string)
	showFeed(text)
end)

local function updatePenaltyLabel()
	local owed = player:GetAttribute(Attributes.PenaltyOwed)
	local done = player:GetAttribute(Attributes.PenaltyDone)
	if typeof(owed) == "number" and typeof(done) == "number" and done < owed then
		penaltyLabel.Text = string.format("Штрафной круг %d/%d — на развилке налево, вокруг красного острова", done + 1, owed)
		penaltyLabel.Visible = true
	else
		penaltyLabel.Visible = false
	end
end
player:GetAttributeChangedSignal(Attributes.PenaltyOwed):Connect(updatePenaltyLabel)
player:GetAttributeChangedSignal(Attributes.PenaltyDone):Connect(updatePenaltyLabel)

RunService.RenderStepped:Connect(function()
	render()
	feed.Visible = os.clock() < feedUntil
end)
