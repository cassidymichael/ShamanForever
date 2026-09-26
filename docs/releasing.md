# Releasing

1. Commit the changes themselves first, as ordinary commits (one per change, each saying what it does).
2. Add an entry at the top of `CHANGELOG.md`, headed `## X.Y.Z (YYYY-MM-DD)`, listing what players
   will notice. Commit it on its own as `Release X.Y.Z`.
3. Tag and push: `git tag -a vX.Y.Z -m "ShamanForever X.Y.Z" && git push origin main vX.Y.Z`

The tag push runs `.github/workflows/release.yml`:

- It cuts that version's section out of `CHANGELOG.md` into `RELEASE_NOTES.md`, the release notes on
  GitHub, CurseForge and Wago, and stops if there is none.
- The BigWigs packager builds the zip (files listed under `ignore` in `.pkgmeta`, and dotfiles, are
  left out), creates the GitHub release and uploads to CurseForge (project 1706929) and Wago (project
  rN4rkrKD), using the `CF_API_KEY` and `WAGO_API_TOKEN` repo secrets. CurseForge's own "Automatic
  Packaging" must stay disabled on the project, or each tag produces two files. The version in the
  TOC comes from the tag.
- It posts the notes to the Discord server's #announcements through the webhook in the
  `DISCORD_WEBHOOK_URL` secret (plain `vX.Y.Z` tags only). A failed post only warns: post it by hand.

`.github/workflows/lint.yml` runs luacheck on every push to main; a release should come from a
commit where it passes.
