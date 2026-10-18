class_name TerrainMovementRules
extends RefCounted

## 畸变_场景机制设计.xlsx rows 5–8. Values are metres per second.
const SPEEDS := {
	"grass": {"demon_dog_leg":5.0, "ostrich_leg":5.0, "wolf_leg":3.0,
		"kangaroo_leg":3.0, "water_snake":3.0, "goose_foot":1.5,
		"gerbil_leg":1.5, "octopus_leg":1.5, "fish_tail":0.0},
	"rock": {"demon_dog_leg":5.0, "wolf_leg":5.0, "kangaroo_leg":3.0,
		"water_snake":3.0, "ostrich_leg":3.0, "gerbil_leg":1.5,
		"octopus_leg":1.5, "fish_tail":0.0, "goose_foot":0.0},
	"desert": {"ostrich_leg":5.0, "gerbil_leg":5.0, "kangaroo_leg":5.0,
		"demon_dog_leg":3.0, "wolf_leg":1.5, "fish_tail":0.0,
		"goose_foot":0.0, "water_snake":0.0, "octopus_leg":0.0},
	"ocean": {"goose_foot":5.0, "fish_tail":5.0, "water_snake":3.0,
		"octopus_leg":3.0, "demon_dog_leg":0.0, "wolf_leg":0.0,
		"gerbil_leg":0.0, "ostrich_leg":0.0, "kangaroo_leg":0.0},
}

static func speed(lower_id: String, ecosystem: String, underwater := false) -> float:
	if ecosystem == "ocean" and underwater and lower_id == "goose_foot":
		return 0.0
	return float(SPEEDS.get(ecosystem, {}).get(lower_id, 0.0))

static func speed_for_tags(lower_id: String, tags: PackedStringArray) -> float:
	# Water wins over overlapping seabed/shore tags. Older test courses only
	# authored "fluid"; preserve that tag while applying the ocean rules.
	if tags.has("fluid") or tags.has("ocean"):
		return speed(lower_id, "ocean", tags.has("ocean") and not tags.has("water_surface"))
	for ecosystem in ["ocean", "desert", "rock", "grass"]:
		if tags.has(ecosystem):
			return speed(lower_id, ecosystem, ecosystem == "ocean" and not tags.has("water_surface"))
	return -1.0
