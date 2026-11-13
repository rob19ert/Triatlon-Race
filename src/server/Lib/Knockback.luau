--!strict
-- Отбросить персонажа: короткий LinearVelocity в HumanoidRootPart.
-- Констрейнт создаёт сервер, а физику персонажа считает его клиент-владелец,
-- поэтому просто выставить AssemblyLinearVelocity на сервере не сработало бы.

local Debris = game:GetService("Debris")

local IMPULSE_NAME = "KnockbackImpulse"
local MAX_FORCE = 1e5

local Knockback = {}

-- direction — горизонтальное направление (нормализуется), speed/upSpeed — стад/с.
function Knockback.apply(root: BasePart, direction: Vector3, speed: number, upSpeed: number, duration: number)
	local flat = direction * Vector3.new(1, 0, 1)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero

	local old = root:FindFirstChild(IMPULSE_NAME)
	if old then
		old:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = IMPULSE_NAME
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = MAX_FORCE
	velocity.VectorVelocity = flat * speed + Vector3.new(0, upSpeed, 0)
	velocity.Parent = attachment
	attachment.Parent = root
	Debris:AddItem(attachment, duration)
end

return Knockback
