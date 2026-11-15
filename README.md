# Free Guild

Guild roster for leaders and officers: select many members, give them a rank, and level rules (15-29 -> Member...), group invites and raid rosters with attendance. /fg

Part of the **Free** addon suite for WoW Forever, by DecardCain.

## Releasing

1. Bump `## Version` in `FreeGuild.toc` and commit.
2. Push a tag with the same version: `git tag v<version> && git push --tags`.
3. GitHub Actions packages the addon with the BigWigs packager and uploads it to CurseForge (secret `CF_API_KEY`) and to the GitHub releases.
