--!strict
-- Имена атрибутов на Player, через которые сервер показывает состояние клиентам.
-- Пишет только сервер, клиент только читает.

return {
	Pulse = "Pulse", -- number 0–100; nil = пульс не отслеживается (не в гонке)
	RedZone = "RedZone", -- boolean
	Sprinting = "Sprinting", -- boolean, спринт реально работает (а не просто нажат)
	HoldBreathUntil = "HoldBreathUntil", -- number, server time конца задержки дыхания
	HoldBreathReadyAt = "HoldBreathReadyAt", -- number, server time, когда можно снова
	PenaltyTime = "PenaltyTime", -- number, накопленное штрафное время за гонку, с (nil — не в гонке)
	RangeOrder = "RangeOrder", -- number, на каком стрельбище сейчас стреляет (nil — не стреляет)
	RangeMarks = "RangeMarks", -- string, выстрелы этой стрельбы: "H" попал, "M" промах (напр. "HHM")
	PushReadyAt = "PushReadyAt", -- number, server time, когда снова можно толкать (nil — толчок недоступен, не в гонке)
}
