--!strict
-- Точки над головой каждого стреляющего — ●●●○○ (белая — попал, красная — промах, серая — ещё не стрелял).
-- Данные — атрибуты RangeOrder/RangeMarks от сервера. Общая плашка «как в трансляции» — ShootingBroadcast.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local SHOTS = Config.Shooting.ShotsPerStage

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
