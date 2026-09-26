# Releasing

1. Add an entry at the top of `CHANGELOG.md`, headed `## X.Y.Z (YYYY-MM-DD)`, and commit.
2. `git tag -a vX.Y.Z -m "X.Y.Z" && git push origin main vX.Y.Z`

The tag push runs `.github/workflows/release.yml`. It first cuts that version's section out of `CHANGELOG.md` into `RELEASE_NOTES.md`, the release notes on GitHub, CurseForge and Wago, and stops if there is none. Then the BigWigs packager builds the zip (files listed under `ignore` in `.pkgmeta` are left out), creates the GitHub release and uploads to CurseForge (project 1706929) and Wago (project rN4rkrKD), using the `CF_API_KEY` and `WAGO_API_TOKEN` repo secrets. CurseForge's own "Automatic Packaging" must stay disabled on the project, or each tag produces two files. The version in the TOC comes from the tag.
