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
	time: number?, -- секунды со штрафом, nil для DNF
	penalty: number?, -- штрафное время в составе time, с
	dnf: boolean,
	hits: number?, -- попаданий за всю гонку (заполняется в итогах)
	shots: number?,
	photoFinish: boolean?, -- разница с соседом < PhotoFinishGap
}

export type RacePhase = "Run" | "Shooting" | "Finished"

-- Строка таблицы позиций во время гонки.
export type StandingEntry = {
	userId: number,
	name: string,
	place: number,
	phase: RacePhase,
	penalty: number, -- накопленное штрафное время, с
	time: number?, -- для phase = "Finished" (со штрафом)
}

export type ShootingStartPayload = {
	eye: CFrame, -- точка и направление глаз стрелка (на центр мишеней)
	stance: "Prone" | "Standing",
	shots: number,
	lane: number,
	targetSpacingDeg: number, -- угол между соседними мишенями из глаз стрелка
	track: { -- маятник мушки на эту стрельбу (Shared/Aim.Track)
		t0: number,
		phase0: number,
		speed: number,
		hAmp: number,
		tremorSeed: number,
	},
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
