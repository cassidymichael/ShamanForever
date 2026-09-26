# Branches and releasing

`main` holds only work that has been tested in game, so anything tagged from it is safe to release.

- Work that changes the addon goes on a short-lived branch named for it (`shield-split`), one commit
  per change, each saying what it does. The branch is pushed as a backup, and CI lints it.
- It is tested in game from the branch, then merged into `main` keeping its commits
  (`git merge --ff-only`, or `--no-ff` for a larger piece of work). The branch is then deleted.
- Changes that don't touch what players get (docs, CI, repo files) can go straight to `main`.
- A pull request only when a written record of a larger change helps; not for every change.

## Releasing

1. Merge the tested work into `main` as above.
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

`.github/workflows/lint.yml` runs luacheck on every push, on any branch; a release comes from a
commit where it passes.
