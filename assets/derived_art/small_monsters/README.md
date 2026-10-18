# 小怪动画资源

六套视图对应五种小怪：章鱼、蝙蝠、恶魔犬、大鹅、袋鼠。袋鼠的 `kangaroo_side` 是左右侧面，`kangaroo_front` 是上下正面。

- `sheets/`：18 张透明 PNG 精灵表，文件名为“英文怪物名_动作”。每帧 512×512，横向排列。
- `sprite_frames/`：每个视图一份 Godot `SpriteFrames`，可在编辑器中查看 `idle`、`walk`、`attack`、`death`。
- `scenes/`：可直接拖入场景的 `AnimatedSprite2D`，与精灵帧同名。
- `preview.tscn`：在 Godot 中打开并运行；W 移动、A 攻击、D 死亡、R 重置。
- `manifest.json`：中文显示名、原 PSD、方向规则、帧数与速度。

移动循环，攻击播放完回到待机，死亡停在透明末帧。袋鼠可调用 `play_walk_direction(Vector2.LEFT/RIGHT/UP/DOWN)`；左右用侧面图，向左时水平翻转，上下用正面图。

这些是 2D 动画资源，已导入项目素材库，未连接到现有 3D 敌人或刷怪逻辑。
