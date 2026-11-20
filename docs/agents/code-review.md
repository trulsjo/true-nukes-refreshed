# Code review — this repository's values

**The procedure is
[`code-review-procedure.md`](../../vendor/grado-factorio-tools/docs/code-review-procedure.md), and
the shared rules
[`code-review-rules.md`](../../vendor/grado-factorio-tools/docs/code-review-rules.md)**, both in
the tools submodule at its pin (on GitHub,
[the procedure](https://github.com/trulsjo/grado-factorio-tools/blob/main/docs/code-review-procedure.md)
and [the rules](https://github.com/trulsjo/grado-factorio-tools/blob/main/docs/code-review-rules.md),
whose `main` may be ahead of the pin). Read both before running a review. This page gives this
repository's values for the procedure's parameters, and its threshold (#74).

## The threshold

**`blocking`**: a finding a reviewer grades `blocking` is fixed before the merge. Every other
finding is reported with its grade, and Truls chooses which of them are fixed, as the rules page's
*The threshold sorts the comment, not the report* says.

## The review panel

Reviews here are run by the review panel, through the `review-panel` skill, when Truls asks for
one. Its parameters are in [`review-panel.md`](review-panel.md): the prefix `tn`, and for each
agent its command, with the model, and its clear command. The panel's answers grade each finding
`blocking`, `should-fix` or `nit`, the grade the threshold above reads.

## The procedure's parameters

| Parameter | Value here |
|---|---|
| When | on the pull request |
| Second pass | none |
| Trigger page | this page |
| Where recorded | one combined review comment on the pull request, with each finding's outcome |
| Merge workflow | `.github/workflows/check.yml` |

Not set here, and Truls's to set: the brief template, the reviewer's copy, further reading, the
check run, raw output and test claims, and the steps the procedure leaves to each repository.
Until he does, the `review-panel` skill's own brief and worktrees stand for the first two.
