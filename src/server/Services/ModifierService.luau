--!strict
-- Модификатор заезда: голосование в лобби и эффект на одну гонку.
--  * openVote()  — лобби пошло на таймер: случайные Options карточек из Pool, голоса с нуля;
--  * decide()    — конец лобби: побеждает больше голосов (ничья / без голосов — случайный из лидеров),
--                  эффект включается до старта;
--  * clear()     — гонка закончилась: всё как было (свет сезона, гравитация, фары).
-- Состояние для клиентов — атрибуты workspace (см. Shared/Modifier), голос — remote ModifierVote.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Modifier = require(ReplicatedStorage.Shared.Modifier)

local M = Config.Modifiers
local HEADLAMP_NAME = "ModifierHeadlamp"
local BASE_JUMP_ATTR = "ModifierBaseJump" -- исходная высота прыжка на Humanoid, чтобы вернуть
local GLOW_NAME = "ModifierGlow"

local ModifierService = {}

local ThemeService: any

local options: { string } = {}
local votes: { [Player]: number } = {} -- игрок -> номер карточки
local active: string? = nil
local defaultGravity = workspace.Gravity
local characterConn: { [Player]: RBXScriptConnection } = {}

local function log(fmt: string, ...: any)
	print("[ModifierService] " .. string.format(fmt, ...))
end

---------------------------------------------------------------- голосование

