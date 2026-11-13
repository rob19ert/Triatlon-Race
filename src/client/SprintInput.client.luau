--!strict
-- Спринт: зажать Shift (клавиатура), L3 (геймпад) или кнопку «Спринт» на экране (тач, модуль TouchButtons).
-- Клиент шлёт только намерение; можно ли бежать быстрее — решает сервер.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local TouchButtons = require(script.Parent:WaitForChild("TouchButtons"))

local ACTION = "Sprint"

local sprintRemote = Remotes.get(Remotes.Names.SprintIntent)
local wantsSprint = false

local function setSprint(value: boolean)
	if value ~= wantsSprint then
		wantsSprint = value
		sprintRemote:FireServer(value)
	end
end

local function onAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		setSprint(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setSprint(false)
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(ACTION, onAction, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)

-- тач: держать кнопку
TouchButtons.create({
	name = "Sprint",
	title = "Спринт",
	slot = 1,
	group = "run",
	color = Color3.fromRGB(70, 170, 255),
	onDown = function()
		setSprint(true)
	end,
	onUp = function()
		setSprint(false)
	end,
})
