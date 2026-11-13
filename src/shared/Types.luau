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

export type ShootingStartPayload = {
	eye: CFrame, -- точка и направление глаз стрелка (на центр мишеней)
	stance: "Prone" | "Standing",
	wind: number, -- уровень со знаком: + вправо от стрелка
	shots: number,
	lane: number,
	targetSpacingDeg: number, -- угол между соседними мишенями из глаз стрелка (для подсказки про ветер)
}

export type ShotResultPayload = {
	hit: boolean,
	targetIndex: number?, -- какая мишень закрылась
	shotsLeft: number,
	impact: Vector3?, -- куда пришла пуля в плоскости мишеней (для следа на щите)
}

export type ShootingSummary = {
	userId: number,
	name: string,
	rangeOrder: number,
	hits: number,
	shots: number,
}

return {}
