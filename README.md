# 畸变（Aberration）

使用 **Godot 4.7.2** 开发的2.5D游戏、3C白盒与可视化关卡编辑器技术验证。

当前关卡编辑器包括：

- 最大600×600格、固定2m地块逐块搭建：左键贴面接块、单次删除、切片查看；
- “默认右键删除”开关切换右键／Alt＋右键删除与转向，支持点击删除物件；
- 自由视角左上角显示 Alt 导航／摆放删除状态，分别使用绿色和红色；
- 空气层与桥下空间、实际底面碰撞；被紧邻上层覆盖的附属内容隐藏并原位恢复；
- 固定正面轻俯视透视相机；
- 47类地貌拓扑Mask、四地貌权重混合、稳定不规则变体与连续世界底纹；
- 草地卷边、岩沙圆钝崖顶、连续侧壁与水岸泡沫；
- 地图级动态着色，不修改美术源图；
- PNG／WebP地块和物件导入；地形套件、细节图集、多面岩石、双状态宝箱和贴墙攀岩点导入，含去黑底、四角校正与遮罩；
- 物件放置、移动、碰撞、遮挡淡出；物件叠放、贴墙附件与级联删除；
- 草屑、碎石、落叶等细节笔刷（无碰撞，分块合批渲染）；
- 营地预制保存、预览和整体投放；
- 撤销／重做、保存／加载和胶囊试玩；试玩支持开宝箱、跳跃、破坏岩石与攀爬。

## 运行环境

- Godot `4.7.2.stable`
- macOS为当前主要验证环境

Godot引擎不包含在仓库中，请从[Godot官网](https://godotengine.org/download/)下载。

## 打开关卡编辑器

1. 使用Godot打开项目根目录的 `project.godot`。
2. 确认“项目 → 项目设置 → 插件 → 畸变地形编辑器”已启用。
3. 点击Godot顶部工具栏的 **关卡编辑器**。

插件会自动打开或复用标准编辑场景、选择 `TerrainBuilder`、切换到3D视图并进入固定2.5D编辑模式，不需要手动展开场景树。

详细使用说明：[`USAGE_GUIDE.md`](USAGE_GUIDE.md)

分层编辑与旧地图迁移：[`STACKED_TERRAIN.md`](STACKED_TERRAIN.md)

## 肢体与场景试玩

试玩场景里的角色仍是编辑器胶囊。肢体规则读的是地形标签：水体是流体，沙地是沙漠，其余实心地面是硬地面。裸崖壁可以给长臂猿爬。出生点东边另有蓝色流体和黄色沙漠色块，用来在没有这些地块的旧地图上试。

- 鱼尾在流体里会游，在硬地上停下。
- 沙鼠前肢只在流体里按 `G` 挖软块。
- 章鱼触手在沙漠上吸不住，在硬地面上可以吸附。
- 长臂猿对裸崖壁按 `G`，再按 `W` 爬上崖顶。

无窗口检查：

```sh
$GODOT --headless --path . --script res://tests/test_editor_play.gd -- \
  --level=res://data/levels/objects_acceptance.tres
```

通过时控制台打印 `EDITOR PLAY: PASS`。

场景美术素材包导入记录、重建命令与已知限制：[`docs/art_pipeline_execution.md`](docs/art_pipeline_execution.md)。美术验收地图：`scenes/art_acceptance.tscn`。

视觉与相机规则：[`TERRAIN_VISUAL_RULES.md`](TERRAIN_VISUAL_RULES.md)

## 其他文档

- [`WHITEBOX_README.md`](WHITEBOX_README.md)：3C白盒与角色系统
- [`LIMB_SYSTEM_DESIGN.md`](LIMB_SYSTEM_DESIGN.md)：肢体拼接设计
- [`TERRAIN_EDITOR.md`](TERRAIN_EDITOR.md)：第一版历史说明
- [`SECOND_VERSION.md`](SECOND_VERSION.md)：第二版历史说明
- [`SCENE_NOTES.md`](SCENE_NOTES.md)：林间营地技术样例

## 自动化测试

```sh
GODOT=/path/to/Godot.app/Contents/MacOS/Godot

$GODOT --headless --path . --script res://tests/test_level_data.gd
$GODOT --headless --path . --script res://tests/test_v2.gd
$GODOT --headless --path . --script res://tests/test_terrain_p0.gd
$GODOT --headless --path . --script res://tests/test_stacked_terrain.gd
$GODOT --headless --path . --script res://tests/test_free_blocks.gd
$GODOT --headless --path . --script res://tests/test_terrain_performance.gd
$GODOT --headless --path . --script res://tests/test_art_pipeline.gd
$GODOT --headless --path . --script res://tests/test_art_level.gd
$GODOT --headless --path . --script res://tests/test_art_runtime.gd
$GODOT --headless --path . --script res://tests/test_runtime_camera.gd -- \
  --level=res://data/levels/acceptance_map.tres
$GODOT --headless --path . --editor -- --test-v2-editor
$GODOT --headless --path . res://scenes/level_playtest.tscn -- \
  --test-editor-level --level=res://data/levels/acceptance_map.tres

# 使用真实图形后端导出分层地形验收图（不可添加 --headless）
$GODOT --path . --rendering-method mobile --script res://tests/render_stacked_terrain.gd
# 美术验收地图渲染，输出 /tmp/aberration-art-*.png（不可添加 --headless）
$GODOT --path . --script res://tests/render_art_acceptance.gd
# 在真实窗口截取导入页和细节页，输出 /tmp/aberration-panel-*.png
$GODOT --path . --editor -- --test-v2-editor --capture-art-panels
```

编辑器测试包括左键贴面摆放、右键单次删除（大画笔、长按和拖动均不扩大删除）、Alt 状态标识、搭建后拆支撑、拖动锁定平面、切片拾取、撤销重做、预览检查，以及导入页图片处理、各导入类型的窄 Dock 宽度和细节页。图形脚本包含悬空桥、覆盖/恢复和底面视角；两处无效保存测试会输出预期的 `Cannot save file`。真实窗口退出时可能出现 Godot 引擎自身的 `Can't use get_node() with absolute paths from outside the active scene tree.`（由恢复的场景选中状态引起，空工程同样出现）。其余脚本/着色器错误应视为失败，即使进程退出码为0。

## 资料与授权

- 游戏设计源文档位于本地仓库上级目录，不包含在GitHub仓库中。
- 项目图片主要用于技术验证；正式使用前应确认各素材的最终授权范围。
- 本机使用过的 `ArialUnicode.ttf` 授权不明确，已被 `.gitignore` 排除。
- 正式发布前需要加入许可明确的中文字体。

## License

尚未选择开源许可证。在明确代码与素材授权之前，仓库内容默认保留全部权利。
