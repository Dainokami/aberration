# 2026-10-17 素材补接记录

## 压缩包复核

已解压并核对项目上级目录的三个 ZIP：

- `素材.zip`：25 张物件面片与状态图。
- `素材_PNG.zip`：9 张地形及参考图。
- `独立PNG素材_带碎渣版_45件.zip`：45 张细节。

79 张图的 SHA-256 均与 `scene_pack_20261014/manifest.json` 中已导入源图一致，没有新增图片。原有地形、树木草花、石柱、宝箱两态、岩石主体及 45 件细节继续使用原资源。

## 补接的四个物件

在编辑器「物件」页点击「刷新物件库」，或重新打开项目，即可找到：

| 名称 | 资源 ID | 此次接入的图片 |
| --- | --- | --- |
| 攀岩岩块 | `painted_climbingrock` | `climbingrock_frontface`、`sideface2`、`sideface3`、`topface` |
| 攀岩岩块·顶面二 | `painted_climbingrock_alt` | 同一组侧面，顶面使用 `climbingrock_topface2` |
| 岩石块·顶面二 | `painted_rock_alt` | 原有岩石侧面，顶面使用此前未挂接的 `rock_topface` |
| 风化岩石·顶面二 | `painted_decayrock_alt` | 原有风化岩石侧面，顶面使用此前未挂接的 `decayrock_topface` |

四者均为 2×2×2 米实体物件，可放在地块或承托物件顶面，支持叠放和侧面附件。风化岩石变体继承耐久 3 和破坏行为。原 `painted_rock` / `painted_decayrock` 的顶面仍为 `*_topface2`，资源 ID、已有场景与地图未被替换。

攀岩岩块提供完整岩体外观和碰撞，行为是「可登顶」。要配置攀爬面，在物件库选择已有的「攀岩抓点」，点击岩块侧面附着；试玩开启攀爬能力后，使用 E 附着、WASD 在相邻攀爬面之间移动。岩体本身不会自动生成攀爬附件。

这次是图片接入。ZIP 中不含缠绕海草、卷吸流沙、刺棘丛、悬崖垂藤、浮升气泡柱、散落遗骸、自然资源簇、塌陷沙坑的新图，这些机制仍需另行补充素材与玩法；果树交互、宝箱掉落等也不因图片导入而完成。

## 处理和重建

- `tools/prepare_remaining_scene_art.py` 校验五张攀岩源图哈希，按四角将绘制透视校正为面纹理，并生成组合缩略图。
- 派生图保存在 `assets/derived_art/scene_pack_20261014/remaining_objects/`；独立 `remaining_objects_manifest.json` 保存源图哈希、四角和组装对应关系。
- `tools/import_remaining_scene_art.gd` 只生成四个新 ID，已有目录仅校验并跳过，不覆盖。
- 原 79 张图的 manifest、原图和既有派生图均不改写。编辑器与运行时使用派生图和保存场景，不依赖本地源图。

重建需要先按已有美术管线还原源图，再执行：

```sh
python3 tools/prepare_remaining_scene_art.py
"../godot-engine/Godot.app/Contents/MacOS/Godot" --headless --path . --import
"../godot-engine/Godot.app/Contents/MacOS/Godot" --headless --path . --script res://tools/import_remaining_scene_art.gd
"../godot-engine/Godot.app/Contents/MacOS/Godot" --headless --path . --import
```

## regular Mask 结论

用户明确要求地块过渡仅使用 irregular，已移除 regular 依赖并删除目录。此前据代码回退行为得出的“必须保留”结论已纠正。

- `TerrainTopology` 从 9 张 irregular 原图旋转、组合出全部 47 种邻接形状，并缓存图像和纹理。
- `TerrainBlendMap` 和 `TerrainBuilder` 共用该结果；贴花也使用相同组合规则。
- 普通顶面与切片封口使用程序生成的全白遮罩。

原始交付 manifest 和 SHA256SUMS 作为源资料保留，其 regular 条目描述历史交付内容，不再代表运行时依赖。当前规则见 `TERRAIN_VISUAL_RULES.md`。

## 验证

Godot 4.7.2：

- `test_remaining_scene_art`：新定义、五张面图、mipmap、真实保存场景材质、2 米碰撞、叠放/贴墙附件、保存重载、实际顶面拾取和风化岩石破坏通过。
- `test_art_pipeline` / `test_art_level` / `test_art_runtime` / `test_terrain_p0` 通过，原 79 张源图哈希及地形 Mask 回归通过。
- 编辑器 `--test-v2-editor` 通过；四个资源都有实际卡片和缩略图，视口点击放置及撤销通过。
- Metal `test_remaining_scene_art -- --capture-remaining-art` 通过；四个物件在项目固定视角和侧面视角的截图已目测。
- 既有 generated / derived 跟踪文件逐一比对 HEAD，无改动。本轮没有提交或推送。
- 移除 regular 后：`test_terrain_p0` 覆盖全部 47 种遮罩的边方向、中心覆盖、原画旋转、缓存复用、三种变体和真实混合权重；局部刷新与重建一致。
- `test_free_blocks` / `test_stacked_terrain` / 编辑器套件 / `test_remaining_scene_art` 均通过。600×600 范围、64×64 填充测试的摆放/擦除局部重建约 30/24ms，低于项目 150ms 上限。
- Metal 渲染全部邻接样例及 `render_dynamic_splat` 通过并已目测；9 张 irregular 原图和用户已有未提交地图/预制/场景的哈希均未变化。
