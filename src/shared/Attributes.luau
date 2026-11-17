--!strict
-- Имена атрибутов на Player, через которые сервер показывает состояние клиентам.
-- Пишет только сервер, клиент только читает.

return {
	Pulse = "Pulse", -- number 0–100; nil = пульс не отслеживается (не в гонке)
	RedZone = "RedZone", -- boolean
	Sprinting = "Sprinting", -- boolean, спринт реально работает (а не просто нажат)
	HoldBreathUntil = "HoldBreathUntil", -- number, server time конца задержки дыхания
	HoldBreathReadyAt = "HoldBreathReadyAt", -- number, server time, когда можно снова
	PenaltyTime = "PenaltyTime", -- number, штраф за гонку, с; может быть < 0 (бонус золотой мишени); nil — не в гонке
	RangeOrder = "RangeOrder", -- number, на каком стрельбище сейчас стреляет (nil — не стреляет)
	RangeMarks = "RangeMarks", -- string, выстрелы этой стрельбы: "H" попал, "M" промах (напр. "HHM")
	TurboUntil = "TurboUntil", -- number, server time конца турбо (5/5 на рубеже)
	ShieldUntil = "ShieldUntil", -- number, server time: щит гасит одно попадание (бокс); nil — нет/потрачен
	GhostUntil = "GhostUntil", -- number, server time конца «Призрака» (бокс): сквозь препятствия и толчки
	MegaPushUntil = "MegaPushUntil", -- number, server time конца бонуса «Мега-толчок» (бокс)
	SnailUntil = "SnailUntil", -- number, server time конца «Улитки» (бокс): медленнее
	InvertUntil = "InvertUntil", -- number, server time конца «Наоборот» (бокс): лево/право перепутаны (клиент)
	SpringJumps = "SpringJumps", -- number, сколько высоких прыжков осталось («Пружина», бокс)
	BigTargets = "BigTargets", -- boolean, бонус «Большие мишени» на следующую стрельбу (бокс)
	IceGrip = "IceGrip", -- number 0..1, сцепление на льду (nil — не на льду)
	Riding = "Riding", -- boolean, едет на велосипеде (nil — пешком)
	PushReadyAt = "PushReadyAt", -- number, server time, когда снова можно толкать (nil — толчок недоступен, не в гонке)
}
