# 呸呸肢体素材（2026-10-18）

用户提供的 `肢体-呸呸.zip` 包含 7 个文件夹、15 张白底 JPG。这里保存逐字节原图；`source_trace.json` 记录 ZIP 内原名、规范化路径、SHA-256 和对应的透明 PNG。透明裁切图位于 `assets/derived_art/limbs_peipei_20261018/`，由 `scripts/import_limb_art_peipei.py` 生成。原 JPG 没有被覆盖。

| 原文件夹 | 游戏部件 ID | 用途 |
| --- | --- | --- |
| 大鹅翅膀 | `goose_wing` | `primary.png` 用于图标与掉落；另一张羽毛层保留 |
| 大鹅脚蹼 | `goose_foot` | `primary.png` 用于图标与掉落；另一只脚和身体层保留 |
| 猩猩、猩猩白化 | `gorilla_arm` | 普通手臂用于图标与掉落；手掌及白化配色保留 |
| 章鱼、章鱼白化 | `octopus_arm`、`octopus_leg` | 同一触手图用于两个现有部件的图标与掉落；另一版及白化配色保留 |
| 犬 | `demon_dog_leg` | 目前只有整只犬图，暂用于部件图标与掉落；不能当作独立腿拼装素材 |

这些 JPEG 层不是动画帧。当前角色拼装仍使用已有的模块化角色图，新增贴图仅用于 `PartCatalog` 的部件图和怪物掉落图。白化配色不新增部件 ID 或能力。
