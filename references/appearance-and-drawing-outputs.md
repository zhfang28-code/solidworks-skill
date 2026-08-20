# SolidWorks 浅色配色与规范视图交付

## 目录

- [标准与优先级](#标准与优先级)
- [浅色模型配色](#浅色模型配色)
- [工程图显示配置](#工程图显示配置)
- [五视图、图框与大小](#五视图图框与大小)
- [图线、图层和剖面](#图线图层和剖面)
- [可编辑 CAD 输出](#可编辑-cad-输出)
- [PNG 与 PDF 输出](#png-与-pdf-输出)
- [视图规范审核数据](#视图规范审核数据)
- [交付门禁](#交付门禁)

## 标准与优先级

优先顺序：用户/客户指定标准与模板 → 企业标准 → 项目模板 → 下列 GB/T 基线。不得把 skill 的后备参数冒充客户标准。

截至 2026-08-20，国家标准全文公开系统将以下标准标为现行；正式项目开始时重新核对状态：

| 范围 | 基线 |
|---|---|
| 图纸幅面和格式 | [GB/T 14689-2008](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=6C3BD0FCD8FFFE7CEC6404FB0180EA96) |
| 比例 | [GB/T 14690-1993](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=C111329A862219BCCCAAF32E14FF4CD0) |
| 投影法 | [GB/T 14692-2008](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=1072044E4F129FBC0423C354C2D6FE51) |
| 技术制图图线 | [GB/T 17450-1998](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=ED5D794A6EFCD039618233C957C058DB) |
| 机械制图图线 | [GB/T 4457.4-2002](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=5B789BF5B537CF6F89B5D743DA71D883) |
| 剖面区域 | [GB/T 4457.5-2013](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=7E48457ABE06799AEBFB9E7C8651BF63) |
| 视图 | [GB/T 4458.1-2002](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=1B3AE836354647D640A592D775EDB683) |
| 轴测图 | [GB/T 4458.3-2013](https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=52098A4E44A7F21B33FB11F2609052B4) |
| 剖视图和断面图 | [GB/T 4458.6-2002](https://openstd.samr.gov.cn/bzgk/gb/newGbInfo?hcno=98FC4489987C8309C89CC2816AFFCE9C) |

使用经批准的 `.drwdot/.slddrt` 模板承载精确图框、标题栏、字体、箭头、线宽和区域设置。没有合格模板时可以使用本参考的后备配置，但结论写“按 skill 后备配置”，不能声称已通过企业制图标准。

## 浅色模型配色

### 双配置原则

- `模型审核_浅色`：三维模型和等轴测图片使用浅色组件外观、白或极浅灰背景、深色边线。
- `工程图_黑白规范`：正式正投影、剖视、PDF 和打印使用白底黑线；组件颜色不得替代线型、剖面线或零件边界。
- 配色只帮助识别零件。不能用颜色掩盖缝隙、干涉、缺边或错误轮廓，也不能只靠红/绿区分状态。

### 默认组件调色板 `light-engineering-v1`

| 角色 | HEX | RGB 0–255 | RGB 0–1 |
|---|---:|---:|---:|
| 固定基体/底座 | `#D7E3F1` | 215, 227, 241 | 0.8431, 0.8902, 0.9451 |
| 壳体/套筒 | `#BFD7EA` | 191, 215, 234 | 0.7490, 0.8431, 0.9176 |
| 运动杆/轴 | `#CFE8CF` | 207, 232, 207 | 0.8118, 0.9098, 0.8118 |
| 调节螺母/操作件 | `#F1D6A8` | 241, 214, 168 | 0.9451, 0.8392, 0.6588 |
| 标准紧固件 | `#D8DDE5` | 216, 221, 229 | 0.8471, 0.8667, 0.8980 |
| 肋板/焊接板 | `#C9E4DF` | 201, 228, 223 | 0.7882, 0.8941, 0.8745 |
| 其他相邻件 1 | `#E5C7D2` | 229, 199, 210 | 0.8980, 0.7804, 0.8235 |
| 其他相邻件 2 | `#E6D9F2` | 230, 217, 242 | 0.9020, 0.8510, 0.9490 |

相邻组件不得使用同一颜色；超过八种时只对不相邻组件循环颜色。临时错误高亮可用 `#F4B6B6`，修复完成后必须恢复正式颜色。

SolidWorks 九参数外观数组统一为：

```text
[R, G, B, Ambient, Diffuse, Specular, Shininess, Transparency, Emission]
[R, G, B, 0.45, 0.75, 0.15, 0.20, 0.00, 0.00]
```

其中 RGB 使用 0–1。优先在装配体显示状态或组件级设置，避免为了展示修改零件材料定义。设置后刷新图形区，再回读九参数并写入审核 JSON。

### 灯光和背景

- 背景使用纯白 `#FFFFFF` 或极浅灰 `#F7F8FA`，边线使用近黑 `#202020`。
- 关闭 RealView、环境光遮蔽、地面阴影和会遮挡孔槽的强高光。
- 主光位于相机前上方，辅光减弱背光面；不得通过移动灯光隐藏几何缝隙。
- 三维审核默认“带边线上色”；几何比对另输出“消除隐藏线”。

## 工程图显示配置

- 把 `SLDDRW` 作为关联、可编辑、可重建的权威工程图；DWG/DXF 是便携副本，PNG/PDF 是视觉证据。
- 使用高质量 HLR/HLV；不得用 Draft Quality 作为正式输出，因为草图/线型可能退化为细实线。
- 关闭选择高亮、草图编辑状态、基准临时显示和视图边界高亮后再导出。
- SolidWorks 的视图选择边界是界面辅助，不属于图样。整张输出只显示标准图框；独立视图 PNG 只保留固定留白，不绘制额外矩形框。
- 切换到 `工程图_黑白规范` 后强制重建、保存、关闭重开，再进行 DWG/PDF/PNG 导出。

## 五视图、图框与大小

默认输出：正面、侧面、俯视、3D 等轴测、剖面。每个视图必须是实际模型派生的工程图视图或命名模型视图，不得用任意相机截图冒充正投影。

### 图幅与图框

1. 从合格模板选择 A 系列图幅和横/竖向，使全部视图、尺寸和明细栏落在可打印区。
2. 校验纸张宽高、图框、标题栏、分区、投影符号、比例、单位、图号、页码和修订。
3. 图框与标题栏不得被视图、尺寸、表格或裁剪区域覆盖。
4. 全图 PNG/PDF/DWG 必须保留图框；独立视图 PNG 不重复标题栏。

### 比例、对齐与外包框

- 主视图先选 GB/T 或项目模板允许的标准比例；投影视图使用父视图比例并保持严格水平/垂直对齐。
- 剖视默认继承父视图比例。等轴测若使用不同的自定义比例，必须显示比例标记并写入审核数据。
- 关闭“自动缩放新工程图视图”造成的无记录变化；最终逐个读取实际 `ScaleDecimal`。
- 使用 `View.GetOutline()` 记录每个视图在纸张坐标中的 `xmin/ymin/xmax/ymax`、宽、高、中心和比例。
- 所有视图外包框必须完整位于图框可打印区，不相互重叠；尺寸、注释和零件序号的包络也要纳入碰撞检查，因为 `GetOutline()` 不包含这些注释。
- 主视图占用最大清晰区域。若视图过小导致孔槽、虚线、剖面或文字在 100% 打印比例下不可辨认，应换大图幅或提高比例，不允许只提高 PNG 像素掩盖纸面过小。
- skill 后备布局的视图/注释包络间距取不小于 10 mm；若项目模板另有规定，使用模板值并记录。

## 图线、图层和剖面

使用文档属性和图层统一控制，不逐条随意改线。若无企业映射，采用以下角色：

| 图层/对象 | 线型 | 相对线宽 | 用途 |
|---|---|---|---|
| `OUTLINE` 可见轮廓 | 连续实线 | 粗 | 可见外形、可见棱边 |
| `HIDDEN` 不可见轮廓 | 虚线 | 细 | 隐藏边；按视图需要显示 |
| `CENTER` 中心/轴线 | 细点画线 | 细 | 轴线、对称中心、中心轨迹 |
| `DIM` 尺寸/界线/引线 | 连续实线 | 细 | 尺寸线、尺寸界线、引出线 |
| `CUTTING` 剖切位置 | 规范剖切线型 | 粗 | 剖切位置、箭头和 A-A 标识 |
| `HATCH` 剖面线 | 连续实线 | 细 | 剖面区域；相邻件方向或间距不同 |
| `BORDER` 图框 | 连续实线 | 模板定义 | 图框与标题栏 |

线宽优先取模板。无模板时，A3/A4 后备值使用粗线 0.50 mm、细线 0.25 mm；更大图幅根据模板提高一级。该数值是 skill 后备配置，不替代客户标准。

必须检查：

- 可见边没有错误变成虚线或细线；隐藏边没有与中心线混淆。
- 中心线超出轮廓适量且不替代真实边。
- 正式剖视中的被剖材料有剖面线；轴、杆、销、紧固件及纵向肋板按图示约定处理。
- 相邻零件剖面线能够区分；剖面线不穿过文字、尺寸或空腔。
- 切边、相切边和螺纹简化线符合图纸表达；不以三维阴影代替图线。

## 可编辑 CAD 输出

默认交付：

1. `<base>.SLDDRW`：权威、模型关联、可编辑。
2. `<base>.DWG`：通用 2D CAD 可编辑整张图；需要兼容时再附加 `<base>.DXF`。
3. 若 SolidWorks 版本支持，启用“将工程图视图导出为块”，使每个视图在 DWG/DXF 中作为独立块；不支持时由 SLDDRW 保证逐视图可编辑，并在聊天窗口说明限制。

DWG/DXF 导出规则：

- 明确目标 AutoCAD/DraftSight 版本；不使用“最新”作为无记录默认值。
- 优先导出全部图纸到 paper space，保留图框和图纸比例。
- 使用 AutoCAD 标准线型并映射到最接近的线宽；若项目提供映射文件，记录其路径和哈希。
- 使用 TrueType 或经验证的字体映射，避免中文、直径符号、公差和粗糙度符号替换。
- 多比例视图不得盲目启用“输出 1:1”。只有用户明确需要模型空间 1:1 几何时才启用，并逐个记录被换算的视图比例。
- 导出后在可用的 2D CAD 中打开，或重新导入 SolidWorks；核对图层、块、实体范围、文字、线型、线宽、剖面和图框。仅文件非空不算通过。

若用户明确要求每个视图单独的 CAD 文件，再输出 `<base>_正视.dwg/.dxf` 等；默认优先使用一个整张 DWG 中的独立视图块，避免比例和位置关系丢失。

## PNG 与 PDF 输出

### 整张工程图

- 输出 `<base>_整张工程图.png` 和 `<base>.PDF`，白底、含图框、标题栏和全部注释。
- PNG 默认 300 DPI；像素按 `round(纸张毫米 / 25.4 × DPI)` 计算，保持纸张纵横比，不用屏幕截图代替打印捕获。
- 曲线和 HLR/HLV 使用高质量设置；导出后按原始像素检查文字、虚线节距、圆弧和剖面线。

### 独立视图图片

- 输出 `<base>_正视.png`、`_侧视.png`、`_俯视.png`、`_等轴测.png`、`_A-A剖视.png`。
- 正面/侧面/俯视/剖面来自工程图黑白线图；等轴测另外使用浅色带边线模型展示。
- 由纸张坐标和视图/注释包络裁剪，四周保留一致留白：默认取包络较长边的 8%，且不少于 24 px。
- 不包含菜单、光标、选择边界、坐标三轴、临时基准、滚动条或黑色背景。
- 文件名、视图方向、投影法和剖切方向与 SLDDRW/DWG 一致；不得单独旋转图片制造视觉匹配。

## 视图规范审核数据

生成 `<base>_视图规范审核.json`，至少记录：

```json
{
  "standard_profile": "GB/T + project template",
  "template_path": "...",
  "template_sha256": "...",
  "sheet": {"width_mm": 420, "height_mm": 297, "scale": "1:1", "projection": "...", "dpi": 300, "image_width_px": 4961, "image_height_px": 3508, "border_verified": true, "title_block_verified": true, "projection_symbol_verified": true},
  "appearance_profile": {"name": "light-engineering-v1", "background_hex": "#FFFFFF", "edge_hex": "#202020", "adjacent_components_distinct": true, "component_colors": []},
  "line_profile": {"visible": "continuous-thick", "hidden": "dashed-thin", "center": "chain-thin", "dimension": "continuous-thin", "cutting": "cutting-thick", "hatch": "continuous-thin", "thin_width_mm": 0.25, "thick_width_mm": 0.50},
  "views": [
    {
      "id": "front",
      "name": "正视",
      "type": "orthographic",
      "scale": "1:1",
      "outline_mm": [0, 0, 0, 0],
      "inside_printable_area": true,
      "overlap_count": 0,
      "linework_verified": true,
      "image_path": "...",
      "image_width_px": 0,
      "image_height_px": 0
    }
  ],
  "cad_roundtrip": {"format": "DWG", "opened": true, "layers_ok": true, "views_editable": true, "scale_ok": true},
  "drawing_reopened": true,
  "blocking_issues": []
}
```

五个视图使用稳定 ID `front/side/top/isometric/section`，且都必须出现；`inside_printable_area=true`、`overlap_count=0`、`linework_verified=true`。剖视另外记录有效剖面数量和不剖件；DWG/DXF 记录回读工具及版本。无法自动证明的项目列入 `blocking_issues` 和聊天窗口，不能伪造布尔值。

## 交付门禁

- [ ] 浅色配色名称、RGB 和九参数数组已记录，相邻件可区分。
- [ ] 正式工程图为白底黑线，选择边界和界面元素未输出。
- [ ] SLDDRW 保存重开有效，五个视图方向和比例正确。
- [ ] 图幅、图框、标题栏、投影符号、比例和单位完整。
- [ ] 可见实线、隐藏虚线、中心点画线、尺寸线、剖切线和剖面线角色正确。
- [ ] 所有视图/注释包络在可打印区内且互不重叠。
- [ ] DWG/DXF 回读后图层、块、文字、线型、线宽、比例和图框正确。
- [ ] 整张 PNG/PDF 与纸张比例一致；五张独立 PNG 清晰且裁剪一致。
- [ ] 视图规范审核 JSON 无阻塞项。
- [ ] `Test-SolidWorksDelivery.ps1 -RequireDrawingPackage` 返回 `Ready=true`。
