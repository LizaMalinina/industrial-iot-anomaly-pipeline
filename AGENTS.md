# AGENTS.md

Operating notes for AI coding assistants (Claude Code, GitHub Copilot, Cursor, etc.) working on this repo.

## What this is

A proof-of-concept IoT product. The repo is in early stages — architecture, language choices, and cloud platform are still being defined. Expect rapid iteration and frequent pivots.

## Commands

_To be defined as the project takes shape._ Once a build/test toolchain is chosen, document the commands here (install, test, lint, deploy, etc.).

## Test-driven development — the working norm

This repo follows TDD for non-trivial logic changes:

1. **Write the failing test first.** Run the test suite and confirm the new test **fails** (red).
2. **Implement the smallest change that makes the test green.**
3. **Refactor with the tests as a safety net.**
4. **All tests must pass locally before commit.**

When TDD isn't the right tool:

- Hardware bringup / one-off flashing scripts.
- Pure wiring / pin-config changes that can only be verified on physical hardware.
- Throwaway prototyping spikes (but promote to TDD once the spike is validated).

## Mandatory workflow: TDD → commit → push

Every change — feature, bug fix, refactor — **must** follow this exact sequence. No exceptions, no shortcuts:

1. **Write the failing test first.** Confirm it fails.
2. **Implement the fix/feature.** Confirm all tests pass.
3. **Refactor if needed** with tests green.
4. **Commit and push** in the same session. Do not leave committed-but-not-pushed changes.

## Pushing to this repo

**The repo is a personal project under [`LizaMalinina`](https://github.com/LizaMalinina).** On the maintainer's Windows machine:

- `git config --get user.email` must return `jelizaveta.malinina@gmail.com` (the personal account email), NOT the Microsoft work email. Verify before the first commit of a session:
  ```powershell
  git config user.email "jelizaveta.malinina@gmail.com"
  git config user.name "LizaMalinina"
  ```
- The shell has a `GITHUB_TOKEN` env var that points at the Microsoft work account. This token wins over the gh CLI's keyring-stored personal token, so a naked `git push` over HTTPS will try to authenticate as the work account against the personal repo and 404 with "Repository not found."
- Workaround for `git push` in this repo, in PowerShell:
  ```powershell
  $env:GITHUB_TOKEN=$null
  gh auth switch --user LizaMalinina   # only needed if active account isn't LizaMalinina
  git -c credential.helper= -c credential.helper="!gh auth git-credential" push
  ```
  The empty `credential.helper=` resets the chain so the `!gh auth git-credential` becomes the only one consulted, which uses the gh-CLI keyring token for the active gh user (LizaMalinina after the switch).
- `gh auth status` shows which account is active. If both `lizamalinina_microsoft` and `LizaMalinina` are logged in (typical), the GITHUB_TOKEN env var forces the former active for tools like `gh pr create` until you unset it.
- **Never commit under the work email.** It pollutes git history with a Microsoft identity on a personal-account repo.

## What NOT to do

- Don't over-engineer infrastructure before the POC validates the core idea.
- Don't commit secrets, keys, or certificates into source code — use environment variables or a secrets manager.
- Don't skip tests for "just a quick change" — quick changes break things too.

## When in doubt

Ask. This is a POC — speed matters, but so does not painting ourselves into a corner. Document design decisions as they're made so future-you (and future-agents) can understand the rationale.
