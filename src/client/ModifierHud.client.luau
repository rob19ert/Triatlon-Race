--!strict
-- Модификатор заезда на экране (только отображение, решает сервер):
--  * лобби — карточки голосования (клик / тап / клавиши 1–3), у каждой число голосов, свой выбор подсвечен;
--  * отсчёт — крупная надпись выигравшего модификатора;
--  * гонка — значок под таймером.
-- Состояние читается из атрибутов workspace (Shared/Modifier).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Modifier = require(Shared:WaitForChild("Modifier"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local M = Config.Modifiers
local CARD_W, CARD_H, GAP = 170, 136, 12

local player = Players.LocalPlayer
local voteRemote = Remotes.get(Remotes.Names.ModifierVote)

local gui = Instance.new("ScreenGui")
gui.Name = "ModifierHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 3

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

local function label(parent: Instance, text: string, font: Enum.Font, size: number, y: number, h: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 6, 0, y)
	l.Size = UDim2.new(1, -12, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextWrapped = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = parent
	return l
end

---------------------------------------------------------------- голосование

local panel = Instance.new("Frame")
panel.Name = "Vote"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.62)
panel.Size = UDim2.fromOffset(CARD_W * 3 + GAP * 2, CARD_H + 44)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = gui

local scale = Instance.new("UIScale")
scale.Parent = panel

local heading = label(panel, "Vote: race modifier", Enum.Font.GothamBlack, 22, 0, 32)
heading.TextStrokeTransparency = 0.4

type Card = { button: TextButton, icon: TextLabel, title: TextLabel, desc: TextLabel, votes: TextLabel, stroke: UIStroke }
local cards: { Card } = {}
local myVote = 0
local currentOptions = ""

for i = 1, M.Options do
	local b = Instance.new("TextButton")
	b.Name = "Card" .. i
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
	b.BackgroundTransparency = 0.15
	b.Position = UDim2.fromOffset((i - 1) * (CARD_W + GAP), 44)
	b.Size = UDim2.fromOffset(CARD_W, CARD_H)
	b.Parent = panel
	corner(b, 14)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(255, 210, 60)
	stroke.Enabled = false
	stroke.Parent = b
	local key = label(b, tostring(i), Enum.Font.GothamBold, 14, 4, 16)
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.TextTransparency = 0.5
	local card: Card = {
		button = b,
		icon = label(b, "", Enum.Font.GothamBold, 40, 6, 46),
		title = label(b, "", Enum.Font.GothamBlack, 18, 52, 22),
		desc = label(b, "", Enum.Font.Gotham, 13, 74, 34),
		votes = label(b, "", Enum.Font.GothamBold, 15, CARD_H - 24, 20),
		stroke = stroke,
	}
	-- длинное название («Низкая гравитация») ужимается в одну строку
	card.title.TextWrapped = false
	card.title.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = card.title
	card.desc.TextColor3 = Color3.fromRGB(200, 205, 220)
	card.votes.TextColor3 = Color3.fromRGB(255, 210, 60)
	b.Activated:Connect(function()
		if panel.Visible then
			myVote = i
			voteRemote:FireServer(i)
			-- подсветка сразу, не дожидаясь сервера
			for j, c in cards do
				c.stroke.Enabled = j == myVote
			end
		end
	end)
	cards[i] = card
end

-- влезть и по ширине, и по высоте (на телефоне карточки иначе закрывают пол-экрана и джойстик)
local function refreshScale()
	local size = Vector2.new(panel.Size.X.Offset, panel.Size.Y.Offset)
	scale.Scale = UiScale.fit(size, 0.94, Config.Ui.VoteHeightShare)
	panel.Position = UDim2.fromScale(0.5, if UiScale.isCompact() then 0.52 else 0.62)
end

local function refreshVote()
	local options = Modifier.options()
	local raw = table.concat(options, ",")
	if raw ~= currentOptions then
		currentOptions = raw
		myVote = 0 -- новое голосование
	end
	panel.Visible = #options > 0
	if not panel.Visible then
		return
	end
	refreshScale()
	local votes = Modifier.votes()
	for i, card in cards do
		local def = Modifier.def(options[i])
		card.button.Visible = def ~= nil
		if def then
			card.icon.Text = def.icon
			card.title.Text = def.title
			card.desc.Text = def.desc
			local n = votes[i] or 0
			card.votes.Text = if n > 0 then string.rep("●", math.min(n, 12)) else "—"
			card.stroke.Enabled = i == myVote
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not panel.Visible then
		return
	end
	local index = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 } :: { [Enum.KeyCode]: number })[input.KeyCode]
	local card = index and cards[index]
	if card and card.button.Visible then
		myVote = index :: number
		voteRemote:FireServer(index)
		refreshVote()
	end
end)

---------------------------------------------------------------- баннер и значок

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.38)
banner.Size = UDim2.fromOffset(520, 120)
banner.BackgroundTransparency = 1
banner.Visible = false
banner.Parent = gui
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner
local bannerTitle = label(banner, "", Enum.Font.GothamBlack, 54, 0, 70)
bannerTitle.TextStrokeTransparency = 0.2
local bannerDesc = label(banner, "", Enum.Font.GothamBold, 22, 72, 30)
bannerDesc.TextStrokeTransparency = 0.4

local badge = Instance.new("TextLabel")
badge.Name = "Badge"
badge.AnchorPoint = Vector2.new(1, 0)
badge.Position = UDim2.new(1, -Config.RaceHud.RightMargin, 0, Config.RaceHud.ModeTop)
badge.Size = UDim2.fromOffset(0, Config.RaceHud.ModeHeight)
badge.AutomaticSize = Enum.AutomaticSize.X
badge.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
badge.BackgroundTransparency = 0.35
badge.Font = Enum.Font.GothamBold
badge.TextSize = 16
badge.TextColor3 = Color3.new(1, 1, 1)
badge.Visible = false
badge.Parent = gui
corner(badge, 13)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = badge

-- string.upper не трогает кириллицу — поднимаем и её (на случай русских названий)
local function utf8upper(s: string): string
	s = string.upper(s)
	local out = {}
	for _, code in utf8.codes(s) do
		if code >= 0x430 and code <= 0x44F then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local bannerToken = 0
local shownActive: string? = nil

local function showBanner(def: any)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = def.icon .. " " .. utf8upper(def.title) .. "!"
	bannerDesc.Text = def.desc
	banner.Visible = true
	local camera = workspace.CurrentCamera
	local fit = math.min(1, (if camera then camera.ViewportSize.X else 1000) * 0.94 / banner.Size.X.Offset)
	bannerScale.Scale = 0.4 * fit
	TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	task.delay(M.BannerTime, function()
		if token == bannerToken then
			banner.Visible = false
		end
	end)
end

local function refreshActive()
	local id = Modifier.active()
	local def = Modifier.def(id)
	badge.Visible = def ~= nil
	if def then
		badge.Text = def.icon .. "  " .. def.title
		if id ~= shownActive then
			showBanner(def)
		end
	else
		banner.Visible = false
	end
	shownActive = id
end

workspace:GetAttributeChangedSignal(Modifier.OptionsAttr):Connect(refreshVote)
workspace:GetAttributeChangedSignal(Modifier.VotesAttr):Connect(refreshVote)
workspace:GetAttributeChangedSignal(Modifier.ActiveAttr):Connect(refreshActive)
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
end

gui.Parent = player:WaitForChild("PlayerGui")
refreshVote()
-- зашёл во время гонки — без баннера, только значок
shownActive = Modifier.active()
refreshActive()
