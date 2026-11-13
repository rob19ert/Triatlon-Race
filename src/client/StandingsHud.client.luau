--!strict
-- Таблица позиций во время гонки (справа сверху): место, имя, статус.
-- Только отображение того, что присылает сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local player = Players.LocalPlayer

local MAX_ROWS = 8
local ROW_HEIGHT = 22
-- маленький экран (телефон): компактнее, чтобы не наезжать на статус гонки
local SMALL_MAX_ROWS = 4
local SMALL_ROW_HEIGHT = 17
local SMALL_WIDTH = 150

-- стандартный список игроков занимает то же место
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

---------------------------------------------------------------- UI

local gui = Instance.new("ScreenGui")
gui.Name = "StandingsHud"
gui.ResetOnSpawn = false
gui.Enabled = false

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -8, 0, 8)
panel.Size = UDim2.fromOffset(200, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.35
panel.Parent = gui
Instance.new("UICorner", panel)
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = panel
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local rows: { TextLabel } = {}
for i = 1, MAX_ROWS + 1 do -- +1: своя строка, если ты ниже MAX_ROWS
	local row = Instance.new("TextLabel")
	row.Name = "Row" .. i
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.GothamMedium
	row.TextSize = 15
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextTruncate = Enum.TextTruncate.AtEnd
	row.RichText = true
	row.Visible = false
	row.Parent = panel
	rows[i] = row
end

gui.Parent = player:WaitForChild("PlayerGui")

local visibleRows = MAX_ROWS
local function applyScreenSize()
	local screen = workspace.CurrentCamera.ViewportSize
	local small = math.min(screen.X, screen.Y) <= 500
	visibleRows = if small then SMALL_MAX_ROWS else MAX_ROWS
	panel.Size = UDim2.fromOffset(if small then SMALL_WIDTH else 200, 0)
	for _, row in rows do
		row.Size = UDim2.new(1, 0, 0, if small then SMALL_ROW_HEIGHT else ROW_HEIGHT)
		row.TextSize = if small then 12 else 15
	end
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScreenSize)
applyScreenSize()

---------------------------------------------------------------- отображение

local function formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	return string.format("%d:%05.2f", m, seconds - m * 60)
end

local function statusText(entry: Types.StandingEntry): string
	if entry.phase == "Finished" then
		return formatTime(entry.time or 0)
	elseif entry.phase == "Shooting" then
		return "стрельба"
	elseif entry.phase == "Penalty" then
		return string.format("штраф %d", entry.penaltyLeft)
	end
	return ""
end

local function fillRow(row: TextLabel, entry: Types.StandingEntry)
	local mine = entry.userId == player.UserId
	local status = statusText(entry)
	row.Text = string.format(
		"<b>%d.</b> %s%s",
		entry.place,
		entry.name,
		if status ~= "" then string.format("  <font color=\"#FFC850\">%s</font>", status) else ""
	)
	row.TextColor3 = if mine then Color3.fromRGB(120, 220, 255) else Color3.new(1, 1, 1)
	row.Visible = true
end

Remotes.get(Remotes.Names.Standings).OnClientEvent:Connect(function(standings: { Types.StandingEntry })
	for _, row in rows do
		row.Visible = false
	end
	local shownMine = false
	for i, entry in standings do
		if i > visibleRows then
			break
		end
		fillRow(rows[i], entry)
		if entry.userId == player.UserId then
			shownMine = true
		end
	end
	-- если ты ниже видимых строк — добавляем свою строку отдельно
	if not shownMine then
		for _, entry in standings do
			if entry.userId == player.UserId then
				fillRow(rows[visibleRows + 1], entry)
				break
			end
		end
	end
	gui.Enabled = #standings > 0
end)

Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	-- таблица нужна только во время гонки
	if payload.state ~= "Racing" then
		gui.Enabled = false
	end
end)
