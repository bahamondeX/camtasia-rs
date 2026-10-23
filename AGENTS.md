# AGENTS.md — Camtasia REA Project

## Mission

Build a functional, independently implemented, AI-native macOS video editor inspired by Camtasia.

Use REA MCP, Hopper, and black-box experiments to investigate observable Camtasia workflows, then reproduce useful functionality using Rust and Swift.

The product must be real, testable, maintainable, and automation-first.

## Priorities

1. Correct, working software.
2. Fast end-to-end delivery.
3. Readable, idiomatic code.
4. Efficient token and tool usage.
5. Resource efficiency on Apple Silicon.
6. Additional feature coverage.

Never optimize token usage at the expense of correctness.

## Technology

- Rust: timeline, project model, editing commands, persistence, automation.
- SwiftUI/AppKit: native macOS interface.
- AVFoundation: playback, composition, media export.
- ScreenCaptureKit: screen/audio recording.
- VideoToolbox: hardware encoding when appropriate.
- UniFFI or minimal C ABI: Rust/Swift interoperability.
- MCP: future Rust server sharing the editing command API.

Prefer native macOS APIs and mature libraries over custom media implementations.

Use simple architecture. Avoid unnecessary crates, abstractions, and services.

## Reverse Engineering

REA MCP is the primary investigation tool. Hopper provides binary inspection when available.

For each feature:

1. Define the exact behavior to reproduce.
2. Inspect Camtasia through targeted REA queries.
3. Perform black-box experiments when useful.
4. Identify relevant functions, symbols, APIs, or data formats.
5. Record evidence and uncertainty.
6. Implement an independent equivalent.
7. Validate observable behavior.

Search imports and symbols before requesting decompilation.

Analyze only relevant functions and call relationships.

Never dump complete binaries or indiscriminately decompile entire modules.

Keep large raw REA results in local files and retrieve specific portions when needed.

REA findings must distinguish:
- Verified evidence.
- Observed behavior.
- Hypotheses.
- Implementation decisions.

If reverse engineering is unproductive, use documented APIs and independent implementation rather than blocking progress.

## Architecture

Keep responsibilities separate:

- `core`: editing commands and domain types.
- `timeline`: tracks, clips, timestamps, edits.
- `project`: serialization and persistence.
- `media`: media metadata and asset management.
- `desktop`: Swift user interface and macOS adapters.
- `automation`: typed commands consumed by UI and future MCP server.

Start with a minimal workspace and introduce additional crates only when justified.

Rust must own project state and editing semantics.

Swift must own native UI behavior and Apple media-framework integration.

Keep FFI narrow, explicit, and safe.

Use integer or rational time values internally. Avoid floating-point accumulation for timeline positions.

Do not implement rendering codecs or capture pipelines from scratch.

## Code Quality

Write idiomatic, production-oriented Rust and Swift.

- Small cohesive modules.
- Descriptive names.
- Explicit error handling.
- No unnecessary cleverness.
- No premature generic frameworks.
- No placeholder implementations presented as complete.
- No duplicated business logic.
- No broad `unwrap()` usage in production Rust paths.
- Comments only where behavior is not obvious.
- Format code with standard tools.

Prefer straightforward code over complicated abstractions.

## Development Workflow

Work in vertical slices.

For each slice:

1. Investigate.
2. Implement.
3. Compile.
4. Test.
5. Fix.
6. Commit when verified.

Do not spend an entire session planning or generating documentation.

Do not add speculative features.

Use the simplest robust implementation that satisfies the current acceptance criteria.

Keep the application runnable throughout development.

## Token and Context Efficiency

- Read only relevant files and sections.
- Prefer `rg`, targeted `sed`, and bounded output.
- Never paste complete binaries, decompilation dumps, or massive logs into context.
- Batch related tool operations when appropriate.
- Do not repeatedly investigate verified findings.
- Save durable findings to files.
- Summarize evidence before changing subsystems.
- Avoid repeatedly rewriting unchanged code.
- Avoid unnecessary explanations and progress narration.
- Use focused tests before broader regression testing.
- Do not artificially limit investigation when more evidence is necessary.

Use large tool outputs only when they materially improve understanding.

Prefer concise tool results over arbitrary truncation of important evidence.

## Testing

Use synthetic fixtures and temporary projects.

Test timeline operations independently of the UI.

Validate exported files with `ffprobe` or AVFoundation.

Check:
- Duration.
- Resolution.
- Frame rate.
- Audio/video streams.
- Playability.
- Timeline correctness.
- Project save/reopen behavior.

Never claim equivalence without evidence.

## Apple Silicon Constraints

Target `aarch64-apple-darwin`.

Optimize for 8 GB unified memory.

- Prefer hardware-accelerated video processing.
- Avoid unbounded buffering.
- Use lazy thumbnails.
- Cache only what is necessary.
- Avoid unnecessary video-frame copying.
- Keep parallel builds and background workers reasonable.

Measure performance before making optimization claims.

## Automation-First Design

Every editing action should eventually be available through a stable typed command interface.

The GUI and future MCP tools must use the same underlying Rust commands.

Example operations:

- `project.create`
- `project.open`
- `project.save`
- `media.import`
- `timeline.add_clip`
- `timeline.trim_clip`
- `timeline.split_clip`
- `timeline.move_clip`
- `timeline.remove_clip`
- `preview.seek`
- `export.mp4`

Do not build the full MCP server before the first working editor slice.

## Documentation

Keep documentation minimal and useful.

Maintain:

- `docs/rea-findings.md`
- `docs/architecture.md`
- `docs/equivalence-matrix.md`
- `README.md`

Update only affected sections.

Avoid recording verbose session transcripts.

## Execution Autonomy

Proceed without asking for routine technical decisions.

Ask only when blocked by missing permissions, credentials, required user interaction, destructive operations, or major ambiguity.

Do not change machine-wide settings or install privileged components without approval.

Do not modify the original Camtasia application.

If an approach fails, diagnose briefly, select a viable alternative, and continue.

Never claim tests, compilation, REA inspection, or GUI verification happened unless they actually occurred.

## Reporting

Keep progress reports short.

Report:
- Verified milestone.
- Actual tests.
- Important blocker.
- Next implementation step.

Keep the final response concise and include exact build/run commands.

## Definition of Done: First Milestone

A user can:

1. Launch the native macOS app.
2. Import an MP4.
3. Preview it.
4. Add it to a timeline.
5. Trim the clip.
6. Export the edited timeline to MP4.
7. Play the exported result.

The Rust timeline engine has automated tests, and the application builds successfully.

No UI-only simulations or fabricated results count as completion.