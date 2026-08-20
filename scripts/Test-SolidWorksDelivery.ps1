[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$BaseName,

    [ValidateSet('Part', 'Assembly')]
    [string]$DocumentType = 'Part',

    [string]$NativeModelPath,
    [string]$StepPath,
    [string]$IsometricPreviewPath,
    [string]$FrontPreviewPath,
    [string]$SidePreviewPath,
    [string]$AuditPath,
    [string]$BuildLogPath,
    [switch]$RequireBom,
    [string]$BomPath,
    [switch]$RequireDrawingPackage,
    [string]$DrawingPath,
    [string]$EditableCadPath,
    [string]$DrawingPdfPath,
    [string]$DrawingSheetPreviewPath,
    [string]$TopPreviewPath,
    [string]$SectionPreviewPath,
    [string]$ViewAuditPath,
    [string]$ProjectRoot,
    [switch]$RequireNoModelsOutsideOutput,
    [switch]$WriteManifest,
    [switch]$Force,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    throw 'OutputDirectory 必须是绝对路径。'
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Container)) {
    throw "交付目录不存在：$resolvedOutput"
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedCandidate = [System.IO.Path]::GetFullPath($Candidate)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    if ($resolvedCandidate.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $rootPrefix = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    return $resolvedCandidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

$resolvedProjectRoot = $null
if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    if (-not [System.IO.Path]::IsPathRooted($ProjectRoot)) {
        throw 'ProjectRoot 必须是绝对路径。'
    }
    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $resolvedProjectRoot -PathType Container)) {
        throw "项目根目录不存在：$resolvedProjectRoot"
    }
    if (-not (Test-PathWithinRoot -Candidate $resolvedOutput -Root $resolvedProjectRoot)) {
        throw "OutputDirectory 必须位于 ProjectRoot 内：$resolvedOutput"
    }
}
elseif ($RequireNoModelsOutsideOutput) {
    throw '使用 RequireNoModelsOutsideOutput 时必须同时提供 ProjectRoot。'
}

function Resolve-DeliveryPath {
    param([string]$Path, [string]$DefaultName)

    $selected = if ([string]::IsNullOrWhiteSpace($Path)) { $DefaultName } else { $Path }
    if ([System.IO.Path]::IsPathRooted($selected)) {
        return [System.IO.Path]::GetFullPath($selected)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $resolvedOutput $selected))
}

function Test-JsonProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-FilePrefixText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Count = 1024
    )
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $buffer = New-Object byte[] $Count
        $read = $stream.Read($buffer, 0, $buffer.Length)
        return [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
    }
    finally {
        $stream.Dispose()
    }
}

function Get-PngDimensions {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $signature = @(137, 80, 78, 71, 13, 10, 26, 10)
    if ($bytes.Length -lt 24) {
        throw "PNG 文件过短：$Path"
    }
    for ($i = 0; $i -lt $signature.Count; $i++) {
        if ($bytes[$i] -ne $signature[$i]) {
            throw "PNG 签名无效：$Path"
        }
    }
    $width = ($bytes[16] -shl 24) -bor ($bytes[17] -shl 16) -bor ($bytes[18] -shl 8) -bor $bytes[19]
    $height = ($bytes[20] -shl 24) -bor ($bytes[21] -shl 16) -bor ($bytes[22] -shl 8) -bor $bytes[23]
    return [pscustomobject]@{ Width = $width; Height = $height }
}

