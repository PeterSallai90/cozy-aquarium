# Cozy Aquarium – Architecture, Setup & Delivery Guide

Oct 27, 2026 · @Peter Sallai

## Purpose and decisions so far

Cozy Aquarium is a free 3D PC game where players build and rebuild a home aquarium and stock it with fish, written entirely by AI under a human product owner. This document is the single reference for the architecture, the Windows 11 development setup, the GitHub board and CI/CD, and the first backlog. Mode 1 (cozy builder) is in scope; Mode 2 (simulation) is out of scope but the architecture prepares for it.

| # | Decision | Choice | Status |
| --- | --- | --- | --- |
| D1 | Game mode in scope | Mode 1 cozy builder; Mode 2 simulation later | Decided |
| D2 | Platform | PC: Windows primary, Linux and macOS builds as a bonus | Decided |
| D3 | Distribution | itch.io first, free; Steam optional later | Proposed |
| D4 | Business goal | Free / hobby release | Decided |
| D5 | Visual style | Stylized low-poly, cozy | Decided |
| D6 | Engine and language | Godot 4.7.2 (pinned), statically typed GDScript, Forward+ renderer | Proposed |
| D7 | Camera | Front default view, orbit around and over, limited below the tank; photo mode may enter the tank | Decided |
| D8 | Text encoding | Unicode (UTF-8) everywhere; fonts must cover CJK and other non-Latin scripts | Decided |
| D9 | Languages | English default, Hungarian selectable; localization-ready from day one | Decided |
| D10 | Team | Human product owner and playtester; AI as BA partner, architect, developer, reviewer | Decided |
| D11 | Code hosting and board | GitHub on the owner's personal account (separate from the Claude account); GitHub Projects board | Decided |
| D12 | Development machine | Windows 11 x64 | Decided |
| D13 | Tanks | Three rectangular sizes in the MVP | Proposed |
| D14 | Progression | Pure sandbox, everything unlocked | Proposed |
| D15 | Species | 12–15 real freshwater species | Proposed |
| D16 | Fish interaction | Watching plus feeding; no consequences in Mode 1 | Proposed |
| D17 | Saving | Autosave plus named slots; screenshots from photo mode | Proposed |
| D18 | Performance target | 60 fish and 100 decor items at 60 FPS on a mid-range PC | Proposed |

"Proposed" items are architect assumptions awaiting the product owner's confirmation. Every decision that changes later gets a new row in the repository's `docs/adr` folder rather than an edit here. That folder is created with the repository skeleton (GitHub repository setup → Create the repository, backlog issue 2).

## Team and roles

The product owner makes every decision and accepts every feature; five AI roles do the rest, each with its own instructions so that they check each other instead of agreeing by default.

| Role | Who | Responsibilities | Model and environment |
| --- | --- | --- | --- |
| Product owner, playtester | You | Vision, priorities, decisions, acceptance, playtesting every build | — |
| BA partner | AI | Drafts epics and stories, writes acceptance criteria, finds edge cases and gaps, checks new stories against existing ones, runs the Definition of Ready check | Claude Opus 5.5 in a claude.ai Project "Aquarium – BA" |
| Architect | AI | Breaks stories into technical tasks, writes ADRs, keeps `CLAUDE.md` and the catalog schema consistent | Claude Opus 5.5 in Claude Code (planning mode) |
| Developer | AI | Implements issues on a branch, writes tests, opens pull requests | Claude Sonnet 5.5 in Claude Code; escalate to Opus 5.5 for shaders, fish behaviour and camera maths |
| Reviewer | AI | Reviews every pull request against the acceptance criteria and `CLAUDE.md`; reviews CI screenshots for visual regressions | Claude Opus 5.5 via the Claude GitHub integration or a Claude Code review session |
| Chores | AI | Labels and triages issues, writes changelogs and release notes, drafts translations | Claude Haiku 5.5 |

### Setting up the AI BA partner

Set this up now, in parallel with the Windows and GitHub setup: it does not depend on the repository, and the BA partner helps write the first documents.

1. In claude.ai, create a Project named **Aquarium – BA** and select Claude Opus 5.5.
2. Add this document to the project knowledge: export it as Markdown or PDF and upload it. It already contains the catalog schema ("Catalog schema") and the decisions log ("Purpose and decisions so far").
3. Paste the following into the project instructions:

```markdown
You are the business analyst partner for Cozy Aquarium, a cozy 3D aquarium builder.
The product owner makes all decisions. Your job is to make their decisions well-informed.

For every feature idea:
1. Restate the goal in one sentence and name the player benefit.
2. Write a user story: As a <player type>, I want <capability>, so that <benefit>.
3. Write acceptance criteria in Given / When / Then form, including failure and edge cases.
4. List what is explicitly out of scope.
5. Flag contradictions with existing decisions or stories, and open questions.
6. Note any impact on Mode 2 (simulation) data, even if Mode 2 is not built yet.

Challenge vague or conflicting requirements. Do not agree just to be agreeable.
Keep stories small enough for one pull request (roughly one day of AI work).
Output issues in the repository's issue-template format so they can be pasted into GitHub.
```

4. Draft `docs/vision.md` with the BA partner as its first task: the player experience, the target audience, and what the game is not. Upload the finished file to the project knowledge.
5. Draft `docs/glossary.md` as its second task: the shared terms every AI role must use, such as decor item, substrate and tank size. Upload it as well.
6. Once the repository skeleton exists (GitHub repository setup → Create the repository, backlog issue 2), let Claude Code commit both files into `docs/`. From then on, the repository is the source of truth for every document.
7. Refresh the project knowledge at each milestone and whenever a decision changes. Project knowledge holds copies, not live links, so stale copies make the BA reason from outdated decisions.
8. Work in one chat per epic. When a story is ready, paste it into a GitHub issue (or let Claude Code create the issue with the `gh` command line tool) and move it to **Ready**.

## Technology stack

Godot 4 with statically typed GDScript is the core choice, because every part of a Godot project (scripts, scenes, materials, UI layouts) is plain text that an AI agent can read, change and test without a human clicking in an editor.

| Area | Choice | Why |
| --- | --- | --- |
| Engine | Godot 4.7.2 (pinned at project start), standard build, not .NET | Free (MIT), text-based scenes, headless test and export, no license activation in CI |
| Language | GDScript with static typing enforced | Best engine integration, fast iteration; typing gives the AI compile-time feedback |
| Renderer | Forward+ | Best water, glow, volumetric fog and light quality; acceptable because the target is PC only |
| Tests | GdUnit4 (unit and scene tests) | Runs headless in CI; supports scene runners for input and camera tests |
| Lint and format | gdtoolkit 4 (`gdlint`, `gdformat`) | Consistent style regardless of which model wrote the code |
| 3D content | Blender 5.2, driven by Python scripts; CC0 asset packs | Low-poly assets can be generated and versioned as code |
| Code editor | VS Code with the godot-tools extension | For you to read code and diffs; the AI edits files directly |
| AI coding agent | Claude Code | Works in the repository, runs Godot, tests and Git itself |
| Version control | Git with Git LFS, GitHub (personal account) | Issues, board, pull requests and CI in one place |
| CI/CD | GitHub Actions | Lint, test, build Windows/Linux/macOS, publish to itch.io |
| Distribution | itch.io via `butler` | Free hosting, automatic patch uploads, no review process |
| Translations | gettext `.po` files | Standard format; editable in Poedit by a human translator if ever needed |

Unity with C# was the main alternative. It has more ready-made assets and more C# training data, but much of its work happens in the editor GUI, CI needs license activation, and its licensing terms have changed repeatedly. For a free, AI-built, PC-only, low-poly game, Godot carries less risk.

## Game architecture

The aquarium is data, and the 3D scene is only a view of that data: every system reads and changes one serializable model, so saving, undo, testing and the future simulation mode all work on the same object.

### Layers

