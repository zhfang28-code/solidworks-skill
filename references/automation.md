# SolidWorks API 自动化

## 环境边界

- 仅在物理 Windows 10/11 x64 和本机 SolidWorks 上运行。
- 先运行 `scripts/Test-SolidWorksEnvironment.ps1 -AsJson`。必须找到 `SLDWORKS.exe`、两个 interop DLL、零件模板和 .NET Framework C# 编译器。
- 启动 SolidWorks GUI 或运行 builder 前按宿主规则请求审批。只读探测不需要启动 SolidWorks。
- 使用当前安装目录中的 interop DLL，不把第三方或旧版本 DLL 写入技能仓库。
- 若系统执行策略禁止 `.ps1`，只对新建进程使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`；不得修改机器或用户级执行策略。

## Builder 接口约定

为每个零件生成独立的 C# 源文件，并遵循：

```text
Builder.exe <output-directory> [--close]
```

- 第一个参数必须是已由用户确认的绝对输出目录。
- `--close` 只允许关闭由 builder 自己启动的 SolidWorks；不得退出用户原本打开的会话。
- 参数集中放在 `Main` 开头或独立数据类中。
- 返回码 `0` 表示构建和保存成功，非零表示失败。
- 记录 SolidWorks revision、模板路径、每个关键特征、保存错误码和异常 HRESULT。

使用包装脚本：

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -NoProfile -ExecutionPolicy Bypass `
  -File '<skill>\scripts\Invoke-SolidWorksBuilder.ps1' `
  -SourcePath 'D:\work\BuildPart.cs' `
  -OutputDirectory 'D:\confirmed-output' `
  -CompileOnly
```

确认编译后，去掉 `-CompileOnly` 执行。需要结束新启动的实例时加 `-CloseWhenFinished`。

## API 实现要点

### 会话生命周期

1. 先尝试 `Marshal.GetActiveObject("SldWorks.Application")`。
2. 连接失败时再创建 `SldWorksClass`，并记录 `createdApplication=true`。
3. 新建实例后立即记录 `sw.GetProcessID()`，用于证明实例归属和诊断残留进程。
4. 只在收到 `--close` 且 `createdApplication=true` 时关闭本任务文档、调用 `ExitApp()` 并释放 COM 引用。
5. 退出后检查该 PID 是否仍存在。不得按进程名广泛强杀 SolidWorks；无法证明归属时请用户保存并退出会话。
6. 不更改用户已有文档，不关闭与本任务无关的窗口。

### 模板和单位

- 优先读取 `swDefaultTemplatePart`，再使用已探测到的 `.prtdot`。
- 不硬编码某一用户名或版本的模板路径。
- SolidWorks API 的几何长度通常以米输入；所有图纸毫米值显式除以 `1000.0`。
- 角度显式从度转换为弧度。

### 特征创建

- 获取稳定基准面后再开始草图，并检查选择是否成功。
- `InsertSketch`、`FeatureExtrusion3`、`FeatureCut4` 等调用后检查返回的 `Feature` 是否为空。
- 对起始偏置、反向拉伸、贯穿全部和合并结果显式设置参数。
- 创建后重命名特征和草图；命名失败写日志但不得掩盖几何失败。
- 对多闭环草图验证预期区域，避免切错封闭域。

### 保存和导出

- 使用静默保存并记录 `errors`、`warnings`；非零值必须进入聊天窗口和日志。
- 先保存原生模型并再次重建，再导出 STEP 和 PNG。
- STEP 导出可先用 `IModelDocExtension.SaveAs`，再按版本能力尝试不带 Copy 的 `ModelDoc2.SaveAs4`；两者失败时保留原生模型并明确标记 `step_exported=false`，不得伪造或沿用旧 STEP。
- 重导已有中性文件前先保存到新修订目录，或把旧文件移入明确的历史目录；不要未经授权删除旧交换文件。
- PNG 依次显示等轴测、正视、侧视，执行缩放适合和重绘后保存。
- 输出审查 JSON 时使用稳定字段名和数值单位后缀，例如 `overall_width_mm`、`mass_kg`。

### 工程图剖视与剖面线

- `View.GetOutline()` 返回图纸页坐标，而视图草图中的剖切线使用视图局部模型坐标。把页坐标换算为草图坐标时使用：`local = (sheetCoordinate - viewCenter) / view.ScaleDecimal`。直接把页坐标传给视图草图会让剖切线看似存在但实际落在模型之外，生成空剖面。
- 创建剖视后不能只检查返回对象。强制重建、保存、关闭并重新打开工程图，再检查剖视类型、剖切线数量、可见组件数和面剖面填充数量。
- 若需让轴、杆或紧固件不显示剖面线，优先对匹配到的 `FaceHatch` 设置 `UseMaterialHatch=false`、区域范围和无填充样式；此操作必须在最后一次重建后执行并再次保存，因为后续重建可能恢复自动填充。
- 组件排除接口在部分 SolidWorks 版本/装配剖视中可能无效或触发 COM 服务端异常；出现版本差异时记录为工具限制，不得把调用成功当作视觉结果成功。
- 通过稳定的组件/几何证据匹配剖面面；若只能依赖临时面编号，保存重开后必须再次验证。

## 推荐审查数据

```json
{
  "part_number": "...",
  "solidworks_revision": "...",
  "body_count": 1,
  "bounding_box_mm": {"x": 0, "y": 0, "z": 0},
  "mass_properties": {"mass_kg": 0, "volume_cm3": 0, "density_kg_m3": 0},
  "parameters": {},
  "features": [],
  "save_errors": [],
  "unmodeled_requirements": []
}
```

## 故障处理

- `REGDB_E_CLASSNOTREG`：位数不匹配、SolidWorks 未正确注册或 interop 版本错误。
- 新建零件返回空：模板路径无效或 SolidWorks 正在显示阻塞对话框。
- 特征返回空：草图未闭合、方向错误、轮廓自交、偏置起点无效或没有合并实体。
- 保存失败：目标文件存在、目录不可写、格式扩展名不匹配或导出器不可用。
- `AddComponent5` 返回空或位置异常：零件未预加载、装配体未激活，或错误地把参数坐标当成零件原点而不是包围盒中心。
- STEP 返回 `swGenericSaveError=1`：先在新路径复现以排除覆盖/锁文件，再检查重建、实体有效性、组件解析状态和残留 SolidWorks 会话；不要无限重试或强杀不明会话。
- API 卡住：先查看 SolidWorks 是否有模态对话框；不要用无限等待。按不超过 60 秒的周期检查并向用户更新。
- 工程图剖视对象存在但没有剖面填充：优先检查剖切线坐标系、视图中心和视图比例；不要先反复切换自动填充。
- 最终重建后不剖件又恢复填充：把无填充设置移到最后一次重建之后，保存并重开验证持久性。

任何本参考未列出的 API 行为、插件依赖或版本差异，都要作为“技能外事项”在聊天窗口说明后再处理。
