# 新小怪动画（Godot 资源）

这里的文件已放进工程的 `assets`，Godot 打开项目后会自动导入。

| 小怪 | 可实例化的分层场景 | 可用于 AnimatedSprite2D/3D 的 SpriteFrames |
| --- | --- | --- |
| 沙鼠 | `rigs/gerbil_rig.tscn` | `sprite_frames/gerbil.tres` |
| 狼 | `rigs/wolf_rig.tscn` | `sprite_frames/wolf.tres` |
| 猩猩 | `rigs/gorilla_rig.tscn` | `sprite_frames/gorilla_front.tres`、`gorilla_side.tres` |
| 长臂猿 | `rigs/gibbon_rig.tscn` | `sprite_frames/gibbon.tres` |
| 鸵鸟 | `rigs/ostrich_rig.tscn` | `sprite_frames/ostrich.tres` |

每个 `.tres` 都有 `walk`（循环）、`attack` 和 `death`（不循环），对应透明底 PNG 图集为每帧 320×320。猩猩横向移动用 `gorilla_side`，纵向移动用 `gorilla_front`。分层场景可直接实例化，并调用 `set_movement()`、`play_attack()`、`play_death()` 控制动作；烘焙图集供二维动画节点或其他场景使用。

原始分层图片保存在 `assets/source_art/new_monsters_20261018`，没有被覆盖。预览页在 `assets/derived_art/new_monsters_20261018/preview.html`。要重新导出图集，可在项目根目录运行 Godot 脚本 `res://tests/export_new_monster_animations.gd`（需要图形渲染器，不使用 `--headless`）。
