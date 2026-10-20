# 恶魔狼（机械狼）四帧动画

打开 [preview.html](preview.html) 预览行走、攻击、死亡。资源目录名沿用 `mechanical_wolf_20261020`，避免现有项目引用失效。

| 动画 | 关键画面 | 播放 | 建议帧率 |
| --- | --- | --- | --- |
| `walk.png` | 四足交错行走的 4 个姿势 | 循环 | 6 FPS |
| `attack.png` | 蓄力、跃起、张嘴扑咬、收势 | 一次 | 5 FPS |
| `death.png` | 狼身、烟雾遮身、灰紫色烟团、透明 | 一次 | 5 FPS |

三张精灵图均为透明 RGBA PNG，尺寸 **4096 × 512**，按 **4 列 × 1 行**排布，每帧 **1024 × 512**。在 Godot `AnimatedSprite2D` 的 `SpriteFrames` 中按 4 列、1 行切分，也可直接导入 `frames/` 下每组的 4 张单帧 PNG。`death` 播放完应隐藏角色或停在透明第 4 帧。

行走、攻击直接使用原有四个关键姿势。死亡的烟团**直接取自猩猩和信天翁共用的死亡贴图** `assets/animations/mechanical_monsters_20261019/gorilla/keyframes/death.png`：第 2 帧烟团遮住狼身，第 3 帧只剩放大的同款烟团，第 4 帧透明。`scripts/build_mechanical_wolf_four_frames.gd` 可重新生成三组四帧动画。用户提供的狼原画位于 `assets/source_art/mechanical_wolf_20261020/reference.png`。
