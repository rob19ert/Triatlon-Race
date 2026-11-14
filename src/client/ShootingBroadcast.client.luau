--!strict
-- Плашка стрельбы «как в трансляции»: справа, под таблицей позиций, видна всем.
-- Секция на каждое стрельбище, где сейчас стреляют; строка на каждого стрелка:
--   ●●○●●  Ник  +3с  [аватар]
--   ● чёрная — мишень закрыта, красное кольцо — промах, пустая — ещё не стрелял.
-- Строка появляется, когда игрок подходит к рубежу, заполняется вживую и уезжает через
-- LeaveSeconds после ухода. Данные — атрибуты RangeOrder/RangeMarks/PenaltyTime от сервера.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local SHOTS = Config.Shooting.ShotsPerStage
local LEAVE_SECONDS = 6
local ROW_H, ROW_H_SMALL = 30, 24
local MAX_ROWS, MAX_ROWS_SMALL = 8, 4
local WIDTH, WIDTH_SMALL = 270, 210

local NAVY = Color3.fromRGB(16, 32, 64)
local PAD = Color3.fromRGB(235, 238, 245)
local HIT = Color3.fromRGB(20, 20, 24)
local MISS = Color3.fromRGB(230, 50, 50)
local EMPTY = Color3.fromRGB(190, 195, 205)
local BONUS = Color3.fromRGB(90, 220, 110)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- данные

type Shooter = {
	userId: number,
	name: string,
	range: number,
	marks: string,
	arrivedAt: number,
	leftAt: number?, -- ушёл с рубежа (строка ещё висит LEAVE_SECONDS)
}

local shooters: { [number]: Shooter } = {} -- по userId

local function rangeTitle(order: number): string
	for _, model in CollectionService:GetTagged(Config.Shooting.RangeTag) do
		if model:GetAttribute("Order") == order then
			return if model:GetAttribute("Stance") == "Standing" then "🎯 СТРЕЛЬБА СТОЯ" else "🎯 СТРЕЛЬБА ЛЁЖА"
		end
	end
	return "🎯 СТРЕЛЬБА " .. order
end

local thumbs: { [number]: string } = {}
local function thumbnail(userId: number): string
	local cached = thumbs[userId]
	if cached then
		return cached
	end
	thumbs[userId] = "" -- чтобы не запрашивать повторно, пока грузится
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok then
			thumbs[userId] = url
		end
	end)
	return ""
end

local function sync(p: Player)
	local range = p:GetAttribute(Attributes.RangeOrder)
	local marks = p:GetAttribute(Attributes.RangeMarks)
	local s = shooters[p.UserId]
	if typeof(range) == "number" then
		if not s or s.range ~= range or s.leftAt then
			s = { userId = p.UserId, name = p.DisplayName, range = range, marks = "", arrivedAt = os.clock(), leftAt = nil }
			shooters[p.UserId] = s
		end
		local sh = s :: Shooter
		sh.marks = if typeof(marks) == "string" then marks else sh.marks
	elseif s and not s.leftAt then
		s.leftAt = os.clock() -- ушёл: строка с итогом ещё повисит
	end
end

local function watch(p: Player)
	p:GetAttributeChangedSignal(Attributes.RangeOrder):Connect(function()
		sync(p)
	end)
	p:GetAttributeChangedSignal(Attributes.RangeMarks):Connect(function()
		sync(p)
	end)
	sync(p)
end
for _, p in Players:GetPlayers() do
	watch(p)
end
Players.PlayerAdded:Connect(watch)

---------------------------------------------------------------- вёрстка

local gui = Instance.new("ScreenGui")
gui.Name = "ShootingBroadcast"
gui.ResetOnSpawn = false
gui.DisplayOrder = 2

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Size = UDim2.fromOffset(WIDTH, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundTransparency = 1
panel.Parent = gui
local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 2)
list.Parent = panel

gui.Parent = playerGui

type RowUi = {
	frame: Frame,
	inner: Frame,
	dots: { Frame },
	name: TextLabel,
	penalty: TextLabel,
	avatar: ImageLabel,
	shownAt: number,
}
local rowUis: { [number]: RowUi } = {} -- по userId
local headers: { [number]: TextLabel } = {} -- по номеру стрельбища

