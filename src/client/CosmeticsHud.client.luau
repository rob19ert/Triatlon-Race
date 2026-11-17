--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Attributes = require(Shared:WaitForChild("Attributes"))
local Config = require(Shared:WaitForChild("Config")).Cosmetics
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShopPreview = require(script.Parent:WaitForChild("ShopPreview"))
local player = Players.LocalPlayer
local selectSkin = Remotes.get(Remotes.Names.SelectBikeSkin)
local gui = Instance.new("ScreenGui")
gui.Name = "CosmeticsHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local function button(parent: Instance, name: string, title: string): TextButton
	local view = Instance.new("TextButton")
	view.Name = name
	view.Text = title
	view.Font = Enum.Font.GothamBold
	view.TextSize = 15
	view.TextColor3 = Color3.fromRGB(248, 250, 255)
	view.BackgroundColor3 = Color3.fromRGB(32, 39, 54)
	view.Parent = parent
	Instance.new("UICorner", view)
	return view
end

local open = button(gui, "OpenShop", "Веломагазин")
open.Position = UDim2.fromOffset(12, 60)
open.Size = UDim2.fromOffset(138, 38)

local overlay = Instance.new("TextButton")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.4
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.Visible = false
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.95, 0.94)
panel.BackgroundColor3 = Color3.fromRGB(20, 25, 36)
panel.Parent = overlay
Instance.new("UICorner", panel)
local limit = Instance.new("UISizeConstraint", panel)
limit.MaxSize = Vector2.new(952, 648)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(20, 0)
title.Size = UDim2.new(1, -70, 0, 52)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Магазин велосипедов"
title.Parent = panel

local close = button(panel, "Close", "×")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 8)
close.Size = UDim2.fromOffset(36, 36)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(16, 60)
list.Size = UDim2.new(1, -32, 1, -76)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.fromOffset(0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel
local layout = Instance.new("UIGridLayout", list)
layout.CellPadding = UDim2.fromOffset(12, 12)
layout.SortOrder = Enum.SortOrder.LayoutOrder
local function resize()
	local width = list.AbsoluteSize.X
	local columns = if width >= 660 then 3 elseif width >= 346 then 2 else 1
	local cardWidth = math.max(1, math.floor((width - 8 - (columns - 1)*12) / columns))
	local height = math.clamp(math.floor(cardWidth * .66), 115, 185) + 93
	if columns == 3 then
		height = math.min(height, math.max(202, math.floor((list.AbsoluteSize.Y - 12) / 2)))
	end
	layout.CellSize = UDim2.fromOffset(cardWidth, height)
end
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
resize()

local showroom = game:GetService("ReplicatedStorage"):WaitForChild("BikeShowroom")
local rows: { [string]: TextButton } = {}
local function unlocked(id: string, requiredLevel: number): boolean
	local level = player:GetAttribute(Attributes.ProfileLevel)
	local owned = player:GetAttribute(Attributes.OwnedBikeSkins)
	return (typeof(level) == "number" and level >= requiredLevel)
		or (typeof(owned) == "string" and table.find(string.split(owned, ","), id) ~= nil)
end

for index, skin in Config.BikeSkins do
	local card = Instance.new("Frame")
	card.Name = skin.id
	card.LayoutOrder = index
	card.BackgroundColor3 = Color3.fromRGB(40, 49, 65)
	card.Parent = list
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	ShopPreview.mount(card, showroom:WaitForChild(skin.id) :: Model)

	local name = title:Clone()
	name.Name = "ModelName"
	name.Text = skin.title
	name.TextSize = 16
	name.Position = UDim2.new(0, 12, 1, -82)
	name.Size = UDim2.new(1, -24, 0, 28)
	name.TextScaled = true
	local textLimit = Instance.new("UITextSizeConstraint", name)
	textLimit.MaxTextSize = 17
	name.Parent = card

	local row = button(card, "Select", "")
	row.Position = UDim2.new(0, 10, 1, -49)
	row.Size = UDim2.new(1, -20, 0, 40)
	rows[skin.id] = row
	row.Activated:Connect(function()
		if player:GetAttribute(Attributes.ProfileLevel) == nil then
			return
		end
		if unlocked(skin.id, skin.level) then
			selectSkin:FireServer(skin.id)
		elseif skin.productId > 0 then
			MarketplaceService:PromptProductPurchase(player, skin.productId)
		end
	end)
end

local function refresh()
	local selected = player:GetAttribute(Attributes.BikeSkin)
	local loaded = player:GetAttribute(Attributes.ProfileLevel) ~= nil
	for _, skin in Config.BikeSkins do
		local row = rows[skin.id]
		local suffix = if not loaded then "Профиль недоступен"
			elseif selected == skin.id then "Выбрано"
			elseif unlocked(skin.id, skin.level) then "Выбрать"
			elseif skin.productId > 0 then "Купить"
			else string.format("Уровень %d", skin.level)
		row.Text = suffix
		local available = loaded and (unlocked(skin.id, skin.level) or skin.productId > 0)
		row.Active = available and selected ~= skin.id
		row.AutoButtonColor = row.Active
		row.TextColor3 = if available then Color3.fromRGB(20, 38, 47) else Color3.fromRGB(194, 205, 220)
		row.BackgroundColor3 = if selected == skin.id then Color3.fromRGB(132, 225, 199) elseif available then Color3.fromRGB(248, 224, 165) else Color3.fromRGB(54, 65, 83)
	end
end

for _, name in { Attributes.BikeSkin, Attributes.ProfileLevel, Attributes.OwnedBikeSkins } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

open.Activated:Connect(function()
	overlay.Visible = true
end)
close.Activated:Connect(function()
	overlay.Visible = false
end)
Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload)
	gui.Enabled = payload.state == "Lobby"
	if not gui.Enabled then
		overlay.Visible = false
	end
end)
