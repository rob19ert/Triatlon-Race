--!strict
-- Спринт: зажать Shift (клавиатура), L3 (геймпад) или кнопку «Спринт» на экране (тач).
-- Клиент шлёт только намерение; можно ли бежать быстрее — решает сервер.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

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

-- true = создать кнопку на экране для сенсорных устройств
ContextActionService:BindAction(ACTION, onAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle(ACTION, "Спринт")
ContextActionService:SetPosition(ACTION, UDim2.new(1, -170, 1, -90))
