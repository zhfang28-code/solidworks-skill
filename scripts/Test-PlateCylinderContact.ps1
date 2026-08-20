[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0.000001, [double]::MaxValue)]
    [double]$CylinderDiameterMm,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0.000001, [double]::MaxValue)]
    [double]$PlateThicknessMm,

    [ValidateSet('FlatTangent', 'CylindricalSeat')]
    [string]$ContactType = 'FlatTangent',

    [ValidateRange(0.0, [double]::MaxValue)]
    [double]$ToleranceMm = 0.01,

    [switch]$FailOnGap,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$radius = $CylinderDiameterMm / 2.0
$halfThickness = $PlateThicknessMm / 2.0
if ($halfThickness -gt $radius) {
    throw 'PlateThicknessMm 不能大于 CylinderDiameterMm；板边已超出圆筒投影范围。'
}

$cylinderHeightAtPlateEdge = [Math]::Sqrt(
    ($radius * $radius) - ($halfThickness * $halfThickness)
)
$flatTangentEdgeGap = $radius - $cylinderHeightAtPlateEdge
$designEdgeGap = if ($ContactType -eq 'CylindricalSeat') { 0.0 } else { $flatTangentEdgeGap }
$withinTolerance = $designEdgeGap -le $ToleranceMm

$result = [pscustomobject]@{
    CylinderDiameterMm = $CylinderDiameterMm
    CylinderRadiusMm = $radius
    PlateThicknessMm = $PlateThicknessMm
    ContactType = $ContactType
    CylinderHeightAtPlateEdgeMm = $cylinderHeightAtPlateEdge
    FlatTangentEdgeGapMm = $flatTangentEdgeGap
    DesignEdgeGapMm = $designEdgeGap
    ToleranceMm = $ToleranceMm
    WithinTolerance = $withinTolerance
    FullSurfaceContactByConstruction = ($ContactType -eq 'CylindricalSeat')
    RecommendedSeatDiameterMm = $CylinderDiameterMm
    Recommendation = if ($withinTolerance) {
        '名义缝隙在给定容差内；仍需检查完整接触范围和制造要求。'
    }
    else {
        '平面顶点相切会在板边产生缝隙；使用与圆筒同轴、同直径的鞍形圆柱面。'
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 4
}
else {
    $result
}

if ($FailOnGap -and -not $withinTolerance) {
    throw ('接触缝隙 {0:F6} mm 超过容差 {1:F6} mm。' -f $designEdgeGap, $ToleranceMm)
}
