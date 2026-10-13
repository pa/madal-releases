<div align="center">

# madal

[![Release](https://img.shields.io/github/v/release/pa/madal-releases?style=flat-square&logo=github)](https://github.com/pa/madal-releases/releases)
[![License: free to use](https://img.shields.io/badge/license-free%20to%20use-blue?style=flat-square)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-blue?style=flat-square)](https://github.com/pa/madal-releases/releases)
[![End-to-end encrypted](https://img.shields.io/badge/end--to--end-encrypted-e8411b?style=flat-square)](docs/DESIGN.md)
[![Stars](https://img.shields.io/github/stars/pa/madal-releases?style=flat-square)](https://github.com/pa/madal-releases/stargazers)

**Share what your AI makes. Even we can't read it.**

Madal turns the HTML and Markdown your coding agent writes into a link.<br>
It's encrypted on your machine, and the key never reaches our server.

[Watch the demo](https://madal.facets.cloud/#demo) · [Install](#install) · [Quick start](#quick-start) · [Sharing](#sharing-with-people-and-teams) · [How it works](#how-the-encryption-works) · [Security](SECURITY.md) · [Report a problem](#report-a-problem)

</div>

A 90-second demo plays live on [the home page](https://madal.facets.cloud/#demo), where you can open the
dashboard it publishes. The same cut is in [docs/madal-demo.mp4](docs/madal-demo.mp4).

---

<div align="center">

## Install

</div>

```bash
curl -fsSL https://madal.facets.cloud/install.sh | sh
```

The script downloads the release for your OS and CPU, checks its SHA-256 against the release's
`checksums.txt`, and installs `madal` into `~/.local/bin`. Pin a version with
`MADAL_VERSION=v0.1.1`, or pick another folder with `MADAL_INSTALL_DIR`.

On Windows, download the zip from [Releases](https://github.com/pa/madal-releases/releases).

To upgrade later:

```bash
madal upgrade           # also refreshes the agent skill, which ships inside the binary
madal upgrade --check   # only say whether a newer release exists
```

Every release is built by GitHub Actions from a tagged commit. To check a download yourself,
compare it with the release's `checksums.txt`:

```bash
sha256sum --check --ignore-missing checksums.txt   # macOS: shasum -a 256 --check --ignore-missing
```

---

<div align="center">

## Quick start

</div>

```bash
madal login                     # sign in, set up sharing, teach your agents to use madal
madal publish report.html       # signed in: a link only you can open
madal publish report.html --link  # a link anyone can open; the key is the part after #
```

`madal login` opens your browser. You sign in with Google, GitHub or an email link. The first time, you
choose a master password, and madal makes a Secret Key and shows it in an **Emergency Kit** to save.
Together they encrypt your sharing keys. After that each browser and machine remembers the Secret
Key, so you only type your master password. Nobody can recover either one. Login also installs a `SKILL.md` into the agents on your machine,
so Claude Code, Codex, Cursor or Antigravity can publish for you.

Signed in, what you publish is private to you, like a new document: the link carries no key and
opens wherever you're signed in. Add `--link` to make a link anyone can open, or `--to` to share
with people by name. You can skip `madal login` for quick, anonymous links. They expire after 7
days.

```bash
madal publish notes.md                          # Markdown is rendered on your machine
madal publish draft.html --password             # the link alone isn't enough
madal publish draft.html --expires 7d --max-opens 3
madal update <link-or-id> report.html           # new version, same link
madal list
madal get <link> -o copy.html
madal get <link> --version 2 -o v2.html     # an earlier version
madal delete <link-or-id>
```

---

<div align="center">

## Sharing with people and teams

</div>

Share by name and the link carries no key at all. Only the people you chose can open it, and a
forwarded link opens nothing.

```bash
madal publish plan.md --to alice@example.com --to team:design
madal share <link-or-id> --with bob@example.com
madal share <link-or-id> --remove bob@example.com
madal share <link-or-id> --access link          # or back to: --access only-people

madal team create design
madal team add design carol@example.com
madal team remove design carol@example.com      # rotates the team key
```

You can share with anyone's email. If they don't use Madal yet they're invited: send them the
link, and the share completes once they sign up and your `madal` next runs.

The first time you share with someone, madal shows their **key fingerprint**. Compare it with what
`madal whoami` shows them, over a channel you trust, to be sure the server handed you their real
key. If their key ever changes, madal stops and tells you the new fingerprint.

### Your account

`madal account delete` (or **Delete my account** on the keys page) deletes everything: what you
published, what you shared and what was shared with you, your teams or your place in them, your
keys, every sign-in and the account itself. You confirm by typing your email.

Lost your master password or Secret Key? Nothing encrypted can be opened without both, by you or by
madal, so **Start from scratch** on the keys page deletes your account and everything in it. Then you
sign in again with the same email and start fresh.

On a new or reset machine, `madal login` and your master password (plus the Secret Key from your
Emergency Kit, once) bring everything back: `madal list` shows your links and titles again.
`madal logout` keeps only what the server can't rebuild; `madal logout --forget` removes everything.

---

<div align="center">

## How the encryption works

</div>

| What | How it's protected |
|---|---|
| **Content** | A random 256-bit key per artifact, AES-256-GCM, bound to the artifact id and version so versions can't be swapped or rolled back |
| **Links** | The key rides after the `#`, which browsers never send to a server. An optional password is mixed in with PBKDF2-SHA256 and HKDF |
| **People** | The key is wrapped to each person's P-256 public key (ECDH, HKDF, AES-GCM) and stored as a grant the server can't open. Remove someone and the next update uses a new key, so the old one opens nothing published after that |
| **Teams** | The key is wrapped to a team key. Every change to the team key is signed by an admin and chained to the one before, and it's rotated when someone leaves |
| **Your keys** | Kept in a vault encrypted on your device with your master password (PBKDF2-SHA256, 600,000 iterations) and a 128-bit Secret Key that never leaves your devices, before it's stored on the server. A copy of the server's data can't be opened by guessing your password |
| **Viewing** | Artifacts render in a sandboxed frame on a separate domain, away from your session and keys |

Exact formats are in [docs/DESIGN.md](docs/DESIGN.md).

### What it can't protect against

- Anyone with a full link can read a link artifact. Use `--to` or a password for anything that
  might travel further than you intend.
- Public pages (`--public`) are plaintext by design, so links unfurl in chat apps.
- The viewer's JavaScript is served by the Madal server, which could in principle serve code that
  reads keys. A verifier extension is planned.
- The first time you share with someone, you trust the server to hand you their real key, unless
  you compare fingerprints with them. After that your devices remember it and stop if it changes.

---

<div align="center">

## Report a problem

</div>

```bash
madal report -m "what went wrong
how you got around it"
```

It opens a prefilled issue on this repository. Link keys, tokens, emails and your home path are
removed first, and nothing is filed until you review it and click Submit. Agents using the skill
do this on their own when something cost them a retry.

Report security issues privately instead: see [SECURITY.md](SECURITY.md).

---

<div align="center">

Free to use. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).

</div>
