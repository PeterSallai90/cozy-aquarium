# ADR 0002: Visual style – stylized, cozy, simple shapes with rich lighting

- Status: Accepted
- Date: 2026-11-01
- Decision log reference: D5 in docs/architecture.md
- Issue: #60 (owner decisions Q1 to Q9 and the follow-up decisions, logged as "Owner decision:"
  comments)

## Context

D5 originally fixed the visual style as a stylized, minimal-geometry look. The asset rules that
followed from it (flat or faceted shading, one palette atlas and no other textures, small triangle
budgets such as 300 to 800 triangles per fish) produce a plain faceted look. Those budgets were a
style limit, not a performance limit: a full tank stays far below what the Forward+ renderer handles
on a mid-range PC.

The product owner wants a higher quality bar: a stylized, cozy tank whose polish comes mostly from
lighting and shaders (caustics, depth tint, in-tank fog, bloom, light transmission through fins and
leaves), comparable in polish, not in look, to games such as Sea of Thieves or Abzû. Assets are still
generated mainly by Blender Python scripts, so every rule must be achievable procedurally.

The art style rules were also split between CLAUDE.md and docs/architecture.md, while the
architecture guide already pointed to a docs/art-style.md that did not exist.

## Decision

- D5 reads: **Stylized, cozy, simple shapes with rich lighting**.
- docs/art-style.md is the single source of truth for art style rules: shading, triangle budgets,
  colouring, rendering and look, and the quality bar. CLAUDE.md and docs/architecture.md only point
  to it.
- The values in docs/art-style.md are the owner decisions on issue #60. In short: smooth normals on
  organic shapes and hard edges only on rocks and furniture; higher triangle budgets that are upper
  limits; a shared palette atlas plus small gradient or mask textures and procedural noise, no
  photographic textures; required and optional rendering effects; a mood board and a golden scene as
  the quality bar.
- D18 (60 fish and 100 decor items at 60 FPS on a mid-range PC) wins over the triangle budgets. The
  budgets are confirmed by the performance pass, #49.
- Vertex-shader swimming and no skeletal rigs in the MVP stay unchanged.

ADR 0001 is not edited: it records the engine decision and the style wording as they were at that
time. docs/art-style.md notes that it refines that wording.

## Alternatives considered

- **Keep the original D5 wording and rules, only fix the documentation pointers** (option C on #60):
  cheapest, but keeps the plain faceted look the owner rejected.
- **Accept the starting proposal as written** (option A): close to the decision, but it left the
  per-effect classification, hero limits and performance guard open.

## Consequences

- Asset generators (#21, #40, #41) follow docs/art-style.md; the old budgets no longer apply.
- Each required rendering effect becomes its own area:render issue, which fixes the numeric
  parameter ranges.
- Triangle counts rise, so the performance pass (#49) must record the worst-case triangle total at
  the D18 load and confirm the budgets. If a budget breaks D18, the budget is lowered.
- Changes to the style rules are made in docs/art-style.md; a change to D5 itself needs a new ADR.
