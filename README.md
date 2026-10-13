# 畸变（Aberration）

使用 **Godot 4.7.2** 开发的2.5D游戏、3C白盒与可视化关卡编辑器技术验证。

当前关卡编辑器包括：

- 2m×2m地块及0m／2m／4m高度；
- 固定正面轻俯视透视相机；
- 47类地貌拓扑Mask、四地貌权重混合、稳定不规则变体与连续世界底纹；
- 草地卷边、岩沙圆钝崖顶、连续侧壁与水岸泡沫；
- 地图级动态着色，不修改美术源图；
- PNG／WebP地块和物件导入；
- 物件放置、移动、碰撞、遮挡淡出；
- 营地预制保存、预览和整体投放；
- 撤销／重做、保存／加载和胶囊试玩。

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
$GODOT --headless --path . --editor -- --test-v2-editor
$GODOT --headless --path . res://scenes/level_playtest.tscn -- \
  --test-editor-level --level=res://data/levels/acceptance_map.tres
```

编辑器测试会故意尝试一次无效保存，用于验证保存失败不会丢失数据，因此会出现一条预期的 `Cannot save file`。

## 资料与授权

- 游戏设计源文档位于本地仓库上级目录，不包含在GitHub仓库中。
- 项目图片主要用于技术验证；正式使用前应确认各素材的最终授权范围。
- 本机使用过的 `ArialUnicode.ttf` 授权不明确，已被 `.gitignore` 排除。
- 正式发布前需要加入许可明确的中文字体。

## License

尚未选择开源许可证。在明确代码与素材授权之前，仓库内容默认保留全部权利。
