# balance.gd — АВТОГЕНЕРАЦИЯ из ../public/js/shared.js (срез: коммит 144e737).
# НЕ ПРАВИТЬ РУКАМИ. Перегенерация: node godot/tools/port_balance.mjs (из корня репы).
# Паритет с веб-версией: все игровые числа берутся ТОЛЬКО отсюда (правило 3 godot/CLAUDE.md).
class_name Balance

const SNAPSHOT_HASH := "144e737"

const RULES := {
	"ROUNDS_TO_WIN": 5,
	"BUY_TIME": 15,
	"ROUND_TIME": 100,
	"SPIKE_TIME": 45,
	"PLANT_TIME": 4,
	"DEFUSE_TIME": 7,
	"ROUND_END_TIME": 6,
	"START_CREDITS": 800,
	"MAX_CREDITS": 9000,
	"KILL_REWARD": 200,
	"WIN_REWARD": 3000,
	"LOSS_REWARD": 2400,
	"PLANT_REWARD": 300,
	"BASE_HP": 100,
	"ARMOR_ABSORB": 0.66,
	"TEAM_MAX": 5
}

const WEAPONS := {
	"knife": {
		"name": "Нож",
		"cat": "knife",
		"slot": "knife",
		"price": 0,
		"dmg": 50,
		"head": 75,
		"leg": 50,
		"rpm": 100,
		"mag": 0,
		"reserve": 0,
		"auto": false,
		"spread": 0,
		"recoil": 0,
		"reload": 0,
		"range": 2.4,
		"melee": true
	},
	"classic": {
		"name": "Классик",
		"cat": "pistol",
		"slot": "sidearm",
		"price": 0,
		"dmg": 26,
		"head": 78,
		"leg": 22,
		"rpm": 400,
		"mag": 12,
		"reserve": 36,
		"auto": false,
		"spread": 0.01,
		"recoil": 0.013,
		"reload": 1.7,
		"falloffStart": 20,
		"falloffMin": 0.8
	},
	"ghost": {
		"name": "Призрак",
		"cat": "pistol",
		"slot": "sidearm",
		"price": 500,
		"dmg": 30,
		"head": 105,
		"leg": 26,
		"rpm": 500,
		"mag": 15,
		"reserve": 45,
		"auto": false,
		"spread": 0.008,
		"recoil": 0.011,
		"reload": 1.8,
		"silenced": true,
		"falloffStart": 22,
		"falloffMin": 0.8
	},
	"sheriff": {
		"name": "Шериф",
		"cat": "pistol",
		"slot": "sidearm",
		"price": 800,
		"dmg": 55,
		"head": 159,
		"leg": 47,
		"rpm": 150,
		"mag": 6,
		"reserve": 18,
		"auto": false,
		"spread": 0.009,
		"recoil": 0.034,
		"reload": 2.2
	},
	"bucky": {
		"name": "Дробаш",
		"cat": "shotgun",
		"slot": "primary",
		"price": 850,
		"dmg": 9,
		"head": 16,
		"leg": 8,
		"rpm": 65,
		"mag": 5,
		"reserve": 10,
		"auto": false,
		"spread": 0.065,
		"recoil": 0.045,
		"reload": 2.8,
		"pellets": 8,
		"falloffStart": 8,
		"falloffMin": 0.25
	},
	"judge": {
		"name": "Судья",
		"cat": "shotgun",
		"slot": "primary",
		"price": 1850,
		"dmg": 8,
		"head": 14,
		"leg": 7,
		"rpm": 210,
		"mag": 7,
		"reserve": 15,
		"auto": true,
		"spread": 0.075,
		"recoil": 0.03,
		"reload": 2.6,
		"pellets": 5,
		"falloffStart": 8,
		"falloffMin": 0.25
	},
	"stinger": {
		"name": "Стингер",
		"cat": "smg",
		"slot": "primary",
		"price": 950,
		"dmg": 24,
		"head": 60,
		"leg": 20,
		"rpm": 900,
		"mag": 20,
		"reserve": 60,
		"auto": true,
		"spread": 0.018,
		"recoil": 0.006,
		"reload": 2.2,
		"falloffStart": 18,
		"falloffMin": 0.75
	},
	"spectre": {
		"name": "Спектр",
		"cat": "smg",
		"slot": "primary",
		"price": 1600,
		"dmg": 26,
		"head": 66,
		"leg": 22,
		"rpm": 750,
		"mag": 30,
		"reserve": 90,
		"auto": true,
		"spread": 0.015,
		"recoil": 0.0065,
		"reload": 2.2,
		"silenced": true,
		"falloffStart": 20,
		"falloffMin": 0.75
	},
	"ares": {
		"name": "Арес",
		"cat": "lmg",
		"slot": "primary",
		"price": 1600,
		"dmg": 28,
		"head": 70,
		"leg": 24,
		"rpm": 800,
		"mag": 50,
		"reserve": 100,
		"auto": true,
		"spread": 0.022,
		"recoil": 0.0075,
		"reload": 3.2
	},
	"bulldog": {
		"name": "Бульдог",
		"cat": "rifle",
		"slot": "primary",
		"price": 2050,
		"dmg": 35,
		"head": 115,
		"leg": 30,
		"rpm": 550,
		"mag": 24,
		"reserve": 72,
		"auto": true,
		"spread": 0.011,
		"recoil": 0.01,
		"reload": 2.5
	},
	"guardian": {
		"name": "Гвардеец",
		"cat": "rifle",
		"slot": "primary",
		"price": 2250,
		"dmg": 65,
		"head": 195,
		"leg": 49,
		"rpm": 350,
		"mag": 12,
		"reserve": 36,
		"auto": false,
		"spread": 0.006,
		"recoil": 0.022,
		"reload": 2.5
	},
	"phantom": {
		"name": "Фантом",
		"cat": "rifle",
		"slot": "primary",
		"price": 2900,
		"dmg": 39,
		"head": 140,
		"leg": 33,
		"rpm": 660,
		"mag": 30,
		"reserve": 60,
		"auto": true,
		"spread": 0.009,
		"recoil": 0.009,
		"reload": 2.5,
		"silenced": true,
		"falloffStart": 25,
		"falloffMin": 0.85
	},
	"vandal": {
		"name": "Вандал",
		"cat": "rifle",
		"slot": "primary",
		"price": 2900,
		"dmg": 40,
		"head": 160,
		"leg": 34,
		"rpm": 585,
		"mag": 25,
		"reserve": 50,
		"auto": true,
		"spread": 0.011,
		"recoil": 0.011,
		"reload": 2.5
	},
	"marshal": {
		"name": "Маршал",
		"cat": "sniper",
		"slot": "primary",
		"price": 950,
		"dmg": 101,
		"head": 202,
		"leg": 85,
		"rpm": 90,
		"mag": 5,
		"reserve": 15,
		"auto": false,
		"spread": 0.06,
		"recoil": 0.04,
		"reload": 2.5,
		"scope": true,
		"scopeSpread": 0.004
	},
	"operator": {
		"name": "Оператор",
		"cat": "sniper",
		"slot": "primary",
		"price": 4700,
		"dmg": 150,
		"head": 255,
		"leg": 120,
		"rpm": 45,
		"mag": 5,
		"reserve": 10,
		"auto": false,
		"spread": 0.09,
		"recoil": 0.055,
		"reload": 3.7,
		"scope": true,
		"scopeSpread": 0.001
	},
	"frenzy": {
		"name": "Френзи",
		"cat": "pistol",
		"slot": "sidearm",
		"price": 500,
		"dmg": 26,
		"head": 78,
		"leg": 22,
		"rpm": 720,
		"mag": 13,
		"reserve": 26,
		"auto": true,
		"spread": 0.02,
		"recoil": 0.009,
		"reload": 1.5,
		"falloffStart": 16,
		"falloffMin": 0.7
	},
	"shorty": {
		"name": "Коротыш",
		"cat": "shotgun",
		"slot": "sidearm",
		"price": 150,
		"dmg": 12,
		"head": 22,
		"leg": 10,
		"rpm": 200,
		"mag": 2,
		"reserve": 6,
		"auto": false,
		"spread": 0.09,
		"recoil": 0.03,
		"reload": 1.8,
		"pellets": 10,
		"falloffStart": 7,
		"falloffMin": 0.2
	},
	"outlaw": {
		"name": "Отступник",
		"cat": "sniper",
		"slot": "primary",
		"price": 2400,
		"dmg": 140,
		"head": 238,
		"leg": 118,
		"rpm": 68,
		"mag": 2,
		"reserve": 6,
		"auto": false,
		"spread": 0.05,
		"recoil": 0.045,
		"reload": 3.5,
		"scope": true,
		"scopeSpread": 0.002
	},
	"odin": {
		"name": "Один",
		"cat": "lmg",
		"slot": "primary",
		"price": 3200,
		"dmg": 38,
		"head": 95,
		"leg": 32,
		"rpm": 780,
		"mag": 100,
		"reserve": 200,
		"auto": true,
		"spread": 0.018,
		"recoil": 0.009,
		"reload": 5
	}
}

