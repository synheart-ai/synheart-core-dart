# Contributing

Thank you for taking the time to look at Synheart Core (Flutter). This document explains
how this repository accepts contributions.

## TL;DR

- **Issues are welcome.** Bug reports, feature requests, and questions help us
  prioritize and improve the SDK.
- **Pull requests are not accepted at this time.** Any externally submitted PR
  will be closed without review.
- **Security reports are not public.** See [SECURITY.md](SECURITY.md) for the
  private disclosure path.

## Why we do not accept pull requests

This SDK is developed in an internal monorepo and mirrored to GitHub for
transparency. The public repository is source-available so anyone can read,
audit, and learn from the code that runs on their device — but the project is
not yet ready to absorb external code contributions.

Specifically:

- **Spec stability.** The Synheart HSI is still evolving against internal RFCs.
  Accepting external changes before the spec settles would create churn for
  everyone, including contributors.
- **Review capacity.** A small team maintains this code. We would rather
  invest review time in stabilizing the HSI than in bouncing PRs back for
  rework.
- **Provenance.** We avoid contributor licensing overhead (CLAs, copyright
  assignment) by sourcing all code internally.

This is a temporary policy and may relax once the HSI is stable. Until then,
issues are the supported way to influence the direction of the SDK.

## Filing an issue

Before opening an issue, please:

1. Search [existing issues](https://github.com/synheart-ai/synheart-core-flutter/issues) to avoid
   duplicates.
2. Use the appropriate issue template (bug report or feature request).
3. Include enough detail for us to reproduce or evaluate the request — version,
   platform, minimal reproduction code, and what you expected vs. observed.

Issues that are well scoped and reproducible get triaged faster.

## What about typo / docs fixes?

Even small documentation fixes are best filed as an issue. Quote the section,
suggest the change, and we will roll it into the next internal sync. This
keeps a single contribution path and avoids ambiguity about what is in scope.

## Code of conduct

Be respectful in issues and discussions. We reserve the right to close issues
that are abusive, off-topic, or used to spam the tracker.
