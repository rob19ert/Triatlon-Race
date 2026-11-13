--!strict
-- Общие типы сервера и клиента.

export type RaceState = "Lobby" | "Countdown" | "Racing" | "Results"

-- То, что сервер шлёт клиентам при смене состояния.
export type RaceStatePayload = {
	state: RaceState,
	endsAt: number, -- workspace:GetServerTimeNow() конца этапа; 0 = без таймера
	raceStartedAt: number, -- серверное время старта гонки; 0 = гонка не идёт
}

export type ResultEntry = {
	userId: number,
	name: string,
	place: number?, -- nil для DNF
	time: number?, -- секунды, nil для DNF
	dnf: boolean,
}

return {}