const WEAPON_FEEL := {
	"knife": {
		"speed": 1.1,
		"equip": 0.3
	},
	"pistol": {
		"speed": 1,
		"equip": 0.5
	},
	"smg": {
		"speed": 0.98,
		"equip": 0.6
	},
	"shotgun": {
		"speed": 0.96,
		"equip": 0.75
	},
	"rifle": {
		"speed": 0.94,
		"equip": 0.8
	},
	"lmg": {
		"speed": 0.9,
		"equip": 0.9
	},
	"sniper": {
		"speed": 0.88,
		"equip": 1
	}
}

const ARMOR := {
	"light": {
		"name": "Лёгкая броня",
		"price": 400,
		"value": 25
	},
	"heavy": {
		"name": "Тяжёлая броня",
		"price": 1000,
		"value": 50
	}
}

const CHARACTERS := {
	"artemiy": {
		"name": "Артемий",
		"title": "Дуэлянт",
		"color": "#ff6b35",
		"darkColor": "#8f2f10",
		"speedMul": 1,
		"ultCost": 5,
		"desc": "Поджигатель на базе Феникса. Огонь лечит его — и сжигает остальных.",
		"abilities": {
			"C": {
				"name": "Вспышка",
				"desc": "Кривой светошар: ослепляет смотрящих (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Огонёк",
				"desc": "Огненный шар: зона огня — жжёт врагов, лечит Артемия",
				"charges": 1
			},
			"E": {
				"name": "Стена огня",
				"desc": "Стена пламени 16 м: жжёт врагов, лечит Артемия",
				"charges": 1
			},
			"X": {
				"name": "Второе дыхание",
				"desc": "УЛЬТА: метка на 10 сек — умер? вернулся на неё с полным HP",
				"charges": 1
			}
		}
	},
	"max": {
		"name": "Макс",
		"title": "Дуэлянт",
		"color": "#7ec8e3",
		"darkColor": "#23566b",
		"speedMul": 1.05,
		"ultCost": 7,
		"desc": "Ветер. Самый быстрый: рывки, вертикаль и ножи, от которых не убежать.",
		"abilities": {
			"C": {
				"name": "Рывок",
				"desc": "Мгновенный рывок в направлении движения (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Взлёт",
				"desc": "Подброс высоко вверх — залетай на ящики и платформы (2 заряда)",
				"charges": 2
			},
			"E": {
				"name": "Порыв",
				"desc": "+40% скорости на 4 сек",
				"charges": 1
			},
			"X": {
				"name": "Стальные перья",
				"desc": "УЛЬТА: 5 ножей (70/150 в голову) на 12 сек, убийство обновляет ножи",
				"charges": 1
			}
		}
	},
	"vova": {
		"name": "Вова",
		"title": "Смокер",
		"color": "#8f7ad1",
		"darkColor": "#3d3266",
		"speedMul": 1,
		"ultCost": 6,
		"desc": "Туманщик. Контролирует карту дымами откуда угодно и роняет небо на голову.",
		"abilities": {
			"C": {
				"name": "Дым по карте",
				"desc": "ГЛОБАЛЬНО: клик по карте — там встаёт дым (3 заряда)",
				"charges": 3
			},
			"Q": {
				"name": "Слепящий заряд",
				"desc": "Быстрая вспышка прямо по курсу",
				"charges": 1
			},
			"E": {
				"name": "Завеса",
				"desc": "Стена из трёх дымов перед собой",
				"charges": 1
			},
			"X": {
				"name": "Орбитальный удар",
				"desc": "УЛЬТА, ГЛОБАЛЬНО: клик по карте — луч выжигает зону",
				"charges": 1
			}
		}
	},
	"sanek": {
		"name": "Санёк",
		"title": "Специалист",
		"color": "#e8c14d",
		"darkColor": "#6b5518",
		"speedMul": 0.98,
		"ultCost": 7,
		"desc": "Инженер. Ставит железо, знает, где враг, и заливает подходы кислотой.",
		"abilities": {
			"C": {
				"name": "Сигналка",
				"desc": "Датчик на полу: враг рядом — подсвечен 3 сек (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Турель",
				"desc": "Автотурель: стреляет по врагам в 20 м (60 HP, можно расстрелять)",
				"charges": 1
			},
			"E": {
				"name": "Кислота",
				"desc": "Лужа кислоты: урон и замедление",
				"charges": 1
			},
			"X": {
				"name": "Рентген",
				"desc": "УЛЬТА, ГЛОБАЛЬНО: все враги подсвечены сквозь стены 8 сек",
				"charges": 1
			}
		}
	},
	"denis": {
		"name": "Денис",
		"title": "Мясник",
		"color": "#7a9b4e",
		"darkColor": "#3d5222",
		"speedMul": 0.95,
		"ultCost": 7,
		"desc": "Вонючий инициатор на базе Пуджа. Жрёт плоть, чует кровь и разделывает крюком.",
		"abilities": {
			"C": {
				"name": "Кровопир",
				"desc": "Жрёт плоть: мгновенный хил + реген. После убийства (6 сек) — усиленно, как гибрид Рейны и Клоува (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Нюх мясника",
				"desc": "Приманка из мяса: враги рядом подсвечены команде, раненых чует вдвое дальше — по запаху крови",
				"charges": 1
			},
			"E": {
				"name": "Смрад",
				"desc": "Смок-вонючка: плотное зелёное облако полностью глушит обзор (2 заряда)",
				"charges": 2
			},
			"X": {
				"name": "Мясной крюк",
				"desc": "УЛЬТА: крюк-кокон тащит жертву к Денису 2.6 сек — дотащил, разделал. Союзники жертвы могут отстрелить кокон (150 HP)",
				"charges": 1
			}
		}
	},
	"ira": {
		"name": "Ира",
		"title": "Поддержка",
		"color": "#e8302c",
		"darkColor": "#f4f0e6",
		"accent": "#ffcf3f",
		"speedMul": 1,
		"ultCost": 7,
		"desc": "Шеф-повар IRAFRIED. Молекулярная кухня как оружие: кормит, лечит и хрустит панировкой.",
		"abilities": {
			"C": {
				"name": "Куриный дозор",
				"desc": "Механический цыплёнок бежит вперёд и подсвечивает врагов в 10 м с кудахтаньем (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Криспи-стена",
				"desc": "Стена из панировки: сквозь неё стреляют, врагов замедляет, союзников лечит на проходе",
				"charges": 1
			},
			"E": {
				"name": "Буфет лечения",
				"desc": "Ведёрко с курицей: облако пара лечит союзников на +50 HP в 8 м. Подбирается 1 раз за раунд",
				"charges": 1
			},
			"X": {
				"name": "Финальный банкет",
				"desc": "УЛЬТА: гигантское ведро KFC на 20 сек — союзникам +30 HP, реген 10/сек, +15% скорости, скрытие от детекта",
				"charges": 1
			}
		}
	},
	"fafik": {
		"name": "Фафик",
		"title": "Обманщик",
		"color": "#3f5c8c",
		"darkColor": "#22304d",
		"accent": "#e6e6e6",
		"speedMul": 1,
		"ultCost": 7,
		"desc": "Носит в себе несколько отцов. Дуэлянт-обманщик: рывки, двойники и рокировка с клоном.",
		"abilities": {
			"C": {
				"name": "Батин тапок",
				"desc": "Метко брошенный тапок: контузит и ослепляет врагов на попадании (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Двойник",
				"desc": "Рывок вперёд, на месте остаётся клон-двойник — приманка, тянущая огонь (2 заряда)",
				"charges": 2
			},
			"E": {
				"name": "Рокировка",
				"desc": "Запусти клона вперёд; нажми ещё раз — мгновенно поменяйся с ним местами (блинк)",
				"charges": 1
			},
			"X": {
				"name": "Клоны бати",
				"desc": "УЛЬТА: укажи точку — 5 клонов бегут туда, ты сам становишься клоном (стрелять нельзя). Нажми ещё раз — клоны исчезают, ты снова стреляешь",
				"charges": 1
			}
		}
	},
	"koniliy": {
		"name": "Конилий",
		"title": "Наездник",
		"color": "#8a5a2b",
		"darkColor": "#4d3117",
		"accent": "#d9b06a",
		"speedMul": 1,
		"ultCost": 6,
		"desc": "Всё про коней. Подковы, ржание, галоп и табун призрачных коней сносят всё на пути.",
		"abilities": {
			"C": {
				"name": "Подкова",
				"desc": "Брошенная подкова оставляет зону — враги вязнут и получают урон (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Ржание",
				"desc": "Оглушительное ржание конусом — контузит и ослепляет врагов перед собой",
				"charges": 1
			},
			"E": {
				"name": "Галоп",
				"desc": "Оседлай призрачного коня: +50% скорости на 3.5 сек",
				"charges": 1
			},
			"X": {
				"name": "Табун",
				"desc": "УЛЬТА: укажи направление — табун призрачных коней проносится линией и оглушает всех на пути (без урона)",
				"charges": 1
			}
		}
	},
	"sova": {
		"name": "Сова",
		"title": "Следопыт",
		"color": "#3fa9c9",
		"darkColor": "#183f4f",
		"accent": "#d6ecf5",
		"speedMul": 1,
		"ultCost": 7,
		"desc": "Охотник-лучник (прототип на базе Sova). Метит стрелами, вскрывает позиции разведкой и добивает сквозь стены.",
		"abilities": {
			"C": {
				"name": "Шок-стрела",
				"desc": "Стрела-разряд: взрыв по области на попадании — урон врагам рядом (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Метка-стрела",
				"desc": "Разведстрела: враги у места попадания подсвечены команде на 5 сек (по прямой видимости)",
				"charges": 2
			},
			"E": {
				"name": "Дрон-филин",
				"desc": "Короткий скан: палит команде всех врагов в 22 м вокруг на 2.5 сек",
				"charges": 1
			},
			"X": {
				"name": "Ярость охотника",
				"desc": "УЛЬТА: три залпа энергии по направлению взгляда — пробивают стены и бьют всех на линии",
				"charges": 1
			}
		}
	},
	"gera": {
		"name": "Гера",
		"title": "Анти-смокер",
		"color": "#5fe0d0",
		"darkColor": "#1f5b54",
		"accent": "#eafffb",
		"speedMul": 1,
		"ultCost": 7,
		"desc": "Разрушитель тумана. Жёсткий контр-пик смокерам: видит дымы на карте, наказывает кемперов в дыму и развеивает завесы.",
		"abilities": {
			"C": {
				"name": "Развеятель",
				"desc": "Устройство: в радиусе развеивает ВРАЖЕСКИЕ дымы и на пару секунд не даёт ставить новые (2 заряда)",
				"charges": 2
			},
			"Q": {
				"name": "Крюк-кошка",
				"desc": "Грэпл: стреляет крюком в поверхность и подтягивается туда — неожиданные углы и насесты (2 заряда)",
				"charges": 2
			},
			"E": {
				"name": "Воронка",
				"desc": "Конус перед собой стягивает врагов к центру — сбор под свой огонь",
				"charges": 1
			},
			"X": {
				"name": "Невесомость",
				"desc": "УЛЬТА: купол — враги в зоне теряют опору и всплывают, лёгкие мишени (заряд только за киллы)",
				"charges": 1
			}
		}
	}
}

