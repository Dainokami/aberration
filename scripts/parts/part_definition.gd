class_name PartDefinition
extends RefCounted

# 部件只描述能力和限制。岩石、流体、沙漠都是场景以后回报的标签，
# 不在这里引用地形、关卡或具体物件脚本。
enum Slot { UPPER, LOWER }
enum Band { NONE, LOW, NORMAL, HIGH }
enum AttackShape { NONE, FACING, AROUND }
enum Rank { R1, R2, R3 }

var id := ""
var display_name := ""
var slot := Slot.UPPER
var attack_power := Band.NONE
var attack_rate := Band.NONE
var attack_shape := AttackShape.NONE
var rank := Rank.R1
var spawn_scenes: PackedStringArray = PackedStringArray()
var blurb := ""

var speed_band := Band.NONE
var allowed_surfaces: PackedStringArray = PackedStringArray()
var jump_count := 0
var breakthrough_jump_count := 0
var air_mode := ""
var burrow := false
var swim := ""
var can_stick := false
var stick_blocked_tags: PackedStringArray = PackedStringArray()
var breakthrough_stick_any := false
var abilities: PackedStringArray = PackedStringArray()
var breakthrough: PackedStringArray = PackedStringArray()


static func power_value(band: Band) -> int:
	match band:
		Band.LOW:
			return 8
		Band.NORMAL:
			return 14
		Band.HIGH:
			return 22
		_:
			return 0


static func cooldown_for(band: Band) -> float:
	match band:
		Band.LOW:
			return 1.15
		Band.NORMAL:
			return 0.62
		Band.HIGH:
			return 0.34
		_:
			return 0.0


static func speed_value(band: Band) -> float:
	match band:
		Band.LOW:
			return 3.2
		Band.NORMAL:
			return 5.6
		Band.HIGH:
			return 8.4
		_:
			return 0.0


func has_ability(ability_id: String, breakthrough_on: bool) -> bool:
	if abilities.has(ability_id):
		return true
	return breakthrough_on and breakthrough.has(ability_id)


func rank_label() -> String:
	return ["r1", "r2", "r3"][rank]


func attack_text() -> String:
	if attack_shape == AttackShape.NONE:
		return "无攻击"
	var power: String = ["无", "低攻", "中攻", "高攻"][attack_power]
	var rate: String = ["", "慢", "中", "快"][attack_rate]
	var shape := "朝向" if attack_shape == AttackShape.FACING else "周围"
	return "%s/%s · %s" % [power, rate, shape]


func jump_count_for(breakthrough_on: bool) -> int:
	if breakthrough_on and breakthrough_jump_count > jump_count:
		return breakthrough_jump_count
	return jump_count
