--!strict
-- Кнопка «Пригласить друзей» (в лобби и на итогах): стандартное окно приглашений Roblox.
-- Друг, впервые зашедший по приглашению, приносит опыт обоим (считает сервер — DataService;
-- кто пригласил, Roblox передаёт сам). В LaunchData — UserId пригласившего (запасной путь).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local I = Config.Invites
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "InviteHud"
gui.ResetOnSpawn = false

local button = Instance.new("TextButton")
button.Name = "Invite"
button.AutomaticSize = Enum.AutomaticSize.X
button.BackgroundColor3 = Color3.fromRGB(70, 160, 255)
button.TextColor3 = Color3.new(1, 1, 1)
button.Font = Enum.Font.GothamBlack
button.Text = string.format("%s  +%d XP", I.Button, I.InviterXP)
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(22, 27, 44)
stroke.Thickness = 3
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = button
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = button

-- под кнопками «Bike Shop» и музыки
UiScale.watch(function(compact: boolean)
	button.Position = UDim2.fromOffset(12, if compact then 136 else 164)
	button.Size = UDim2.fromOffset(0, if compact then 32 else 40)
	button.TextSize = if compact then 14 else 17
end)

local function canInvite(): boolean
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	return ok and can == true
end

button.Activated:Connect(function()
	if not canInvite() then
		return
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.PromptMessage = I.Prompt
	options.LaunchData = tostring(player.UserId)
	pcall(SocialService.PromptGameInvite, SocialService, player, options)
end)

-- видна в лобби, на отсчёте и на итогах; в гонке не мешает
Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	button.Visible = payload.state ~= "Racing"
end)

-- где приглашать нельзя (платформа, настройки аккаунта) — кнопку не показываем вовсе
task.spawn(function()
	gui.Enabled = canInvite() or RunService:IsStudio() -- в Studio окна приглашений нет, но вид проверяем
end)

gui.Parent = player:WaitForChild("PlayerGui")
