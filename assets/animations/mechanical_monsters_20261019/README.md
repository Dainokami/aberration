# 机械怪动画预览

打开 [preview.html](preview.html) 查看六种怪物的移动、攻击和死亡。鹰、信天翁的“移动”是飞行动画；死亡在烟雾散尽后停在透明帧，点击移动或攻击可重播。

| 目录 | 怪物 | 移动 | 攻击 |
| --- | --- | --- | --- |
| `eagle` | 机械鹰 | 振翅飞行 | 俯冲抓击 |
| `albatross` | 机械信天翁 | 振翅飞行 | 俯冲突袭 |
| `gorilla` | 机械猩猩 | 交替踏步 | 前冲重拳 |
| `gibbon` | 机械长臂猿 | 四肢交错 | 前扑挥臂 |
| `ostrich` | 机械鸵鸟 | 双腿交替 | 前踢 |
| `gerbil` | 机械沙鼠 | 小步快跑 | 前掌挥击 |

每个目录的 `walk.png`、`attack.png`、`death.png` 均为透明 RGBA 横向精灵表，尺寸 **3072 × 384**，每帧 **384 × 384**，共 **8 帧**。Godot 的 AnimatedSprite2D 可将其按 `8` 列、`1` 行导入 SpriteFrames；推荐帧率见 `manifest.json`。`walk` 循环，`attack` 和 `death` 播放一次；死亡末帧透明。

原始 JPG 截图保存在 `assets/source_art/mechanical_monsters_20261019/`，构建脚本是 `scripts/build_mechanical_monster_animations.py`。因为用户提供的是合成参考图而非透明分层素材，攻击从现有姿势组合和位移推演，边缘可能有轻微 JPG 压缩痕迹。这组图用于动作预览；若后续提供分层源文件，可替换切帧并细化独立肢体动作。
