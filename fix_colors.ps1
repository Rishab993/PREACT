$files = @(
  'lib\features\dashboard\dashboard_screen.dart',
  'lib\features\ground_truth\ground_truth_screen.dart',
  'lib\shared\widgets\alert_card.dart',
  'lib\shared\widgets\app_toggles.dart',
  'lib\features\assistant\voice_assistant_overlay.dart',
  'lib\shared\widgets\glass_card.dart',
  'lib\shared\widgets\officer_card.dart'
)
foreach ($f in $files) {
  $content = Get-Content $f -Raw
  $fixed = $content -replace 'AppColors\.neonBlue', 'const Color(0xFF2563EB)'
  Set-Content $f $fixed
  Write-Host "Fixed: $f"
}
Write-Host "All color replacements done."
