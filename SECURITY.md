# Security Policy

## Supported versions

Security fixes are prioritized for the latest release and the default branch. Older
releases may receive fixes where practical.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/remyhuang03/remya-settings/security/advisories/new).
Keep vulnerability details out of issues and pull requests. Include the affected version
or commit, environment, expected security boundary, observed impact, and sanitized
evidence. Remove credentials, private data, and sensitive logs.

Coordinate disclosure with the maintainer so they can verify the report and prepare a
fix.

## Scope

Remy'a Settings is a desktop client of Remy'a Core. Report boundary violations in how it
presents and initiates changes, handles user confirmation or conflicts, or processes
camera preview and settings data. Reports about authorization or system writes
implemented by the daemon belong with Remy'a Core.

Report standalone dependency vulnerabilities to the upstream project. Report exposure
specific to this application's integration here.