$documentExtension = if ($DocumentType -eq 'Assembly') { '.SLDASM' } else { '.SLDPRT' }
$expected = @(
    [pscustomobject]@{ Kind = 'NativeModel'; Required = $true; Path = (Resolve-DeliveryPath $NativeModelPath ($BaseName + $documentExtension)) },
    [pscustomobject]@{ Kind = 'STEP'; Required = $true; Path = (Resolve-DeliveryPath $StepPath ($BaseName + '.STEP')) },
    [pscustomobject]@{ Kind = 'IsometricPreview'; Required = $true; Path = (Resolve-DeliveryPath $IsometricPreviewPath ($BaseName + '_等轴测.png')) },
    [pscustomobject]@{ Kind = 'FrontPreview'; Required = $true; Path = (Resolve-DeliveryPath $FrontPreviewPath ($BaseName + '_正视.png')) },
    [pscustomobject]@{ Kind = 'SidePreview'; Required = $true; Path = (Resolve-DeliveryPath $SidePreviewPath ($BaseName + '_侧视.png')) },
    [pscustomobject]@{ Kind = 'AuditData'; Required = $true; Path = (Resolve-DeliveryPath $AuditPath ($BaseName + '_模型审查数据.json')) },
    [pscustomobject]@{ Kind = 'BuildLog'; Required = $true; Path = (Resolve-DeliveryPath $BuildLogPath ($BaseName + '_生成日志.txt')) }
)

if ($RequireBom) {
    $expected += [pscustomobject]@{
        Kind = 'BOM'
        Required = $true
        Path = (Resolve-DeliveryPath $BomPath ($BaseName + '_BOM.xlsx'))
    }
}

if ($RequireDrawingPackage) {
    $drawing = Resolve-DeliveryPath $DrawingPath ($BaseName + '.SLDDRW')
    $editableCad = Resolve-DeliveryPath $EditableCadPath ($BaseName + '.DWG')
    $drawingPdf = Resolve-DeliveryPath $DrawingPdfPath ($BaseName + '.PDF')
    $drawingSheetPreview = Resolve-DeliveryPath $DrawingSheetPreviewPath ($BaseName + '_整张工程图.png')
    $topPreview = Resolve-DeliveryPath $TopPreviewPath ($BaseName + '_俯视.png')
    $sectionPreview = Resolve-DeliveryPath $SectionPreviewPath ($BaseName + '_A-A剖视.png')
    $viewAudit = Resolve-DeliveryPath $ViewAuditPath ($BaseName + '_视图规范审核.json')

    if ([System.IO.Path]::GetExtension($drawing).ToUpperInvariant() -ne '.SLDDRW') {
        throw 'DrawingPath 必须使用 .SLDDRW。'
    }
    if ([System.IO.Path]::GetExtension($editableCad).ToUpperInvariant() -notin '.DWG', '.DXF') {
        throw 'EditableCadPath 必须使用 .DWG 或 .DXF。'
    }
    if ([System.IO.Path]::GetExtension($drawingPdf).ToUpperInvariant() -ne '.PDF') {
        throw 'DrawingPdfPath 必须使用 .PDF。'
    }
    foreach ($pngPath in @($drawingSheetPreview, $topPreview, $sectionPreview)) {
        if ([System.IO.Path]::GetExtension($pngPath).ToUpperInvariant() -ne '.PNG') {
            throw "工程图图片必须使用 .PNG：$pngPath"
        }
    }
    if ([System.IO.Path]::GetExtension($viewAudit).ToUpperInvariant() -ne '.JSON') {
        throw 'ViewAuditPath 必须使用 .JSON。'
    }

    $expected += @(
        [pscustomobject]@{ Kind = 'NativeDrawing'; Required = $true; Path = $drawing },
        [pscustomobject]@{ Kind = 'EditableCAD'; Required = $true; Path = $editableCad },
        [pscustomobject]@{ Kind = 'DrawingPDF'; Required = $true; Path = $drawingPdf },
        [pscustomobject]@{ Kind = 'DrawingSheetPreview'; Required = $true; Path = $drawingSheetPreview },
        [pscustomobject]@{ Kind = 'TopPreview'; Required = $true; Path = $topPreview },
        [pscustomobject]@{ Kind = 'SectionPreview'; Required = $true; Path = $sectionPreview },
        [pscustomobject]@{ Kind = 'ViewStandardsAudit'; Required = $true; Path = $viewAudit }
    )
}

