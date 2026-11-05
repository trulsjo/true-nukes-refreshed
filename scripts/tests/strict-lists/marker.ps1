# Fixture for strict-lists.ps1, never run: the "strict-lists: one" marker covers only the
# statement it directly follows. Lines to flag end in "expect: flag".
Set-StrictMode -Version Latest
function Get-None { }

# The marker follows the second statement on the line, not the first.
$u = Get-None; $v = Start-Process pwsh -PassThru  # strict-lists: one
$u.Count                                            # expect: flag
$v.Id

# The marker text in a string is not a comment.
$w = Get-None "# strict-lists: one"
$w.Count                                            # expect: flag

# A marker on a statement nested inside does not cover the outer assignment.
$outer = foreach ($i in 1..2) {
    $p = Start-Process pwsh -PassThru  # strict-lists: one
}
$outer.Count                                        # expect: flag
