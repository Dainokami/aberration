# 2.5D 关卡白盒

运行 `scenes/main.tscn` 即可试玩。当前操作：

- `WASD`：相机朝向相对移动
- `Space`：按住起飞、松开缓降
- `C`：循环切换六种肢体组合
- `Q`：装卸翅膀
- `J`：攻击并显示移动/攻击通道冲突

关卡采用《塞尔达传说：智慧的再现》式紧凑俯视野外布局：南侧草地进入河谷，两岸由木桥连接，树林和岩石构成自然边界，北侧高台遗迹是临时终点。步行可走桥和台阶，飞行可跨河或直接登上高台。跌入水面下方会自动复位。

## 美术接入

`scenes/player.tscn` 把碰撞、移动与表现分开：

- `Player/Collision`：玩法碰撞体，不依赖美术尺寸。
- `Player/ArtRoot/Composite`：当前 PSD 导出的合成图。替换 Texture 即可更换整图角色。
- `Player/ArtRoot/PartSockets/RuntimeSkeleton`：运行时骨骼与刚性挂点，包含头、躯干、左右手、双足、四足、三段蛇尾和左右翅膀。
- `PlayerVisualRig.visual_mode`：切换 `COMPOSITE` / `PARTS`。拆图后把各 `Sprite3D` 挂到对应 Socket，再切到 `PARTS`。

移动逻辑集中在 `scripts/player_controller.gd`，形态参数集中在 `scripts/character_assembly_controller.gd`。速度倍率、加速度、减速度、步态频率和推进脉冲分别按头滚、单臂、双臂、双足、四足、蛇行配置；实际位移和 `scripts/modular_character_rig.gd` 的骨骼动画共用步态相位。跳跃高度、滞空时间、飞行升降速度仍暴露为 Inspector 参数；后续更换肢体或动画时不需要修改移动代码。

完整的移动优先级、攻击通道冲突和美术动画清单见 `LIMB_SYSTEM_DESIGN.md`。

源 PSD 保存在 `art/source/聚光灯角色拼接&拆分验证.psd`，透明裁切预览保存在 `art/characters/prototype/character_composite.png`。

最终运行画面可查看 `docs/whitebox_preview.png`。
