--!strict
-- Телефон — только горизонтально (как и StarterGui.ScreenOrientation = LandscapeSensor в плейсе):
-- дублируем в коде, чтобы ориентация не зависела от того, сохранён ли плейс.

local Players = game:GetService("Players")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
