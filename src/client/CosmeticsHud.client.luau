--!strict
-- Bike shop: a spinning podium with the focused bike and a grid of thumbnails.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Attributes = require(Shared:WaitForChild("Attributes"))
local AllConfig = require(Shared:WaitForChild("Config"))
local Config = AllConfig.Cosmetics
local Remotes = require(Shared:WaitForChild("Remotes"))
local BikeSkins = require(Shared:WaitForChild("BikeSkins"))

local ShopPreview = require(script.Parent:WaitForChild("ShopPreview"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
-- телефон: магазин занимает почти весь экран, всё внутри — крупнее (BIG — множитель значков)
local compact = UiScale.isCompact()
local function big(n: number): number
	return if compact then math.floor(n * 1.3 + 0.5) else n
end
local player = Players.LocalPlayer
local selectSkin = Remotes.get(Remotes.Names.SelectBikeSkin)
local showroom = game:GetService("ReplicatedStorage"):WaitForChild("BikeShowroom")
local rgb = Color3.fromRGB

local INK = rgb(22, 27, 44)
local CARD = rgb(34, 42, 64)
local WHITE = rgb(250, 250, 255)
local MUTED = rgb(170, 182, 205)
local GOLD = rgb(255, 205, 70)
local MINT = rgb(110, 225, 170)

local gui = Instance.new("ScreenGui")
gui.Name = "CosmeticsHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	Instance.new("UICorner", parent).CornerRadius = UDim.new(0, radius)
end
local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = parent
	return line
end
local function label(parent: Instance, name: string, font: Enum.Font, maxSize: number, color: Color3): TextLabel
	maxSize = big(maxSize)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextColor3 = color
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = parent
	local limit = Instance.new("UITextSizeConstraint", text)
	limit.MaxTextSize = maxSize
	return text
end
local function button(parent: Instance, name: string, text: string, color: Color3): TextButton
	local view = Instance.new("TextButton")
	view.Name = name
	view.Text = text
	view.Font = Enum.Font.GothamBlack
	view.TextScaled = true
	view.TextColor3 = INK
	view.BackgroundColor3 = color
	view.Parent = parent
	corner(view, 10)
	local limit = Instance.new("UITextSizeConstraint", view)
	limit.MaxTextSize = big(20)
	local pad = Instance.new("UIPadding", view)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	return view
end

-- Open button in the lobby
local open = button(gui, "OpenShop", "🚲 Bike Shop", GOLD)
open.Position = UDim2.fromOffset(12, 60)
open.Size = UDim2.fromOffset(170, 46)
-- на телефоне кнопка входа — меньше
stroke(open, INK, 3)

local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = rgb(8, 10, 20)
overlay.BackgroundTransparency = 0.35
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.Visible = false
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.96, 0.94)
panel.BackgroundColor3 = INK
panel.Active = true -- clicks on the panel must not reach the overlay (closes the shop)
panel.Parent = overlay
corner(panel, 18)
stroke(panel, rgb(70, 85, 125), 3)
local limit = Instance.new("UISizeConstraint", panel)
limit.MaxSize = Vector2.new(1000, 620)
if compact then
	panel.Size = UDim2.fromScale(0.985, 0.97)
end
local popScale = Instance.new("UIScale", panel)

-- Header: title, level with XP bar, close
local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 52)
header.Parent = panel

local title = label(header, "Title", Enum.Font.GothamBlack, 26, WHITE)
title.Text = "🚲 BIKE SHOP"
title.Position = UDim2.fromOffset(18, 10)
title.Size = UDim2.new(0.45, -18, 0, 34)

local close = button(header, "Close", "X", rgb(255, 105, 105))
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 8)
close.Size = UDim2.fromOffset(38, 38)

