# Сверка среза баланса с исходником (public/js/shared.js).
# Значения захардкожены при генерации — трипвайр от случайной правки balance.gd руками
# и от дрейфа при перегенерации из изменившегося shared.js (паритет!).
#
# Метка среза 144e737 → 80dcf62 (G9): balance.gd перегенерирован ради каталога MAPS для
# лобби. ЧИСЛА НЕ УЕХАЛИ — `git diff 144e737 HEAD -- public/js/shared.js` пуст, то есть
# исходник байт-в-байт тот же; сменилась только метка коммита-среза. Заморозка баланса
# на время порта (правило 3) соблюдена, и её настоящие сторожа — жёсткие проверки ниже.
extends GutTest


func test_snapshot_hash() -> void:
	assert_eq(Balance.SNAPSHOT_HASH, "80dcf62", "срез баланса сменился — сверь с VERSIONS.md")


func test_rules() -> void:
	assert_eq(int(Balance.RULES["ROUNDS_TO_WIN"]), 5)
	assert_eq(int(Balance.RULES["BUY_TIME"]), 15)
	assert_eq(int(Balance.RULES["ROUND_TIME"]), 100)
	assert_eq(int(Balance.RULES["SPIKE_TIME"]), 45)
	assert_eq(int(Balance.RULES["DEFUSE_TIME"]), 7)
	assert_eq(int(Balance.RULES["BASE_HP"]), 100)
	assert_almost_eq(float(Balance.RULES["ARMOR_ABSORB"]), 0.66, 0.001)


func test_weapons() -> void:
	assert_eq(int(Balance.WEAPONS["vandal"]["dmg"]), 40)
	assert_eq(int(Balance.WEAPONS["vandal"]["head"]), 160)
	assert_eq(int(Balance.WEAPONS["phantom"]["rpm"]), 660)
	assert_eq(int(Balance.WEAPONS["operator"]["dmg"]), 150)
	assert_eq(int(Balance.WEAPONS["classic"]["price"]), 0)
	assert_eq(int(Balance.WEAPONS["sheriff"]["head"]), 159)
	assert_eq(int(Balance.WEAPONS["bucky"]["pellets"]), 8)


func test_move() -> void:
	assert_almost_eq(float(Balance.MOVE["RUN_SPEED"]), 6.2, 0.001)
	assert_almost_eq(float(Balance.MOVE["RADIUS"]), 0.38, 0.001)
	assert_almost_eq(float(Balance.MOVE["STEP_UP"]), 0.45, 0.001)
	assert_almost_eq(float(Balance.MOVE["JUMP_VEL"]), 6.5, 0.001)


func test_agents_and_ability() -> void:
	assert_eq(Balance.CHARACTERS.size(), 10, "10 агентов в ростере")
	assert_eq(int(Balance.CHARACTERS["artemiy"]["ultCost"]), 5)
	assert_eq(int(Balance.CHARACTERS["gera"]["ultCost"]), 7)
	assert_almost_eq(float(Balance.ABILITY["SMOKE_R"]), 4.3, 0.001)
	assert_eq(int(Balance.ABILITY["SOVA_SHOCK_DMG"]), 55)
	assert_almost_eq(float(Balance.ABILITY["GERA_SMOKE_DMG_MUL"]), 1.15, 0.001)
	assert_eq(int(Balance.ABILITY["KNIFE_HEAD"]), 150)


func test_bot_presets() -> void:
	assert_almost_eq(float(Balance.BOT_PRESETS["medium"]["pHitMax"]), 0.42, 0.001)
	assert_almost_eq(float(Balance.BOT_PRESETS["hard"]["head"]), 0.22, 0.001)
	assert_almost_eq(float(Balance.BOT_PRESETS["easy"]["react"]), 0.35, 0.001)


func test_weapon_feel_helper() -> void:
	assert_almost_eq(float(Balance.weapon_feel("knife")["speed"]), 1.10, 0.001)
	assert_almost_eq(float(Balance.weapon_feel("operator")["speed"]), 0.88, 0.001)
