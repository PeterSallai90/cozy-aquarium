# Cozy Aquarium – rules for AI contributors

## Product
Cozy 3D aquarium builder for PC. Mode 1 (cozy builder) only. Mode 2 (simulation) is future work:
never implement it, but keep its catalog fields intact. Read docs/vision.md and docs/glossary.md.
Mode 2 is called "simulation mode" in the docs; "survival mode" refers to the same mode; the final
name is decided later. Treat both names as Mode 2.

## Tech
- Godot 4.7.2, standard build, GDScript only, Forward+ renderer.
- gdtoolkit 4.5.0 (gdformat, gdlint); same version in .pre-commit-config.yaml and ci.yml.
- Static typing everywhere: typed variables, parameters and return values. No untyped `var x = ...`
  unless the type is inferred with `:=`.
- Project root is /game. Run Godot as `godot_console --headless --path game`.

## Architecture rules
- The aquarium model (game/model) is pure data. No Node references in it.
- Every change to the model goes through a Command with do() and undo().
- Systems communicate through model signals or the EventBus autoload, never by direct reference.
- Catalog data lives in game/catalog as .tres resources. Never hard-code species or item data.
- Every visible string uses tr()/tr_n() with a key; add the key to en.po AND hu.po.
- Text files are UTF-8, LF line endings.

## Assets
- Art style rules (shading, triangle budgets, colouring, rendering and look, quality bar) live in
  docs/art-style.md. Follow them for every asset and shader.
- Generate assets with tools/blender scripts where possible.
- Any third-party asset needs a row in docs/asset-licenses.md in the same PR.

## Workflow
- One issue = one branch = one pull request. Branch name: <issue-number>-<short-slug>.
- Feature branches start from develop; pull requests target develop.
- Read the issue's acceptance criteria first; ask in the issue if anything is unclear.
- Write or update GdUnit4 tests for every acceptance criterion that can be tested automatically.
- Before opening a PR run: gdformat --check, gdlint, and the full test suite headless.
- A PR is opened only after the code-reviewer agent approved the current HEAD commit; a hook blocks
  `gh pr create` otherwise.
- PR description: link the issue ("Closes #N"), list what changed, how to playtest, known limits.
- After creating a pull request into develop, always enable auto-merge:
  `gh pr merge --auto --squash`. The owner gate blocks the merge when the owner is needed.
- Never commit to main. Never change CLAUDE.md, CI workflows or the Godot version without an issue
  that explicitly asks for it.
- Agents never add the `owner-approved` label, never merge into main and never change rulesets or
  repository settings. A release pull request from develop to main is opened only when the owner
  asks for it; the owner merges it.

## Orchestrator
The main Claude Code session is the orchestrator: the owner's only conversation partner. It runs
the flows below, delegates the work to the agents in .claude/agents and does not do their work
itself.

### Rules
- One issue at a time; no parallel development.
- Never choose or override models: the agent files fix them. Never pass a model when delegating.
- Each agent starts with a fresh context: give it the issue number, the branch and what it needs
  from earlier steps.
- Report to the owner when an issue starts, when a pull request merges, the BA decision digest,
  and anything that needs the owner.

### Delegation map
| Role | Agent |
| --- | --- |
| User story, player value, scope, acceptance criteria | product-ba |
| Aquarium realism, species data, Mode 2 impact | domain-ba |
| Questions, gaps, contradictions, Definition of Ready | requirements-reviewer |
| Technical plan, ADRs, architecture drift check | architect |
| Tests before implementation, test runs, playtest, test report, bug issues | tester |
| Implementation and fixes | developer |
| Independent review and approval before any PR | code-reviewer |
| Issues, labels, fields, statuses, links | board-keeper |

### Requirements flow
1. An idea or bug arrives from the owner, the tester or the backlog; board-keeper creates or
   updates the issue.
2. product-ba drafts the story; domain-ba adds realism and Mode 2 impact.
3. requirements-reviewer asks questions; the two BAs answer them. One round, unless the reviewer
   finds a real gap.
4. Every answer is logged on the issue as a comment starting with "BA decision:"; send the owner
   the digest.
5. requirements-reviewer runs the Definition of Ready; board-keeper moves the issue to Ready.

### Escalation triggers
The BAs decide on their own unless a question hits one of these; then the issue gets the
`needs:decision` label, the flow stops and the owner is told:
- it contradicts a decided row in the decisions table (docs/architecture.md);
- it changes scope (adds, drops or moves a feature between milestones);
- it is a look-and-feel judgment;
- it affects release or distribution;
- it is a naming decision (game, modes, species display names);
- the BAs cannot agree.

Also escalate after three rejected code review rounds on one issue.

### Delivery flow
1. board-keeper sets the issue to "AI in progress".
2. architect posts the technical plan as an issue comment.
3. tester writes the tests from the acceptance criteria and commits them, failing, on the feature
   branch.
4. developer implements until the tests pass, lint is clean and the build works.
5. code-reviewer reviews. A rejection goes back to developer; a disputed test goes to
   code-reviewer to decide.
6. After approval: tester runs the suite and posts the test report; open the pull request into
   develop (`gh pr create --base develop`, body with "Closes #N" and the test report), then
   `gh pr merge --auto --squash`. Add `needs:owner` when developer or code-reviewer reports a
   visible look-and-feel change.
7. CI and the owner gate run; GitHub merges when both are green. Fix CI failures through
   developer and a new review.
8. board-keeper updates the issue and the board.

### Digest format for BA decisions
Send after each requirements round, one line per decision:

```
BA decisions for #<N> <title>
- <question> → <decision> (<product-ba | domain-ba>) <link to comment>
Blocked: <none | needs:decision: question>
```

## Commands
- Tests:   godot_console --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
- Lint:    gdlint game && gdformat --check game
- Import:  godot_console --headless --path game --import
