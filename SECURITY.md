# Security Policy

## Reporting a vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Instead, use GitHub's private vulnerability reporting: go to the repository's
**Security** tab and click **Report a vulnerability** (or open
`https://github.com/KasparWe/kanso/security/advisories/new`). This opens a
private security advisory that only the maintainer can see.

Include as much of the following as you can:

- A description of the vulnerability and its impact
- Steps to reproduce, or a proof of concept
- The app version (or commit) and iOS version you tested against

You should get an initial response within a week. Please give the maintainer a
reasonable window to ship a fix before disclosing publicly.

## Scope

This repository contains only the iOS client, and it is a fork of
[Hermex](https://github.com/uzairansaruzi/hermex). Route reports to the project that owns
the code:

- **Present in upstream Hermex too** → report to
  [uzairansaruzi/hermex](https://github.com/uzairansaruzi/hermex/security/advisories/new),
  since a fix there benefits every user. Feel free to tell us as well.
- **Specific to this fork** (Kanso-only code, its app identity, or its persistence) →
  report here.
- **In the [hermes-webui](https://github.com/nesquena/hermes-webui) server** → report to
  that project instead.

Issues with how *this app* stores credentials, talks to the server, or handles untrusted
server responses are in scope here.