local levelChip = Instance.new("Frame")
levelChip.Name = "Level"
levelChip.AnchorPoint = Vector2.new(1, 0)
levelChip.Position = UDim2.new(1, -58, 0, 12)
levelChip.Size = UDim2.new(0.4, 0, 0, 30)
levelChip.BackgroundColor3 = CARD
levelChip.Parent = header
corner(levelChip, 15)
local chipLimit = Instance.new("UISizeConstraint", levelChip)
chipLimit.MaxSize = Vector2.new(230, 30)
local levelText = label(levelChip, "Text", Enum.Font.GothamBlack, 15, GOLD)
levelText.Position = UDim2.fromOffset(12, 6)
levelText.Size = UDim2.new(0, 56, 0, 18)
local barBack = Instance.new("Frame")
barBack.Name = "Bar"
barBack.Position = UDim2.new(0, 72, 0.5, -5)
barBack.Size = UDim2.new(1, -86, 0, 10)
barBack.BackgroundColor3 = rgb(16, 20, 34)
barBack.Parent = levelChip
corner(barBack, 5)
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.BackgroundColor3 = GOLD
barFill.Size = UDim2.fromScale(0, 1)
barFill.Parent = barBack
corner(barFill, 5)

-- Body: stage (left / top) and thumbnails (right / bottom)
local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(14, 56)
body.Size = UDim2.new(1, -28, 1, -70)
body.Parent = panel

local stageCard = Instance.new("Frame")
stageCard.Name = "Stage"
stageCard.BackgroundColor3 = CARD
stageCard.Parent = body
corner(stageCard, 14)

local stageView = Instance.new("Frame")
stageView.Name = "Podium"
stageView.BackgroundTransparency = 1
stageView.Position = UDim2.fromOffset(8, 8)
stageView.Parent = stageCard
local stage = ShopPreview.stage(stageView)

local info = Instance.new("Frame")
info.Name = "Info"
info.BackgroundTransparency = 1
info.Parent = stageCard

-- продаёт картинка: крупное имя и звёзды редкости, без описаний
local bikeName = label(info, "BikeName", Enum.Font.GothamBlack, 30, WHITE)
bikeName.Position = UDim2.fromScale(0, 0.04)
bikeName.Size = UDim2.new(0.5, -6, 0.56, 0)
local rarityText = label(info, "Rarity", Enum.Font.GothamBold, 18, WHITE)
rarityText.Position = UDim2.fromScale(0, 0.62)
rarityText.Size = UDim2.new(0.5, -6, 0.34, 0)
local action = button(info, "Action", "", GOLD)
action.AnchorPoint = Vector2.new(1, 0.5)
action.Position = UDim2.fromScale(1, 0.5)
action.Size = UDim2.new(0.5, 0, 0.9, 0)
local actionStroke = stroke(action, INK, 3)

