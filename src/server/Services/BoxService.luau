--!strict
-- Секретные боксы «?» на трассе (всё решает сервер):
--  * на Active случайных точках (теги BoxSpot) стоят боксы;
--  * участник на трассе (не на рубеже) проехал сквозь бокс — получает случайный бонус только себе,
--    бокс пропадает у всех и через RespawnTime появляется в другой свободной точке;
--  * бонусы: ⚡ Турбо (то же, что за 5/5), 💥 Мега-толчок на N секунд, 🎯 Большие мишени на следующую стрельбу,
--    🛡 Щит (одно попадание), 👻 Призрак (сквозь препятствия), 💚 Второе дыхание (пульс вниз), ⏱ −2 с,
--    🦘 Пружина (3 высоких прыжка), 🎲 Рулетка (случайный, подвох или польза);
--  * подвохи: 🐌 Улитка, 🔄 Наоборот — лидеру чаще, последнему редко; щит/призрак их гасят.
-- Боксы стоят всё время (и в лобби — видно, где они), брать можно только в гонке.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local Protection = require(script.Parent.Parent.Lib.Protection)

local B = Config.Boxes

local BoxService = {}

local RaceManager: any
local ProgressTracker: any
local ShootingService: any
local StaminaService: any
local PenaltyService: any
local AnalyticsTracker: any
local takenRemote: RemoteEvent

local spots: { BasePart } = {}
local boxes: { [BasePart]: BasePart } = {} -- точка -> бокс на ней
local reserved: { [BasePart]: boolean } = {} -- точка ждёт респауна (бокс только что взят)
local folder: Folder
local rng = Random.new()
local lastEffect: { [Player]: string } = {} -- последний выпавший бонус (не повторяем подряд)
local springConn: { [Player]: RBXScriptConnection } = {}

local function log(fmt: string, ...: any)
	print("[BoxService] " .. string.format(fmt, ...))
end

---------------------------------------------------------------- боксы

local function makeBox(spot: BasePart): BasePart
	local box = Instance.new("Part")
	box.Name = "PowerBox"
	box.Size = Vector3.one * B.Size
	box.CFrame = CFrame.new(spot.Position)
	box.Color = B.Color
	box.Material = Enum.Material.Neon
	box.Transparency = 0.15
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	for _, face in Enum.NormalId:GetEnumItems() do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "?"
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = box
	end
	CollectionService:AddTag(box, B.BoxTag)
	box.Parent = folder
	return box
end

-- Свободная точка (без бокса и не только что опустевшая), случайная.
local function freeSpot(): BasePart?
	local free = {}
	for _, spot in spots do
		if not boxes[spot] and not reserved[spot] then
			table.insert(free, spot)
		end
	end
	return if #free > 0 then free[rng:NextInteger(1, #free)] else nil
end

local function spawnOne()
	local spot = freeSpot()
	if spot then
		boxes[spot] = makeBox(spot)
	end
end

---------------------------------------------------------------- бонусы

