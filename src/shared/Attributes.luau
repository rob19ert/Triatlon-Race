--!strict
-- Имена атрибутов на Player, через которые сервер показывает состояние клиентам.
-- Пишет только сервер, клиент только читает.

return {
	Pulse = "Pulse", -- number 0–100; nil = пульс не отслеживается (не в гонке)
	RedZone = "RedZone", -- boolean
	Sprinting = "Sprinting", -- boolean, спринт реально работает (а не просто нажат)
	HoldBreathUntil = "HoldBreathUntil", -- number, server time конца задержки дыхания
	HoldBreathReadyAt = "HoldBreathReadyAt", -- number, server time, когда можно снова
	PenaltyOwed = "PenaltyOwed", -- number, сколько штрафных кругов назначено (nil — штрафа нет)
	PenaltyDone = "PenaltyDone", -- number, сколько уже пробежал
	PushReadyAt = "PushReadyAt", -- number, server time, когда снова можно толкать (nil — толчок недоступен, не в гонке)
}
