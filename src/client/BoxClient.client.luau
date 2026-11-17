--!strict
-- Секретные боксы у клиента (только картинка, всё решает сервер — BoxService):
--  * боксы на трассе крутятся и покачиваются;
--  * бокс взяли — вспышка конфетти у всех;
--  * свои бонусы — плашки у левого края: «💥 МЕГА-ТОЛЧОК 4.2», «🎯 Большие мишени»…
-- Турбо из бокса показывает TurboFx (то же турбо, что за 5/5).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Attributes = require(Shared:WaitForChild("Attributes"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local B = Config.Boxes
local SPIN = 1.6 -- рад/с
local BOB = 0.5 -- стад вверх-вниз
local player = Players.LocalPlayer

---------------------------------------------------------------- вращение

-- исходное положение каждого бокса (сервер ставит, клиент только крутит вокруг него)
local homes: { [BasePart]: CFrame } = {}

local function track(box: Instance)
	if box:IsA("BasePart") then
		homes[box] = box.CFrame
	end
end
for _, box in CollectionService:GetTagged(B.BoxTag) do
	track(box)
end
CollectionService:GetInstanceAddedSignal(B.BoxTag):Connect(track)
CollectionService:GetInstanceRemovedSignal(B.BoxTag):Connect(function(box)
	homes[box :: BasePart] = nil
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for box, home in homes do
		local phase = home.Position.X * 0.1 + home.Position.Z * 0.1 -- соседи не в такт
		box.CFrame = home * CFrame.new(0, math.sin(t * 2 + phase) * BOB, 0) * CFrame.Angles(0.3, t * SPIN + phase, 0.3)
	end
end)


---------------------------------------------------------------- плашки своих бонусов

local gui = Instance.new("ScreenGui")
gui.Name = "BoxHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- плашки — колонкой у левого края (центр экрана не закрываем), видимые идут подряд
local column = Instance.new("Frame")
column.AnchorPoint = Vector2.new(0, 0.5)
column.Position = UDim2.new(0, 16, 0.4, 0)
column.Size = UDim2.fromOffset(240, 140)
column.BackgroundTransparency = 1
column.Parent = gui
local layout = Instance.new("UIListLayout")
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = column

local function pill(order: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.fromOffset(0, 24)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = color
	label.BackgroundTransparency = 0.1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Visible = false
	label.Parent = column
	Instance.new("UICorner", label).CornerRadius = UDim.new(0.4, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = label
	return label
end

local D = B.Defs
local TOAST_SECONDS = 3
local toast = pill(0, Color3.fromRGB(30, 30, 40)) -- что выпало из бокса: «🛡 Щит — погасит один удар»
local toastUntil = 0
local mega = pill(1, Color3.fromRGB(220, 60, 60))
local ghostPill = pill(2, Color3.fromRGB(120, 110, 170))
local shieldPill = pill(3, Color3.fromRGB(60, 170, 120))
local big = pill(4, Color3.fromRGB(40, 140, 220))
local springPill = pill(5, Color3.fromRGB(200, 120, 40))
local snailPill = pill(6, Color3.fromRGB(110, 90, 60))
local invertPill = pill(7, Color3.fromRGB(170, 60, 160))

local function left(p: Player, name: string): number
	local v = p:GetAttribute(name)
	return if typeof(v) == "number" then v - workspace:GetServerTimeNow() else 0
end

local function describe(effect: string): string
	local def = (D :: any)[effect]
	return if def then string.format("%s %s — %s", def.icon, def.title, def.hint) else effect
end

Remotes.get(Remotes.Names.BoxTaken).OnClientEvent:Connect(function(position: Vector3, userId: number, effect: string, rolled: string?, blocked: boolean?)
	Fx.burst("Confetti", position)
	if userId ~= player.UserId or not (D :: any)[effect] then
		return
	end
	local shown = rolled or effect
	local text = if blocked
		then string.format("%s %s — щит погасил!", (D :: any)[shown].icon, (D :: any)[shown].title)
		else describe(shown)
	if rolled then
		text = D.Roulette.icon .. " Рулетка → " .. text
	end
	toast.Text = text
	toastUntil = os.clock() + TOAST_SECONDS
end)

---------------------------------------------------------------- «Наоборот»: лево и право перепутаны
-- После штатного управления (клавиатура, стик, тач) зеркалим направление движения относительно камеры.
RunService:BindToRenderStep("BoxInvert", Enum.RenderPriority.Input.Value + 1, function()
	if left(player, Attributes.InvertUntil) <= 0 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not humanoid or not camera then
		return
	end
	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.01 then
		return
	end
	local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
	if right.Magnitude < 0.01 then
		return
	end
	right = right.Unit
	humanoid:Move(dir - 2 * dir:Dot(right) * right, false)
end)

---------------------------------------------------------------- щит и призрак у всех

local BUBBLE_NAME = "ShieldBubble"

local function bubbleFor(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local existing = character:FindFirstChild(BUBBLE_NAME)
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local ball = Instance.new("Part")
	ball.Name = BUBBLE_NAME
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 7
	ball.Material = Enum.Material.ForceField
	ball.Color = Color3.fromRGB(90, 220, 160)
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Massless = true
	ball.CastShadow = false
	ball.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ball
	weld.Parent = ball
	ball.Parent = character -- только у этого клиента: Instance создан локально
	return ball
end

-- кому мы сделали персонажа прозрачным (чтобы вернуть)
local ghosted: { [Model]: boolean } = {}

local function setGhost(character: Model, amount: number)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= BUBBLE_NAME and d.Name ~= "HumanoidRootPart" then
			d.LocalTransparencyModifier = amount
		end
	end
end

-- щит пропал раньше срока — значит, погасил удар: вспышка
local shieldSeen: { [Player]: number } = {}

RunService.Heartbeat:Connect(function()
	-- свои плашки
	toast.Visible = os.clock() < toastUntil
	local megaLeft = left(player, Attributes.MegaPushUntil)
	mega.Visible = megaLeft > 0
	if megaLeft > 0 then
		mega.Text = string.format("%s МЕГА-ТОЛЧОК %.1f", D.MegaPush.icon, megaLeft)
	end
	local ghostLeft = left(player, Attributes.GhostUntil)
	ghostPill.Visible = ghostLeft > 0
	if ghostLeft > 0 then
		ghostPill.Text = string.format("%s ПРИЗРАК %.1f", D.Ghost.icon, ghostLeft)
	end
	shieldPill.Visible = left(player, Attributes.ShieldUntil) > 0
	if shieldPill.Visible then
		shieldPill.Text = D.Shield.icon .. " Щит"
	end
	local jumps = player:GetAttribute(Attributes.SpringJumps)
	springPill.Visible = typeof(jumps) == "number" and jumps > 0
	if springPill.Visible then
		springPill.Text = string.format("%s Пружина ×%d", D.Spring.icon, jumps :: number)
	end
	local snailLeft = left(player, Attributes.SnailUntil)
	snailPill.Visible = snailLeft > 0
	if snailLeft > 0 then
		snailPill.Text = string.format("%s УЛИТКА %.1f", D.Snail.icon, snailLeft)
	end
	local invertLeft = left(player, Attributes.InvertUntil)
	invertPill.Visible = invertLeft > 0
	if invertLeft > 0 then
		invertPill.Text = string.format("%s НАОБОРОТ %.1f", D.Invert.icon, invertLeft)
	end
	big.Visible = player:GetAttribute(Attributes.BigTargets) == true
	if big.Visible then
		big.Text = D.BigTargets.icon .. " Большие мишени"
	end

	-- щит и призрак у всех игроков
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if not character then
			continue
		end
		local shieldLeft = left(p, Attributes.ShieldUntil)
		local bubble = character:FindFirstChild(BUBBLE_NAME)
		if shieldLeft > 0 then
			bubbleFor(character)
			shieldSeen[p] = shieldLeft
		else
			if bubble then
				bubble:Destroy()
				local was = shieldSeen[p]
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if was and was > 0.3 and root then
					Fx.burst("Dust", root.Position)
				end
			end
			shieldSeen[p] = nil
		end
		if left(p, Attributes.GhostUntil) > 0 then
			setGhost(character, D.Ghost.transparency)
			ghosted[character] = true
		elseif ghosted[character] then
			setGhost(character, 0)
			ghosted[character] = nil
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	shieldSeen[p] = nil
end)
