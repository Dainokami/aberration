# 场景美术导入与编辑器实施

用户已批准实施，补充要求：编辑器 UI 美观、可读。工作分支 `feat/art-pipeline-editor`。

## 约束

- 保留三个 ZIP、附件及所有原图；处理稿与配方单独保存，可重建。
- 保留上一轮交互修复和用户的 `data/prefabs/demo_camp.tres` 修改。
- 本轮不提交、不推送 Git；遵循项目现行规则。
- 地形仍使用连续 2m 分层柱。相机规范保持不变。
- 黑底与黑色轮廓有歧义时，支持显式遮罩/轮廓修正，不声称无损恢复原始透明度。
- Excel 优先于旧 Word。攀岩点为贴墙附件；三角攀岩柱、滚石、矿脉的完整玩法不属于这批资源的实施范围。

## 交付顺序与验收

1. [x] 素材处理：不可变源图、透明化、有效范围、面片四角、尺寸、Atlas、配方与联系表。
2. [x] 资源与工厂：TerrainArtSet、DetailSet、多面/多状态物件、玩法组件；现有单图导入兼容。
3. [x] LevelData v7：独立细节数组、顶面/侧壁/物件支撑锚点、校验、迁移、撤销与预制旋转。
4. [x] 渲染与运行：套件地形/坡面、分块 MultiMesh、完整玩法场景实例化；交互/跳跃/破坏/攀岩验证。
5. [x] 编辑器：简洁的导入类型入口、可折叠高级参数、多图槽位、处理前后预览、搜索资源库、细节笔刷、玩法属性。
6. [x] 样例：导入这批素材，独立美术验收地图；不覆盖用户地图或旧资源 ID。
7. [x] 验证：源图哈希（本地有原图时）、处理稿目测、数据/物理/编辑器回归、Metal 实际渲染与真实窗口操作、使用文档。
   真实窗口验证为自动化输入和 Godot 内部截图，见“已知限制”。

## 数据和交互约定

- 地形套件聚合已有 TileDefinition 的顶面、2m侧壁、边缘和坡面配置；每层材质独立。
- DetailSet 包含贴地/固定视角立片的变体、Atlas UV、米制尺寸与支点；一笔保留确定的随机种子及实例数据。
- PlaceableDefinition 保留单图接口，新增多面素材、状态图和行为配置；AssetFactory 是编辑器和运行时共用入口。
- 地面/物件顶面的支撑锚点决定物件位置；侧壁附件包含层和方向，不随柱顶乱跳。
- 删除支撑的影响必须在候选数据阶段处理，整次撤销可恢复；运行时破坏状态不能回写编辑地图。
- 切片只改变编辑显示与拾取；不允许把切片临时盖面当作可放物件的真实支撑面。
- 所有地图编辑通过 EditorUndoRedoManager；预览必须使用与最终资源相同的工厂。

## UI 约定

- 保留「地形 / 物件 / 导入 / 预制」入口习惯，加入「细节」工具页；视角设置保持独立。
- 常用操作在顶部，资源卡片有清晰名称、图片、尺寸/用途提示；搜索后保留仍有效的选择。
- 窄 Dock 中不横向滚动、不出现超宽文件路径、不堆长按钮；一个页面只有一个垂直滚动容器。
- 高级参数默认折叠；新增类型仅显示该类型所需字段。
- 下拉菜单统一限制高度；预览和错误原因靠近产生它们的操作。

## 实施结果

### 素材

- 三个 ZIP 的 79 张 PNG 原样保存在本地 `assets/source_art/scene_pack_20261014`，不提交到仓库（`.gitignore`）；manifest 记录每张的 SHA-256。本地有原图时测试逐一校验哈希，没有原图时跳过这一项。
- 编辑器、试玩和渲染只使用已提交的处理稿、图集和生成资源，不依赖原图；只有用 `tools/prepare_scene_art.py` 重新处理素材时才需要原图或原始 ZIP。
- `tools/prepare_scene_art.py` 生成处理稿、两张 2048² Atlas（贴地 20、立片 25 个变体）、联系表 `review_*.png` 和 manifest v2。派生图开启 mipmap，关闭 3D 自动检测。
- 黑底只清除与画布边缘相连的黑色；岩石/风化岩石各面按 alpha 轮廓四角校正；彩色背景拐角只生成参考遮罩。
- 悬崖源图拆成两个模块：`rim_grass.png` 只取草带并保留描边，无缝，宽 6.4453m，高出顶面 0.2344m、垂下 0.5m；`cliff_body.png` 为双向无缝岩体，6.4453×1.0078m。
- 攀岩抓点 `climb_grips.png` 由正面岩壁叠加原图中的白色抓点生成。

### 资源与运行

