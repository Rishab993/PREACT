$results = Get-ChildItem lib -Recurse -Filter *.dart | Select-String 'AppColors\.neonBlue'
$filtered = $results | Where-Object { $_.Filename -notin @('colors.dart','app_theme.dart') }
if ($filtered.Count -eq 0) {
  Write-Host "CLEAN: No remaining AppColors.neonBlue in UI files."
} else {
  $filtered | ForEach-Object { Write-Host "$($_.Filename):$($_.LineNumber): $($_.Line.Trim())" }
}
