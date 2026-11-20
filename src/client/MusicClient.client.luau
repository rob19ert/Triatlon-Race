--!strict
-- Фоновая музыка: трек по состоянию гонки (Config.Music.ByState) — лобби, гонка (по кругу), итоги.
-- Смена — плавная (затухание старого, нарастание нового). Играет только у этого игрока.
-- Кнопка 🎵 / 🔇 слева вверху — выключить/включить музыку (на эту сессию).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local M = Config.Music
local player = Players.LocalPlayer

local group = Instance.new("SoundGroup")
group.Name = "Music"
group.Volume = M.Volume
group.Parent = SoundService

local sounds: { [string]: Sound } = {}
for key, track in M.Tracks do
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. key
	sound.SoundId = "rbxassetid://" .. track.id
	sound.Looped = track.looped
	sound.Volume = 0
	sound.SoundGroup = group
	sound.Parent = SoundService
	sounds[key] = sound
end

local current: string? = nil
local muted = false

local function fade(sound: Sound, to: number, onDone: (() -> ())?)
	local tween = TweenService:Create(sound, TweenInfo.new(M.FadeTime, Enum.EasingStyle.Sine), { Volume = to })
	if onDone then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				onDone()
			end
		end)
	end
	tween:Play()
end

local function play(key: string?)
	if key == current then
		return
	end
	local old = if current then sounds[current] else nil
	current = key
	if old then
		local stopping = old
		fade(stopping, 0, function()
			if sounds[current or ""] ~= stopping then
				stopping:Stop()
			end
		end)
	end
	local new = if key then sounds[key] else nil
	if new then
		new.TimePosition = 0
		new.Volume = 0
		new:Play()
		fade(new, 1)
	end
end

Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	play((M.ByState :: any)[payload.state])
end)

-- до первого состояния от сервера — музыка лобби
if not current then
	play("Lobby")
end

---------------------------------------------------------------- кнопка 🎵 / 🔇

local gui = Instance.new("ScreenGui")
gui.Name = "MusicToggle"
gui.ResetOnSpawn = false

local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(0, 0)
button.Position = UDim2.new(0, 12, 0, 114) -- под кнопкой «Веломагазин»
button.Size = UDim2.fromOffset(40, 40)
UiScale.watch(function(compact: boolean)
	button.Position = UDim2.new(0, 12, 0, if compact then 94 else 114)
	button.Size = if compact then UDim2.fromOffset(34, 34) else UDim2.fromOffset(40, 40)
end)
button.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
button.BackgroundTransparency = 0.35
button.TextScaled = true
button.Font = Enum.Font.GothamBold
button.TextColor3 = Color3.new(1, 1, 1)
button.Text = "🎵"
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0.5, 0)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = button

button.Activated:Connect(function()
	muted = not muted
	group.Volume = if muted then 0 else M.Volume
	button.Text = if muted then "🔇" else "🎵"
end)

gui.Parent = player:WaitForChild("PlayerGui")