const ABILITY := {
	"FLASH_FUSE": 0.7,
	"FLASH_SPEED": 17,
	"FLASH_MAX_BLIND": 1.9,
	"FIRE_ZONE_R": 4,
	"FIRE_ZONE_TIME": 8,
	"FIRE_DPS": 15,
	"FIRE_HEAL": 12,
	"WALL_LEN": 16,
	"WALL_TIME": 8,
	"PHOENIX_ULT_TIME": 10,
	"SMOKE_R": 4.3,
	"SMOKE_TIME": 13,
	"SMOKE_WALL_GAP": 5.5,
	"ORBITAL_DELAY": 1.4,
	"ORBITAL_DUR": 3,
	"ORBITAL_R": 5.5,
	"ORBITAL_DPS": 40,
	"DASH_DIST": 6.5,
	"LAUNCH_V": 8.5,
	"BOOST_MUL": 1.4,
	"BOOST_TIME": 4,
	"KNIVES_COUNT": 5,
	"KNIFE_DMG": 70,
	"KNIFE_HEAD": 150,
	"KNIVES_TIME": 12,
	"TURRET_R": 20,
	"TURRET_DMG": 5,
	"TURRET_TICK": 0.5,
	"TURRET_HP": 60,
	"TRAP_R": 3,
	"TRAP_REVEAL": 3,
	"TRAP_SLOW": 0.55,
	"TRAP_SLOW_TIME": 3,
	"XRAY_TIME": 6,
	"PUDDLE_R": 3.5,
	"PUDDLE_TIME": 7,
	"PUDDLE_DPS": 10,
	"PUDDLE_SLOW": 0.65,
	"ACID_R": 3.2,
	"ACID_TIME": 6,
	"ACID_DPS": 12,
	"ACID_SLOW": 0.7,
	"COCOON_RANGE": 30,
	"COCOON_SPEED": 45,
	"COCOON_HIT_DMG": 30,
	"COCOON_TIME": 2.6,
	"COCOON_HP": 150,
	"COCOON_FREE_DMG": 20,
	"DENIS_REGEN": 3.5,
	"DENIS_REGEN_CAP": 100,
	"DENIS_REGEN_DELAY": 4,
	"CRISPY_LEN": 10,
	"CRISPY_TIME": 15,
	"CRISPY_SLOW": 0.6,
	"CRISPY_HEAL": 20,
	"BUFFET_R": 8,
	"BUFFET_HEAL": 50,
	"BUFFET_ARM_TIME": 1.2,
	"SCOUT_SPEED": 9,
	"SCOUT_RANGE": 10,
	"SCOUT_LIFE": 7,
	"SCOUT_REVEAL": 3,
	"BANQUET_R": 6,
	"BANQUET_TIME": 20,
	"BANQUET_INSTANT": 30,
	"BANQUET_REGEN": 10,
	"BANQUET_SPEED": 1.15,
	"IRA_CORPSE_R": 4.5,
	"IRA_CORPSE_TIME": 5,
	"IRA_CORPSE_RATE": 14,
	"CLONES_COUNT": 5,
	"CLONES_TIME": 18,
	"CLONES_SPEED": 6.4,
	"MANGAL_R": 3.6,
	"MANGAL_TIME": 7,
	"MANGAL_DPS": 15,
	"TWIN_DASH": 7,
	"TWIN_DECOY_TIME": 5,
	"SWAP_SPEED": 13,
	"SWAP_LIFE": 7,
	"SWAP_DECOY_RANGE": 16,
	"CLONE_POP_STUN_R": 4.5,
	"CLONE_POP_STUN": 1.3,
	"BLOODFEAST_INSTANT": 30,
	"BLOODFEAST_FED": 62,
	"BLOODFEAST_HOT": 7,
	"BLOODFEAST_HOT_FED": 11,
	"BLOODFEAST_HOT_TIME": 4,
	"BLOODFEAST_FED_WINDOW": 6,
	"BLOODFEAST_R": 3.6,
	"CORPSE_LIFE": 14,
	"PICKUP_R": 1.6,
	"PICKUP_LIFE": 25,
	"SCENT_R": 8,
	"SCENT_LIFE": 12,
	"SCENT_REVEAL": 4,
	"SCENT_WOUND_HP": 70,
	"SCENT_BLOOD_MUL": 2,
	"HORSESHOE_R": 3,
	"HORSESHOE_TIME": 6,
	"HORSESHOE_DPS": 10,
	"HORSESHOE_SLOW": 0.6,
	"GALLOP_MUL": 1.5,
	"GALLOP_TIME": 3.5,
	"STAMPEDE_LEN": 26,
	"STAMPEDE_WIDTH": 3,
	"STAMPEDE_STUN": 1.4,
	"STAMPEDE_SPEED": 26,
	"SOVA_SHOCK_R": 3.2,
	"SOVA_SHOCK_DMG": 55,
	"SOVA_MARK_R": 8,
	"SOVA_MARK_REVEAL": 5,
	"SOVA_DRONE_R": 22,
	"SOVA_DRONE_REVEAL": 2.5,
	"SOVA_FURY_DMG": 55,
	"SOVA_FURY_LEN": 42,
	"SOVA_FURY_WIDTH": 1.5,
	"SOVA_FURY_WAVES": 3,
	"GERA_DISPEL_R": 6.5,
	"GERA_DISPEL_BLOCK": 4,
	"GERA_GRAPPLE_RANGE": 24,
	"GERA_GRAPPLE_SPEED": 26,
	"GERA_VORTEX_RANGE": 11,
	"GERA_VORTEX_HALFANG": 0.62,
	"GERA_VORTEX_PULL": 9,
	"GERA_VORTEX_TIME": 0.9,
	"GERA_ULT_R": 6,
	"GERA_ULT_TIME": 4,
	"GERA_ULT_SLOW": 0.35,
	"GERA_SMOKE_DMG_MUL": 1.15
}

