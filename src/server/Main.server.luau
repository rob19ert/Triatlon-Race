--!strict
-- Единая точка входа сервера: создаёт RemoteEvent'ы и запускает сервисы.
-- Порядок: сначала init() у всех (связи между сервисами), потом start().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.createAll()

local servicesFolder = script.Parent:WaitForChild("Services")

local SERVICE_ORDER = {
	"ProgressTracker",
	"StaminaService",
	"RaceManager",
}

local services: { [string]: any } = {}
for _, name in SERVICE_ORDER do
	services[name] = require(servicesFolder:WaitForChild(name) :: ModuleScript)
end

for _, name in SERVICE_ORDER do
	local service = services[name]
	if service.init then
		service.init(services)
	end
end

for _, name in SERVICE_ORDER do
	local service = services[name]
	if service.start then
		service.start()
	end
end

print("[Main] Services started")
