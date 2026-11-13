--!strict
-- Звуки и частицы на клиенте — один модуль для всех скриптов.
--   Fx.play("Bonk")                — 2D-звук из Config.Sounds
--   Fx.burst("Confetti", position) — вспышка частиц в точке (Confetti / Dust / Firework)
-- Всё локальное: ничего не реплицируется и сервер не нагружает.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local E = Config.Effects

local Fx = {}

---------------------------------------------------------------- звуки

local soundFolder = Instance.new("Folder")
soundFolder.Name = "FxSounds"
soundFolder.Parent = SoundService

local sounds: { [string]: Sound } = {}

-- Звук по имени из Config.Sounds (создаётся один раз).
function Fx.sound(name: string): Sound?
	local existing = sounds[name]
	if existing then
		return existing
	end
	local spec = (Config.Sounds :: any)[name]
	if not spec then
		warn("[Fx] unknown sound " .. name)
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. tostring(spec.id)
	s.Volume = spec.volume
	s.Parent = soundFolder
	sounds[name] = s
	return s
end

-- Проиграть 2D-звук. Короткие звуки могут накладываться (каждый раз — копия).
function Fx.play(name: string, volumeScale: number?)
	local s = Fx.sound(name)
	if not s then
		return
	end
	local copy = s:Clone()
	copy.Volume = s.Volume * (volumeScale or 1)
	copy.Parent = soundFolder
	copy:Play()
	copy.Ended:Once(function()
		copy:Destroy()
	end)
	Debris:AddItem(copy, 15) -- страховка, если Ended не придёт
end

---------------------------------------------------------------- частицы

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 40)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 220, 100)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 150, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 90, 255)),
})

type BurstSpec = {
	count: number,
	build: (ParticleEmitter) -> (),
	lifetime: number,
}

local SPECS: { [string]: BurstSpec } = {
	Confetti = {
		count = E.ConfettiCount,
		lifetime = 1.6,
		build = function(p)
			p.Texture = SPARKLE
			p.Color = RAINBOW
			p.Size = NumberSequence.new(0.6, 0.2)
			p.Lifetime = NumberRange.new(0.8, 1.4)
			p.Speed = NumberRange.new(10, 18)
			p.SpreadAngle = Vector2.new(70, 70)
			p.Acceleration = Vector3.new(0, -25, 0)
			p.Drag = 2
			p.Rotation = NumberRange.new(0, 360)
			p.RotSpeed = NumberRange.new(-300, 300)
			p.LightEmission = 0.6
		end,
	},
	Dust = {
		count = E.DustCount,
		lifetime = 1.4,
		build = function(p)
			p.Texture = SMOKE
			p.Color = ColorSequence.new(Color3.fromRGB(220, 200, 170))
			p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
			p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			p.Lifetime = NumberRange.new(0.6, 1.1)
			p.Speed = NumberRange.new(5, 9)
			p.SpreadAngle = Vector2.new(180, 30)
			p.Drag = 4
			p.Rotation = NumberRange.new(0, 360)
		end,
	},
	Firework = {
		count = E.FireworkCount,
		lifetime = 2,
		build = function(p)
			p.Texture = SPARKLE
			p.Color = RAINBOW
			p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
			p.Lifetime = NumberRange.new(1, 1.8)
			p.Speed = NumberRange.new(18, 28)
			p.SpreadAngle = Vector2.new(180, 180)
			p.Acceleration = Vector3.new(0, -12, 0)
			p.Drag = 1.5
			p.LightEmission = 1
		end,
	},
}

function Fx.burst(kind: string, position: Vector3)
	local spec = SPECS[kind]
	if not spec then
		warn("[Fx] unknown burst " .. kind)
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	attachment.WorldPosition = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	spec.build(emitter)
	emitter.Parent = attachment
	emitter:Emit(spec.count)
	Debris:AddItem(attachment, spec.lifetime + 0.5)
end

return Fx
