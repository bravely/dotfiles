# Branch naming

When creating a git branch for new work, choose the name by how the work was framed:

- **Work tied to an issue** (you referenced an issue number, or I'm acting on a tracker issue): name the branch `<issue-number>-<kebab-case-issue-title>`, e.g. issue #42 "Add CSV export" → `42-add-csv-export`. Fetch the real title first (e.g. `gh issue view <n>`) rather than guessing it.
- **Work requested directly** (no issue in play): use a short "good enough" kebab-case descriptor of the change, e.g. `fix-csv-quoting`.
- **When unsure of a good name** (ambiguous scope, multiple plausible descriptors, or the work doesn't reduce to one clear phrase): stop and ask me for the branch name before creating it.
