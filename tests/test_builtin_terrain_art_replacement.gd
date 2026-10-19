extends SceneTree

const ROOT := "res://assets/source_art/terrain_handoff_v02/"
const EXPECTED := {
	"top/grass_top.png": "8d5c16814e5c73d6515c5859358da577a3185d2b8a1b945a272663251fa02a30",
	"cliff/grass_cliff.png": "66ee7c70c13e7d67a41f08209203c8c51ef3084ae00efbdff35eac78b3212a01",
	"rim/grass_rim_soft.png": "50f9dad27f0d500145af4b35d0df165a181207cdaae41618cd04132044a8a26f",
	"top/rock_top.png": "da6c921522399098959991eb97bb97d0c110f1cb300e7c03bb82ea6e22f91912",
	"cliff/rock_cliff.png": "da6c921522399098959991eb97bb97d0c110f1cb300e7c03bb82ea6e22f91912",
	"rim/rock_rim_soft.png": "f4c5936da14173bdd67f47c27c4790c23642ba9607acb16e8a8705346e8188f1",
	"top/sand_top.png": "f6c95620a482d328353b3d231187cd7919a38dcb5b2b5996622f79fb7e89362a",
	"cliff/sand_cliff.png": "f3ca3a3a07a238120b0f4cddf7c7db00f7ac350097ed3300c2bf32fa7aa55307",
	"rim/sand_rim_soft.png": "689dd57e56dffaede16707631bf072230da8ad52ae3b7d23f5e9b14dc5f1e9c8",
	"top/water_top.png": "be2a91488ac8724a88b2eb52231e7a11ef3d153e99e5d9e3812a07c960dde406",
	"water/shore_foam.png": "da5ffcd95a74d910d1fa48be72c13a53e3756267ffc434379651c4d01f3c0cc8",
}
const PAINTED_UNCHANGED := {
	"res://data/tiles/painted_grass.tres":
		"9683d4c2a118eb72bc20fd97242ebac0e24654ded4abba2ba1d4ed2e90eade81",
	"res://data/tiles/painted_meadow.tres":
		"1b9f2537d86edf416e85ac08400f11e8c324f368a7d227dd6d4237f553d6e82c",
	"res://data/terrain_art/painted_grass.tres":
		"f686095e1aa9fe6f5e22c01692a47d0f45ad68abff880ee733d0e6a8d3b7cf69",
	"res://data/terrain_art/painted_meadow.tres":
		"d71551114cdbec741eba4dedc7fcd7ed0de2b7e350701e2d037cf82818985ca6",
	"res://assets/derived_art/scene_pack_20261014/terrain/grass.png":
		"562f42e7b8470271b00e418b6f9f108b16527722f3959459151736b760e601cb",
	"res://assets/derived_art/scene_pack_20261014/terrain/meadow.png":
		"93244403d8b6561d659f4b2bada053696568eafa0f6ffb813d7d20ce7e40c1f2",
}

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("BUILTIN TERRAIN ART CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func run() -> void:
	for relative: String in EXPECTED:
		var path := ROOT + relative
		check(FileAccess.get_sha256(path) == EXPECTED[relative],
			"replacement bytes " + relative)
		check(load(path) is Texture2D, "replacement imports " + relative)
	for path: String in PAINTED_UNCHANGED:
		check(FileAccess.get_sha256(path) == PAINTED_UNCHANGED[path],
			"painted terrain unchanged " + path.get_file())
	var expected_paths := {
		"grass": ["top/grass_top.png", "cliff/grass_cliff.png", "rim/grass_rim_soft.png"],
		"rock": ["top/rock_top.png", "cliff/rock_cliff.png", "rim/rock_rim_soft.png"],
		"sand": ["top/sand_top.png", "cliff/sand_cliff.png", "rim/sand_rim_soft.png"],
		"water": ["top/water_top.png", "", "water/shore_foam.png"],
	}
	for tile_id: String in expected_paths:
		var tile := TileRegistry.find(tile_id)
		var paths: Array = expected_paths[tile_id]
		check(tile != null and tile.tile_id == tile_id, "stable tile id " + tile_id)
		check(tile.texture_path == ROOT + paths[0], "top path " + tile_id)
		check(tile.cliff_texture_path == ("" if paths[1].is_empty() else ROOT + paths[1]),
			"cliff path " + tile_id)
		var edge_path := tile.foam_texture_path if tile_id == "water" else tile.rim_texture_path
		check(edge_path == ROOT + paths[2], "edge path " + tile_id)
	for map_path in [
		"res://data/levels/dynamic_splat_acceptance.tres",
		"res://data/levels/acceptance_map.tres",
	]:
		var data := load(map_path) as LevelData
		check(data != null and data.validate().is_empty(), "old map loads unchanged " + map_path.get_file())
	print("BUILTIN TERRAIN ART CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
