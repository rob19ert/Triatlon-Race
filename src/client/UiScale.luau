--!strict
-- Подстройка интерфейса под экран: «компактный» — телефон (низкий экран в ландшафте).
-- UiScale.watch(fn) вызывает fn(compact, viewport) сразу и при каждом изменении размера окна.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local U = Config.Ui

local UiScale = {}

function UiScale.viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

function UiScale.isCompact(): boolean
	return UiScale.viewport().Y < U.CompactHeight
end

-- Множитель, чтобы блок size (в пикселях макета) влез в долю экрана shareX × shareY (не больше 1).
function UiScale.fit(size: Vector2, shareX: number, shareY: number): number
	local vp = UiScale.viewport()
	return math.min(1, vp.X * shareX / size.X, vp.Y * shareY / size.Y)
end

function UiScale.watch(fn: (compact: boolean, viewport: Vector2) -> ())
	local connection: RBXScriptConnection? = nil
	local function update()
		fn(UiScale.isCompact(), UiScale.viewport())
	end
	local function bind()
		if connection then
			connection:Disconnect()
		end
		local camera = workspace.CurrentCamera
		if camera then
			connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind)
	bind()
end

return UiScale
