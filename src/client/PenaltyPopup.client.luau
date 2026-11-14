--!strict
-- «+3 с» над головой игрока при каждом промахе (зелёное «−3 с» — золотая мишень) — видят все.
-- Следим за атрибутом PenaltyTime у всех игроков: вырос — всплывает разница.
-- Всё локально (BillboardGui в PlayerGui с Adornee = голова), сервер не нагружаем.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))

local P = Config.Penalty
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function popup(target: Player, added: number) -- added < 0 — бонус (золотая мишень)
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PenaltyPopup"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(120, 50)
	gui.StudsOffset = Vector3.new(0, P.PopupOffsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = if added > 0 then string.format("+%d с", added) else string.format("−%d с", -added)
	label.TextColor3 = if added > 0 then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(70, 220, 90)
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = label
	gui.Parent = playerGui

	local info = TweenInfo.new(P.PopupTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, P.PopupOffsetY + P.PopupRise, 0) }):Play()
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(P.PopupTime * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, P.PopupTime * 0.5), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(P.PopupTime + 0.1, function()
		gui:Destroy()
	end)
end

local function watch(target: Player)
	local last = 0
	local function current(): number
		local v = target:GetAttribute(Attributes.PenaltyTime)
		return if typeof(v) == "number" then v else 0
	end
	last = current()
	target:GetAttributeChangedSignal(Attributes.PenaltyTime):Connect(function()
		local now = current()
		if now ~= last and target:GetAttribute(Attributes.PenaltyTime) ~= nil and math.abs(now - last) < 30 then
			popup(target, now - last)
		end
		last = now -- обнуление в новой гонке — без всплывашки
	end)
end

for _, p in Players:GetPlayers() do
	watch(p)
end
Players.PlayerAdded:Connect(watch)
