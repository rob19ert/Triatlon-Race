--!strict
-- 3D previews for the bike shop: static thumbnails and a spinning podium.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")).Cosmetics.Showroom

local ShopPreview = {}
local rgb = Color3.fromRGB

-- Rarity-tinted backdrop behind a transparent viewport (a gradient on the viewport itself would tint the bike too).
local function backdrop(parent: GuiObject, tint: Color3): Frame
	local back = Instance.new("Frame")
	back.Name = "Backdrop"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.Parent = parent
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 10)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Tint"
	gradient.Rotation = 90
	gradient.Parent = back
	ShopPreview.tint(back, tint)
	return back
end

function ShopPreview.tint(back: Frame, tint: Color3)
	local gradient = back:FindFirstChild("Tint") :: UIGradient
	gradient.Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.55), tint:Lerp(rgb(20, 24, 40), 0.35))
end

local function viewport(parent: GuiObject): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.Name = "View"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = rgb(205, 208, 222)
	view.LightColor = rgb(255, 255, 255)
	view.LightDirection = Vector3.new(0.7, -1, 0.35)
	view.Parent = parent
	return view
end

local function place(source: Model, parent: Instance): (Model, CFrame, Vector3)
	local bike = source:Clone()
	bike:PivotTo(CFrame.identity)
	local bounds, size = bike:GetBoundingBox()
	-- Centre the bike on the turntable axis.
	bike:PivotTo(CFrame.new(-bounds.Position.X, 0, -bounds.Position.Z))
	bike.Parent = parent
	local centred = CFrame.new(0, bounds.Position.Y, 0)
	return bike, centred, size
end

-- Distance that fits a sphere of the given radius into the camera on both axes.
local function fitDistance(radius: number, fov: number, aspect: number): number
	local half = math.rad(fov) / 2
	local horizontal = math.atan(math.tan(half) * aspect)
	return radius / math.sin(math.min(half, horizontal))
end

function ShopPreview.thumbnail(parent: GuiObject, source: Model, tint: Color3): Frame
	local back = backdrop(parent, tint)
	local view = viewport(back)
	local _, centre, size = place(source, view)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = view
	view.CurrentCamera = camera
	local direction = Vector3.new(-1, 0.35, -0.5).Unit
	local function frame()
		local aspect = view.AbsoluteSize.X / math.max(1, view.AbsoluteSize.Y)
		-- кадр — отдельно по высоте и по ширине: плитка широкая и низкая, велосипед — тоже
		local half = math.rad(camera.FieldOfView) / 2
		local halfH = math.atan(math.tan(half) * aspect)
		local distance = math.max(size.Y * 0.6 / math.tan(half), size.Z * 0.55 / math.tan(halfH))
		local target = centre.Position
		camera.CFrame = CFrame.lookAt(target + direction * distance, target)
	end
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame)
	frame()
	return back
end

export type Stage = {
	show: (source: Model, tint: Color3) -> (),
	setActive: (active: boolean) -> (),
}

function ShopPreview.stage(parent: GuiObject): Stage
	local back = backdrop(parent, rgb(150, 170, 195))
	local view = viewport(back)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.Parent = view
	view.CurrentCamera = camera

	-- Turntable: a fat disc with a glowing rim under the wheels.
	-- Parts are turned one by one: a Model without PrimaryPart would pivot around its first part.
	local podium = Instance.new("Folder")
	podium.Name = "Podium"
	podium.Parent = view
	local discs: { [Part]: CFrame } = {}
	local function disc(name: string, height: number, diameter: number, y: number, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.Size = Vector3.new(height, diameter, diameter)
		part.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2)
		part.Color = color
		part.Parent = podium
		discs[part] = part.CFrame
		return part
	end

	local bike: Model? = nil
	local centre = CFrame.identity
	local size = Vector3.one
	local rim: Part? = nil
	local angle = 0
	local dragging = false
	local resumeAt = 0

	local function frame()
		local aspect = view.AbsoluteSize.X / math.max(1, view.AbsoluteSize.Y)
		local radius = math.max(size.Z * 0.46, size.Y * 0.5)
		local distance = fitDistance(radius, camera.FieldOfView, aspect)
		local target = centre.Position - Vector3.new(0, size.Y * 0.22, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(-0.9, 0.42, 0).Unit * distance, target)
	end
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame)

	local function turn()
		if bike then
			local spin = CFrame.Angles(0, angle, 0)
			for part, base in discs do
				part.CFrame = spin * base
			end
			bike:PivotTo(CFrame.Angles(0, angle, 0) * (bike:GetAttribute("Offset") :: CFrame))
		end
	end

	local stage = {}
	function stage.show(source: Model, tint: Color3)
		if bike then
			bike:Destroy()
		end
		podium:ClearAllChildren()
		table.clear(discs)
		local clone, centred, extent = place(source, view)
		clone:SetAttribute("Offset", clone:GetPivot())
		bike, centre, size = clone, centred, extent
		local floor = centred.Position.Y - extent.Y / 2
		local diameter = math.max(extent.Z, extent.X) * 1.05
		disc("Base", 0.4, diameter, floor - 0.2, rgb(245, 245, 250))
		rim = disc("Rim", 0.22, diameter + 0.5, floor - 0.5, tint)
		;(rim :: Part).Material = Enum.Material.Neon
		disc("Shadow", 0.3, diameter + 1, floor - 0.75, rgb(40, 46, 70))
		ShopPreview.tint(back, tint)
		frame()
		turn()
	end

	local connection: RBXScriptConnection? = nil
	function stage.setActive(active: boolean)
		if active and not connection then
			connection = RunService.RenderStepped:Connect(function(dt)
				if not dragging and os.clock() >= resumeAt then
					angle += Config.SpinSpeed * dt
					turn()
				end
			end)
		elseif not active and connection then
			connection:Disconnect()
			connection = nil
		end
	end

	-- Drag to rotate (mouse or finger).
	local lastX = 0
	back.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			lastX = input.Position.X
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			angle += (input.Position.X - lastX) * Config.DragSpeed
			lastX = input.Position.X
			turn()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			resumeAt = os.clock() + Config.ResumeSpinAfter
		end
	end)

	return stage :: Stage
end

return ShopPreview
