# True Nukes Refreshed

The port of the True Nukes mods to Factorio 2.1, and the scripts that check it. Its terms for
tooling are grado-factorio-tools' (`vendor/grado-factorio-tools/GLOSSARY.md`), which are
realistic-fusion-refreshed's: a term defined there means the same here, and this page adds only
what this repository needs. It differs from it in two places. **Check** is narrower here: a test
is not a check, though a check may run one. **Probe** is left undefined: there a probe asserts
nothing, while this repository's probes pass or fail (#87).

## Language

### Checks and tests

**Check**:
A script that asserts an invariant of the mods or of the repository. It is a gate: it passes or
fails, and a failure blocks. `load-check.ps1` is one, and so is `asset-paths.ps1`, though it is
filed under `scripts/tests/`.
_Avoid_: test, for a check

**Test**:
A script whose subject is another script, which it runs or whose functions it calls, asserting what
that script does. A script that only reads other scripts, or runs fixtures as its own self-test, is
a check; `freeze-time-cleanup.ps1` and `harness-lib.ps1` are tests.
_Avoid_: check, for a test

**Assertion**:
One thing a check or a test asserts, passing or failing on its own within the run. Named apart
because "check" means the whole script.
_Avoid_: check, for one assertion

### Pin moves

**Form**:
One entry of the forms file, `scripts/pin-forms.psd1`: a script and its arguments, which
`pin-measure.ps1` runs at both pins of a pin move.
_Avoid_: case or measurement, for a form
