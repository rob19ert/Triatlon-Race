--!strict
-- Большие экранные кнопки для тача, дугой вокруг стандартной кнопки прыжка.
-- Создаются на устройствах с тачем (без тача create возвращает nil), а видны в «тач-режиме»:
-- последний ввод был касанием, или клавиатуры нет вовсе. Взялся за клавиатуру/мышь — кнопки прячутся.
-- (KeyboardEnabled в эмуляторе Studio и на планшетах с клавиатурой меняется на лету, поэтому
-- решаем по последнему вводу, как стандартное тач-управление Roblox.)
-- Раскладка повторяет логику Roblox для кнопки прыжка: маленький экран (мин. сторона ≤ 500) — 70 px, иначе 120 px.
--
-- Слоты (угол от центра кнопки прыжка): 1 — слева, 2 — слева-сверху, 3 — сверху, 4 — дальше слева.
-- Несколько кнопок могут делить слот, если видны в разное время (бег / рубеж).
-- Группы: setGroupHidden("run", true) прячет все кнопки группы (например, пока стреляешь).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local TouchButtons = {}

export type Options = {
	name: string,
	title: string,
	slot: number,
	group: string?,
	color: Color3?,
	big: boolean?, -- крупнее обычного (Огонь)
	onDown: (() -> ())?,
	onUp: (() -> ())?,
}

export type Handle = {
	setTitle: (self: Handle, text: string) -> (),
	setCooldown: (self: Handle, fraction: number) -> (), -- 0 — готово, 1 — только что нажали
	setVisible: (self: Handle, visible: boolean) -> (),
	destroy: (self: Handle) -> (),
}

-- угол слота: 0° — влево от прыжка, 90° — вверх; множитель радиуса
local SLOTS: { { angle: number, radius: number } } = {
	{ angle = 0, radius = 1 },
	{ angle = 54, radius = 1 },
	{ angle = 100, radius = 1 },
	{ angle = 22, radius = 1.95 },
}

local DEFAULT_COLOR = Color3.fromRGB(255, 170, 40)

type Entry = {
	options: Options,
	button: TextButton,
	shade: Frame,
	visible: boolean,
}

local entries: { [string]: Entry } = {}
local hiddenGroups: { [string]: boolean } = {}
local gui: ScreenGui? = nil

local function getGui(): ScreenGui
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "TouchButtons"
	g.ResetOnSpawn = false
	g.DisplayOrder = 5
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
	return g
end

-- Настоящая кнопка прыжка (если стандартное тач-управление уже создано).
local function findJumpButton(): GuiObject?
	local touchGui = Players.LocalPlayer:FindFirstChild("PlayerGui") and Players.LocalPlayer.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	return if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then jump else nil
end

-- Центр кнопки прыжка и её размер (в координатах нашего ScreenGui).
local function jumpGeometry(): (Vector2, number)
	local g = getGui()
	local jump = findJumpButton()
	if jump then
		local center = jump.AbsolutePosition + jump.AbsoluteSize / 2
		local jumpGui = jump:FindFirstAncestorOfClass("ScreenGui")
		if jumpGui and jumpGui.IgnoreGuiInset ~= g.IgnoreGuiInset then
			local inset = GuiService:GetGuiInset()
			center += if jumpGui.IgnoreGuiInset then -inset else inset
		end
		return center, jump.AbsoluteSize.X
	end
	-- запасной вариант — формула стандартного TouchJump
	local screen = g.AbsoluteSize
	local small = math.min(screen.X, screen.Y) <= 500
	local size = if small then 70 else 120
	local left = screen.X - (size * 1.5 - 10)
	local top = if small then screen.Y - size - 20 else screen.Y - size * 1.75
	return Vector2.new(left + size / 2, top + size / 2), size
end

