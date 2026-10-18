# 2026-10-18 肢体素材

源自用户提供的 `怪物肢体.zip` 和 `肢体2.zip`。28 张 PNG 均逐字节保留；`source_trace.json` 记录原 ZIP 条目名、规范化后的路径、SHA-256。`preview.html` 用于直接预览，不是游戏 HUD。

| PartCatalog ID | 槽位 | 掉落/图标用图 | 原有能力对应 |
| --- | --- | --- | --- |
| `wolf_leg` | 下肢 | `wolf_leg/body.png` | 硬地中速 |
| `ostrich_leg` | 下肢 | `ostrich_leg/body.png` | 硬地高速 |
| `gerbil_leg` | 下肢 | `gerbil_leg/body.png` | 硬地中速、遁地 |
| `kangaroo_leg` | 下肢 | `kangaroo_leg/body.png` | 硬地高速、一段跳、突破后两段跳 |
| `bat_wing` | 上肢 | `bat_wing/primary.png` | 滑翔 |
| `albatross_wing` | 上肢 | `albatross_wing/primary.png` | 悬停 |
| `eagle_wing` | 上肢 | `eagle_wing/primary.png` | 自由飞行 |
| `fish_tail` | 下肢 | `fish_tail/primary.png` | 流体中高速悬浮游动 |

独立 PNG 作为肢体图；`preview.png` / `white_preview.png` 是带角色头部的效果图，不可当作肢体图。`feet.png`、`tail.png`、`forelimbs.png` 是分层素材，保留供后续制作肢体动画。`white.png` 是鹰和信天翁的另一种配色，与原 ID 共用机制。

`pangolin_claw_unmapped/primary.png` 目前没有对应的 `PartCatalog` ID 或能力，先保留原画，不加到掉落或装备池，也不借用其他怪物的能力。`piranha` 的旧掉落 ID `piranha_gill` 不存在于 `PartCatalog`；这次按食人鱼鱼尾图改为已实现的 `fish_tail`。

本次代码把已匹配的图绑定到 `PartCatalog`，怪物掉落会按掉落肢体 ID 显示对应图。世界场景的拾取仍使用现有 `scene_inventory` 实现；该场景当前没有把这套背包接到角色装备 UI，因此这里没有宣称装备后的角色拼装已改用这些原画。
