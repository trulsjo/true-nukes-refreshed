# Fixture for strict-lists.ps1, never run: .Count reads. Each line strict-lists.ps1 must flag ends
# in "expect: flag"; every other read must pass.
Set-StrictMode -Version Latest
function Get-None { }

$bare = Get-None
$bare.Count                                         # expect: flag
(Get-None | Where-Object { $_ }).Count              # expect: flag
"$((Get-None).Count)"                               # expect: flag
$(Get-None).Count                                   # expect: flag
((Get-None)).Count                                  # expect: flag
([array](Get-None)).Count                           # expect: flag

$wrapped = @(Get-None)
$wrapped.Count
@(Get-None).Count

# A type constraint or cast does not wrap: an empty result stays $null.
[string[]] $typed = Get-None
$typed.Count                                        # expect: flag
$cast = [array](Get-None)
$cast.Count                                         # expect: flag
$paren = (Get-None)
$paren.Count                                        # expect: flag
$sub = $(Get-None)
$sub.Count                                          # expect: flag

# Rewrapped before the read.
$re = Get-None
$re = @($re)
$re.Count

# += keeps the state the variable had.
$grown = Get-None
$grown += 1
$grown.Count                                        # expect: flag
$list = @()
$list += Get-None
$list.Count

# Several variables from one command; a later plain value clears them.
$first, $rest = Get-None
$rest.Count                                         # expect: flag
$one, $two = Get-None
$one, $two = 1, 2
$one.Count

# A statement used as a value is unrolled, even with @() in every branch.
$loop = foreach ($i in 1..2) { $i }
$loop.Count                                         # expect: flag
$branch = if ($true) { @() } else { @(1) }
$branch.Count                                       # expect: flag
# Known false hit: each branch emits an array as one object.
$whole = if ($true) { , @(1) } else { , @(2) }
$whole.Count                                        # expect: flag

# Round a loop: the bare assignment reaches the read on the next pass.
$carried = @()
foreach ($i in 1..2) {
    $carried.Count                                  # expect: flag
    $carried = Get-None
}
# Unless an assignment earlier in the same loop comes first.
foreach ($i in 1..2) {
    $fresh = @(Get-None)
    $fresh.Count
    $fresh = Get-None
}

$literal = 1..3
$literal.Count
$wrapped | ForEach-Object { $_.Count }

function Get-Inner {
    $bare.Count                                     # no assignment in this function: not followed
    $inner = Get-None
    $inner.Count                                    # expect: flag
}

# Known miss: an assignment inside the read.
($inline = Get-None).Count
