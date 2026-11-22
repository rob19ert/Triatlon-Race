--!strict
-- Geometry is authored in bike-root space. Wheel details follow their original motors.
local BikeModels = {}
local rgb, vec = Color3.fromRGB, Vector3.new
local metal, glow, smooth = Enum.Material.Metal, Enum.Material.Neon, Enum.Material.SmoothPlastic
local ink, cream, copper = rgb(27,30,45), rgb(250,239,205), rgb(181,93,46)

function BikeModels.build(template: Model, id: string, accent: Color3): Model
	local model = template:Clone()
	local root = assert(model.PrimaryPart)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") then
			part.Color = accent
		end
	end
	local function piece(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: BasePart?)
		local p = Instance.new("Part")
		p.Name, p.Shape, p.Size = name, shape, size
		p.Color, p.Material = color, material
		p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
		p.CFrame = root.CFrame * cf
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = parent or root, p, p
	end
	local function oval(name: string, x: number,y: number,z: number,w: number,h: number,d: number,col: Color3,mat: Enum.Material)
		piece(name, Enum.PartType.Ball, vec(w,h,d), CFrame.new(x,y,z),col,mat)
	end
	local function bar(name: string, a: Vector3,b: Vector3,width: number,col: Color3,mat: Enum.Material)
		piece(name,Enum.PartType.Cylinder,vec((a-b).Magnitude,width,width),CFrame.lookAt((a+b)/2,b)*CFrame.Angles(0,math.pi/2,0),col,mat)
	end
	-- «Полировка» под иконки магазина (все велосипеды): рама толще, стыки скруглены, седло крупнее.
	local FRAME_TUBES = { TopTube = true, DownTube = true, SeatTube = true, HeadTube = true,
		ChainStayL = true, ChainStayR = true, SeatStayL = true, SeatStayR = true, ForkL = true, ForkR = true }
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and FRAME_TUBES[part.Name] then
			part.Size = vec(part.Size.X, part.Size.Y * 1.3, part.Size.Z * 1.3)
			part.Reflectance = 0.06
		end
	end
	local frameColor = accent
	local top = model:FindFirstChild("TopTube", true) :: BasePart?
	if top then
		frameColor = top.Color
	end
	oval("JointHead", 0, 2.1, -1.53, .58, .58, .58, frameColor, smooth)
	oval("JointSeat", 0, 2.02, .5, .46, .46, .46, frameColor, smooth)
	for _, side in {-1, 1} do
		oval("JointDropout", side * .18, 1.3, 1.9, .3, .3, .3, frameColor, smooth)
	end
	local seat = model:FindFirstChild("Seat", true) :: BasePart?
	if seat then
		seat.Size = vec(.9, .36, 1.3) -- седло пошире и потолще (шар сплющить нельзя — Ball всегда круглый)
	end
	-- Keep the axle motors as the animation roots, and lace the open wheels to them.
	if id ~= "ember" and id ~= "violet" then
		for _, name in {"FrontWheel", "RearWheel"} do
			local axle = model:FindFirstChild(name, true) :: BasePart
			local center = root.CFrame:PointToObjectSpace(axle.Position)
			local rimColor = if id == "gold" then copper elseif id == "auto" then rgb(108,199,221) else accent
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and (part == axle or part.Name == name.."Rim" or part.Name == name.."Spoke") then
					part.Transparency = 1
				end
			end
			local segments = 28
			for i = 1, segments do
				local angle = i * math.pi * 2 / segments
				local radial = CFrame.new(center) * CFrame.Angles(angle, 0, 0)
				piece("Tread", Enum.PartType.Block, vec(.42,.3,.32), radial*CFrame.new(0,1.2,0), ink, smooth, axle)
				piece("Rim", Enum.PartType.Block, vec(.26,.14,.28), radial*CFrame.new(0,1.0,0), rimColor, smooth, axle)
				if i % 2 == 0 then
					piece("Spoke", Enum.PartType.Block, vec(.045,.9,.045), radial*CFrame.new(0,.52,0), cream, metal, axle)
				end
			end
			piece("Hub", Enum.PartType.Cylinder, vec(.5,.42,.42), CFrame.new(center), rimColor, metal, axle)
		end
	end
	local function wheels(disc: Color3, trim: Color3)
		for _, name in {"FrontWheel","RearWheel"} do
			local wheel = model:FindFirstChild(name,true) :: BasePart
			local pos = root.CFrame:PointToObjectSpace(wheel.Position)
			piece("WheelDisc",Enum.PartType.Cylinder,vec(.45,2.25,2.25),CFrame.new(pos),trim,metal,wheel)
			piece("WheelInset",Enum.PartType.Cylinder,vec(.48,1.92,1.92),CFrame.new(pos),disc,smooth,wheel)
			for i=1,5 do
				local cf = CFrame.new(pos)*CFrame.Angles(i*math.pi*2/5,0,0)*CFrame.new(0,.63,0)*CFrame.Angles(.35,0,0)
				piece("TurbineBlade",Enum.PartType.Block,vec(.51,.62,.13),cf,trim,metal,wheel)
			end
		end
	end
	if id == "auto" then -- pastel bubble cruiser with a candy basket
		for i=0,7 do
			local angle = i*math.pi/4
			bar("BasketWire",vec(.37*math.cos(angle),2.65,-2.25+.3*math.sin(angle)),vec(.55*math.cos(angle),3.25,-2.25+.47*math.sin(angle)),.07,cream,metal)
		end
		for i=0,7 do
			local a,b = i*math.pi/4,(i+1)*math.pi/4
			bar("BasketLip",vec(.55*math.cos(a),3.25,-2.25+.47*math.sin(a)),vec(.55*math.cos(b),3.25,-2.25+.47*math.sin(b)),.075,cream,metal)
		end
		oval("Basket",0,2.76,-2.25,.91,.33,.79,accent,smooth)
		for i=1,5 do
			local angle=i*math.pi*2/5
			oval("Gumball",.29*math.cos(angle),3.09,-2.25+.25*math.sin(angle),.52,.56,.52,if i%2==0 then rgb(255,119,181) else rgb(109,231,255),smooth)
		end
		oval("BubbleGuard",0,2.42,1.92,.71,.52,1.7,rgb(255,146,200),smooth)
	elseif id == "ice" then -- shuttle with swept wings and twin engines
		oval("Fuselage",0,2.18,-.83,1.02,.9,3.65,cream,metal)
		oval("Canopy",0,2.51,-1.65,.73,.58,1.45,rgb(34,92,139),Enum.Material.Glass)
		for _, side in {-1,1} do
			piece("Wing",Enum.PartType.Block,vec(1.32,.13,.79),CFrame.new(side*.83,1.89,.45)*CFrame.Angles(0,side*-.52,0),cream,metal)
			oval("Nacelle",side*.76,1.87,1.14,.47,.5,1.45,ink,metal)
			bar("EngineBand",vec(side*.76,1.87,1.55),vec(side*.76,1.87,1.68),.48,cream,metal)
			oval("IonJet",side*.76,1.87,1.92,.35,.36,.65,accent,glow)
		end
	elseif id == "ember" then -- horned fire drake
		wheels(rgb(86,32,41),rgb(255,152,31))
		oval("Scales",0,1.82,-.14,.69,.74,2.45,rgb(149,51,44),smooth)
		bar("Neck",vec(0,1.84,-1),vec(0,3.08,-1.85),.52,accent,smooth)
		oval("Skull",0,3.13,-1.94,.73,.69,1.0,accent,smooth)
		oval("Snout",0,3.02,-2.48,.59,.37,.78,rgb(138,47,41),smooth)
		for _, side in {-1,1} do
			bar("Horn",vec(side*.25,3.36,-1.73),vec(side*.4,3.91,-1.35),.16,cream,metal)
			for i=0,3 do
				oval("NeckScale",side*.23,2.04+i*.24,-1.15-i*.17,.17,.32,.37,rgb(187,77+i*9,42),metal)
			end
			oval("Eye",side*.33,3.24,-2.13,.12,.17,.23,rgb(255,205,55),glow)
		end
		bar("Tail",vec(0,1.92,.8),vec(0,2.63,2.65),.35,accent,smooth)
		for i=1,4 do
			bar("Crest",vec(0,2.02+i*.15,.78+i*.4),vec(0,2.53+i*.15,.96+i*.4),.19,cream,metal)
		end
	elseif id == "lime" then -- living wood, forked branches and leaf canopy
		for _, side in {-1,1} do
			bar("Bough",vec(0,1.0,.1),vec(side*.36,2.93,-1.65),.27,rgb(112,69,42),Enum.Material.Wood)
			bar("Branch",vec(side*.25,2.5,-1.45),vec(side*.96,3.31,-1.95),.16,copper,Enum.Material.Wood)
			for i=1,3 do
				oval("Leaf",side*(.29+i*.23),2.97+i*.14,-1.8+i*.15,.47,.19,.72,if i%2==0 then accent else rgb(58,156,102),smooth)
				oval("Petal",side*.44,2.53+i*.08,1.04+i*.27,.23,.14,.25,cream,smooth)
				oval("Blossom",side*.33,2.43+i*.08,1.0+i*.27,.36,.36,.35,rgb(255,150+i*15,173),smooth)
			end
		end
		oval("Planter",0,2.37,1.59,.86,.62,1.49,rgb(143,86,44),Enum.Material.Wood)
	elseif id == "violet" then -- low neon street racer
		wheels(ink,accent)
		oval("Armor",0,1.89,-.66,1.14,1.04,2.79,ink,metal)
		for _, side in {-1,1} do
			oval("CheekArmor",side*.44,1.92,-.73,.25,.65,1.91,rgb(58,44,85),metal)
			bar("LightRail",vec(side*.48,1.64,.28),vec(side*.48,2.2,-1.6),.13,accent,glow)
			piece("SplitFin",Enum.PartType.Block,vec(.18,.47,1.63),CFrame.new(side*.48,2.38,1.52)*CFrame.Angles(-.24,side*.23,0),accent,metal)
		end
		piece("Visor",Enum.PartType.Block,vec(.92,.24,.52),CFrame.new(0,2.76,-1.76)*CFrame.Angles(.42,0,0),rgb(84,242,255),glow)
	elseif id == "gold" then -- brass steam engine and external gear train
		oval("Boiler",0,1.86,-.71,1.02,1.08,2.22,copper,metal)
		for _, z in {-.98,-.39} do
			bar("BoilerBand",vec(0,1.86,z-.05),vec(0,1.86,z+.05),1.09,accent,metal)
		end
		bar("Chimney",vec(0,2.15,-1.44),vec(0,3.33,-1.44),.41,ink,metal)
		bar("BrassLip",vec(0,3.24,-1.44),vec(0,3.42,-1.44),.59,accent,metal)
		for _, side in {-1,1} do
			for i=0,2 do
				local cf=CFrame.new(side*.48,1.41+i%2*.31,-.68+i*.68)
				piece("Cog",Enum.PartType.Cylinder,vec(.19,.75,.75),cf,accent,metal)
				for tooth=1,4 do
					piece("GearTeeth",Enum.PartType.Block,vec(.16,.91,.16),cf*CFrame.Angles(tooth*math.pi/4,0,0),accent,metal)
				end
			end
		end
	end
	return model
end

return BikeModels