local function isSmall(): boolean
	local v = workspace.CurrentCamera.ViewportSize
	return math.min(v.X, v.Y) <= 500
end

local function makeHeader(order: number): TextLabel
	local h = Instance.new("TextLabel")
	h.Name = "Header" .. order
	h.Size = UDim2.new(1, 0, 0, 22)
	h.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
	h.BorderSizePixel = 0
	h.Font = Enum.Font.FredokaOne
	h.TextScaled = true
	h.TextColor3 = Color3.new(1, 1, 1)
	h.Text = rangeTitle(order)
	h.Parent = panel
	Instance.new("UICorner", h).CornerRadius = UDim.new(0, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = h
	return h
end

local function makeRow(userId: number): RowUi
	local frame = Instance.new("Frame") -- держатель (по высоте), внутри — выезжающая полоса
	frame.Name = "Row" .. userId
	frame.BackgroundTransparency = 1
	frame.ClipsDescendants = true
	frame.Parent = panel

	local inner = Instance.new("Frame")
	inner.Size = UDim2.fromScale(1, 1)
	inner.Position = UDim2.fromScale(1, 0) -- старт за правым краем
	inner.BackgroundColor3 = NAVY
	inner.BackgroundTransparency = 0.08
	inner.BorderSizePixel = 0
	inner.Parent = frame
	Instance.new("UICorner", inner).CornerRadius = UDim.new(0, 6)

	-- светлая подложка с пятью мишенями (как в трансляции)
	local pad = Instance.new("Frame")
	pad.AnchorPoint = Vector2.new(0, 0.5)
	pad.Position = UDim2.new(0, 4, 0.5, 0)
	pad.Size = UDim2.new(0.38, 0, 1, -6)
	pad.BackgroundColor3 = PAD
	pad.BorderSizePixel = 0
	pad.Parent = inner
	Instance.new("UICorner", pad).CornerRadius = UDim.new(0, 5)
	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	dotsLayout.Padding = UDim.new(0.03, 0)
	dotsLayout.Parent = pad

	local dots: { Frame } = {}
	for i = 1, SHOTS do
		local d = Instance.new("Frame")
		d.LayoutOrder = i
		d.Size = UDim2.fromScale(0.16, 0.75)
		d.BackgroundColor3 = PAD
		d.BorderSizePixel = 0
		d.Parent = pad
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.Parent = d
		Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = EMPTY
		stroke.Parent = d
		dots[i] = d
	end

	local name = Instance.new("TextLabel")
	name.Position = UDim2.new(0.41, 0, 0, 0)
	name.Size = UDim2.new(0.38, 0, 1, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = inner
	local namePad = Instance.new("UIPadding")
	namePad.PaddingTop = UDim.new(0.2, 0)
	namePad.PaddingBottom = UDim.new(0.2, 0)
	namePad.Parent = name

	local penalty = Instance.new("TextLabel")
	penalty.Position = UDim2.new(0.79, 0, 0, 0)
	penalty.Size = UDim2.new(0.1, 0, 1, 0)
	penalty.BackgroundTransparency = 1
	penalty.Font = Enum.Font.GothamBold
	penalty.TextScaled = true
	penalty.TextColor3 = MISS
	penalty.Parent = inner
	local penPad = Instance.new("UIPadding")
	penPad.PaddingTop = UDim.new(0.25, 0)
	penPad.PaddingBottom = UDim.new(0.25, 0)
	penPad.Parent = penalty

	local avatar = Instance.new("ImageLabel")
	avatar.AnchorPoint = Vector2.new(1, 0.5)
	avatar.Position = UDim2.new(1, -4, 0.5, 0)
	avatar.BackgroundColor3 = Color3.fromRGB(60, 80, 120)
	avatar.BorderSizePixel = 0
	avatar.Parent = inner
	local avatarRatio = Instance.new("UIAspectRatioConstraint")
	avatarRatio.Parent = avatar
	Instance.new("UICorner", avatar).CornerRadius = UDim.new(0, 4)
	avatar.Size = UDim2.new(1, -6, 1, -6) -- ширину ограничит аспект 1:1

	-- выезд справа
	TweenService:Create(inner, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
	return { frame = frame, inner = inner, dots = dots, name = name, penalty = penalty, avatar = avatar, shownAt = os.clock() }
end

local function paintDots(row: RowUi, marks: string)
	for i, d in row.dots do
		local c = string.sub(marks, i, i)
		local stroke = d:FindFirstChildOfClass("UIStroke") :: UIStroke
		if c == "H" then
			d.BackgroundColor3 = HIT
			stroke.Color = HIT
		elseif c == "M" then
			d.BackgroundColor3 = PAD
			stroke.Color = MISS
			stroke.Thickness = 2.5
		else
			d.BackgroundColor3 = PAD
			stroke.Color = EMPTY
			stroke.Thickness = 1.5
		end
	end
end

---------------------------------------------------------------- каждый кадр

local function standingsBottom(): number
	local standings = playerGui:FindFirstChild("StandingsHud")
	local sp = standings and standings:FindFirstChild("Panel")
	if standings and (standings :: ScreenGui).Enabled and sp and sp:IsA("GuiObject") then
		return sp.AbsolutePosition.Y + sp.AbsoluteSize.Y + 8
	end
	return 8
end

local function render()
	local now = os.clock()
	local small = isSmall()
	panel.Size = UDim2.fromOffset(if small then WIDTH_SMALL else WIDTH, 0)
	panel.Position = UDim2.new(1, -8, 0, standingsBottom())
	local rowH = if small then ROW_H_SMALL else ROW_H
	local maxRows = if small then MAX_ROWS_SMALL else MAX_ROWS

	-- кто показывается: стреляют сейчас или ушли недавно
	local byRange: { [number]: { Shooter } } = {}
	for userId, s in shooters do
		if s.leftAt and now - s.leftAt > LEAVE_SECONDS then
			shooters[userId] = nil
		elseif not Players:GetPlayerByUserId(userId) then
			shooters[userId] = nil
		else
			byRange[s.range] = byRange[s.range] or {}
			table.insert(byRange[s.range], s)
		end
	end

	local orders = {}
	for order in byRange do
		table.insert(orders, order)
	end
	table.sort(orders)

	local layoutOrder = 0
	local shownRows = 0
	local keepRows: { [number]: boolean } = {}
	local keepHeaders: { [number]: boolean } = {}
	for _, order in orders do
		local group = byRange[order]
		table.sort(group, function(a, b)
			return a.arrivedAt < b.arrivedAt
		end)
		local header = headers[order] or makeHeader(order)
		headers[order] = header
		keepHeaders[order] = true
		layoutOrder += 1
		header.LayoutOrder = layoutOrder
		for _, s in group do
			if shownRows >= maxRows then
				break
			end
			shownRows += 1
			local row = rowUis[s.userId] or makeRow(s.userId)
			rowUis[s.userId] = row
			keepRows[s.userId] = true
			layoutOrder += 1
			row.frame.LayoutOrder = layoutOrder
			row.frame.Size = UDim2.new(1, 0, 0, rowH)
			paintDots(row, s.marks)
			row.name.Text = s.name
			local p = Players:GetPlayerByUserId(s.userId)
			local pen = p and p:GetAttribute(Attributes.PenaltyTime)
			local penNum = if typeof(pen) == "number" then pen else 0
			row.penalty.Text = Format.penalty(penNum, true)
			row.penalty.TextColor3 = if penNum < 0 then BONUS else MISS
			-- ушёл с рубежа — полоса светлее
			row.inner.BackgroundTransparency = if s.leftAt then 0.35 else 0.08
			local url = thumbnail(s.userId)
			if url ~= "" and row.avatar.Image ~= url then
				row.avatar.Image = url
			end
		end
	end

	for userId, row in rowUis do
		if not keepRows[userId] then
			row.frame:Destroy()
			rowUis[userId] = nil
		end
	end
	for order, header in headers do
		if not keepHeaders[order] then
			header:Destroy()
			headers[order] = nil
		end
	end
	gui.Enabled = shownRows > 0
end

RunService.Heartbeat:Connect(render)