local grid = Instance.new("ScrollingFrame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 4
grid.CanvasSize = UDim2.new()
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.Parent = body
local gridLayout = Instance.new("UIGridLayout", grid)
gridLayout.CellPadding = UDim2.fromOffset(10, 10)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Responsive layout: side by side in landscape, stacked in portrait.
local function layout()
	local size = body.AbsoluteSize
	local portrait = size.X < size.Y * 1.1
	local infoHeight = if compact
		then math.clamp(math.floor(size.Y * 0.27), 62, 96)
		else math.clamp(math.floor(size.Y * 0.18), 64, 96)
	local columns, rows
	if portrait then
		stageCard.Size = UDim2.new(1, 0, 0.56, -5)
		grid.Position = UDim2.new(0, 0, 0.56, 5)
		grid.Size = UDim2.new(1, 0, 0.44, -5)
		columns, rows = 3, 2
	else
		stageCard.Size = UDim2.new(0.6, -5, 1, 0)
		grid.Position = UDim2.new(0.6, 5, 0, 0)
		grid.Size = UDim2.new(0.4, -5, 1, 0)
		columns, rows = 2, 3
	end
	stageView.Size = UDim2.new(1, -16, 1, -infoHeight - 14)
	info.Position = UDim2.new(0, 14, 1, -infoHeight - 8)
	info.Size = UDim2.new(1, -28, 0, infoHeight)
	local area = grid.AbsoluteSize
	local pad = gridLayout.CellPadding.X.Offset
	local width = math.floor((area.X - 6 - (columns - 1) * pad) / columns)
	local height = math.floor((area.Y - (rows - 1) * pad) / rows)
	gridLayout.CellSize = UDim2.fromOffset(math.max(1, width), math.max(1, height))
end
body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

local function rarityOf(skin): any
	return Config.Rarities[skin.rarity] or Config.Rarities.Common
end

local function unlocked(skin): boolean
	return BikeSkins.unlocked(player, skin)
end

-- Robux prices come from Roblox, so they are never hard-coded here.
local prices: { [string]: number } = {}
local function priceText(skin): string
	local price = prices[skin.id]
	return if price then string.format("R$ %d", price) else "R$"
end

type Tile = { button: TextButton, highlight: UIStroke, badge: TextLabel, lock: Frame }
local tiles: { [string]: Tile } = {}
local focused = Config.BikeSkins[1]

local refresh: () -> ()
local function focus(skin)
	focused = skin
	stage.show(showroom:WaitForChild(skin.id) :: Model, rarityOf(skin).color)
	refresh()
end

for index, skin in Config.BikeSkins do
	local rarity = rarityOf(skin)
	local tile = Instance.new("TextButton")
	tile.Name = skin.id
	tile.LayoutOrder = index
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.BackgroundColor3 = CARD
	tile.Parent = grid
	corner(tile, 12)
	local highlight = stroke(tile, WHITE, 3)

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.BackgroundTransparency = 1
	thumb.Position = UDim2.fromOffset(4, 4)
	-- превью — только над подписью: велосипед целиком и крупно, подпись его не закрывает
	local captionShare = if compact then 0.3 else 0.24
	thumb.Size = UDim2.new(1, -8, 1 - captionShare, -6)
	thumb.Parent = tile
	ShopPreview.thumbnail(thumb, showroom:WaitForChild(skin.id) :: Model, rarity.color, skin.image)

	-- Rarity stripe and name along the bottom
	local strip = Instance.new("Frame")
	strip.Name = "Caption"
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.new(0, 4, 1, -4)
	strip.Size = UDim2.new(1, -8, captionShare, 0)
	strip.BackgroundColor3 = INK
	strip.BackgroundTransparency = 0.25
	strip.ZIndex = 3
	strip.Parent = tile
	corner(strip, 8)
	local name = label(strip, "Name", Enum.Font.GothamBold, 15, WHITE)
	name.Text = skin.title
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.Position = UDim2.new(0, 6, 0.12, 0)
	name.Size = UDim2.new(1, -12, 0.76, 0)
	name.ZIndex = 3
	local stripe = Instance.new("Frame")
	stripe.Name = "RarityStripe"
	stripe.Size = UDim2.new(1, 0, 0, 3)
	stripe.BackgroundColor3 = rarity.color
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 3
	stripe.Parent = strip

	-- Dim veil over locked bikes
	local lock = Instance.new("Frame")
	lock.Name = "Locked"
	lock.Position = UDim2.fromOffset(4, 4)
	lock.Size = UDim2.new(1, -8, 1, -8)
	lock.BackgroundColor3 = INK
	lock.BackgroundTransparency = 0.45
	lock.ZIndex = 2
	lock.Parent = tile
	corner(lock, 10)

	local badge = label(tile, "Badge", Enum.Font.GothamBlack, 14, INK)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -6, 0, 6)
	badge.Size = UDim2.fromOffset(big(74), big(24))
	badge.BackgroundTransparency = 0
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.ZIndex = 4
	corner(badge, 12)

	tiles[skin.id] = { button = tile, highlight = highlight, badge = badge, lock = lock }
	tile.Activated:Connect(function()
		focus(skin)
		if player:GetAttribute(Attributes.ProfileLevel) ~= nil and unlocked(skin) and BikeSkins.effective(player) ~= skin.id then
			selectSkin:FireServer(skin.id)
		end
	end)
end

local function stars(count: number): string
	return string.rep("★", count) .. string.rep("☆", 4 - count)
end

