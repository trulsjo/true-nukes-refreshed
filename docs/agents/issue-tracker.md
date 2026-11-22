> **Re-running `/setup-matt-pocock-skills` rewrites this stub page in place** and drops its links
> to the shared pages below: restore them from git.

# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

**The conventions shared with the siblings are on
[`tracker-conventions.md`](../../vendor/grado-factorio-tools/docs/tracker-conventions.md)**, in
the tools submodule at its pin
([on GitHub](https://github.com/trulsjo/grado-factorio-tools/blob/main/docs/tracker-conventions.md),
whose `main` may be ahead of the pin): reading an issue with `--json`, multi-line bodies through
`--body-file`, searching before filing, blocked-by, closing, and the bar for a follow-up ticket.
Read it before filing, blocking or closing an issue. What a pull request's body holds is on
[`pr-body-convention.md`](../../vendor/grado-factorio-tools/docs/pr-body-convention.md)
([on GitHub](https://github.com/trulsjo/grado-factorio-tools/blob/main/docs/pr-body-convention.md)),
and what a ticket's evidence holds on
[`claim-grades.md`](../../vendor/grado-factorio-tools/docs/claim-grades.md)'s *Tickets and ruling
comments* ([on GitHub](https://github.com/trulsjo/grado-factorio-tools/blob/main/docs/claim-grades.md)),
both in the same submodule. This page holds the setup template's core and this repository's own
parts (#74).

## Conventions

- **Create an issue**: `gh issue create --title "..." --body-file <path>`, the file written with
  the Write tool, after searching the open issues as the shared page says. **The other tracker to
  search is `trulsjo/grado-factorio-tools`**, for a ticket about a shared script or page, with the
  same command and `-R trulsjo/grado-factorio-tools`.
- **Blocking between issues**: set each edge as the shared page's *Blocked by* says, as the
  tickets are created. **Run the POST with the Bash tool**: a `Bash(...)` rule in the tracked
  `.claude/settings.json` allows it there, for a ticket of this repository,
  `grado-factorio-modpack`, `grado-factorio-tools` or `realistic-fusion-refreshed`.
- **Pull request body**: the shared page's four rules, with no switch turned on here, and above
  the template's headings one `Closes #<n>` line for each ticket the branch resolves. Where its
  evidence quotes a scratch run, the paragraph of [`checks.md`](checks.md) that begins
  "A scratch run quoted as evidence", with its list, says what the body gives, whether or not
  the change touches a check. The shared
  `refuse-pr-body.ps1`, a hook in `.claude/settings.json` (#71), refuses a `gh pr create` or
  `gh pr edit` with an inline body, a create with no body file, and one whose body file fails
  `pr-body-check.ps1`; and a `gh pr comment`, `gh issue create` or `gh issue comment` whose body
  file names no file or fails `markdown-check.ps1 -Body`, where an inline body is let through. Its
  header lists each case.
  `.github/workflows/body.yml` checks the body of each pull request again, and again when it is
  edited (#73).
- **Read an issue**, not with `--comments`, for the shared page's reason:

  ```sh
  gh issue view <number> --json "title,body,labels,comments" --jq '{title, body, labels: [.labels[].name], comments: [.comments[].body]}'
  ```

- **Read a pull request**, and `gh pr diff <number>` for the diff:

  ```sh
  gh pr view <number> --json "title,body,comments" --jq '{title, body, comments: [.comments[].body]}'
  ```

- **List issues**, with appropriate `--label` and `--state` filters, and `--limit`, since `gh`
  fetches 30 without it, as the shared page's *Search the open issues before filing* says:

  ```sh
  gh issue list --state open --limit 500 --json "number,title,body,labels,comments" --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'
  ```

- **Comment on an issue**: `gh issue comment <number> --body "..."`, or `--body-file <path>` for
  more than one line.
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`, after the shared page's *Before closing*.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature
requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr`
equivalents:

- **Read a PR**: the **Read a pull request** command under Conventions.
- **List external PRs for triage**, then keep only `authorAssociation` of `CONTRIBUTOR`,
  `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`):

  ```sh
  gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments
  ```
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`,
  `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with
`gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue, after the shared page's *Search the open issues before filing*. A ticket's
evidence follows `claim-grades.md`'s *Tickets and ruling comments*.

## When a skill says "fetch the relevant ticket"

Run the **Read an issue** command under Conventions.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body.
  `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues
  endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put
  `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>`
  (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving
  dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation,
  added with the child's `## Blocked by` section kept in step, as the shared page's *Blocked by*
  says. GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate).
  Where dependencies aren't available, the section alone records the edges. A ticket is unblocked
  when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the
  map's sub-issues / task list), drop any with an open blocker
  (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `## Blocked by` section) or
  an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body-file <path>` with the answer, then
  `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
