# Fixture for strict-lists.ps1, never run: no Set-StrictMode, so nothing here is checked.
function Get-None { }
$bare = Get-None
$bare.Count
