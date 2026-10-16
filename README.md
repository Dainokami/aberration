# 畸变（Aberration）

使用 **Godot 4.7.2** 开发的 2.5D 游戏与关卡编辑器技术验证。

当前验证方向：

- 3D 世界、碰撞与高低地形；
- 固定正交相机下的手绘 2.5D 表现；
- 2m × 2m 地形格及 0m / 2m / 4m 高度；
- 图片美术资产通用导入；
- 场景物件放置、移动、碰撞和撤销；
- 营地预制的保存与整体投放。

## 运行环境

- Godot `4.7.2.stable`
- macOS 为当前主要验证环境

Godot 引擎本身不包含在仓库中，请从 [Godot 官网](https://godotengine.org/download/) 下载。

## 开始使用

1. 使用 Godot 打开本目录下的 `project.godot`。
2. 打开 `scenes/terrain_editor_v2.tscn`。
3. 在场景树选中 `TerrainBuilder`。
4. 使用左侧/右侧的“关卡编辑器”Dock：
   - **地形**：绘制地面、高度、阶梯和出生点；
   - **导入**：将透明 PNG/WebP 生成为 2.5D 物件；
   - **物件**：放置、移动、旋转和删除物件；
   - **预制**：保存及投放营地片段。

双营地验收地图：

```text
data/levels/objects_acceptance.tres
```

## 肢体与场景试玩

按 F5 进入 `scenes/level_playtest.tscn`。默认地图是上面的双营地验收图。角色出生点东边有两块色块：蓝色是流体，黄色是沙漠。

操作：

- `WASD`：移动
- `Z` / `X`：切换上肢 / 下肢
- `G`：捡肢体，或对当前肢体做场景交互
- `J`：攻击最近的可攻击对象
- `T`：开关突破能力
- `R`：回到出生点
- `Tab`：背包

可以逐项试这些交互：

- 鱼尾在蓝块里会游，回到草地或岩地就停。
- 沙鼠前肢在蓝块里按 `G`，能挖掉池中的软块；在硬地上挖不开。
- 章鱼触手在黄块上按 `G` 吸不住，在硬地面上可以吸附。
- 长臂猿靠近裸崖壁按 `G` 抓住，再按 `W` 爬上崖顶。没有这个肢体时，崖壁会挡住去路。
- 岩石可以推，树和栅栏可以砸，草丛可以砍。

无窗口检查：

```sh
$GODOT --headless --path . --script res://tests/test_editor_play.gd -- \
  --level=res://data/levels/objects_acceptance.tres
```

通过时控制台打印 `EDITOR PLAY: PASS`。

详细说明：

- [`TERRAIN_EDITOR.md`](TERRAIN_EDITOR.md)：第一版地形编辑器
- [`SECOND_VERSION.md`](SECOND_VERSION.md)：图片导入、物件及营地预制
- [`SCENE_NOTES.md`](SCENE_NOTES.md)：林间营地技术样例

## 自动化测试

在仓库目录执行：

```sh
GODOT=/path/to/Godot.app/Contents/MacOS/Godot

$GODOT --headless --path . --script res://tests/test_level_data.gd
$GODOT --headless --path . --script res://tests/test_v2.gd
$GODOT --headless --path . --editor -- --test-v2-editor
$GODOT --headless --path . res://scenes/level_playtest.tscn -- \
  --test-editor-level --level=res://data/levels/acceptance_map.tres
```

编辑器测试会故意尝试一次无效保存，以验证保存失败不会丢失数据，因此会出现一条预期的 `Cannot save file`。

## 资料与字体说明

- 游戏设计源文档目前位于本地仓库上级目录，**不包含在本仓库中**。
- 项目中的图片均为技术验证占位图，不是最终美术资产。
- 本机验证使用过的 `ArialUnicode.ttf` 授权不明确，已被 `.gitignore` 排除；项目使用 Godot/系统字体回退。
- 发布正式版本前需要选用并登记许可明确的中文字体。

## 当前限制

- 单张图片不能自动还原真实 3D 深度或背面。
- 包裹体深度、碰撞和接地点只能自动提供初值，需要人工确认。
- 固定相机是美术资产规范的一部分，不支持自由旋转相机。
- 当前为最小技术验证，不包含完整怪物 AI、战斗、倒计时和 BOSS 事件系统。

## License

尚未选择开源许可证。在明确代码与素材授权之前，仓库内容默认保留全部权利。