1. **Catalog** – read-only definitions of every species, plant, substrate, decoration and tank. Stored as typed Godot resources (`.tres`, plain text).
2. **Aquarium model** – the current state: chosen tank, substrate and colour, placed items with transforms, fish instances. Pure data, no nodes, serializable to JSON.
3. **Commands** – every change to the model (place, move, rotate, recolour, delete, add fish) is a command object with `do()` and `undo()`. This gives unlimited undo/redo and a single place to validate changes.
4. **Systems** – placement, fish behaviour, feeding, camera, photo mode, save/load, settings and localization. Systems listen to model change signals; they never talk to each other directly.
5. **Presentation** – scenes, shaders, UI and audio that render the model.
6. **Game mode** – `CozyMode` now. `SimulationMode` later adds a fixed-rate simulation tick and rules on top of the same model and catalog.

### Catalog schema (Mode 2 ready)

Every species carries its simulation attributes from day one. Mode 1 ignores them; the AI BA fills them with real data as species are added, so Mode 2 starts with a complete catalog.

```gdscript
class_name FishSpecies
extends Resource

# --- Mode 1: identity and presentation ---
@export var id: StringName                  # "neon_tetra"
@export var name_key: String                # translation key "FISH_NEON_TETRA_NAME"
@export var description_key: String
@export var scene: PackedScene              # low-poly model with swim shader
@export var colour_variants: Array[Color] = []
@export var adult_length_cm: float = 3.5
@export var preferred_zone: Zone = Zone.MIDDLE   # TOP, MIDDLE, BOTTOM
@export var schooling: bool = true
@export var swim_speed: float = 1.0          # relative, drives behaviour

# --- Mode 2: simulation (stored now, used later) ---
@export var temp_min_c: float = 20.0
@export var temp_max_c: float = 26.0
@export var ph_min: float = 6.0
@export var ph_max: float = 7.5
@export var min_group_size: int = 6
@export var min_tank_litres: int = 40
@export var bioload: float = 1.0             # waste production, relative
@export var temperament: Temperament = Temperament.PEACEFUL
@export var diet: Array[StringName] = []     # "flakes", "live", "algae"
@export var light_preference: Light = Light.MODERATE
@export var needs_hiding_places: bool = false
@export var incompatible_with: Array[StringName] = []
```

Plants, decorations, substrates and tanks follow the same pattern: presentation fields plus simulation fields such as light need, growth rate, effect on water parameters, or volume in litres. These schema scripts live in `game/catalog/`, which exists only after the repository skeleton (GitHub repository setup → Create the repository, backlog issue 2); the fish schema itself is written in backlog issue 23.

### Aquarium model and save format

```json
{
  "format_version": 1,
  "name": "My first tank",
  "tank_id": "tank_medium_60l",
  "substrate": { "id": "sand_fine", "colour": "#E8D9B0", "heightmap": "base64..." },
  "items": [
    { "uid": "a1f3", "catalog_id": "rock_slate_01", "position": [0.1, 0.0, -0.05],
      "rotation_y": 35.0, "scale": 1.0, "colour": null }
  ],
  "fish": [
    { "uid": "f001", "species_id": "neon_tetra", "variant": 0, "nickname": "" }
  ],
  "created": "2026-10-27T18:00:00Z",
  "modified": "2026-10-27T18:30:00Z"
}
```

Rules: `format_version` increases with every breaking change and a migration function upgrades old saves; saves are UTF-8 JSON in the user data folder; the autosave slot is written after every command, debounced to at most once per 5 seconds. The model and serializer are written in backlog issues 5 and 6.

### Core systems

| System | Responsibility | Key technique |
| --- | --- | --- |
| Placement | Pick, place, move, rotate, scale, delete items inside the tank | Raycast onto substrate and items; snapping; overlap check with collision shapes; ghost preview |
| Substrate | Sand and gravel types, colours, sculpting slopes | Heightmap mesh; colour as shader parameter |
| Fish behaviour | Natural movement within the tank | Boids (separation, alignment, cohesion), preferred depth zone, obstacle avoidance, idle and dart states |
| Fish animation | Swimming without rigs | Vertex shader: sine-wave body bend scaled by speed |
| Feeding | Drop food, fish swim to it | Particle food with simple physics; fish switch to a seek state |
| Camera | Orbit, zoom, limits, photo mode | See the camera specification |
| Water rendering | Cozy, readable water | Glass shader, caustics projected on substrate, volumetric fog tint, bubbles |
| Save/load | Slots, autosave, migration | JSON via the model serializer |
| Settings | Language, audio, graphics quality, controls | Godot `ConfigFile` in the user data folder |
| Localization | All visible text | gettext `.po`, `tr()` keys only |

### Repository layout

This layout does not exist yet. Claude Code creates the folders and configuration files in GitHub repository setup → Create the repository (backlog issue 2); the folders under `game/` fill with content as the M0 and M1 issues are implemented. Every file, and the step that creates it, is listed in "Repository files and when they are created".

```
cozy-aquarium/
├─ game/                     # the Godot project (project.godot lives here)
│  ├─ catalog/               # .tres definitions: fish/, plants/, decor/, substrates/, tanks/
│  ├─ model/                 # aquarium model, commands, serializer
│  ├─ systems/               # placement, fish, camera, photo, save, settings
│  ├─ scenes/                # main menu, build scene, tank, furniture
│  ├─ shaders/               # water, glass, caustics, swim, sway, substrate
│  ├─ ui/                    # themes, fonts, screens
│  ├─ assets/                # models (.glb), textures, audio — tracked with Git LFS
│  ├─ localization/          # messages.pot, en.po, hu.po
│  └─ tests/                 # GdUnit4 tests mirroring the folders above
├─ tools/
│  ├─ blender/               # Python scripts that generate low-poly assets
│  └─ scripts/               # helper scripts (export, screenshot, pseudo-localization)
├─ docs/
│  ├─ adr/                   # architecture decision records
│  ├─ vision.md
│  ├─ glossary.md
│  └─ asset-licenses.md
├─ .github/                  # workflows, issue templates, PR template
├─ CLAUDE.md
├─ .gitattributes
├─ .gitignore
├─ .editorconfig
└─ README.md
```

## Camera specification

The build camera behaves like a person walking around a real tank on a cabinet: it orbits freely around and over the tank but cannot drop below the cabinet; only photo mode may enter the water. All numbers below are starting values, tuned during playtesting and kept in one settings resource.

### Build camera (orbit)

| Parameter | Starting value | Notes |
| --- | --- | --- |
| Pivot | Centre of the tank's water volume | Can be panned within the tank's footprint, never outside it |
| Default view | Front, elevation 5°, tank width fills about 85% of the screen | Restored by the reset action |
| Horizontal orbit | Full 360° | Back and side views allowed |
| Elevation, minimum | −10° | "Crouching by the cabinet"; plus a hard rule: camera height never below the cabinet top |
| Elevation, maximum | 85° | Near top-down; 90° avoided to prevent the view flipping |
| Zoom distance | 0.6× to 2.5× the default distance | Scaled by tank size |
| Collision | Camera never enters the glass, the cabinet or room geometry | Sphere cast from pivot to camera; camera is pulled in when blocked |
| Smoothing | Damped interpolation, about 0.15 s | Toggle in settings for players sensitive to motion |
| Field of view | 50° | Adjustable 40–70° in settings |

**Controls (mouse and keyboard):** right-drag orbits, mouse wheel zooms, middle-drag pans, `Home` resets to the front view, `Q`/`E` orbit in 45° steps, `R`/`F` raise and lower elevation. Left mouse stays reserved for selecting and placing items. All bindings are remappable.

**The cabinet:** a simple low-poly aquarium cabinet sits under the tank in a cozy room corner. It explains the lower camera limit visually and can become customizable later (wood colours, styles).

### Photo mode (may enter the tank)

Photo mode is a free camera for composing pictures, including underwater shots between plants and fish.