refresh = function()
	local selected = BikeSkins.effective(player)
	local level = player:GetAttribute(Attributes.ProfileLevel)
	local loaded = typeof(level) == "number"

	-- Header level and XP
	local xp = player:GetAttribute(Attributes.ProfileXP)
	levelText.Text = if loaded then string.format("Lv. %d", level :: number) else "Lv. —"
	local perLevel = AllConfig.Profile.XPPerLevel
	local progress = if typeof(xp) == "number" then (xp % perLevel) / perLevel else 0
	barFill.Size = UDim2.fromScale(progress, 1)

	for _, skin in Config.BikeSkins do
		local tile = tiles[skin.id]
		local isUnlocked = loaded and unlocked(skin)
		tile.lock.Visible = not isUnlocked
		tile.highlight.Transparency = if focused == skin then 0 else 1
		tile.button.BackgroundColor3 = if focused == skin then rgb(60, 72, 108) else CARD
		if selected == skin.id then
			tile.badge.Visible = true
			tile.badge.Text = "✓"
			tile.badge.BackgroundColor3 = MINT
			tile.badge.Size = UDim2.fromOffset(big(28), big(24))
		elseif not isUnlocked and skin.robuxOnly then
			tile.badge.Visible = true
			tile.badge.Text = priceText(skin)
			tile.badge.BackgroundColor3 = rgb(110, 225, 130)
			tile.badge.Size = UDim2.fromOffset(62, 20) -- компактный ценник: не закрывает велосипед
		elseif not isUnlocked then
			tile.badge.Visible = true
			tile.badge.Text = string.format("🔒 Lv. %d", skin.level)
			tile.badge.BackgroundColor3 = rgb(225, 230, 240)
			tile.badge.Size = UDim2.fromOffset(big(78), big(24))
		else
			tile.badge.Visible = false
		end
	end

	local skin = focused
	local rarity = rarityOf(skin)
	bikeName.Text = skin.title
	rarityText.Text = string.format("%s  %s", stars(rarity.stars), rarity.title)
	rarityText.TextColor3 = rarity.color

	local isUnlocked = loaded and unlocked(skin)
	local canAct = true
	if not loaded then
		action.Text, action.BackgroundColor3, canAct = "Profile unavailable", rgb(80, 92, 120), false
	elseif selected == skin.id then
		action.Text, action.BackgroundColor3, canAct = "✓ RIDING", MINT, false
	elseif isUnlocked then
		action.Text, action.BackgroundColor3 = "RIDE IT", GOLD
	elseif skin.productId > 0 then
		action.Text, action.BackgroundColor3 = "BUY · " .. priceText(skin), rgb(110, 225, 130)
	else
		action.Text, action.BackgroundColor3, canAct = string.format("🔒 Level %d", skin.level), rgb(80, 92, 120), false
	end
	action.TextColor3 = if canAct or selected == skin.id then INK else MUTED
	action.AutoButtonColor = canAct
	actionStroke.Transparency = if canAct then 0 else 1
end

action.Activated:Connect(function()
	local skin = focused
	if player:GetAttribute(Attributes.ProfileLevel) == nil or BikeSkins.effective(player) == skin.id then
		return
	end
	if unlocked(skin) then
		selectSkin:FireServer(skin.id)
	elseif skin.productId > 0 then
		MarketplaceService:PromptProductPurchase(player, skin.productId)
	end
end)

for _, skin in Config.BikeSkins do
	if skin.productId > 0 then
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, skin.productId, Enum.InfoType.Product)
			if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
				prices[skin.id] = info.PriceInRobux
				refresh()
			end
		end)
	end
end

for _, name in { Attributes.BikeSkin, Attributes.ProfileLevel, Attributes.ProfileXP, Attributes.OwnedBikeSkins } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end

local function setOpen(visible: boolean)
	overlay.Visible = visible
	stage.setActive(visible)
	if visible then
		popScale.Scale = 0.85
		TweenService:Create(popScale, TweenInfo.new(Config.Showroom.OpenTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

-- Start on the bike the player rides now.
local current = BikeSkins.effective(player)
for _, skin in Config.BikeSkins do
	if skin.id == current then
		focused = skin
	end
end
focus(focused)
-- телефон / планшет: кнопка входа меньше, шапка ниже (на ходу — поворот экрана, смена окна)
UiScale.watch(function(isCompact: boolean)
	compact = isCompact
	open.Size = if isCompact then UDim2.fromOffset(132, 36) else UDim2.fromOffset(170, 46)
	open.Position = UDim2.fromOffset(12, if isCompact then 52 else 60)
end)
layout()

open.Activated:Connect(function()
	local selected = BikeSkins.effective(player)
	for _, skin in Config.BikeSkins do
		if skin.id == selected then
			focus(skin)
		end
	end
	setOpen(true)
end)
close.Activated:Connect(function()
	setOpen(false)
end)
overlay.Activated:Connect(function()
	setOpen(false)
end)
Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload)
	gui.Enabled = payload.state == "Lobby"
	if not gui.Enabled then
		setOpen(false)
	end
end)