const MOVE := {
	"RUN_SPEED": 6.2,
	"WALK_SPEED": 3.1,
	"CROUCH_SPEED": 2.6,
	"ACCEL": 14,
	"AIR_ACCEL": 3,
	"GRAVITY": 21,
	"JUMP_VEL": 6.5,
	"HEIGHT": 1.8,
	"CROUCH_HEIGHT": 1.25,
	"EYE": 0.12,
	"RADIUS": 0.38,
	"STEP_UP": 0.45
}

const BOT_PRESETS := {
	"easy": {
		"react": 0.35,
		"reactJit": 0.3,
		"pHitMin": 0.07,
		"pHitMax": 0.26,
		"head": 0.05,
		"turn": 0.2,
		"hearMul": 0.7,
		"abilityMul": 1.5,
		"sprMul": 1.4
	},
	"medium": {
		"react": 0.14,
		"reactJit": 0.18,
		"pHitMin": 0.13,
		"pHitMax": 0.42,
		"head": 0.13,
		"turn": 0.32,
		"hearMul": 1,
		"abilityMul": 1,
		"sprMul": 1
	},
	"hard": {
		"react": 0.06,
		"reactJit": 0.1,
		"pHitMin": 0.18,
		"pHitMax": 0.55,
		"head": 0.22,
		"turn": 0.45,
		"hearMul": 1.3,
		"abilityMul": 0.7,
		"sprMul": 0.7
	}
}

