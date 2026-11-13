--!strict
-- Сезон карты: красит детали с тегом Themed по роли (атрибут Role) из Shared/Themes,
-- настраивает свет и атмосферу, показывает только папку Decor/<Сезон>.
-- Детали анкорные и неподвижные, поэтому красим на сервере — изменения реплицируются всем.
-- Сезонный декор прячем, перенося папки в ServerStorage (меньше деталей у клиентов).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Themes = require(ReplicatedStorage.Shared.Themes)

local T = Config.Theme

local ThemeService = {}

local current: string? = nil
local storedDecor: Folder -- спрятанные сезонные папки

local function log(fmt: string, ...: any)
	print("[ThemeService] " .. string.format(fmt, ...))
end

local function paint(part: Instance, theme: Themes.Theme)
	if not part:IsA("BasePart") then
		return
	end
	local role = part:GetAttribute(T.RoleAttribute)
	local style = if typeof(role) == "string" then theme.roles[role] else nil
	if style then
		part.Color = style.color
		part.Material = style.material
	end
end

local function applyLighting(theme: Themes.Theme)
	local l = theme.lighting
	Lighting.ClockTime = l.clockTime
	Lighting.Brightness = l.brightness
	Lighting.Ambient = l.ambient
	Lighting.OutdoorAmbient = l.outdoorAmbient
	Lighting.ColorShift_Top = l.colorShiftTop

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	local a = theme.atmosphere
	local atm = atmosphere :: Atmosphere
	atm.Density = a.density
	atm.Offset = a.offset
	atm.Color = a.color
	atm.Decay = a.decay
	atm.Glare = a.glare
	atm.Haze = a.haze
end

-- Видна только папка текущего сезона, остальные — в ServerStorage.
local function applyDecor(season: string)
	local decor = workspace:FindFirstChild(T.DecorFolder)
	if not decor then
		return
	end
	for _, folder in decor:GetChildren() do
		if folder:IsA("Folder") and Themes[folder.Name] and folder.Name ~= season then
			folder.Parent = storedDecor
		end
	end
	local wanted = storedDecor:FindFirstChild(season)
	if wanted then
		wanted.Parent = decor
	end
end

function ThemeService.apply(season: string)
	local theme = Themes[season]
	if not theme then
		warn("[ThemeService] unknown season " .. season)
		return
	end
	current = season
	local count = 0
	for _, part in CollectionService:GetTagged(T.Tag) do
		paint(part, theme)
		count += 1
	end
	applyLighting(theme)
	applyDecor(season)
	workspace:SetAttribute("Season", season)
	log("season %s applied to %d part(s)", season, count)
end

function ThemeService.getSeason(): string?
	return current
end

function ThemeService.start()
	storedDecor = Instance.new("Folder")
	storedDecor.Name = "SeasonDecor"
	storedDecor.Parent = ServerStorage

	ThemeService.apply(T.Current)
	-- детали, добавленные позже (например, если декор догрузится), тоже красим
	CollectionService:GetInstanceAddedSignal(T.Tag):Connect(function(part)
		local theme = current and Themes[current]
		if theme then
			paint(part, theme)
		end
	end)
end

return ThemeService