- **Entering:** a photo-mode button or `P` key; the UI hides, the camera keeps its current position, and a minimal photo toolbar appears.
- **Movement:** free fly with `WASD` plus mouse look, `Space`/`Ctrl` for up/down, `Shift` for slow movement, mouse wheel for field of view.
- **Allowed space:** the room around the tank plus the water volume of the tank. Inside the water, the camera keeps a margin of 1 cm from glass and the water surface and 2 cm above the substrate, and is pushed out of decorations and plants by collision.
- **Getting in:** the camera enters the water through the open top or straight through the glass walls. When it crosses a pane, it skips the glass thickness in a single step, so it never stops inside the glass or takes a picture from there. Crossing the glass switches the underwater effect on or off instantly. A "Dive in" shortcut moves the camera smoothly from its current position to just below the water surface.
- **Underwater look:** when the camera is below the water line, an underwater effect switches on: depth-based colour tint and fog, moving caustic light, floating particles, and a gentle wobble. Looking up at the surface shows a bright, rippled surface.
- **Photo tools:** pause the fish (freeze time), depth of field with focus distance, a few cozy colour filters, frame overlays (rule of thirds), and hide or show the cabinet and room.
- **Taking a picture:** `Enter` or the shutter button saves a PNG at screen resolution or 2× to a "Cozy Aquarium" folder inside the player's Pictures folder, and shows a small confirmation.
- **Leaving:** `Esc` returns to the build camera at its last orbit position.

### Acceptance criteria (camera epic)

- Given the build camera, when the player drags to orbit downward, then the camera stops at −10° elevation and never drops below the cabinet top.
- Given the build camera, when the player orbits to 85° elevation and keeps dragging, then the view stays stable and does not flip.
- Given any camera position, when the player presses `Home`, then the camera returns smoothly to the default front view.
- Given the build camera, when the player zooms in, then the camera never passes through the glass.
- Given photo mode, when the player flies through a glass wall from outside, then the camera enters the water, the underwater effect turns on, and the camera never comes to rest inside the glass.
- Given photo mode above the tank, when the player flies down through the water surface, then the camera enters the water and the underwater effect turns on.
- Given photo mode underwater, when the player flies into a rock or plant, then the camera slides along it instead of entering it.
- Given photo mode, when the player takes a photo, then a PNG appears in the Pictures folder and no UI is visible in it.

## Unicode, localization and fonts

All text is Unicode end to end: UTF-8 files, Godot's Unicode strings, gettext translations, and a font stack that falls back to Noto fonts so that any script, including Chinese, Japanese and Korean, renders instead of showing empty boxes.

The files named in this section are created with the repository, not before: `.editorconfig` and `.gitattributes` in the repository skeleton (GitHub repository setup → Create the repository, backlog issue 2), and the `game/localization/` files in backlog issue 7.

### Encoding rules

- Every text file in the repository (scripts, scenes, `.po`, JSON, Markdown) is UTF-8 without BOM with LF line endings, enforced by `.editorconfig` and `.gitattributes`.
- Save files and settings are written as UTF-8.
- Godot's advanced text server (the default) handles complex shaping and right-to-left text, so later languages such as Arabic need no engine change.
- Player-typed text (aquarium names, fish nicknames) accepts any Unicode input, including Windows IME input for CJK. This is why CJK-capable fonts are needed even while the UI itself is only English and Hungarian.

### Language handling

| Item | Rule |
| --- | --- |
| Default language | English |
| Selectable at launch | English, Magyar (Hungarian), each shown in its own language in the menu |
| First start | Use the Windows display language if it is supported, otherwise English |
| Storage | Selected language saved in settings; switching applies immediately without restart |
| Source strings | Never in code or scenes: only translation keys through `tr()` and `tr_n()` |
| Files | `game/localization/messages.pot` (extracted), `en.po`, `hu.po` |
| Numbers and units | Metric; decimal separator follows the language (3.5 cm in English, 3,5 cm in Hungarian) |
| Species names | Translated common name plus the Latin scientific name, which is never translated |

### Font stack

| Layer | Purpose | Candidate (license) |
| --- | --- | --- |
| 1. Display / UI font | Cozy rounded look for Latin, including Hungarian ő and ű | Nunito or a similar rounded font under the SIL Open Font License; verify full Latin Extended-A coverage before choosing |
| 2. Latin, Cyrillic, Greek fallback | Wider European coverage | Noto Sans (SIL OFL) |
| 3. CJK fallback | Chinese, Japanese, Korean player text and future translations | Noto Sans CJK: SC, TC, JP and KR variants (SIL OFL) |
| 4. Last resort | Anything not covered above, such as emoji or rare scripts | Godot `SystemFont`, which uses fonts installed in Windows |

The fallback chain is set once in the global UI theme, so every label inherits it. CJK fonts are large, roughly 15–20 MB each, so the build ships them compressed and loads glyphs on demand. This is acceptable for a PC download and can be revisited if download size becomes an issue.

### Quality gates

- **Pseudo-localization:** Godot's built-in pseudo-localization runs in a CI test that lengthens every string by about 40% and adds accented characters, then checks screenshots for overflow and missing glyphs.
- **Missing key check:** CI fails if any key in `messages.pot` is missing from `en.po` or `hu.po`.
- **Glyph test:** a test scene renders a fixed sample (`Árvíztűrő tükörfúrógép`, `熱帯魚`, `열대어`, `Аквариум`) and checks that no glyph falls back to the empty box.
- **Translation review:** the AI drafts Hungarian translations (Haiku 5.5 for volume, Opus 5.5 for anything tricky); you review them in a pull request before merge.

## Art and asset pipeline

Assets are produced mainly as code: Python scripts run Blender in the background to generate low-poly models from parameters, so the AI can create, change and regenerate them, and every asset is versioned and reviewable like source code.

The `tools/blender/` and `game/assets/` folders and `docs/asset-licenses.md` are created with the repository skeleton (GitHub repository setup → Create the repository, backlog issue 2), and the style rules below go into `CLAUDE.md` in the same step. The first generator script arrives with backlog issue 10.

### Sources, in order of preference

1. **Procedural generation in Blender (primary).** One script per asset family: a parametric fish generator (body length, height, tail and fin shapes, colour pattern), rock and pebble generators, driftwood, and plant generators (stem count, leaf shape, height). Each species or item is a small parameter file, and the script exports a `.glb` file into `game/assets/`.
2. **CC0 asset packs.** Public-domain low-poly packs, for example from Quaternius or Kenney, for furniture, room props and fallback decorations. CC0 needs no attribution and allows any use.
3. **AI 3D generators (optional).** For a few unique hero pieces only, such as a sunken ship or treasure chest. Outputs are reduced to the low-poly style in Blender, and each tool's terms are checked before use.
4. **Hand-made by a human artist (optional).** Possible at any time; the pipeline accepts any `.glb`.

### Style rules (go into `CLAUDE.md`)

| Asset | Triangle budget | Colouring |
| --- | --- | --- |
| Fish | 300–800 | Vertex colours or a shared palette texture; pattern masks for colour variants |
| Plants | 200–1,500 | Palette texture; sway in a vertex shader |
| Rocks, wood, decor | 100–600 | Palette texture; colour tint parameter |
| Tank, cabinet, room | 500–3,000 | Palette texture |

- Flat shading or soft low-poly shading; no photographic textures.
- One shared palette texture (a small gradient atlas) for most models keeps the look consistent and draw calls low.
- Colour customization works through shader parameters, never through duplicate models.
- Fish swim through a vertex shader; no skeletal rigs in the MVP.

### Pipeline commands

```powershell
# Generate all fish from their parameter files and export .glb into the Godot project
blender --background --python tools/blender/generate_fish.py -- --all

# Regenerate one species
blender --background --python tools/blender/generate_fish.py -- --species neon_tetra
```

Godot imports `.glb` files automatically when the project opens or when CI runs `godot --headless --import`.

### Audio

Ambient water, bubbles, filter hum, soft UI sounds and calm music come from CC0 libraries (for example Kenney audio packs, or Freesound filtered to CC0). Every sound file is logged like any other asset. AI music or sound tools may be used if their terms allow free distribution.

### Asset license log

Every asset that is not generated by our own scripts gets a row in `docs/asset-licenses.md` in the same pull request that adds it. CI fails if a file in `game/assets/` has no matching row.

| File | Source | Author | License | Link | Added |
| --- | --- | --- | --- | --- | --- |
| assets/room/cabinet\_01.glb | Example CC0 pack | Pack author | CC0 1.0 | Pack's page | Date added |

