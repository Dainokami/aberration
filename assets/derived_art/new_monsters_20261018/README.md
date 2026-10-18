# 新小怪动画

本目录配合 `scenes/new_monsters_preview.tscn` 使用。Godot 4 中打开该场景并按 F6，可预览沙鼠、狼、猩猩正面与侧面、长臂猿、鸵鸟的分层行走、攻击和烟雾死亡动画。

直接双击 `preview.html` 可在浏览器中观看循环录制版，无需先打开 Godot。

- `W`：切换行走 / 停止
- `空格`：播放攻击
- `D`：播放烟雾死亡
- `R`：重置预览

`scripts/adventure/layered_monster_rig.gd` 是游戏中使用的可导入动画骨架。原始图片保存在 `assets/source_art/new_monsters_20261018/`，没有修改；白底在渲染时由 `white_key.gdshader` 和 `white_key_2d.gdshader` 去除。

怪物分布和掉落依据《怪物以及boss机制文档.xlsx》：草地有狼、长臂猿；沙漠有沙鼠、鸵鸟；岩石地形有猩猩、长臂猿。狼、猩猩主动攻击，沙鼠、鸵鸟、长臂猿受攻击后反击。沙鼠掉腿，狼掉腿，猩猩与长臂猿掉手臂，鸵鸟掉腿。
