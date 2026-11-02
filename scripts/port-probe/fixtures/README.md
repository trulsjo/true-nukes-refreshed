# Port probe fixtures

`tn-continued-fixture.zip` is a save made on **Factorio 2.0.77 with True Nukes Continued 0.3.36**,
base game. The `fixture` and `fixturesite` probes in `scripts/port-probe.ps1` load it with
`--test-save` to check that a Continued save keeps working on the port (#22), against the values
measured on it under #13.

SHA-256: `98ec59f472c85d11989a7a0152e678cc99de990e7482e9fdae14f626ac80cc28`.
`scripts/port-probe.ps1` refuses to run those probes if the file no longer matches. Do not resave it:
the game is given a copy.
