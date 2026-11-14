--!strict
-- Давление соперников на рубеже (только отображение, данные — атрибуты RangeOrder/RangeMarks от сервера):
--  * над головой каждого стреляющего — ●●●○○ (белая — попал, красная — промах, серая — ещё не стрелял);
--  * пока стреляешь сам — панель «Соседи»: кто ещё на этом стрельбище и сколько закрыл,
--    кто уже ушёл с рубежа, и сколько ты сам стоишь на рубеже.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local Types = require(Shared:WaitForChild("Types"))

local SHOTS = Config.Shooting.ShotsPerStage
local LEFT_SHOW_SECONDS = 8 -- сколько показывать «ушёл с рубежа»
local MAX_ROWS = 5

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Точки выстрелов в RichText: «HHM» -> белая, белая, красная, серая, серая.
local function marksText(marks: string): string
	local parts = {}
	for i = 1, SHOTS do
		local c = string.sub(marks, i, i)
		local color = if c == "H" then "#FFFFFF" elseif c == "M" then "#FF4B4B" else "#5A5A6E"
		table.insert(parts, string.format('<font color="%s">●</font>', color))
	end
	return table.concat(parts)
end

local function rangeOf(p: Player): number?
	local v = p:GetAttribute(Attributes.RangeOrder)
	return if typeof(v) == "number" then v else nil
end

local function marksOf(p: Player): string
	local v = p:GetAttribute(Attributes.RangeMarks)
	return if typeof(v) == "string" then v else ""
end

---------------------------------------------------------------- точки над головой

local overheads: { [Player]: BillboardGui } = {}

local function updateOverhead(p: Player)
	local range = rangeOf(p)
	local character = p.Character
	local head = character and character:FindFirstChild("Head")
	local gui = overheads[p]
	if not range or not head or p == player then
		if gui then
			gui:Destroy()
			overheads[p] = nil
		end
		return
	end
	if not gui or gui.Adornee ~= head then
		if gui then
			gui:Destroy()
		end
		local newGui = Instance.new("BillboardGui")
		newGui.Name = "RangeMarks_" .. p.Name
		newGui.Adornee = head :: BasePart
		newGui.Size = UDim2.fromOffset(110, 26)
		newGui.StudsOffset = Vector3.new(0, 2.6, 0)
		newGui.AlwaysOnTop = true
		newGui.MaxDistance = 120
		newGui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Name = "Marks"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		label.BackgroundTransparency = 0.35
		label.RichText = true
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = newGui
		Instance.new("UICorner", label).CornerRadius = UDim.new(0.5, 0)
		newGui.Parent = playerGui
		gui = newGui
		overheads[p] = newGui
	end
	((gui :: BillboardGui):FindFirstChild("Marks") :: TextLabel).Text = marksText(marksOf(p))
end

local function watch(p: Player)
	p:GetAttributeChangedSignal(Attributes.RangeOrder):Connect(function()
		updateOverhead(p)
	end)
	p:GetAttributeChangedSignal(Attributes.RangeMarks):Connect(function()
		updateOverhead(p)
	end)
	p.CharacterAdded:Connect(function()
		task.wait()
		updateOverhead(p)
	end)
	updateOverhead(p)
end

for _, p in Players:GetPlayers() do
	watch(p)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(p)
	local gui = overheads[p]
	if gui then
		gui:Destroy()
		overheads[p] = nil
	end
end)

---------------------------------------------------------------- панель «Соседи» (когда стреляешь сам)

local gui = Instance.new("ScreenGui")
gui.Name = "RangeRivals"
gui.IgnoreGuiInset = false
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 3

local panel = Instance.new("Frame")
panel.Position = UDim2.fromOffset(12, 60)
panel.Size = UDim2.fromOffset(230, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.3
panel.Parent = gui
Instance.new("UICorner", panel)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.Parent = panel
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = panel

local function line(order: number, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.LayoutOrder = order
	t.Size = UDim2.new(1, 0, 0, size + 4)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.RichText = true
	t.Parent = panel
	return t
end

local timerLine = line(1, 16)
local titleLine = line(2, 14)
titleLine.TextColor3 = Color3.fromRGB(255, 200, 80)
local rows: { TextLabel } = {}
for i = 1, MAX_ROWS do
	rows[i] = line(10 + i, 14)
end

gui.Parent = playerGui

-- кто недавно ушёл с рубежа: userId -> { name, hits, shots, rangeOrder, at }
type Left = { name: string, hits: number, shots: number, rangeOrder: number, at: number }
local recentlyLeft: { [number]: Left } = {}

Remotes.get(Remotes.Names.ShootingFinished).OnClientEvent:Connect(function(summary: Types.ShootingSummary)
	if summary.userId ~= player.UserId then
		recentlyLeft[summary.userId] = {
			name = summary.name,
			hits = summary.hits,
			shots = summary.shots,
			rangeOrder = summary.rangeOrder,
			at = os.clock(),
		}
	end
end)

local myRangeSince = 0
player:GetAttributeChangedSignal(Attributes.RangeOrder):Connect(function()
	if rangeOf(player) then
		myRangeSince = os.clock()
	end
end)

local function renderPanel()
	local myRange = rangeOf(player)
	gui.Enabled = myRange ~= nil
	if not myRange then
		return
	end
	timerLine.Text = string.format("⏱ На рубеже: %.1f с", os.clock() - myRangeSince)

	local n = 0
	for _, p in Players:GetPlayers() do
		if p ~= player and rangeOf(p) == myRange and n < MAX_ROWS then
			n += 1
			rows[n].Text = string.format("%s  %s", marksText(marksOf(p)), p.DisplayName)
			rows[n].Visible = true
		end
	end
	local now = os.clock()
	for userId, left in recentlyLeft do
		if now - left.at > LEFT_SHOW_SECONDS then
			recentlyLeft[userId] = nil
		elseif left.rangeOrder == myRange and n < MAX_ROWS then
			n += 1
			rows[n].Text = string.format('<font color="#8CDCFF">➜ ушёл: %s %d/%d</font>', left.name, left.hits, left.shots)
			rows[n].Visible = true
		end
	end
	for i = n + 1, MAX_ROWS do
		rows[i].Visible = false
	end
	titleLine.Text = if n > 0 then "Соседи:" else "Соседей нет — ты один на рубеже"
end

RunService.Heartbeat:Connect(renderPanel)