const PASSIVES := {
	"artemiy": {
		"name": "Саламандра",
		"desc": "не горит в своём огне (свой огонь лечит)"
	},
	"max": {
		"name": "Ветер",
		"desc": "бесшумный бег и повышенная скорость"
	},
	"denis": {
		"name": "Регенерация мясника",
		"desc": "медленно восстанавливает HP вне боя"
	},
	"sova": {
		"name": "Зоркий глаз",
		"desc": "видит иконки брошенного оружия сквозь стены"
	},
	"sanek": {
		"name": "Радар",
		"desc": "шаги врагов отображаются на его миникарте"
	},
	"ira": {
		"name": "Прощальный ужин",
		"desc": "её убийство создаёт у трупа врага хил-зону для союзников"
	},
	"vova": {
		"name": "Хозяин тумана",
		"desc": "в своих дымах видит силуэты союзников"
	},
	"fafik": {
		"name": "Батина закалка",
		"desc": "контузии и ослепления на нём короче на ~30%"
	},
	"koniliy": {
		"name": "Разгон",
		"desc": "2 с бега по прямой без стрельбы дают +скорость"
	},
	"gera": {
		"name": "Барометр + Охотник за туманщиками",
		"desc": "все вражеские дымы видны на миникарте; +15% урона по врагу, стоящему в дыму"
	}
}

const SIGNATURES := {
	"artemiy": {
		"key": "C",
		"cd": 40
	},
	"max": {
		"key": "C",
		"cd": 30
	},
	"vova": {
		"key": "C",
		"cd": 30
	},
	"sanek": {
		"key": "C",
		"cd": 30
	},
	"denis": {
		"key": "E",
		"cd": 35
	},
	"ira": {
		"key": "C",
		"cd": 30
	},
	"fafik": {
		"key": "Q",
		"cd": 35
	},
	"koniliy": {
		"key": "C",
		"cd": 35
	},
	"sova": {
		"key": "Q",
		"cd": 25
	},
	"gera": {
		"key": "C",
		"cd": 30
	}
}


static func weapon_feel(id: String) -> Dictionary:
	var w: Dictionary = WEAPONS.get(id, {})
	return WEAPON_FEEL.get(w.get("cat", "pistol"), WEAPON_FEEL["pistol"])
