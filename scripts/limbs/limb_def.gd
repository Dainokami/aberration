class_name LimbDef
extends RefCounted

var id := ""
var display_name := ""
# upper、lower，或 none。none 不能装配。
var slot := "none"
var family := ""
var tier := 1
var rare := false
var upgrade_id := ""
var rare_id := ""
var texture_path := ""
var visual := ""
var visual_scale := 1.0
var tint := Color.WHITE
var blurb := ""
var speed_scale := 1.0
# 只有飞书能力表中的 17 个基础部件可以再次放进培养皿。
var culture_ingredient := false
# 缺少正式素材的合成结果使用现有代理图，并明确保留占位状态。
var placeholder_art := false
var result_kind := "ordinary"
