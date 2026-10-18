# shutiao 的地图工作区

这里保存 shutiao 与助手共同制作的地图内容。默认只在本目录内写文件，工程公共代码只读。
本目录是协作约定，不是操作系统权限锁；其他协作者仍需尊重该边界。

## 从哪里看

- **查看布局**：[地图检查预览](output/world_map_template_v01/map_preview.png)。
- **查看方案和数据规则**：[布局说明](output/world_map_template_v01/map_notes.md)。
- **交给其他程序同事**：[完整交付包](output/world_map_template_v01.zip)，内有数据图、JSON、说明和生成脚本。

目前没有可以直接在 Godot 里试玩的新地图场景。当前文件是地图源数据，后续需要在本工作区内新增转换工具与独立测试场景。

## 文件分工

```text
shutiao_map/
├── AGENTS.md                  助手继续工作时必须遵守的边界
├── README.md                  本说明
├── tools/
│   ├── generate_world_map_template.py   生成地图与执行二维检查
│   └── world_map_template_v01.json      尺寸、生态、高台、候选点参数
├── output/
│   ├── world_map_template_v01/          本版图片、规划数据、说明
│   └── world_map_template_v01.zip       完整交付包
└── validation/
    └── previous_checks/                本次此前的检查记录和缓存
```

## 调整后重新生成

在本目录打开终端，安装有 Python、numpy、Pillow 时运行：

```powershell
python tools/generate_world_map_template.py --output output/world_map_template_v02
```

默认读取 `tools/world_map_template_v01.json`；修改它即可调整下一版。
工具的默认路径根据脚本所在位置确定，从工程根目录运行也不会把结果写回公共 `output/`。
显式指定 `--output` 时，路径相对于终端当前位置，且必须仍位于本工作区内；工具会拒绝越界写入。

保留旧版本，优先输出到新的版本目录。只有要更新本工具已经生成的目录时才使用 `--replace-generated`。
基础图的像素尺寸、颜色、高度映射、坐标与文件校验值保存在每一版的 `map_metadata.json` 中。

## 当前检查记录

原始地图二维数据检查通过，包括 10 条具有 8m 净空的路线、候选区及整圈衔接空间、PNG 精确编码与交付包一致性。
此前另测过 800×600m 尺寸，关卡仍保持 100×100m；200×200m 因空间不足被明确拒绝。
此前 Godot 无窗口加载未发现脚本解析错误，但有系统根证书读取错误；这不代表本次地图已经接入或完成三维验收。
旧日志保留在 `validation/previous_checks/` 中，不需要运行其中的缓存文件。

后续新增 Godot 测试时也会留在此目录内，不改全工程主场景；需要公共代码接入时先说明，再等待用户同意。
