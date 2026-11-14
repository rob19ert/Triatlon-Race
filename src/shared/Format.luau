--!strict
-- Общие форматтеры для HUD/табло/таблиц.

local Format = {}

-- Штраф/бонус со знаком: "+6 с", "−3 с"; 0 → "". compact = без пробела и «с» ("+6", "−3").
function Format.penalty(seconds: number?, compact: boolean?): string
	local s = seconds or 0
	if s == 0 then
		return ""
	end
	local sign = if s > 0 then "+" else "−"
	local n = math.abs(s)
	return if compact then string.format("%s%d", sign, n) else string.format("%s%d с", sign, n)
end

return Format
