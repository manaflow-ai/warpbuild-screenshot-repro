# Contributing

This repository is a small, maintained diagnostic for a provider-specific
macOS screenshot issue. Contributions are accepted through pull requests.

The repository does not currently require a CLA. The maintainers will decide
whether a CLA and a software license are appropriate before accepting code
outside the diagnostic scope. Do not add a CLA check or change the license in
an unreviewed pull request.

Security-sensitive files require review from both maintainers:

- [@austinywang](https://github.com/austinywang)
- [@azooz2003-bit](https://github.com/azooz2003-bit)

Before opening a pull request, run:

```bash
bash -n probe.sh
python3 -m unittest discover -s tests -v
```

Do not add `pull_request` execution on the WarpBuild or Blacksmith runners.
Probe jobs must keep an empty or read-only permission set, and must not expose
secrets. Keep third-party dependencies pinned by version and hash.
