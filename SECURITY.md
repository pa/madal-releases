# Security

Madal's whole claim is that the server can't read what you share. If you find a way around that,
or any other security problem, please report it privately.

How the encryption, sharing and sandbox work, and the limits of the design:
[madal.facets.cloud/security](https://madal.facets.cloud/security).

## Reporting

Use GitHub's private vulnerability reporting: the **Security** tab of this repository, then
**Report a vulnerability**. Please don't open a public issue for security problems.

Include what you found, how to reproduce it, and what an attacker gains. A proof of concept helps.

## In scope

- Anything that lets the server, or anyone between you and it, read artifact content or keys.
- Ways for an artifact's own HTML to escape its sandbox, reach the viewer page, or read a key.
- Bypassing sharing: opening an artifact that wasn't shared with you, keeping access after being
  removed from a team, or acting as another account.
- Weaknesses in the formats described on the [security page](https://madal.facets.cloud/security).

## Known limits

These are documented trade-offs, not vulnerabilities:

- The viewer's JavaScript is served by the Madal server, which therefore has to be trusted not to
  serve code that reads keys.
- Public pages are plaintext on purpose.
- The first share with a person trusts the server to provide their real public key.
- Anyone holding a full link can open a link-shared artifact.
