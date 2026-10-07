param([string]$InputPath = 'logs/long-text-results-noto.json')
$ErrorActionPreference = 'Stop'
$Data = Get-Content -Raw -LiteralPath $InputPath | ConvertFrom-Json
if (-not $Data.complete -or $Data.results.Count -ne 144 -or $Data.errors.Count -ne 0 -or $Data.loadedFontBytes -le 0) {
    throw 'Incomplete, errored, or font-unverified run; no valid comparison can be exported.'
}
function Percentile($Values, [double]$P) {
    $Sorted = @($Values | Sort-Object)
    if ($Sorted.Count -eq 0) { return $null }
    return [math]::Round($Sorted[[math]::Ceiling($Sorted.Count * $P) - 1] / 1000, 3)
}
$Rows = foreach ($Case in $Data.results) {
    foreach ($Sample in $Case.samples) {
        $BuildUs = ($Sample.frames.buildUs | Measure-Object -Sum).Sum
        $RasterUs = ($Sample.frames.rasterUs | Measure-Object -Maximum).Maximum
        [pscustomobject]@{
            Editor = $Case.editor
            Length = $Case.lengthUtf16
            Shape = $Case.shape
            Width = $Case.width
            Operation = $Case.operation
            Action = $Sample.action
            Round = $Case.round
            Frames = $Sample.frames.Count
            UpdateUs = $Sample.updateUs
            UiWorkUs = $Sample.updateUs + $BuildUs
            BuildUs = $BuildUs
            RasterUs = $RasterUs
            ThroughFrameUs = $Sample.throughFrameUs
        }
    }
}
Write-Host "Complete=$($Data.complete) Cases=$($Data.results.Count) Samples=$($Rows.Count) Errors=$($Data.errors.Count)"
Write-Host "Samples without matched frames: $(@($Rows | Where-Object Frames -eq 0).Count)"
Write-Host "Content checksum mismatches: $(@($Data.results | Where-Object { $_.sourceChecksum -ne $_.finalChecksum }).Count)"
if ($Rows.Count -ne 2880 -or @($Rows | Where-Object Frames -ne 1).Count -ne 0 -or @($Data.results | Where-Object { $_.sourceChecksum -ne $_.finalChecksum }).Count -ne 0) {
    throw 'Invalid sample count, frame matching, or text integrity.'
}
$Summary = $Rows | Group-Object Editor,Length,Shape,Width,Operation,Action | ForEach-Object {
    $First = $_.Group[0]
    [pscustomobject]@{
        Editor = $First.Editor
        Length = $First.Length
        Shape = $First.Shape
        Width = $First.Width
        Operation = $First.Operation
        Action = $First.Action
        Samples = $_.Count
        UiP50Ms = Percentile $_.Group.UiWorkUs 0.5
        UiP95Ms = Percentile $_.Group.UiWorkUs 0.95
        BuildP95Ms = Percentile $_.Group.BuildUs 0.95
        UpdateP95Ms = Percentile $_.Group.UpdateUs 0.95
        RasterP95Ms = Percentile $_.Group.RasterUs 0.95
        ThroughFrameP95Ms = Percentile $_.Group.ThroughFrameUs 0.95
    }
}
$Output = [IO.Path]::ChangeExtension($InputPath, '.csv')
$Summary | Export-Csv -NoTypeInformation -Encoding utf8 -LiteralPath $Output
$Summary | Where-Object { $_.Width -eq 720 -and $_.Action -eq 'insert' -and $_.Operation -eq 'middle' } | Format-Table -AutoSize
Write-Host "Summary: $Output"
