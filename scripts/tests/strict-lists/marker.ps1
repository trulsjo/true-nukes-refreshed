# Fixture for strict-lists.ps1, never run: the "strict-lists: one" marker covers only the
# statement it directly follows. Lines to flag end in "expect: flag".
Set-StrictMode -Version Latest
function Get-None { }

# The marker follows the second statement on the line, not the first.
$u = Get-None; $v = Start-Process pwsh -PassThru  # strict-lists: one
$u.Count                                            # expect: flag
$v.Id

# A ; between the statement and the marker is fine.
$semi = Get-Item .;  # strict-lists: one
$semi.Name

# The marker text in a string is not a comment.
$w = Get-None "# strict-lists: one"
$w.Count                                            # expect: flag

# A marker on a statement nested inside does not cover the outer assignment.
$outer = foreach ($i in 1..2) {
    $p = Start-Process pwsh -PassThru  # strict-lists: one
}
$outer.Count                                        # expect: flag

# An inline read inside ( ), a call or a condition is covered by the marker after its statement.
if ((Get-Item .).Name -eq 'x') { }  # strict-lists: one
Join-Path ((Get-Item .).Name) 'x'  # strict-lists: one

# A string's marker covers its one unsafe read, but neither of two, and not a statement inside.
"$((Get-Item .).Name)"  # strict-lists: one
"$((Get-None).Count) and $((Get-Item .).Name)"  # strict-lists: one  # expect: flag
"$($inString = Get-None)"  # strict-lists: one
$inString.Count                                     # expect: flag