## Windows 11 development environment setup

The whole environment installs in about an hour from one PowerShell window, mostly with `winget`; Godot is installed manually so that your machine and CI use exactly the same pinned version.

### Step 0 – Before you start

- [ ] Windows 11 x64 fully updated (Settings → Windows Update).
- [ ] Latest graphics driver from NVIDIA, AMD or Intel. Godot's Forward+ renderer needs Vulkan or Direct3D 12 support.
- [ ] At least 30 GB free disk space.
- [ ] Administrator rights on the machine.
- [ ] Your **personal** GitHub username and password (plus two-factor device) at hand.
- [ ] Your Claude account with a plan that includes Claude Code (Pro or Max).
- [ ] Optional: enable **Developer Mode** (Settings → System → For developers) so Git can create symbolic links.

### Step 1 – Terminal

Windows Terminal ships with Windows 11. Install PowerShell 7, then use it for every command in this guide.

```powershell
winget install --id Microsoft.PowerShell -e
```

Open **Windows Terminal**, open Settings, and set **PowerShell** (not "Windows PowerShell") as the default profile.

### Step 2 – Install the tools

```powershell
winget install --id Git.Git -e                       # Git for Windows, includes Git LFS and Git Bash
winget install --id GitHub.cli -e                    # gh: GitHub from the command line
winget install --id Microsoft.VisualStudioCode -e    # code editor for reading code and diffs
winget install --id BlenderFoundation.Blender -e     # 3D asset generation
winget install --id Python.Python.3.12 -e           # for gdtoolkit and pre-commit
```

Close and reopen the terminal afterwards so the new programs are on your PATH.

### Step 3 – Configure Git

Use the name and the private "noreply" email of your personal GitHub account (GitHub → Settings → Emails → "Keep my email addresses private" shows it).

```powershell
git config --global user.name "Your Name"
git config --global user.email "12345678+yourname@users.noreply.github.com"
git config --global init.defaultBranch main
git config --global core.autocrlf false        # line endings are controlled by .gitattributes
git config --global pull.rebase true
git config --system core.longpaths true        # run in an administrator terminal
git lfs install
```

### Step 4 – Connect GitHub with your personal account

Your Claude account and your GitHub account are completely independent. Claude Code uses whatever Git and GitHub credentials are set up on your machine, so every commit, issue and pull request it creates belongs to your personal GitHub account.

```powershell
gh auth login
# ? Where do you use GitHub?            GitHub.com
# ? Preferred protocol for Git?          HTTPS
# ? Authenticate Git with credentials?   Yes
# ? How would you like to authenticate?  Login with a web browser
gh auth setup-git
gh auth status          # must show your personal account as active
```

When the browser opens, check that you are signed in to the **personal** GitHub account before approving. If you also use another GitHub account on this machine, `gh auth login` can store both, and `gh auth switch` changes the active one. Always confirm with `gh auth status` before a work session.

### Step 5 – Install Godot (pinned version)

1. Download the **standard** (not .NET) Windows 64-bit zip of the latest stable Godot 4 release from godotengine.org. Note the exact version number (the project uses 4.7.2). It is recorded later in `docs/adr/0001-engine.md`, when Claude Code creates the repository skeleton (GitHub repository setup → Create the repository, backlog issue 2); CI uses the same number.
2. Create the folder `C:\Tools\Godot` and extract both files there: the editor `.exe` and the `_console.exe`.
3. Rename them to `godot.exe` and `godot_console.exe`.
4. Add `C:\Tools\Godot` to your PATH:

```powershell
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Tools\Godot", "User")
```

5. Reopen the terminal, then check: `godot_console --version`.
6. Install the export templates. Use a throwaway project:
   1. Run `godot.exe` from `C:\Tools\Godot`. The **Project Manager** opens first
   2. Click **Create**, name the project `scratch`, choose any empty folder, keep the **Forward+** renderer, and click **Create & Edit**.
   3. In the editor's top menu bar, click **Editor → Manage Export Templates…**
   4. Click **Download and Install** with the default "Best available mirror". The download is large, roughly a gigabyte, so allow a few minutes.
   5. When the dialog shows the version as installed, close Godot and delete the `scratch` folder.

Export templates are precompiled versions of the Godot engine for each platform, without the editor parts. When you build the game, Godot packs your scenes, scripts and assets into the Windows template to produce the standalone `CozyAquarium.exe`; without templates, the game runs inside the editor but cannot be built. They are stored in `%APPDATA%\Godot\export_templates\`, in a folder named after the version. Only local builds need them: the CI pipeline downloads its own copy, so this step can also wait until Claude Code has created the real project.

Upgrading Godot later is a deliberate decision: a new ADR, a pull request that changes the version in CI, and a full test run.

### Step 6 – Blender on the PATH

```
# Adjust the version folder to the one winget installed
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Program Files\Blender Foundation\Blender 5.2", "User")
```

Reopen the terminal and check `blender --version`.

### Step 7 – Python tools

```powershell
py -m pip install --upgrade pip
py -m pip install "gdtoolkit==4.5.0" pre-commit
gdlint --version
pre-commit --version
```

### Step 8 – VS Code extensions

```powershell
code --install-extension geequlim.godot-tools
code --install-extension EditorConfig.EditorConfig
code --install-extension GitHub.vscode-pull-request-github
code --install-extension ms-python.python
```

In Godot in a throwaway project, open Editor → **Editor Settings → Network → Language Server** and keep port 6005. VS Code's godot-tools then shows errors and code navigation while the Godot editor is open.

### Step 9 – Install Claude Code

The native Windows installer is the recommended method ([Claude Code setup docs](https://code.claude.com/docs/en/setup.md)). Because Git for Windows is already installed, Claude Code uses Git Bash for its shell commands; without it, it falls back to PowerShell.

```powershell
irm https://claude.ai/install.ps1 | iex
```

Close and reopen the terminal, then:

```powershell
claude --version
claude                 # first start: sign in with your Claude account in the browser
```

Inside Claude Code, `/model` switches between Sonnet 5.5 and Opus 5.5. The Claude Desktop app also includes Claude Code if you prefer a window to a terminal; the Desktop steps are described in GitHub repository setup → Create the repository, and work the same way for every later issue.

**If `claude` is not recognized** after installation:

1. Close Windows Terminal completely, every tab, and open it again. New tabs inherit the PATH of the running Windows Terminal app, so closing one tab is not enough.
2. If it still fails, check whether the program was installed:

```powershell
Test-Path "$env:USERPROFILE\.local\bin\claude.exe"
```

3. `True` means Claude Code is installed but not on your PATH. Add the folder to your user PATH, then restart Windows Terminal again:

```powershell
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$userPath;$env:USERPROFILE\.local\bin", "User")
```

4. `False` means the installation did not complete. Run the install command again and read its output for error messages.
5. Still failing: see the troubleshooting section of the [Claude Code setup docs](https://code.claude.com/docs/en/setup.md).

**A note on the PATH commands in this guide:** earlier versions of Steps 5 and 6 wrote `$env:Path` into the user PATH. That copies the whole system PATH into the user PATH. It works, but creates duplicates. If you ran those older commands, clean up later in **Settings → System → About → Advanced system settings → Environment Variables**: in the user `Path`, remove entries that also appear in the system `Path`.

### Step 10 – Optional tools

- **Poedit** (poedit.net) to review `.po` translation files comfortably.
- **itch.io account** and the `butler` command line tool, needed once releases start (see CI/CD).
- **A Godot MCP server** (community projects) that lets Claude Code launch the game and read its errors directly. Evaluate one in a separate branch before relying on it.

### Step 11 – Verify everything

Run all checks at once and save the output to a file, because the repository and the board do not exist yet:

```powershell
& {
  git --version; git lfs version; gh auth status
  godot_console --version; blender --version
  py --version; gdlint --version; pre-commit --version
  claude --version; code --version
} *>&1 | Tee-Object "$HOME\env-check.txt"
```

The output appears on screen and is saved to `env-check.txt` in your user folder. `*>&1` makes sure messages that some tools print as errors, such as `gh auth status`, also end up in the file.

Every command must print a version number, and `gh auth status` must name your personal account.

The file becomes the first backlog issue, "Verify development environment and record versions", once the repository exists (GitHub repository setup → Create the repository) and the labels and board are set up (Project board → Create the board, Labels). Then, inside the repository folder:

```powershell
gh issue create --title "Environment verified" --label "type:chore" --body-file "$HOME\env-check.txt"
```

The board's auto-add rule puts the issue in Backlog; move it straight to Done, because the work is already complete.

## GitHub repository setup

The repository lives on your personal GitHub account and is created from the command line; protection rules make sure nothing reaches `main` without a pull request and a green CI run, no matter which AI wrote it.

### Public or private

| Option | Pros | Cons |
| --- | --- | --- |
| Public (recommended for a free game) | Unlimited free GitHub Actions minutes, including Windows and macOS runners; possible community contributions | Code and assets are visible to everyone |
| Private | Only you see it | Monthly free Actions minute cap; Windows and macOS runners consume it several times faster |

The repository can switch from private to public at any time, so starting private and opening it before the first release is also reasonable.

### Create the repository

```powershell
mkdir C:\Dev; cd C:\Dev
gh repo create cozy-aquarium --private --clone --description "A cozy 3D aquarium builder" --license mit
cd cozy-aquarium
```

The command above creates only an empty repository with a license file. Every other folder and file described in this document is created in the next step, the repository skeleton (backlog issue 2); until then, none of them exist.

1. Export this document as Markdown (click the doc's name → **Export** → Markdown).
2. In the cloned folder, create the `docs` folder by hand and save the export there, so Claude Code can read the specification. If the AI BA has already drafted `vision.md` and `glossary.md`, save them into `docs` too.

```powershell
mkdir docs
Move-Item "$HOME\Downloads\<exported file name>.md" docs\architecture.md
```

3. Start Claude Code in the repository folder (`claude`) and give it this task:

> Create the repository skeleton described in docs/architecture.md, sections "Repository layout", "GitHub repository setup" and "Project board": all folders; .gitattributes, .gitignore, .editorconfig, .pre-commit-config.yaml, CLAUDE.md and README.md; docs/adr/0001-engine.md recording Godot version \<your version from Step 5>; docs/asset-licenses.md with only the table header; .github/ISSUE\_TEMPLATE with feature.yml, bug.yml and test.yml; .github/pull\_request\_template.md; and an empty Godot 4 project in /game with the Forward+ renderer. Commit any files already in docs/. Open a pull request.

**Using the Claude Desktop app instead of the terminal** (it includes Claude Code, so no separate install is needed):

1. Open the Claude Desktop app and click the **Code** tab at the top center of the window.
2. Choose **Local**, click **Select folder**, and pick `C:\Dev\cozy-aquarium`.
3. In the model dropdown next to the send button, choose **Opus 5.5** for the skeleton; Sonnet 5.5 is enough for most later issues.
4. Paste the task above into the message box and send it.
5. Approve the proposed changes. The Code tab starts in a permission mode where Claude proposes each file change and command (such as `git` and `gh`) and waits for your approval. Keep it for the first sessions; switch to a less interrupting mode once you trust the workflow.

The Desktop app uses the same Git and GitHub login as the terminal, so commits and pull requests still go to your personal account; `gh auth status` confirms it. Details: [Claude Code desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart.md).

4. Review the pull request, merge it on GitHub, then run `git pull` locally.

The subsections below (.gitattributes to CLAUDE.md) are the contents Claude Code writes in step 3; you do not type them yourself.

### .gitattributes

```
* text=auto eol=lf

