--!strict
-- Палитры сезонов. Роль детали (атрибут Role) -> цвет и материал.
-- Прозрачность и форму детали не трогаем: только цвет и материал.
-- Новый сезон = новая таблица здесь + папка Decor/<Сезон> в мире.

export type RoleStyle = { color: Color3, material: Enum.Material }

export type Theme = {
	roles: { [string]: RoleStyle },
	lighting: {
		clockTime: number,
		brightness: number,
		ambient: Color3,
		outdoorAmbient: Color3,
		colorShiftTop: Color3,
	},
	atmosphere: {
		density: number,
		offset: number,
		color: Color3,
		decay: Color3,
		glare: number,
		haze: number,
	},
}

local rgb = Color3.fromRGB

local Themes: { [string]: Theme } = {
	Summer = {
		roles = {
			Ground = { color = rgb(106, 190, 70), material = Enum.Material.Grass }, -- поле вокруг трассы
			Hill = { color = rgb(88, 170, 62), material = Enum.Material.Grass }, -- холмы, валы стрельбищ
			FarHill = { color = rgb(120, 170, 120), material = Enum.Material.SmoothPlastic }, -- дальний фон, чуть выцветший
			Path = { color = rgb(222, 112, 72), material = Enum.Material.Pavement }, -- беговая дорожка
			Curb = { color = rgb(250, 250, 250), material = Enum.Material.SmoothPlastic },
			Water = { color = rgb(70, 190, 255), material = Enum.Material.Glass },
			Foliage = { color = rgb(70, 175, 70), material = Enum.Material.SmoothPlastic },
			Foliage2 = { color = rgb(130, 205, 70), material = Enum.Material.SmoothPlastic },
			Trunk = { color = rgb(130, 85, 50), material = Enum.Material.Wood },
			Rock = { color = rgb(160, 160, 170), material = Enum.Material.SmoothPlastic },
		},
		lighting = {
			clockTime = 13.5,
			brightness = 3,
			ambient = rgb(110, 110, 120),
			outdoorAmbient = rgb(150, 150, 160),
			colorShiftTop = rgb(255, 245, 225),
		},
		atmosphere = {
			density = 0.28,
			offset = 0.1,
			color = rgb(200, 225, 255),
			decay = rgb(120, 170, 230),
			glare = 0.2,
			haze = 1,
		},
	},
}

return Themes