local function publishVotes()
	if #options == 0 then
		return
	end
	local counts = table.create(#options, 0)
	for _, index in votes do
		counts[index] += 1
	end
	local parts = {}
	for i = 1, #options do
		parts[i] = tostring(counts[i])
	end
	workspace:SetAttribute(Modifier.VotesAttr, table.concat(parts, ","))
end

local function onVote(player: Player, index: unknown)
	if #options == 0 or typeof(index) ~= "number" or index ~= index // 1 or index < 1 or index > #options then
		return
	end
	votes[player] = index
	publishVotes()
end

function ModifierService.openVote()
	table.clear(votes)
	local pool = table.clone(M.Pool)
	table.clear(options)
	for _ = 1, math.min(M.Options, #pool) do
		table.insert(options, table.remove(pool, math.random(#pool)) :: string)
	end
	workspace:SetAttribute(Modifier.OptionsAttr, table.concat(options, ","))
	publishVotes()
	log("vote: %s", table.concat(options, ", "))
end

---------------------------------------------------------------- эффекты

local function setAtmosphere(a: any)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere or not a then
		return
	end
	atmosphere.Density = a.density
	atmosphere.Offset = a.offset
	atmosphere.Haze = a.haze
	atmosphere.Glare = a.glare
	atmosphere.Color = a.color
	atmosphere.Decay = a.decay
end

local function removeHeadlamp(character: Model?)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, name in { HEADLAMP_NAME, GLOW_NAME } do
			local light = root:FindFirstChild(name)
			if light then
				light:Destroy()
			end
		end
	end
end

local function addHeadlamp(character: Model, h: any)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root or root:FindFirstChild(HEADLAMP_NAME) then
		return
	end
	local lamp = Instance.new("SpotLight")
	lamp.Name = HEADLAMP_NAME
	lamp.Face = Enum.NormalId.Front
	lamp.Range = h.range
	lamp.Brightness = h.brightness
	lamp.Angle = h.angle
	lamp.Color = h.color
	lamp.Shadows = false
	lamp.Parent = root
	-- лёгкое свечение вокруг, чтобы соперника было видно и сзади
	local glow = Instance.new("PointLight")
	glow.Name = GLOW_NAME
	glow.Range = h.glowRange
	glow.Brightness = h.glowBrightness
	glow.Color = h.color
	glow.Shadows = false
	glow.Parent = root
end

local function setJump(character: Model, multiplier: number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local base = humanoid:GetAttribute(BASE_JUMP_ATTR)
	if multiplier then
		if typeof(base) ~= "number" then
			humanoid:SetAttribute(BASE_JUMP_ATTR, humanoid.JumpHeight)
			humanoid.JumpHeight *= multiplier
		end
	elseif typeof(base) == "number" then
		humanoid.JumpHeight = base
		humanoid:SetAttribute(BASE_JUMP_ATTR, nil)
	end
end

-- Эффекты на персонажах (фары, прыжок): на текущих и на тех, кто появится до конца гонки.
local function decorate(character: Model, def: any)
	if def.headlamp then
		addHeadlamp(character, def.headlamp)
	end
	if def.jumpMultiplier then
		setJump(character, def.jumpMultiplier)
	end
end

local function watchCharacters(def: any)
	for _, player in Players:GetPlayers() do
		if player.Character then
			task.spawn(decorate, player.Character, def)
		end
		characterConn[player] = player.CharacterAdded:Connect(function(character)
			decorate(character, def)
		end)
	end
end

local function unwatchCharacters()
	for player, conn in characterConn do
		conn:Disconnect()
	end
	table.clear(characterConn)
	for _, player in Players:GetPlayers() do
		if player.Character then
			removeHeadlamp(player.Character)
			task.spawn(setJump, player.Character, nil)
		end
	end
end

local function apply(id: string)
	local def = Modifier.def(id)
	if not def then
		return
	end
	if def.lighting then
		local l = def.lighting
		Lighting.ClockTime = l.clockTime
		Lighting.Brightness = l.brightness
		Lighting.Ambient = l.ambient
		Lighting.OutdoorAmbient = l.outdoorAmbient
	end
	setAtmosphere(def.atmosphere)
	if def.gravity then
		workspace.Gravity = def.gravity
	end
	watchCharacters(def)
end

-- Конец лобби: выбрать победителя и включить.
function ModifierService.decide()
	if #options == 0 then
		return
	end
	local counts = table.create(#options, 0)
	for _, index in votes do
		counts[index] += 1
	end
	local best = math.max(table.unpack(counts))
	local leaders = {}
	for i, n in counts do
		if n == best then
			table.insert(leaders, options[i])
		end
	end
	local id = leaders[math.random(#leaders)]
	table.clear(options)
	table.clear(votes)
	workspace:SetAttribute(Modifier.OptionsAttr, nil)
	workspace:SetAttribute(Modifier.VotesAttr, nil)

	active = id
	apply(id)
	workspace:SetAttribute(Modifier.ActiveAttr, id)
	log("active: %s (%d vote(s))", id, best)
end

-- Конец гонки (или лобби сорвалось): вернуть всё как было.
function ModifierService.clear()
	if #options > 0 then
		table.clear(options)
		table.clear(votes)
		workspace:SetAttribute(Modifier.OptionsAttr, nil)
		workspace:SetAttribute(Modifier.VotesAttr, nil)
	end
	if not active then
		return
	end
	unwatchCharacters()
	workspace.Gravity = defaultGravity
	ThemeService.restoreLighting()
	log("cleared %s", active :: string)
	active = nil
	workspace:SetAttribute(Modifier.ActiveAttr, nil)
end

function ModifierService.getActive(): string?
	return active
end

function ModifierService.init(services: { [string]: any })
	ThemeService = services.ThemeService
end

function ModifierService.start()
	Remotes.get(Remotes.Names.ModifierVote).OnServerEvent:Connect(onVote)
	Players.PlayerRemoving:Connect(function(player)
		if votes[player] then
			votes[player] = nil
			publishVotes()
		end
		local conn = characterConn[player]
		if conn then
			conn:Disconnect()
			characterConn[player] = nil
		end
	end)
	-- зашедшие во время гонки тоже с фарами / прыжком
	Players.PlayerAdded:Connect(function(player)
		local def = Modifier.def(active)
		if def then
			characterConn[player] = player.CharacterAdded:Connect(function(character)
				decorate(character, def)
			end)
		end
	end)
end

return ModifierService