$checks = foreach ($item in $expected) {
    $exists = Test-Path -LiteralPath $item.Path -PathType Leaf
    $file = if ($exists) { Get-Item -LiteralPath $item.Path } else { $null }
    [pscustomobject]@{
        Kind = $item.Kind
        Required = $item.Required
        Path = $item.Path
        Exists = $exists
        SizeBytes = $(if ($file) { $file.Length } else { 0 })
        Sha256 = $(if ($file -and $file.Length -gt 0) { (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash } else { $null })
    }
}

$drawingPackageIssues = @()
$viewAuditDocument = $null
if ($RequireDrawingPackage) {
    $checkByKind = @{}
    foreach ($check in $checks) {
        $checkByKind[$check.Kind] = $check
    }

    foreach ($pngKind in @('IsometricPreview', 'FrontPreview', 'SidePreview', 'TopPreview', 'SectionPreview', 'DrawingSheetPreview')) {
        $pngCheck = $checkByKind[$pngKind]
        if ($pngCheck.Exists -and $pngCheck.SizeBytes -gt 0) {
            try {
                [void](Get-PngDimensions -Path $pngCheck.Path)
            }
            catch {
                $drawingPackageIssues += "$pngKind 不是有效 PNG：$($_.Exception.Message)"
            }
        }
    }

    $pdfCheck = $checkByKind['DrawingPDF']
    if ($pdfCheck.Exists -and $pdfCheck.SizeBytes -gt 0) {
        $pdfPrefix = Get-FilePrefixText -Path $pdfCheck.Path -Count 8
        if (-not $pdfPrefix.StartsWith('%PDF-')) {
            $drawingPackageIssues += 'DrawingPDF 文件签名无效。'
        }
    }

    $cadCheck = $checkByKind['EditableCAD']
    if ($cadCheck.Exists -and $cadCheck.SizeBytes -gt 0) {
        $cadPrefix = Get-FilePrefixText -Path $cadCheck.Path -Count 1024
        $cadExtension = [System.IO.Path]::GetExtension($cadCheck.Path).ToUpperInvariant()
        if ($cadExtension -eq '.DWG' -and $cadPrefix -notmatch '^AC10\d{2}') {
            $drawingPackageIssues += 'EditableCAD 的 DWG 文件签名无效。'
        }
        elseif ($cadExtension -eq '.DXF' -and $cadPrefix -notmatch 'SECTION|AutoCAD Binary DXF') {
            $drawingPackageIssues += 'EditableCAD 的 DXF 文件签名无效。'
        }
    }

    $viewAuditCheck = $checkByKind['ViewStandardsAudit']
    if ($viewAuditCheck.Exists -and $viewAuditCheck.SizeBytes -gt 0) {
        try {
            $viewAuditDocument = Get-Content -LiteralPath $viewAuditCheck.Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            $drawingPackageIssues += "视图规范审核 JSON 无法解析：$($_.Exception.Message)"
        }
    }

    if ($null -ne $viewAuditDocument) {
        foreach ($propertyName in @('standard_profile', 'sheet', 'appearance_profile', 'line_profile', 'views', 'cad_roundtrip', 'drawing_reopened', 'blocking_issues')) {
            if (-not (Test-JsonProperty -Object $viewAuditDocument -Name $propertyName)) {
                $drawingPackageIssues += "视图规范审核缺少字段：$propertyName"
            }
        }

        if ((Test-JsonProperty -Object $viewAuditDocument -Name 'drawing_reopened') -and $viewAuditDocument.drawing_reopened -ne $true) {
            $drawingPackageIssues += 'SLDDRW 未通过保存重开验证。'
        }
        if (Test-JsonProperty -Object $viewAuditDocument -Name 'blocking_issues') {
            $declaredBlockingIssues = @($viewAuditDocument.blocking_issues)
            if ($declaredBlockingIssues.Count -gt 0) {
                $drawingPackageIssues += "视图规范审核声明了 $($declaredBlockingIssues.Count) 个阻塞项。"
            }
        }

        if (Test-JsonProperty -Object $viewAuditDocument -Name 'appearance_profile') {
            $appearance = $viewAuditDocument.appearance_profile
            if (-not (Test-JsonProperty -Object $appearance -Name 'name') -or [string]::IsNullOrWhiteSpace([string]$appearance.name)) {
                $drawingPackageIssues += 'appearance_profile 缺少配色名称。'
            }
            foreach ($appearanceField in @('background_hex', 'edge_hex', 'adjacent_components_distinct')) {
                if (-not (Test-JsonProperty -Object $appearance -Name $appearanceField)) {
                    $drawingPackageIssues += "appearance_profile 缺少字段：$appearanceField"
                }
            }
            foreach ($hexField in @('background_hex', 'edge_hex')) {
                if ((Test-JsonProperty -Object $appearance -Name $hexField) -and [string]$appearance.$hexField -notmatch '^#[0-9A-Fa-f]{6}$') {
                    $drawingPackageIssues += "appearance_profile.$hexField 不是有效 HEX 颜色。"
                }
            }
            if ((Test-JsonProperty -Object $appearance -Name 'adjacent_components_distinct') -and $appearance.adjacent_components_distinct -ne $true) {
                $drawingPackageIssues += '相邻组件配色未通过区分性检查。'
            }
            if (-not (Test-JsonProperty -Object $appearance -Name 'component_colors') -or @($appearance.component_colors).Count -eq 0) {
                $drawingPackageIssues += 'appearance_profile 缺少组件颜色参数。'
            }
            else {
                $colorIndex = 0
                foreach ($componentColor in @($appearance.component_colors)) {
                    $colorIndex++
                    foreach ($colorField in @('component', 'hex', 'material_property_values')) {
                        if (-not (Test-JsonProperty -Object $componentColor -Name $colorField)) {
                            $drawingPackageIssues += "组件颜色 $colorIndex 缺少字段：$colorField"
                        }
                    }
                    if ((Test-JsonProperty -Object $componentColor -Name 'hex') -and [string]$componentColor.hex -notmatch '^#[0-9A-Fa-f]{6}$') {
                        $drawingPackageIssues += "组件颜色 $colorIndex 的 hex 无效。"
                    }
                    if (Test-JsonProperty -Object $componentColor -Name 'material_property_values') {
                        $materialValues = @($componentColor.material_property_values)
                        if ($materialValues.Count -ne 9) {
                            $drawingPackageIssues += "组件颜色 $colorIndex 的 material_property_values 必须有 9 个值。"
                        }
                        else {
                            foreach ($materialValue in $materialValues) {
                                if ([double]$materialValue -lt 0.0 -or [double]$materialValue -gt 1.0) {
                                    $drawingPackageIssues += "组件颜色 $colorIndex 的九参数数组存在 0–1 范围外数值。"
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }

        if (Test-JsonProperty -Object $viewAuditDocument -Name 'line_profile') {
            $expectedLineRoles = @{
                visible = 'continuous-thick'
                hidden = 'dashed-thin'
                center = 'chain-thin'
                dimension = 'continuous-thin'
                cutting = 'cutting-thick'
                hatch = 'continuous-thin'
            }
            foreach ($lineName in $expectedLineRoles.Keys) {
                if (-not (Test-JsonProperty -Object $viewAuditDocument.line_profile -Name $lineName) -or [string]::IsNullOrWhiteSpace([string]$viewAuditDocument.line_profile.$lineName)) {
                    $drawingPackageIssues += "line_profile 缺少字段：$lineName"
                }
                elseif ([string]$viewAuditDocument.line_profile.$lineName -ne $expectedLineRoles[$lineName]) {
                    $drawingPackageIssues += "line_profile.$lineName 必须为 $($expectedLineRoles[$lineName])。"
                }
            }
            foreach ($widthField in @('thin_width_mm', 'thick_width_mm')) {
                if (-not (Test-JsonProperty -Object $viewAuditDocument.line_profile -Name $widthField)) {
                    $drawingPackageIssues += "line_profile 缺少字段：$widthField"
                }
                elseif ([double]$viewAuditDocument.line_profile.$widthField -le 0) {
                    $drawingPackageIssues += "line_profile.$widthField 必须大于 0。"
                }
            }
            if ((Test-JsonProperty -Object $viewAuditDocument.line_profile -Name 'thin_width_mm') -and (Test-JsonProperty -Object $viewAuditDocument.line_profile -Name 'thick_width_mm') -and [double]$viewAuditDocument.line_profile.thick_width_mm -le [double]$viewAuditDocument.line_profile.thin_width_mm) {
                $drawingPackageIssues += '粗线宽必须大于细线宽。'
            }
        }

        $expectedViewImages = @{
            front = $checkByKind['FrontPreview'].Path
            side = $checkByKind['SidePreview'].Path
            top = $checkByKind['TopPreview'].Path
            isometric = $checkByKind['IsometricPreview'].Path
            section = $checkByKind['SectionPreview'].Path
        }
        $requiredViewIds = @('front', 'side', 'top', 'isometric', 'section')
        $views = if (Test-JsonProperty -Object $viewAuditDocument -Name 'views') { @($viewAuditDocument.views) } else { @() }
        foreach ($viewId in $requiredViewIds) {
            $matchingViews = @($views | Where-Object { (Test-JsonProperty -Object $_ -Name 'id') -and [string]$_.id -eq $viewId })
            if ($matchingViews.Count -ne 1) {
                $drawingPackageIssues += "视图 ID $viewId 的数量必须为 1，实际为 $($matchingViews.Count)。"
                continue
            }
            $view = $matchingViews[0]
            foreach ($viewProperty in @('scale', 'outline_mm', 'inside_printable_area', 'overlap_count', 'linework_verified', 'image_path', 'image_width_px', 'image_height_px')) {
                if (-not (Test-JsonProperty -Object $view -Name $viewProperty)) {
                    $drawingPackageIssues += "视图 $viewId 缺少字段：$viewProperty"
                }
            }
            if ((Test-JsonProperty -Object $view -Name 'inside_printable_area') -and $view.inside_printable_area -ne $true) {
                $drawingPackageIssues += "视图 $viewId 超出可打印区。"
            }
            if ((Test-JsonProperty -Object $view -Name 'overlap_count') -and [int]$view.overlap_count -ne 0) {
                $drawingPackageIssues += "视图 $viewId 存在重叠。"
            }
            if ((Test-JsonProperty -Object $view -Name 'linework_verified') -and $view.linework_verified -ne $true) {
                $drawingPackageIssues += "视图 $viewId 图线未通过审核。"
            }
            if ((Test-JsonProperty -Object $view -Name 'outline_mm') -and @($view.outline_mm).Count -ne 4) {
                $drawingPackageIssues += "视图 $viewId 的 outline_mm 必须包含 4 个数。"
            }
            if ((Test-JsonProperty -Object $view -Name 'image_path') -and -not [string]::IsNullOrWhiteSpace([string]$view.image_path)) {
                $auditImagePath = Resolve-DeliveryPath ([string]$view.image_path) ''
                if (-not $auditImagePath.Equals($expectedViewImages[$viewId], [System.StringComparison]::OrdinalIgnoreCase)) {
                    $drawingPackageIssues += "视图 $viewId 的 image_path 与交付路径不一致。"
                }
                elseif (Test-Path -LiteralPath $auditImagePath -PathType Leaf) {
                    try {
                        $dimensions = Get-PngDimensions -Path $auditImagePath
                        if ((Test-JsonProperty -Object $view -Name 'image_width_px') -and [int]$view.image_width_px -ne $dimensions.Width) {
                            $drawingPackageIssues += "视图 $viewId 的 image_width_px 与 PNG 不一致。"
                        }
                        if ((Test-JsonProperty -Object $view -Name 'image_height_px') -and [int]$view.image_height_px -ne $dimensions.Height) {
                            $drawingPackageIssues += "视图 $viewId 的 image_height_px 与 PNG 不一致。"
                        }
                    }
                    catch {
                        $drawingPackageIssues += "视图 $viewId PNG 检查失败：$($_.Exception.Message)"
                    }
                }
            }
        }

        if (Test-JsonProperty -Object $viewAuditDocument -Name 'cad_roundtrip') {
            foreach ($cadField in @('format', 'opened', 'layers_ok', 'views_editable', 'scale_ok')) {
                if (-not (Test-JsonProperty -Object $viewAuditDocument.cad_roundtrip -Name $cadField)) {
                    $drawingPackageIssues += "cad_roundtrip 缺少字段：$cadField"
                }
            }
            foreach ($cadBoolean in @('opened', 'layers_ok', 'views_editable', 'scale_ok')) {
                if ((Test-JsonProperty -Object $viewAuditDocument.cad_roundtrip -Name $cadBoolean) -and $viewAuditDocument.cad_roundtrip.$cadBoolean -ne $true) {
                    $drawingPackageIssues += "cad_roundtrip.$cadBoolean 未通过。"
                }
            }
        }

        if (Test-JsonProperty -Object $viewAuditDocument -Name 'sheet') {
            $sheet = $viewAuditDocument.sheet
            foreach ($sheetField in @('width_mm', 'height_mm', 'scale', 'projection', 'dpi', 'image_width_px', 'image_height_px', 'border_verified', 'title_block_verified', 'projection_symbol_verified')) {
                if (-not (Test-JsonProperty -Object $sheet -Name $sheetField)) {
                    $drawingPackageIssues += "sheet 缺少字段：$sheetField"
                }
            }
            foreach ($sheetBoolean in @('border_verified', 'title_block_verified', 'projection_symbol_verified')) {
                if ((Test-JsonProperty -Object $sheet -Name $sheetBoolean) -and $sheet.$sheetBoolean -ne $true) {
                    $drawingPackageIssues += "sheet.$sheetBoolean 未通过。"
                }
            }
            if ($checkByKind['DrawingSheetPreview'].Exists) {
                try {
                    $sheetDimensions = Get-PngDimensions -Path $checkByKind['DrawingSheetPreview'].Path
                    if ((Test-JsonProperty -Object $sheet -Name 'image_width_px') -and [int]$sheet.image_width_px -ne $sheetDimensions.Width) {
                        $drawingPackageIssues += 'sheet.image_width_px 与整张工程图 PNG 不一致。'
                    }
                    if ((Test-JsonProperty -Object $sheet -Name 'image_height_px') -and [int]$sheet.image_height_px -ne $sheetDimensions.Height) {
                        $drawingPackageIssues += 'sheet.image_height_px 与整张工程图 PNG 不一致。'
                    }
                    if ((Test-JsonProperty -Object $sheet -Name 'width_mm') -and (Test-JsonProperty -Object $sheet -Name 'height_mm') -and (Test-JsonProperty -Object $sheet -Name 'dpi')) {
                        $expectedWidth = [int][System.Math]::Round(([double]$sheet.width_mm / 25.4) * [double]$sheet.dpi)
                        $expectedHeight = [int][System.Math]::Round(([double]$sheet.height_mm / 25.4) * [double]$sheet.dpi)
                        $widthTolerance = [System.Math]::Max(2, [System.Math]::Round($expectedWidth * 0.01))
                        $heightTolerance = [System.Math]::Max(2, [System.Math]::Round($expectedHeight * 0.01))
                        if ([System.Math]::Abs($sheetDimensions.Width - $expectedWidth) -gt $widthTolerance -or [System.Math]::Abs($sheetDimensions.Height - $expectedHeight) -gt $heightTolerance) {
                            $drawingPackageIssues += '整张工程图 PNG 像素与纸张毫米/DPI 不一致。'
                        }
                    }
                }
                catch {
                    $drawingPackageIssues += "整张工程图 PNG 检查失败：$($_.Exception.Message)"
                }
            }
        }
    }
}

$missing = @($checks | Where-Object { $_.Required -and (-not $_.Exists -or $_.SizeBytes -le 0) })
$drawingPackageKinds = @('NativeDrawing', 'EditableCAD', 'DrawingPDF', 'DrawingSheetPreview', 'TopPreview', 'SectionPreview', 'ViewStandardsAudit')
$missingDrawingPackage = @($missing | Where-Object { $drawingPackageKinds -contains $_.Kind })
$modelExtensions = @('.SLDPRT', '.SLDASM', '.SLDDRW', '.STEP', '.STP')
$outsideModels = @()
if ($resolvedProjectRoot) {
    $outsideModels = @(
        Get-ChildItem -LiteralPath $resolvedProjectRoot -Recurse -File |
            Where-Object {
                $modelExtensions -contains $_.Extension.ToUpperInvariant() -and
                -not (Test-PathWithinRoot -Candidate $_.FullName -Root $resolvedOutput)
            } |
            Sort-Object FullName |
            ForEach-Object {
                [pscustomobject]@{
                    Path = [System.IO.Path]::GetFullPath($_.FullName)
                    SizeBytes = $_.Length
                    Sha256 = $(if ($_.Length -gt 0) { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } else { $null })
                }
            }
    )
}

$hygieneFailed = $RequireNoModelsOutsideOutput -and $outsideModels.Count -gt 0
$drawingPackageFailed = $RequireDrawingPackage -and ($drawingPackageIssues.Count -gt 0 -or $missingDrawingPackage.Count -gt 0)
$blockingReasons = @()
if ($missing.Count -gt 0) {
    $blockingReasons += '缺少一个或多个必需交付文件。'
}
if ($hygieneFailed) {
    $blockingReasons += "最终目录外仍有 $($outsideModels.Count) 个 SolidWorks/STEP 模型文件。"
}
if ($drawingPackageFailed) {
    $blockingReasons += "工程图交付包缺少 $($missingDrawingPackage.Count) 个文件，并有 $($drawingPackageIssues.Count) 个规范审核问题。"
}
$result = [pscustomobject]@{
    Ready = ($missing.Count -eq 0 -and -not $hygieneFailed -and -not $drawingPackageFailed)
    OutputDirectory = $resolvedOutput
    BaseName = $BaseName
    DocumentType = $DocumentType
    Checks = @($checks)
    MissingRequired = @($missing)
    ModelSetHygiene = [pscustomobject]@{
        Required = [bool]$RequireNoModelsOutsideOutput
        ProjectRoot = $resolvedProjectRoot
        AllowedModelDirectory = $resolvedOutput
        ModelExtensions = @($modelExtensions)
        OutsideModelCount = $outsideModels.Count
        OutsideModels = @($outsideModels)
    }
    DrawingPackageAudit = [pscustomobject]@{
        Required = [bool]$RequireDrawingPackage
        Ready = (-not $RequireDrawingPackage -or ($drawingPackageIssues.Count -eq 0 -and $missingDrawingPackage.Count -eq 0))
        AuditPath = $(if ($RequireDrawingPackage) { $checkByKind['ViewStandardsAudit'].Path } else { $null })
        RequiredViewIds = @('front', 'side', 'top', 'isometric', 'section')
        MissingFiles = @($missingDrawingPackage)
        Issues = @($drawingPackageIssues)
    }
    BlockingReasons = @($blockingReasons)
    CheckedAt = (Get-Date).ToString('o')
}

if ($WriteManifest) {
    $manifestPath = Join-Path $resolvedOutput 'delivery_manifest.json'
    $hashPath = Join-Path $resolvedOutput 'SHA256.txt'
    foreach ($target in @($manifestPath, $hashPath)) {
        if ((Test-Path -LiteralPath $target) -and -not $Force) {
            throw "目标已存在；如确认覆盖清单文件，请加 -Force：$target"
        }
    }

    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $hashLines = $checks |
        Where-Object { $_.Sha256 } |
        ForEach-Object { $_.Sha256 + '  ' + [System.IO.Path]::GetFileName($_.Path) }
    $hashLines | Set-Content -LiteralPath $hashPath -Encoding UTF8
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 12
}
else {
    $result
}