- `tools/import_scene_pack.gd` 生成 3 种地形（手绘草地/草坪/泥土）、2 个细节套件、12 种物件；已有资源跳过。
- TileDefinition 新增 `art_set`、`rim_cutout`、`cliff_course_repeat`。侧壁岩体按世界尺寸无缝平铺，相邻层和相邻柱连续；草边为 alpha scissor 透明贴条；阶梯两侧使用坡面图。
- GameplayProp：宝箱双状态、可破坏岩石耐久、攀岩点。试玩接入 E/J/Space/C；破坏后级联清除依附物件，不写回地图。
- 地图加载实例化保存的物件场景，保留脚本、状态节点与碰撞；碰撞和交互形状使用固定节点名 `Shape`。

### 编辑器

- 导入页 7 种类型，只显示所需字段；玩法、当前图片下拉框与“类型”使用同一标签列，图片槽位按钮与“名称/ID”对齐。“图片处理与对照”默认折叠，后台线程处理，提供原图/处理稿对照并保存配方。
- 处理稿和图集在写入 PNG 前先写好导入设置（mipmap、关闭 3D 自动检测），首次导入即与素材包一致，避免 Godot 之后自动改为显存压缩重新导入。
- 「细节」页：单件/散布/擦除；散布明确分为“混合全部/单一散布”，单一散布才显示搜索与素材卡片。选中素材使用独立强调色信息框；素材大小和可复现的散布种子收在“更多设置”中，按 Enter 应用，种子可一键随机。大尺寸贴地素材约束随机中心并重试，无法获得完整支撑时显示红色预览和原因。一笔一次撤销，只刷新受影响批次。
- 预制页以两个高对比操作按钮切换“制作预制/使用预制”，不再依赖容易被误认成输入框的原生页签。
- 物件页按真实碰撞拾取顶面/侧壁，支持叠放与贴墙；资源卡片显示玩法与放置提示。
- 卡片、图标、Dock 宽度和标签列宽按编辑器缩放。缩放 2.0 时，导入页 7 种类型的最小宽度均为 285 逻辑像素，细节卡片保持三列。

### 验收地图

`scenes/art_acceptance.tscn` / `data/levels/art_acceptance.tres`：14×14；三种手绘地形，两层平台与阶梯；宝箱、可破坏岩石（上叠岩石、侧面抓点）、地形侧壁抓点、树木/石柱/草花；218 个细节（贴地 117、立片 101）。

## 验证

本机 Apple M5 Pro / Godot 4.7.2：

- 无窗口：`test_art_pipeline`、`test_art_level`、`test_art_runtime`（14 项）、`test_level_data`、`test_v2`、`test_terrain_p0`、`test_stacked_terrain`、`test_runtime_camera`、`level_playtest --test-editor-level`、whitebox/assembly 冒烟测试均通过。
- 编辑器套件 188 项：无窗口和真实窗口（编辑器缩放 2.0）均通过；覆盖单一/混合散布、设置提交、随机种子、大尺寸支撑提示、2.5D 近侧/远侧相邻落格、选中信息框和预制操作按钮。
- Metal：`render_art_acceptance` 输出 `/tmp/aberration-art-{overview,props,edge,chest-closed,chest-open}.png`；已目测墙面、草边和宝箱两态接地。
- 面板截图：`--capture-art-panels` 输出 `/tmp/aberration-panel-*.png`，已目测。

重建素材包：

```sh
python3 tools/prepare_scene_art.py   # 需要 Pillow、numpy、scipy；ZIP 默认位于项目上级目录
$GODOT --headless --path . --import
$GODOT --headless --path . --script res://tools/import_scene_pack.gd
$GODOT --headless --path . --script res://tools/create_art_acceptance.gd
```

- 仓库不包含原图；`prepare_scene_art.py` 会从三个 ZIP 中重新解出原图到 `assets/source_art/scene_pack_20261014`，再生成处理稿。可用 `--archives <目录>` 指定 ZIP 所在位置。

- `import_scene_pack.gd` 加 `-- --refresh-scene-pack` 时，只重建素材包自己的地形和细节资源；物件目录已存在时保持不变。
- 验收地图已存在时保持不变。
- 首次生成（尚无 `.import`）时，导入后再运行一次 Python 脚本写入 mipmap 设置，然后再次 `--import`。

## 已知限制

- 彩色背景拐角仍为参考图，只生成参考遮罩；地形拐角由拓扑几何和弯折的草边贴条生成。
- 多面岩石素材没有背面，背面复用正面。
- 三角攀岩柱、滚石、矿脉玩法未实现。攀爬一次上升一层（2m），胶囊角色没有攀爬动画。
- 物件放置、移动、删除仍重建整张地图；细节笔刷只刷新受影响批次。
- 自动去黑底不能保证恢复原始透明度；黑描边与背景粘连时需要遮罩。
- Computer Use 读取 Godot 时只返回菜单栏，无法截图。UI 目测依赖 Godot 内部截图和真实窗口自动化测试，没有人工逐项点击全部控件。
- 真实窗口退出编辑器时可能输出 `Can't use get_node() with absolute paths from outside the active scene tree.`。它由 Godot 4.7.2 处理场景保存的选中节点（`.godot/editor/*-editstate-*.cfg` 中的 `$selected_nodes`）引起：无脚本空工程同样复现，清除该记录后消失；与项目代码无关，不影响数据。
