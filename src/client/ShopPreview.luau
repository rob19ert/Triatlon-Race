--!strict
-- A miniature section of the stadium plaza, in the same coordinates as the display bike.
local ShopPreview = {}
local rgb = Color3.fromRGB

local function scenery(view: ViewportFrame)
	local function block(name: string, size: Vector3, position: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CanCollide = false
		part.Size = size
		part.Position = position
		part.Color = color
		part.Parent = view
		return part
	end

	block("Grout", Vector3.new(22,.12,36), Vector3.new(0,-.13,0), rgb(146,93,77))
	local clay = {rgb(225,143,105), rgb(216,129,96), rgb(237,155,112), rgb(228,145,110)}
	for course = -4, 5 do
		for brick = -5, 5 do
			local z = (brick + course%2*.5)*2.55
			block("Paver", Vector3.new(1.22,.08,2.5), Vector3.new(course*1.26,-.06,z), clay[(course*7+brick*3)%#clay+1])
		end
	end
	block("TrackWall", Vector3.new(.6,1.45,42), Vector3.new(4.4,.61,0), rgb(239,239,228))
	block("Coping", Vector3.new(.78,.12,42), Vector3.new(4.4,1.38,0), rgb(255,246,222))
	block("Infield", Vector3.new(24,.45,42), Vector3.new(16,.88,0), rgb(119,179,130))
	for _, z in {-10, -4, 2, 8} do
		block("Banner", Vector3.new(.16,1.05,2.9), Vector3.new(7.4,1.7,z), if z%4==0 then rgb(45,96,148) else rgb(240,163,70))
	end
	-- ViewportFrames have no cast shadows. Two low ellipses anchor the wheels.
	for _, z in {-1.9,1.9} do
		local shade = block("ContactShadow", Vector3.new(.9,.025,1.6), Vector3.new(.09,-.008,z), rgb(91,58,51))
		shade.Shape = Enum.PartType.Ball
		shade.Transparency = .36
	end
end

function ShopPreview.mount(parent: Frame, source: Model)
	local view = Instance.new("ViewportFrame")
	view.Name = "Courtyard"
	view.Size = UDim2.new(1, -12, 1, -93)
	view.Position = UDim2.fromOffset(6,6)
	view.BackgroundColor3 = rgb(184,214,232)
	view.BorderSizePixel = 0
	view.Ambient = rgb(153,162,183)
	view.LightColor = rgb(255,236,211)
	view.LightDirection = Vector3.new(.55,-1,.52)
	view.Parent = parent
	Instance.new("UICorner", view).CornerRadius = UDim.new(0,8)

	local bike = source:Clone()
	bike:PivotTo(CFrame.identity)
	bike.Parent = view
	local bounds, size = bike:GetBoundingBox()
	scenery(view)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 29
	camera.Parent = view
	view.CurrentCamera = camera
	local direction = Vector3.new(-1,.44,-.56).Unit
	local function frame()
		local aspect = view.AbsoluteSize.X / math.max(1, view.AbsoluteSize.Y)
		local projectedWidth = size.Z*.88 + size.X*.49
		local projectedHeight = size.Y + size.Z*.13
		local distance = math.max(projectedHeight, projectedWidth / math.max(.5,aspect)) * 2.24
		camera.CFrame = CFrame.lookAt(bounds.Position + direction*distance, bounds.Position)
	end
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame)
	frame()
end

return ShopPreview