# Windows scripts keep CRLF
*.bat  text eol=crlf
*.cmd  text eol=crlf

# Binary assets in Git LFS
*.glb   filter=lfs diff=lfs merge=lfs -text
*.blend filter=lfs diff=lfs merge=lfs -text
*.png   filter=lfs diff=lfs merge=lfs -text
*.jpg   filter=lfs diff=lfs merge=lfs -text
*.webp  filter=lfs diff=lfs merge=lfs -text
*.ogg   filter=lfs diff=lfs merge=lfs -text
*.wav   filter=lfs diff=lfs merge=lfs -text
*.ttf   filter=lfs diff=lfs merge=lfs -text
*.otf   filter=lfs diff=lfs merge=lfs -text
```

### .gitignore

```
# Godot 4 cache (re-created automatically); .import files ARE committed
.godot/

# Build output
build/
export/
*.pck
*.exe

# Python
__pycache__/
.venv/

# Editors and OS
.vscode/*
!.vscode/extensions.json
!.vscode/settings.json
Thumbs.db
.DS_Store

# Secrets, never committed
.env
*.key
```

### .editorconfig

```
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.gd]
indent_style = tab

[*.{json,yml,yaml,md}]
indent_style = space
indent_size = 2

[*.{bat,cmd}]
end_of_line = crlf
```

### Pre-commit hooks (.pre-commit-config.yaml)

```yaml
repos:
  - repo: https://github.com/Scony/godot-gdscript-toolkit
    rev: 4.5.0          # pinned at repository creation
    hooks:
      - id: gdformat
      - id: gdlint
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-merge-conflict
      - id: check-yaml
      - id: check-json
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-added-large-files
        args: ["--maxkb=500"]   # large files must go through LFS
```

Run `pre-commit install` once in the repository folder, after the skeleton pull request is merged and pulled (step 4 above); before that, the configuration file does not exist.

### CLAUDE.md (the AI team's rulebook)

Claude Code reads this file at the start of every session. It is the most important lever for consistent AI output, so you approve every change to it.

```markdown
# Cozy Aquarium – rules for AI contributors

## Product
Cozy 3D aquarium builder for PC. Mode 1 (cozy builder) only. Mode 2 (simulation) is future work:
never implement it, but keep its catalog fields intact. Read docs/vision.md and docs/glossary.md.

## Tech
- Godot 4.7.2, standard build, GDScript only, Forward+ renderer.
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
- Low-poly style; triangle budgets and palette rules in docs/art-style.md.
- Generate assets with tools/blender scripts where possible.
- Any third-party asset needs a row in docs/asset-licenses.md in the same PR.

## Workflow
- One issue = one branch = one pull request. Branch name: <issue-number>-<short-slug>.
- Read the issue's acceptance criteria first; ask in the issue if anything is unclear.
- Write or update GdUnit4 tests for every acceptance criterion that can be tested automatically.
- Before opening a PR run: gdformat --check, gdlint, and the full test suite headless.
- PR description: link the issue ("Closes #N"), list what changed, how to playtest, known limits.
- Never commit to main. Never change CLAUDE.md, CI workflows or the Godot version without an issue
  that explicitly asks for it.

## Commands
- Tests:   godot_console --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
- Lint:    gdlint game && gdformat --check game
- Import:  godot_console --headless --path game --import
```

### Protect the main branch

In GitHub: **Settings → Rules → Rulesets → New branch ruleset** for `main`:

- [ ] Require a pull request before merging, with 0 required approvals. Claude Code opens pull requests under your account, and GitHub does not let authors approve their own pull requests; your approval is the act of merging after playtesting.
- [ ] Require status checks to pass: `lint`, `test`, `build-windows`.
- [ ] Block force pushes and deletions.
- [ ] Require linear history (squash merges keep the history readable).

### Claude on GitHub (optional, later)

Claude Code can install a GitHub app and workflow in your repository (run `/install-github-app` inside Claude Code), after which mentioning `@claude` in an issue or pull request starts work or a review in GitHub Actions. Authentication options and costs are described in the Claude Code docs; check them before enabling, because this runs on GitHub's servers and may need an API key or subscription token stored as a repository secret. Start with local Claude Code sessions and add this once the workflow is stable.

## Project board

One GitHub Projects board shows every feature, bug, test task and chore with its status; issues are the work items, epics are parent issues with sub-issues, and pull requests move cards automatically.

Run the commands in this section inside the repository folder, after the skeleton pull request is merged (GitHub repository setup → Create the repository, step 4). The issue and pull request templates shown below are written by Claude Code in that skeleton step; the board, its fields and the labels are created by the commands here.

### Create the board

```powershell
gh auth refresh -s project            # allow gh to manage Projects
gh project create --owner "@me" --title "Cozy Aquarium"
```

Then in the browser, open the project and link it to the `cozy-aquarium` repository (project **Settings → Manage access / Linked repositories**).

### Fields

| Field | Type | Values |
| --- | --- | --- |
| Status | Single select | Backlog, Ready, AI in progress, Human review, Done |
| Priority | Single select | P0 must, P1 should, P2 could |
| Size | Single select | S (under half a day of AI work), M (about a day), L (split it) |
| Epic | Parent issue | Shown through GitHub sub-issues |
| Milestone | Repository milestone | M0 Foundation, M1 First playable, M2 Content, M3 Release 1.0 |

### Views

- **Board** grouped by Status: the daily view.
- **Backlog** table sorted by Priority, filtered to Status = Backlog or Ready.
- **By epic** table grouped by parent issue, showing progress per epic.
- **Tests** board filtered to the `type:test` label.
- **Bugs** table filtered to `type:bug`, sorted by Priority.

### Built-in automations (project Workflows menu)

- Item added to project → Status = Backlog.
- Pull request opened that links an issue → Status = Human review.
- Pull request merged → Status = Done; issue closed.
- Issue reopened → Status = Ready.
- Auto-add to project: every new issue in `cozy-aquarium`.

### Labels

```powershell
gh label create "type:feature"   --color 1D76DB --description "New player-facing capability"
gh label create "type:bug"       --color D73A4A --description "Something does not work as specified"
gh label create "type:test"      --color 0E8A16 --description "Test task: automated or manual playtest"
gh label create "type:chore"     --color C5DEF5 --description "Tooling, CI, refactoring, docs"
gh label create "type:asset"     --color FBCA04 --description "Models, audio, fonts, generator scripts"
gh label create "type:epic"      --color 5319E7 --description "Parent issue grouping stories"
gh label create "area:build"     --color BFD4F2
gh label create "area:fish"      --color BFD4F2
gh label create "area:camera"    --color BFD4F2
gh label create "area:ui"        --color BFD4F2
gh label create "area:i18n"      --color BFD4F2
gh label create "area:render"    --color BFD4F2
gh label create "area:ci"        --color BFD4F2
gh label create "mode:1"         --color EDEDED
gh label create "mode:2-impact"  --color EDEDED --description "Affects future simulation data"
gh label create "needs:decision" --color E99695 --description "Blocked on the product owner"
```

### Issue templates (.github/ISSUE\_TEMPLATE)

**feature.yml**

```yaml
name: Feature / user story
description: A player-facing capability
labels: ["type:feature", "mode:1"]
body:
  - type: textarea
    id: story
    attributes:
      label: User story
      placeholder: As a <player>, I want <capability>, so that <benefit>.
    validations: { required: true }
  - type: textarea
    id: acceptance
    attributes:
      label: Acceptance criteria
      description: Given / When / Then, one per line, including edge cases.
    validations: { required: true }
  - type: textarea
    id: out_of_scope
    attributes:
      label: Out of scope
  - type: textarea
    id: tests
    attributes:
      label: Test notes
      description: What is tested automatically, what needs a manual playtest.
  - type: textarea
    id: mode2
    attributes:
      label: Mode 2 impact
      description: Any data or hooks the simulation will need later.
  - type: textarea
    id: design
    attributes:
      label: Mockups, references, links
```

**bug.yml** asks for: what happened, what was expected, steps to reproduce, build version, screenshot or video, and the log file from `%APPDATA%\Godot\app_userdata\Cozy Aquarium\logs`.

**test.yml** (for test tasks) asks for: what is tested, linked story, type (automated, manual playtest, visual check, performance), test steps, expected result, and the pass/fail record.

### Pull request template (.github/pull\_request\_template.md)

```markdown
Closes #

## What changed

## How to playtest
1. Download the Windows build from this PR's CI run (Artifacts).
2. ...

## Acceptance criteria
- [ ] (copied from the issue, ticked by the developer AI, verified by the product owner)

## Screenshots

## Known limitations
```

### Definition of Ready (checked by the AI BA before a story moves to Ready)

- [ ] User story with a clear player benefit.
- [ ] Acceptance criteria in Given / When / Then, including at least one edge or failure case.
- [ ] Out of scope stated.
- [ ] Size S or M (L must be split).
- [ ] Dependencies linked; no open `needs:decision` label.
- [ ] New visible strings and new assets named.
- [ ] Mode 2 impact considered.

### Definition of Done (checked by the AI reviewer and you before merge)

- [ ] All acceptance criteria met and ticked in the pull request.
- [ ] Automated tests added or updated; CI green (lint, tests, Windows build).
- [ ] No new warnings in the Godot output.
- [ ] All new strings translated in `en.po` and `hu.po`.
- [ ] New assets logged in `docs/asset-licenses.md`.
- [ ] You have playtested the Windows build from the pull request.
- [ ] Docs, ADRs or `CLAUDE.md` updated if behaviour or rules changed.

## CI/CD pipelines

Two GitHub Actions workflows do all checking and shipping: `ci.yml` lints, tests and builds every pull request into a downloadable Windows build, and `release.yml` publishes a tagged version to itch.io for Windows, Linux and macOS.

None of these files exist until the repository skeleton is merged. Claude Code then creates `.github/workflows/ci.yml`, `game/export_presets.cfg`, GdUnit4 in `game/addons/` and the two check scripts in `tools/scripts/` in backlog issues 3 and 4; `release.yml` follows in backlog issue 40.

| Workflow | Trigger | Jobs | Result |
| --- | --- | --- | --- |
| ci.yml | Every pull request and push to `main` | lint → test → build-windows | Green check required for merge; Windows zip as a run artifact (kept 14 days) |
| release.yml | Tag `v*` (for example `v0.3.0`) | build Windows, Linux, macOS → upload to itch.io | New version on itch.io; GitHub Release with zips and changelog |
| visual.yml (later) | Nightly and on demand | Render fixed camera shots with a software renderer, compare to approved screenshots | Report with differences; AI reviewer comments on suspicious changes |

All builds run on Ubuntu runners: Godot exports Windows, Linux and macOS builds from Linux, which is faster and cheaper than Windows runners. The macOS build is unsigned, which itch.io allows; players must right-click → Open the first time.

### ci.yml

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

env:
  GODOT_VERSION: "4.7.2"        # must match docs/adr/0001-engine.md

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install "gdtoolkit==4.5.0"
      - run: gdformat --check game
      - run: gdlint game
      - run: python tools/scripts/check_translations.py     # every key in en.po and hu.po
      - run: python tools/scripts/check_asset_licenses.py   # every asset logged

  test:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - name: Install Godot
        run: |
          wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
          unzip -q Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
          sudo mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot
      - name: Import project
        run: godot --headless --path game --import
      - name: Run tests
        # exact GdUnit4 flags are verified in the CI setup issue for the pinned GdUnit4 version
        run: godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: test-reports, path: game/reports }

  build-windows:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - name: Install Godot and export templates
        run: |
          wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
          wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz
          unzip -q Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
          sudo mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot
          mkdir -p ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable
          unzip -q Godot_v${GODOT_VERSION}-stable_export_templates.tpz
          mv templates/* ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable/
      - run: godot --headless --path game --import
      - run: mkdir -p build/windows && godot --headless --path game --export-release "Windows Desktop" ../build/windows/CozyAquarium.exe
      - uses: actions/upload-artifact@v4
        with:
          name: CozyAquarium-windows-${{ github.sha }}
          path: build/windows
          retention-days: 14
```

### release.yml (outline)

1. Trigger on tags matching `v*`.
2. Install Godot and export templates (same steps as above; the AI moves them into a reusable composite action to avoid duplication).
3. Write the version from the tag into `project.godot` (`application/config/version`).
4. Export the presets `Windows Desktop`, `Linux` and `macOS`.
5. Install `butler` and push each build: `butler push build/windows yourname/cozy-aquarium:windows --userversion ${VERSION}` (and `:linux`, `:mac`).
6. Create a GitHub Release with the zips attached and release notes drafted by Claude Haiku 5.5 from the merged pull requests.

### Secrets and one-time setup

- [ ] Create an itch.io account and a project page "Cozy Aquarium" (can stay hidden or draft until the first public release).
- [ ] Generate a butler API key on itch.io (account settings → API keys).
- [ ] Store it in GitHub: `gh secret set BUTLER_API_KEY` (paste the key when asked). Secrets are never written in files or chats.
- [ ] Commit `game/export_presets.cfg` with the three presets; it must contain no passwords or keys.

### Versioning

Semantic versions: `0.x.y` until release 1.0. Minor version per milestone (`0.1` First playable, `0.2` Content, …), patch versions for fixes. The version appears on the main menu so playtest feedback always names the build.

## Repository files and when they are created

Apart from the license and the exported architecture document, every repository file in this guide is written by Claude Code, and none of them exist before the repository skeleton (backlog issue 2); this chapter lists them all in the order they appear.

### The order of creation

1. **Windows setup, Steps 0–11:** installs tools on your machine only; no repository files yet.
2. **GitHub repository setup → Create the repository, steps 1–2:** `gh repo create` makes the empty repository with `LICENSE`; you add `docs/architecture.md` by hand.
3. **Repository skeleton (backlog issue 2):** Claude Code writes all configuration files, templates, documentation stubs, the folder tree and the empty Godot project in one pull request.
4. **Project board:** commands create the board, fields and labels on GitHub; no files change.
5. **CI and tests (backlog issues 3 and 4):** workflow, export presets, check scripts, GdUnit4.
6. **Feature issues (5 onward):** game code, catalog, translations, generators and later workflows, each in its own pull request.

### Every file and folder

| Path | Purpose | Specified in section | Created in | By |
| --- | --- | --- | --- | --- |
| `LICENSE` | MIT license | GitHub repository setup | Create the repository, step 1 | `gh repo create` |
| `docs/architecture.md` | Export of this document, the specification Claude Code reads | GitHub repository setup | Create the repository, step 2 | You |
| `docs/vision.md`, `docs/glossary.md` | Product vision and shared terms | Team and roles → Setting up the AI BA partner | Drafted with the AI BA; saved in step 2 or committed later | AI BA and you |
| `.gitattributes` | Line endings, Git LFS file types | GitHub repository setup | Backlog issue 2 | Claude Code |
| `.gitignore` | Files Git ignores | GitHub repository setup | Backlog issue 2 | Claude Code |
| `.editorconfig` | UTF-8, LF, indentation | GitHub repository setup | Backlog issue 2 | Claude Code |
| `.pre-commit-config.yaml` | gdformat, gdlint and file checks before each commit | GitHub repository setup | Backlog issue 2 | Claude Code |
| `CLAUDE.md` | Rules for all AI contributors, including art style rules | GitHub repository setup; Art and asset pipeline | Backlog issue 2 | Claude Code; you approve changes |
| `README.md` | Project overview | GitHub repository setup | Backlog issue 2 | Claude Code |
| `docs/adr/0001-engine.md` | Engine decision and pinned Godot version | Purpose and decisions; Windows setup Step 5 | Backlog issue 2 | Claude Code, with your version number |
| `docs/asset-licenses.md` | License log, header only at first | Art and asset pipeline | Backlog issue 2 | Claude Code |
| `.github/ISSUE_TEMPLATE/feature.yml`, `bug.yml`, `test.yml` | Issue forms | Project board | Backlog issue 2 | Claude Code |
| `.github/pull_request_template.md` | Pull request checklist | Project board | Backlog issue 2 | Claude Code |
| `game/project.godot` | Empty Godot 4 project, Forward+ renderer | GitHub repository setup | Backlog issue 2 | Claude Code |
| Folder tree: `game/` subfolders, `tools/blender/`, `tools/scripts/`, `docs/adr/` | Structure from "Repository layout" | Game architecture | Backlog issue 2 | Claude Code |
| `.github/workflows/ci.yml` | Lint, test, Windows build | CI/CD pipelines | Backlog issue 3 | Claude Code |
| `game/export_presets.cfg` | Windows, Linux, macOS export presets | CI/CD pipelines | Backlog issue 3 | Claude Code |
| `tools/scripts/check_translations.py`, `check_asset_licenses.py` | CI checks for translation keys and asset licenses | CI/CD pipelines | Backlog issue 3 | Claude Code |
| `game/addons/gdUnit4/`, `game/tests/` | Test framework and first test | Technology stack | Backlog issue 4 | Claude Code |
| `game/model/` | Aquarium model, commands, EventBus | Game architecture | Backlog issue 5 | Claude Code |
| `game/model/` serializer | Save and load JSON | Game architecture | Backlog issue 6 | Claude Code |
| `game/localization/messages.pot`, `en.po`, `hu.po` | Translations | Unicode, localization and fonts | Backlog issue 7 | Claude Code; you review Hungarian |
| `game/ui/` theme and fonts, glyph test scene | Font stack and fallbacks | Unicode, localization and fonts | Backlog issue 8 | Claude Code |
| `tools/blender/generate_fish.py` | First asset generator | Art and asset pipeline | Backlog issue 10 | Claude Code |
| `game/catalog/` schema scripts and `.tres` data | Species and item definitions | Game architecture | Backlog issue 23 and the content issues | Claude Code |
| `.github/workflows/release.yml` | itch.io releases | CI/CD pipelines | Backlog issue 40 | Claude Code |
| `.github/workflows/visual.yml` | Visual regression screenshots | CI/CD pipelines | Backlog issue 42 | Claude Code |

Git does not store empty folders, so the skeleton places an empty `.gitkeep` file in each folder that has no content yet.

### Outside the repository (your machine only)

| Path or setting | Purpose | Created in |
| --- | --- | --- |
| `C:\Tools\Godot\godot.exe`, `godot_console.exe` | Pinned Godot editor | Windows setup, Step 5 |
| `%APPDATA%\Godot\export_templates\` | Export templates for local builds | Windows setup, Step 5 |
| User `Path` entries for Godot, Blender and Claude Code | Command line access | Windows setup, Steps 5, 6 and 9 |
| `$HOME\env-check.txt` | Tool versions for the first issue | Windows setup, Step 11 |
| `C:\Dev\cozy-aquarium\` | Local clone of the repository | GitHub repository setup, step 1 |

### Changing these files later

After creation, every file changes only through an issue and a pull request. `CLAUDE.md`, the CI workflows and the pinned Godot version change only when an issue explicitly asks for it, as `CLAUDE.md` itself states.

## Day-to-day workflow

Every change follows the same path from idea to merge, and you appear at exactly three points: deciding what to build, playtesting the result, and merging it.

&#91;embedded content: issue lifecycle · 8 steps, one rework loop\]

A failed CI run, a review with requested changes, or a failed playtest all send the pull request back to the developer AI on the same branch; the board card returns to AI in progress.

### A typical session

1. **Pick work:** open the board, move the top Ready issue to AI in progress.
2. **Start Claude Code** in the repository: `claude`, then *"Work on issue #23. Read CLAUDE.md and the issue, plan first, then implement with tests and open a pull request."* Use `/model` to choose Opus 5.5 for planning-heavy issues.
3. **Approve the plan:** Claude Code shows its plan before changing files. Check it against the acceptance criteria; correct it if needed.
4. **Let it work:** it creates the branch, writes code and tests, runs lint and tests locally, commits, pushes and opens the pull request.
5. **Review:** start a fresh Claude Code session with Opus 5.5: *"Review PR #57 against issue #23 and CLAUDE.md. List problems by severity."* Fixes go back to the developer session.
6. **Playtest:** download the Windows build from the pull request's CI run, unzip, play, tick the acceptance criteria.
7. **Merge:** squash-merge on GitHub. The card moves to Done automatically.

### Habits that keep AI output good

- One issue per session; start a new session for the next issue so old context does not leak in.
- When the AI repeats the same mistake twice, add a rule to `CLAUDE.md` through a small chore pull request.
- Every bug found in playtesting becomes a `type:bug` issue with steps to reproduce, never a quick fix in chat.
- Once a week, ask the AI BA to review the backlog for duplicates, gaps and outdated stories.
- Before each milestone, the AI architect reviews the code for drift from this document and files `type:chore` issues.

## Initial backlog

The first backlog has 10 epics and 42 items across four milestones; M1 "First playable" is the first build worth showing anyone: one furnished tank, a working camera, placing decorations, and three species swimming.

| Milestone | Goal | Exit criterion |
| --- | --- | --- |
| M0 Foundation | Everything runs end to end with no gameplay | An empty scene builds in CI, tests run, language switches, a save file round-trips |
| M1 First playable (v0.1) | The core cozy loop in one tank | You can arrange a tank, add 3 species, orbit the camera, save and reload |
| M2 Content and photo mode (v0.2) | Variety and sharing | 12–15 species, 10 plants, 15 decorations, 5 substrates, photo mode with underwater shots |
| M3 Release 1.0 | Ready for itch.io | Audio, performance target met, Hungarian complete, release pipeline live |

The AI BA turns each row into a full issue (story, acceptance criteria, out of scope, test notes) before it moves to Ready. Sizes are estimates for planning; anything that turns out L is split.

| ID | Item | Epic | Milestone | Type | Size | Priority |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Verify development environment and record versions | E0 Foundation | M0 | chore | S | P0 |
| 2 | Repository skeleton, config files, CLAUDE.md, empty Godot project | E0 Foundation | M0 | chore | S | P0 |
| 3 | CI: lint, headless tests, Windows build artifact | E0 Foundation | M0 | chore | M | P0 |
| 4 | GdUnit4 installed with a first passing test | E0 Foundation | M0 | test | S | P0 |
| 5 | Aquarium model, command framework with undo/redo, EventBus | E0 Foundation | M0 | feature | M | P0 |
| 6 | Save and load model as UTF-8 JSON with format version | E0 Foundation | M0 | feature | M | P0 |
| 7 | Localization pipeline: keys, en.po, hu.po, language setting, live switch | E0 Foundation | M0 | feature | M | P0 |
| 8 | Font stack with Noto fallbacks and glyph test scene | E0 Foundation | M0 | feature | S | P0 |
| 9 | Settings system (language, audio, graphics, controls) | E0 Foundation | M0 | feature | S | P1 |
| 10 | Blender pipeline proof: one generated fish exported and imported | E0 Foundation | M0 | asset | M | P0 |
| 11 | Cozy room corner with cabinet and medium tank | E1 Tank and room | M1 | feature | M | P0 |
| 12 | Water and glass shading, basic caustics | E1 Tank and room | M1 | feature | M | P0 |
| 13 | Choose tank size: small, medium, large | E1 Tank and room | M1 | feature | S | P1 |
| 14 | Orbit camera with elevation limits and cabinet floor | E2 Camera | M1 | feature | M | P0 |
| 15 | Camera zoom, pan, collision, reset to front view | E2 Camera | M1 | feature | M | P0 |
| 16 | Automated camera limit tests | E2 Camera | M1 | test | S | P0 |
| 17 | Substrate types with colour selection | E3 Substrate | M1 | feature | M | P0 |
| 18 | Sculpt substrate slopes | E3 Substrate | M2 | feature | M | P2 |
| 19 | Catalog browser UI (categories, thumbnails, search) | E4 Placement | M1 | feature | M | P0 |
| 20 | Place, move and rotate items with ghost preview and snapping | E4 Placement | M1 | feature | M | P0 |
| 21 | Delete and recolour items; undo/redo in UI | E4 Placement | M1 | feature | S | P0 |
| 22 | Placement validity: overlap and tank bounds | E4 Placement | M1 | feature | S | P1 |
| 23 | Fish catalog with 3 species and swim shader | E5 Fish | M1 | feature | M | P0 |
| 24 | Fish behaviour: schooling, depth zones, obstacle avoidance | E5 Fish | M1 | feature | M | P0 |
| 25 | Add and remove fish UI with species info card | E5 Fish | M1 | feature | S | P0 |
| 26 | Feeding: drop food, fish seek it | E5 Fish | M2 | feature | M | P1 |
| 27 | Main menu, save slots, autosave | E6 Saves and menus | M1 | feature | M | P0 |
| 28 | M1 manual playtest checklist and run | E6 Saves and menus | M1 | test | S | P0 |
| 29 | Parametric fish generator: 12–15 species with real Mode 2 data | E7 Content | M2 | asset | L (split per 4 species) | P0 |
| 30 | Plant generator: 10 plants with sway shader | E7 Content | M2 | asset | M | P0 |
| 31 | Decorations: 15 rocks, wood and ornaments | E7 Content | M2 | asset | M | P0 |
| 32 | Five substrate types (sand, gravel, pebbles, black sand, coloured gravel) | E7 Content | M2 | asset | S | P1 |
| 33 | Photo mode: free camera, hide UI, save PNG | E8 Photo mode | M2 | feature | M | P1 |
| 34 | Photo mode: enter tank from the top, underwater effect | E8 Photo mode | M2 | feature | M | P1 |
| 35 | Photo tools: pause fish, depth of field, filters, frame overlay | E8 Photo mode | M2 | feature | M | P2 |
| 36 | Photo mode collision tests | E8 Photo mode | M2 | test | S | P1 |
| 37 | Ambient audio and music with volume settings | E9 Polish and release | M3 | feature | M | P1 |
| 38 | Performance pass: 60 fish, 100 items, 60 FPS | E9 Polish and release | M3 | test | M | P0 |
| 39 | Pseudo-localization and Hungarian review pass | E9 Polish and release | M3 | test | S | P0 |
| 40 | Release workflow to itch.io (Windows, Linux, macOS) | E9 Polish and release | M3 | chore | M | P0 |
| 41 | itch.io page: description, screenshots from photo mode | E9 Polish and release | M3 | chore | S | P1 |
| 42 | Visual regression screenshots in CI | E9 Polish and release | M3 | chore | M | P2 |

Once the repository exists, Claude Code can create all of these as issues, sub-issues and milestones with `gh` in one session, from this table.

## Risks, open questions and next steps

The biggest risks are visual quality and AI drift, both handled by early proofs and strict review; the next step is installing the environment and running issues 1 and 2.

### Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Generated fish and plants look crude | High: the cozy feel depends on looks | Issue 10 proves the Blender pipeline early; CC0 packs and a human artist remain fallbacks |
| AI code drifts from the architecture over time | High: harder changes, more bugs | `CLAUDE.md` rules, small issues, AI review on every pull request, your playtest before merge |
| Water and underwater rendering is hard to get right | Medium | Start simple (tint, fog, caustics); improve in later issues; escalate shader work to Opus 5.5 |
| Claude plan usage limits slow down work | Medium | Sonnet 5.5 for routine work, Opus 5.5 only where it pays off; batch small chores for Haiku 5.5 |
| GDScript has less AI training data than C# | Low to medium | Static typing, linting and tests catch mistakes early |
| Godot updates break the project | Low | Pinned version; upgrades only through an ADR and a full test run |
| Asset license mistakes | Medium for a public release | License log enforced by CI |
| CJK fonts make the download large | Low for PC | Compressed fonts; revisit if the size becomes a complaint |

### Open questions for the product owner

- [ ] Confirm or change the "Proposed" decisions D3 and D13–D18.
- [ ] Public or private repository at the start?
- [ ] Should fish have names and personalities in Mode 1, or only species?
- [ ] Any reference games or pictures that capture the look you want?
- [ ] Target date for M1 First playable?

### Next steps

1. Work through the Windows 11 setup guide, steps 0–11.
2. Create the repository and the board.
3. In parallel with steps 1–2, set up the "Aquarium – BA" project in claude.ai and draft the vision and glossary with it.
4. Let Claude Code run issue 2 (repository skeleton), then issue 3 (CI).
5. Let Claude Code create the remaining backlog issues from the backlog table.
6. Start M0 Foundation.