local function layout()
	local center, jumpSize = jumpGeometry()
	local small = jumpSize < 100
	local baseSize = if small then 62 else 92
	local gap = if small then 14 else 20 -- зазор между краем прыжка и краем кнопки
	for _, e in entries do
		local slot = SLOTS[e.options.slot] or SLOTS[1]
		local size = if e.options.big then baseSize * 1.2 else baseSize
		local a = math.rad(slot.angle)
		local r = (jumpSize / 2 + size / 2 + gap) * slot.radius
		local pos = center + Vector2.new(-math.cos(a) * r, -math.sin(a) * r)
		e.button.Size = UDim2.fromOffset(size, size)
		e.button.Position = UDim2.fromOffset(pos.X, pos.Y)
		e.button.TextSize = math.floor(size * 0.24)
	end
end

local function refreshVisibility(e: Entry)
	local group = e.options.group
	e.button.Visible = e.visible and not (group and hiddenGroups[group])
end

local TOUCH_INPUT = Enum.UserInputType.Touch
local KEYBOARD_MOUSE: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseWheel] = true,
}

local touchMode = UserInputService.TouchEnabled
	and (not UserInputService.KeyboardEnabled or UserInputService:GetLastInputType() == TOUCH_INPUT)

-- Сейчас играют пальцами (кнопки на экране видны).
function TouchButtons.isTouch(): boolean
	return touchMode
end

function TouchButtons.create(options: Options): Handle?
	if not UserInputService.TouchEnabled then
		return nil
	end
	local old = entries[options.name]
	if old then
		old.button:Destroy()
	end

	local button = Instance.new("TextButton")
	button.Name = options.name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.AutoButtonColor = false
	button.BackgroundColor3 = options.color or DEFAULT_COLOR
	button.BackgroundTransparency = 0.1
	button.Font = Enum.Font.FredokaOne
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.5
	button.Text = options.title
	button.ZIndex = 2
	Instance.new("UICorner", button).CornerRadius = UDim.new(0.5, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	-- затемнение на время отката: высота = доля оставшегося времени
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.ZIndex = 1
	shade.Parent = button
	Instance.new("UICorner", shade).CornerRadius = UDim.new(0.5, 0)

	local entry: Entry = { options = options, button = button, shade = shade, visible = true }
	entries[options.name] = entry

	-- удержание: отпускание считаем по тому же касанию, даже если палец съехал с кнопки
	local activeInput: InputObject? = nil
	button.InputBegan:Connect(function(input)
		if activeInput or input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		activeInput = input
		button.BackgroundTransparency = 0.35
		if options.onDown then
			options.onDown()
		end
	end)
	local function release(input: InputObject)
		if input ~= activeInput then
			return
		end
		activeInput = nil
		button.BackgroundTransparency = 0.1
		if options.onUp then
			options.onUp()
		end
	end
	local endedConn = UserInputService.InputEnded:Connect(release)
	button.InputEnded:Connect(release)

	button.Parent = getGui()
	layout()
	refreshVisibility(entry)

	local handle = {}
	function handle.setTitle(_: Handle, text: string)
		if button.Text ~= text then
			button.Text = text
		end
	end
	function handle.setCooldown(_: Handle, fraction: number)
		shade.Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1))
	end
	function handle.setVisible(_: Handle, visible: boolean)
		entry.visible = visible
		refreshVisibility(entry)
	end
	function handle.destroy(_: Handle)
		if entries[options.name] == entry then
			entries[options.name] = nil
		end
		endedConn:Disconnect()
		button:Destroy()
	end
	return (handle :: any) :: Handle
end

function TouchButtons.setGroupHidden(group: string, hidden: boolean)
	hiddenGroups[group] = hidden or nil
	for _, e in entries do
		refreshVisibility(e)
	end
end

if UserInputService.TouchEnabled then
	local g = getGui()
	g.Enabled = touchMode
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if inputType == TOUCH_INPUT then
			touchMode = true
		elseif KEYBOARD_MOUSE[inputType] then
			touchMode = false
		else
			return -- геймпад и прочее — не меняем
		end
		g.Enabled = touchMode
	end)
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	-- кнопка прыжка появляется/переезжает позже нас (поворот экрана, респаун) — подстраиваемся
	task.spawn(function()
		local last: Vector2? = nil
		while true do
			task.wait(0.5)
			local center = jumpGeometry()
			if center ~= last then
				last = center
				layout()
			end
		end
	end)
end

return TouchButtons
