--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Attributes = require(Shared:WaitForChild("Attributes"))
local Config = require(Shared:WaitForChild("Config")).Cosmetics
local Remotes = require(Shared:WaitForChild("Remotes"))

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
panel.Size = UDim2.fromScale(0.92, 0.86)
panel.BackgroundColor3 = Color3.fromRGB(20, 25, 36)
panel.Parent = overlay
Instance.new("UICorner", panel)
local limit = Instance.new("UISizeConstraint", panel)
limit.MaxSize = Vector2.new(820, 510)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(18, 0)
title.Size = UDim2.new(1, -70, 0, 52)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 19
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Магазин велосипедов"
title.Parent = panel

local close = button(panel, "Close", "×")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 8)
close.Size = UDim2.fromOffset(36, 36)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(10, 54)
list.Size = UDim2.new(1, -20, 1, -66)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.fromOffset(0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel
local layout = Instance.new("UIGridLayout", list)
layout.CellPadding = UDim2.fromOffset(8, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
local function resize()
	local width = list.AbsoluteSize.X
	local columns = if width >= 600 then 3 elseif width >= 300 then 2 else 1
	layout.CellSize = UDim2.fromOffset(math.max(1, math.floor((width - 8 * columns) / columns)), 174)
end
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
resize()

local showroom = game:GetService("ReplicatedStorage"):WaitForChild("BikeShowroom")
local rows: { [string]: TextButton } = {}
local function preview(row: TextButton, source: Model, accent: Color3)
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.new(1, -8, 1, -52)
	view.Position = UDim2.fromOffset(4, 4)
	view.BackgroundColor3 = Color3.fromRGB(41, 49, 66):Lerp(accent, 0.18)
	view.Ambient = Color3.fromRGB(183, 192, 213)
	view.LightColor = Color3.fromRGB(255, 241, 217)
	view.LightDirection = Vector3.new(-1, -2, 1)
	view.Parent = row
	Instance.new("UICorner", view)
	local bike = source:Clone()
	bike:PivotTo(CFrame.identity)
	bike.Parent = view
	local bounds, size = bike:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local function frame()
		local aspect = view.AbsoluteSize.X / math.max(1, view.AbsoluteSize.Y)
		local distance = math.max(size.Y + size.X * 0.38, size.Z / math.max(0.5, aspect)) * 2.2
		camera.CFrame = CFrame.lookAt(bounds.Position + Vector3.new(1, 0.32, -0.48).Unit * distance, bounds.Position)
	end
	camera.Parent = view
	view.CurrentCamera = camera
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame)
	frame()
end
local function unlocked(id: string, requiredLevel: number): boolean
	local level = player:GetAttribute(Attributes.ProfileLevel)
	local owned = player:GetAttribute(Attributes.OwnedBikeSkins)
	return (typeof(level) == "number" and level >= requiredLevel)
		or (typeof(owned) == "string" and table.find(string.split(owned, ","), id) ~= nil)
end

for index, skin in Config.BikeSkins do
	local row = button(list, skin.id, "")
	row.LayoutOrder = index
	row.TextYAlignment = Enum.TextYAlignment.Bottom
	row.TextSize = 14
	row.TextWrapped = true
	local source = showroom:WaitForChild(skin.id) :: Model
	preview(row, source, skin.color)
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
		row.Text = skin.title .. "\n" .. suffix
		row.BackgroundColor3 = if selected == skin.id then Color3.fromRGB(37, 89, 83) else Color3.fromRGB(32, 39, 54)
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