-- Есть ли рядом соперник в гонке (иначе мега-толчок некого толкать).
local function rivalNear(player: Player, radius: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, other in Players:GetPlayers() do
		local oc = other ~= player and RaceManager.isParticipant(other) and ProgressTracker.isTracked(other) and other.Character
		local oroot = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
		if oroot and (oroot.Position - root.Position).Magnitude <= radius then
			return true
		end
	end
	return false
end

-- Бонус бесполезен прямо сейчас: «Большие мишени» уже есть или стрельб больше не будет,
-- мега-толчок без соперников рядом, второе дыхание при спокойном пульсе.
local function isUseless(player: Player, effect: string): boolean
	if effect == "MegaPush" then
		return not rivalNear(player, B.Defs.MegaPush.rivalRadius)
	elseif effect == "BigTargets" then
		return player:GetAttribute(Attributes.BigTargets) == true
			or ShootingService.getCompletedStages(player) >= ShootingService.getRangeCount()
	elseif effect == "SecondWind" then
		return (StaminaService.getPulse(player) or 0) < B.Defs.SecondWind.uselessBelow
	end
	return false
end

-- Бонус по времени ещё действует (повтор только продлит его).
local function isActive(player: Player, effect: string): boolean
	local name = if effect == "Turbo"
		then Attributes.TurboUntil
		elseif effect == "MegaPush" then Attributes.MegaPushUntil
		elseif effect == "Shield" then Attributes.ShieldUntil
		elseif effect == "Ghost" then Attributes.GhostUntil
		elseif effect == "Snail" then Attributes.SnailUntil
		elseif effect == "Invert" then Attributes.InvertUntil
		else nil
	if effect == "Spring" then
		return (player:GetAttribute(Attributes.SpringJumps) or 0) :: number > 0
	end
	local v = name and player:GetAttribute(name)
	return typeof(v) == "number" and v > workspace:GetServerTimeNow()
end

local function kindOf(effect: string): string
	return ((B.Defs :: any)[effect].kind or "good") :: string
end

-- Шанс подвоха по месту: лидер — Leader, последний — Last, между ними плавно.
local function badChance(player: Player): number
	local place, count = RaceManager.getPlace(player)
	if not place or count <= 1 then
		return B.BadChance.Solo
	end
	local f = (place - 1) / (count - 1)
	return B.BadChance.Leader + (B.BadChance.Last - B.BadChance.Leader) * f
end

-- Случайный бонус. По порядку ослабляем правила, пока есть из чего выбрать:
-- не бесполезный, не действующий, не прошлый → … → не бесполезный (полезное есть всегда: −2 с).
-- wantBad: true — только подвохи (и «any»), false — только польза (и «any»); nil — любой.
local function pickEffect(player: Player, wantBad: boolean?, exclude: string?): string
	local last = lastEffect[player]
	local function filter(skipActive: boolean, skipLast: boolean): { string }
		local list = {}
		for _, effect in B.Effects do
			local kind = kindOf(effect)
			local kindOk = wantBad == nil or kind == "any" or (kind == "bad") == wantBad
			if effect ~= exclude and kindOk and not isUseless(player, effect) and not (skipActive and isActive(player, effect)) and not (skipLast and effect == last) then
				table.insert(list, effect)
			end
		end
		return list
	end
	local pools = { filter(true, true), filter(true, false), filter(false, true), filter(false, false) }
	for _, list in pools do
		if #list > 0 then
			return list[rng:NextInteger(1, #list)]
		end
	end
	return if wantBad then pickEffect(player, nil, exclude) else "TimeBonus"
end

-- «Пружина»: JumpHeight ×multiplier на jumps прыжков (или до конца seconds).
local function endSpring(player: Player, humanoid: Humanoid?)
	local conn = springConn[player]
	if conn then
		conn:Disconnect()
		springConn[player] = nil
		local mult = B.Defs.Spring.multiplier
		if humanoid and humanoid.Parent then
			humanoid.JumpHeight /= mult
		end
		log("%s spring over (%s jump(s) left)", player.Name, tostring(player:GetAttribute(Attributes.SpringJumps)))
	end
	player:SetAttribute(Attributes.SpringJumps, nil)
end

local function startSpring(player: Player)
	local def = B.Defs.Spring
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	endSpring(player, humanoid)
	humanoid.JumpHeight *= def.multiplier
	player:SetAttribute(Attributes.SpringJumps, def.jumps)
	springConn[player] = humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			local left = ((player:GetAttribute(Attributes.SpringJumps) or 0) :: number) - 1
			player:SetAttribute(Attributes.SpringJumps, left)
			if left <= 0 then
				-- дать оттолкнуться высоко, потом вернуть обычный прыжок
				task.delay(0.3, endSpring, player, humanoid)
			end
		end
	end)
	local conn = springConn[player]
	task.delay(def.seconds, function()
		if springConn[player] == conn then
			endSpring(player, humanoid)
		end
	end)
end

-- Выдать бонус. Возвращает, во что превратилась рулетка, и погашен ли подвох защитой.
local function grant(player: Player, effect: string): (string?, boolean)
	local def = (B.Defs :: any)[effect]
	if effect == "Roulette" then
		local rolled = pickEffect(player, rng:NextNumber() < 0.5, "Roulette")
		local _, blocked = grant(player, rolled)
		return rolled, blocked
	end
	if def.kind == "bad" and Protection.absorb(player) then
		return nil, true
	end
	if effect == "Snail" then
		StaminaService.grantSlow(player, def.speed, def.seconds)
	elseif effect == "Invert" then
		player:SetAttribute(Attributes.InvertUntil, workspace:GetServerTimeNow() + def.seconds)
	elseif effect == "Spring" then
		startSpring(player)
	elseif effect == "Turbo" then
		StaminaService.grantTurbo(player, def.seconds)
	elseif effect == "MegaPush" then
		player:SetAttribute(Attributes.MegaPushUntil, workspace:GetServerTimeNow() + def.seconds)
	elseif effect == "BigTargets" then
		player:SetAttribute(Attributes.BigTargets, true)
	elseif effect == "Shield" then
		player:SetAttribute(Attributes.ShieldUntil, workspace:GetServerTimeNow() + def.seconds)
	elseif effect == "Ghost" then
		player:SetAttribute(Attributes.GhostUntil, workspace:GetServerTimeNow() + def.seconds)
	elseif effect == "SecondWind" then
		local pulse = StaminaService.getPulse(player)
		if pulse and pulse > def.pulse then
			StaminaService.addPulse(player, def.pulse - pulse)
		end
	elseif effect == "TimeBonus" then
		PenaltyService.add(player, -def.seconds)
	end
	return nil, false
end

local function take(player: Player, spot: BasePart, box: BasePart)
	boxes[spot] = nil
	reserved[spot] = true
	local position = box.Position
	box:Destroy()
	local effect = pickEffect(player, rng:NextNumber() < badChance(player))
	lastEffect[player] = effect
	local rolled, blocked = grant(player, effect)
	takenRemote:FireAllClients(position, player.UserId, effect, rolled, blocked)
	log("%s took %s%s%s", player.Name, effect, if rolled then " -> " .. rolled else "", if blocked then " (blocked)" else "")
	AnalyticsTracker.boxTaken(player, effect, rolled)
	task.delay(B.RespawnTime, function()
		spawnOne() -- сначала новая точка, потом освобождаем старую: бокс не вернётся туда же
		reserved[spot] = nil
	end)
end

local function step()
	if RaceManager.getState() ~= "Racing" then
		return
	end
	for _, player in Players:GetPlayers() do
		if not RaceManager.isParticipant(player) or not ProgressTracker.isTracked(player) or ShootingService.isShooting(player) then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		for spot, box in boxes do
			if (box.Position - root.Position).Magnitude <= B.PickupRadius then
				take(player, spot, box)
				break
			end
		end
	end
end

-- Новая гонка: бонусы прошлой не переносятся.
local function clearPlayerBonuses()
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Attributes.MegaPushUntil, nil)
		player:SetAttribute(Attributes.BigTargets, nil)
		player:SetAttribute(Attributes.ShieldUntil, nil)
		player:SetAttribute(Attributes.GhostUntil, nil)
		player:SetAttribute(Attributes.InvertUntil, nil)
		local character = player.Character
		endSpring(player, character and character:FindFirstChildOfClass("Humanoid"))
	end
	table.clear(lastEffect)
end

function BoxService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	StaminaService = services.StaminaService
	PenaltyService = services.PenaltyService
	AnalyticsTracker = services.AnalyticsTracker
	takenRemote = Remotes.get(Remotes.Names.BoxTaken)
end

function BoxService.start()
	for _, spot in CollectionService:GetTagged(B.SpotTag) do
		if spot:IsA("BasePart") then
			table.insert(spots, spot)
		end
	end
	folder = Instance.new("Folder")
	folder.Name = "PowerBoxes"
	folder.Parent = workspace
	for _ = 1, math.min(B.Active, #spots) do
		spawnOne()
	end
	log("%d spot(s), %d box(es)", #spots, math.min(B.Active, #spots))
	Players.PlayerRemoving:Connect(function(player)
		lastEffect[player] = nil
		local conn = springConn[player]
		if conn then
			conn:Disconnect()
			springConn[player] = nil
		end
	end)

	local lastState = RaceManager.getState()
	RunService.Heartbeat:Connect(function()
		local state = RaceManager.getState()
		if state ~= lastState then
			if state == "Countdown" or state == "Results" then
				clearPlayerBonuses()
			end
			lastState = state
		end
		step()
	end)
end

return BoxService
