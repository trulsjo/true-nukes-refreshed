# Fixture for strict-lists.ps1, never run: .Id and .Name reads, which throw off $null and off an
# empty array alike, so @() does not make them safe. Lines to flag end in "expect: flag".
Set-StrictMode -Version Latest
function Get-None { }

(Get-None).Name                                     # expect: flag
@(Get-None).Name                                    # expect: flag
@(Get-None).Id                                      # expect: flag
$wrapped = @(Get-None)
$wrapped.Name                                       # expect: flag
$wrapped.Count
$bare = Get-None
$bare.Id                                            # expect: flag
$first, $rest = @(Get-None)
$rest.Count                                         # expect: flag

# The fix: ForEach-Object gives nothing for nothing.
$names = @(Get-None | ForEach-Object Name)
$names.Count

# A command that always outputs exactly one object, marked.
$proc = Start-Process pwsh -PassThru -NoNewWindow `
    -RedirectStandardOutput nul  # strict-lists: one
$proc.Id
(Get-Item .).Name  # strict-lists: one
