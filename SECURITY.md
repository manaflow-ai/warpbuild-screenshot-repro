# Security policy

This public repository runs diagnostic commands on external macOS runners and
publishes screenshots. It has no application secrets and no release channel.

Report a vulnerability privately through
[GitHub private vulnerability reporting](https://github.com/manaflow-ai/warpbuild-screenshot-repro/security/advisories/new).
Do not include credentials or private desktop images in a public issue.

The supported security boundary is the protected `main` branch. Probe runs
accept only pushes to that branch and repository dispatches from the two named
maintainers or the repository owner. Pull requests are never executed on the
external runners.

Actions artifacts are retained for 14 days and then deleted by GitHub. The
probe strips PNG metadata before upload, but visible screen content is not
automatically redacted. Review each image before external distribution.

Security-sensitive changes require review from both:

- [@austinywang](https://github.com/austinywang)
- [@azooz2003-bit](https://github.com/azooz2003-bit)
