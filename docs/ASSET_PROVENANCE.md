# 素材来源声明

记录日期：2026-10-21。此文档区分项目提供者的来源确认与可独立查阅的第三方来源记录。

## Maintainer-declared AI originals

项目提供者在发布准备过程中明确确认，先前被列为来源待核实的这组素材为 **AI 原创**。
根据这一确认，以下 39 个成品不再作为“来源未知”阻塞项目发布，随项目原创内容按根目录 MIT
许可证分发。此分类的依据是项目提供者声明，尚未归档生成平台、模型版本、提示词或导出记录，
不能将其描述为审查工具已独立验证的生成历史。

| 文件 | 数量 | 当前来源分类 |
|---|---:|---|
| `game/assets/models/regina.glb` | 1 | 项目提供者确认 AI 原创 |
| `game/assets/sfx/*.wav` | 35 | 项目提供者确认 AI 原创 |
| `game/assets/decals/graffiti_*.png` | 3 | 项目提供者确认 AI 原创 |

此前注释曾把手柄模型关联到 Phalange，把音效关联到 BigSoundBank/Kenney，把贴花关联到照片
裁切工具。下载缓存中也存在外部音效和图片，但此前没有完整的逐成品映射。保留这些历史说明作为
来源差异记录，以项目提供者本次明确确认作为当前分类依据，不将历史推断继续写成已核实结论。
如以后补齐生成记录或发现成品实际使用了第三方输入，应按实际情况更新对应文件的来源与许可。

## Documented third-party inputs

以下已明确记录第三方输入的资源继续保留原来源与 CC0 说明，不因项目其他内容使用 AI 制作而
改写为 AI 原创：

- `game/assets/polyhaven/`：Poly Haven 原始素材及减面加工产物，保留其来源清单。
- `game/assets/characters/`：MakeHuman/MPFB 官方系统素材与本项目 Blender 脚本生成的角色。
- `game/assets/golf/trees/`：Poly Haven 树木模型经烘焙得到的图集。

这些内容见 [THIRD_PARTY.md](THIRD_PARTY.md)。后续贡献请记录实际输入、加工步骤和输出文件；
有生成记录的 AI 素材也应一并归档记录，不使用“AI 参与制作”覆盖已知的第三方许可要求。
