# True Nukes Refreshed

The port of the True Nukes mods to Factorio 2.1, and the scripts that check it. Its terms for
tooling are grado-factorio-tools' (`vendor/grado-factorio-tools/GLOSSARY.md`), which are
realistic-fusion-refreshed's: a term defined there means the same here, and this page adds only
what this repository needs. The one exception is **probe**: there a probe asserts nothing, while
this repository's probes pass or fail, so the word is left undefined here until that is settled.

## Language

### Checks and tests

**Check**:
A script that asserts an invariant of the mods or of the repository. It is a gate: it passes or
fails, and a failure blocks. `load-check.ps1` is one, and so is `asset-paths.ps1`, though it is
filed under `scripts/tests/`.
_Avoid_: test, for a check

**Test**:
A script whose subject is another script: it runs that script and asserts what it does.
`freeze-time-cleanup.ps1` tests `freeze-time.ps1`. A test is not a check, though a check may run it
as a gate, as `load-check.ps1` runs `harness-lib.ps1`. A tools script's own `-SelfTest` is its
self-test, not a test here.
_Avoid_: check, for a test

**Assertion**:
One thing a check or a test asserts, passing or failing on its own within the run: in a test here,
one call to its `Check` function. Named apart because "check" means the whole script.
_Avoid_: check, for one assertion

### Pin moves

**Form**:
One way of running a script that `pin-measure.ps1` runs at both pins of a pin move: the script,
where it is found, and its arguments, as one entry of the forms file, `scripts/pin-forms.psd1`.
_Avoid_: case, measurement
