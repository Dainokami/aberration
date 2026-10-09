# 地形编辑器 v0.1

> 第二版已加入美术导入、物件和营地预制，使用说明见 [SECOND_VERSION.md](SECOND_VERSION.md)。
> 当前 Dock 名称为左侧“关卡编辑器”；下文保留第一版地形功能说明。

## 开始使用

1. 用 Godot 4.7.2 打开项目。
2. 打开 `scenes/terrain_editor_test.tscn`。
3. 在场景树中选择 `TerrainBuilder`。
4. 右侧出现“地形编辑器”Dock。若没有出现，在“项目设置 > 插件”启用“畸变地形编辑器”。
5. 先点“新建”，或用“打开”选择 `data/levels/acceptance_map.tres`。

## 工具

- **地面**：选择草地/岩地以及0m/2m/4m，在空格或已有格上绘制。
- **高度**：仅修改已有普通地块，不自动填空。
- **擦除**：删除普通地块；点阶梯任意占地格会删除整段阶梯。
- **阶梯**：从低端格开始放置，Q/E旋转。高端目标格必须恰好高2m。
- **出生点**：只能放在普通地块顶面。
- **画笔**：地面、高度、擦除支持1×1和3×3；阶梯和出生点按单格处理。

左键点击或拖动绘制。右键不被插件占用，用于Godot原生视口导航。一个连续拖笔只产生一次撤销记录。

地图默认保存为Godot文本资源 `.tres`。保存后点“保存并试玩当前地图”，编辑器会启动 `level_playtest.tscn`。试玩中使用WASD/方向键移动，R重置。

## 示例地图

- `data/levels/blank_map.tres`：16×16空地图。
- `data/levels/acceptance_map.tres`：0m、2m、4m三平台，两段连续阶梯和出生点。
- `scenes/forest_camp.tscn`：此前认可的林间营地样例，保持独立。

## 自动检查

```sh
HOME=/private/tmp/godot-home ../godot-engine/Godot.app/Contents/MacOS/Godot \
  --headless --path . --script res://tests/test_level_data.gd

HOME=/private/tmp/godot-home ../godot-engine/Godot.app/Contents/MacOS/Godot \
  --headless --path . res://scenes/level_playtest.tscn -- \
  --test-editor-level --level=res://data/levels/acceptance_map.tres
```

第一条验证坐标、阶梯合法性、占地以及资源保存读取。第二条实际推动CharacterBody3D验证0→2m、2→4m阶梯和无阶梯崖壁阻挡。

## 已知限制

- 地图是单层高度表，不支持桥下通行、洞穴或上下重叠。
- 阶梯固定宽2m、长4m、高2m。
- 插件每次笔画后完整重建当前小地图；16×16验证规模足够，量产版再做局部重建。
- 画笔交互、中文Dock和未保存确认仍需在Godot图形窗口人工验收。无窗口测试不能替代UI验收。
- “新建/打开”的未保存确认提供放弃或取消；需要保存时应先按“保存”。第一版没有三按钮“保存/放弃/取消”对话框。
- 试玩关卡路径暂写入项目设置，因此会修改 `project.godot` 的自定义设置；后续可换成编辑器会话参数。
- 项目内中文字体来自本机，仅用于本地验证；发布前应替换为许可明确的项目字体。
