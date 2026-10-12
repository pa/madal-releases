# Madal v0 design

Madal publishes HTML and Markdown artifacts from any coding agent to a link. The CLI encrypts
everything before upload. The server stores ciphertext and never sees a key. This doc pins the
parts that are expensive to change later: the envelope format, the URL shape, the two origins and
the data model.

## Pieces

- `madal` is a single Go binary. It does all crypto locally, talks to the API, and keeps the API token
  in the OS keychain.
- `madald` is the server, one Go binary that runs in two modes from one image. `MODE=app` serves
  the API, the viewer shell and the sign-in pages. `MODE=content` serves only the artifact frame
  and public artifact bodies.
- `skill/SKILL.md` teaches an agent when and how to call the CLI.

## Tiers

**Private tier** (the default for a signed-in publish with sharing keys on the machine). The link
carries no key. The artifact key is wrapped to the owner's account key, and to anyone shared with
by name, so it opens wherever the owner is signed in and unlocked. A forwarded link opens nothing.

**Link tier** (`--link`, or any publish while signed out). The key lives in the URL fragment,
which browsers never send to a server. Anyone with the full link can read it. Anyone without the
fragment gets ciphertext. An optional password adds a second factor: the link alone is not
enough. When the publisher is signed in, the owner also gets a grant, so a link without its
fragment still opens for them, and their other machines can open and update it.

**Public tier.** Plaintext, for signed-in accounts only. The server stores the HTML and serves
Open Graph tags so links unfurl in Slack and on social sites. Public means public: no encryption
claim is made for this tier.

## Envelope format (v1)

```
content key  K   = 32 random bytes (CSPRNG)
link             = https://<app>/a/<id>#<base64url(K)>        (no padding)

no password      EK = K
with password    S  = PBKDF2-SHA256(password, salt16, 600000 iterations, 32 bytes)
                 EK = HKDF-SHA256(ikm = K, salt = S, info = "madal/v1/content", 32 bytes)

AAD              = "madal/v1/" + id + "/" + version
blob             = "MDL1" || nonce(12) || AES-256-GCM(EK, nonce, plaintext, AAD)
plaintext        = JSON {"title", "type": "html"|"markdown", "html"}
```

Decisions and why:

- **Password is HKDF over the fragment key, not a replacement for it.** A password-only key would
  let anyone holding the ciphertext brute-force the password offline. Mixing it with a 256-bit
  random key means a server breach yields nothing, and a leaked link still needs the password.
- **PBKDF2, not Argon2.** The browser decrypts with WebCrypto, which has PBKDF2 and no Argon2.
  600,000 iterations follows the OWASP 2023 figure for PBKDF2-SHA256. The salt and iteration
  count are stored in plaintext next to the artifact. They are not secret.
- **AAD binds the blob to its id and version.** The server cannot serve version 2's blob as
  version 3 or swap one artifact's blob into another's URL without the tag check failing.
- **One key per artifact, fresh nonce per version.** The link stays the same across updates.
  Random 96-bit nonces are safe for far more versions than any artifact will have. A private
  artifact gets a new key after someone loses access (see Revoking), so it can hold several keys,
  one per generation.
- **The title is inside the envelope.** The server learns only the blob size, the owner and
  timestamps.
- **Markdown renders in the CLI** (goldmark) into a full HTML document before encryption. The
  viewer only ever handles HTML, which keeps the browser code small.

The browser mirrors this in `web/app/crypto.js`. `internal/envelope/testdata/vectors.json` holds
vectors produced by the Go code. A Node test decrypts them with the same `crypto.js` the viewer
ships, so a drift between the two implementations fails CI.

## Two origins

Artifact HTML is untrusted code, often agent-written, sometimes hostile. It must never run on the
origin that holds sign-in state or API tokens.

```
app origin      <app-site>.web.app       -> cloudrun "api"      (MODE=app)
content origin  <content-site>.web.app   -> cloudrun "content"  (MODE=content)
```

`web.app` is on the Public Suffix List (checked 2026-10-11), so the two sites are separate
registrable domains. Cookies cannot be shared between them. Safe Browsing can flag one without
the other.

Viewing a link-tier artifact:

1. The browser loads `/a/<id>` on the app origin, a static shell.
2. The shell reads the key from `location.hash`, fetches the blob from `/api/a/<id>/blob`, asks
   for the password if the artifact has one, and decrypts.
3. The shell creates `<iframe sandbox="allow-scripts allow-popups" src="<content>/frame">`.
   Without `allow-same-origin` the frame runs in an opaque origin.
4. The frame page sends `ready`. The shell posts the plaintext HTML to it, and the frame swaps
   it in with `document.open()` / `document.write()`. The key never leaves the shell.

The frame response carries
`Content-Security-Policy: form-action 'none'; frame-ancestors <app origin>; base-uri 'none'` and
nothing that restricts scripts. Agent artifacts load Tailwind and chart libraries from CDNs, and
blocking that would break the main use case. The sandbox already denies cookies, storage,
top-level navigation and access to the parent. `form-action 'none'` stops credential-phishing
forms.

The landing page is the one app page that relaxes the shell's CSP. Its demo runs live with
`@remotion/player`, which injects a style tag and plays `data:` media to start, so `/` adds
`style-src 'unsafe-inline'` and `media-src 'self' data:`. It holds no keys except Try it's
throwaway one. The viewer and the keys page keep the strict policy. The player is built from
`demo/video` (`npm run player`) into `web/app/media/player.js`.

Public artifacts skip the decrypt step. `/p/<id>` on the app origin is a shell with OG tags,
and its iframe points at `<content>/p/<id>/raw`, which serves the HTML directly under the same
CSP plus a `sandbox allow-scripts allow-popups` CSP directive.

## Accounts and tokens

- **Web sign-in.** Google, GitHub or an emailed magic link, through Firebase Authentication with
  a per-app Identity Platform tenant. `GOOGLE_SIGNIN=1` and `GITHUB_SIGNIN=1` show those buttons.
  The sign-in page trades the Firebase ID token for a `__session` cookie, the only cookie
  Firebase Hosting forwards.
- **Only verified emails count.** Sharing finds people by email, so the server trusts an address
  only when Firebase marks it verified. Google and email links verify it; GitHub may not, and
  then the sign-in page sends a confirmation email and waits. Until an account's email is
  verified it can't start a session or set up keys, lookups skip it, and invites to that address
  stay hidden from it. Without this, someone could claim an address they don't own, set up keys,
  and receive the shares meant for its owner once the owner verifies it.
- **One account per email.** If someone who signs in by email link later picks Google or GitHub,
  Firebase refuses the second account. The page emails a sign-in link to that address and, after
  it's opened, offers to add the provider to the existing account. Only the provider's name waits
  in `localStorage`, never a credential.
- **`madal login`.** The CLI starts a loopback listener on `127.0.0.1:<random>`, makes a PKCE
  verifier, and opens `https://<app>/cli/login?port=…&state=…&challenge=…`. The page signs the
  user in, calls `POST /api/cli/codes` with the ID token and the challenge, and redirects to the
  loopback with a one-time code. The CLI exchanges code plus verifier at `POST /api/cli/token`
  for an API token. A code is single-use, expires after 2 minutes, and is useless without the
  verifier.
- **API tokens** are `mdl_` + 32 random bytes, base64url. The server stores SHA-256 hashes only.
  The CLI keeps the token in the OS keychain (`go-keyring`).
- **Anonymous publish** returns an edit token, hashed the same way, so the publisher can update or
  delete without an account.

## Data model

Firestore through its MongoDB API. Blobs go to GCS.

```
users      {_id: uid, email, created_at}
tokens     {_id: sha256(token), uid, created_at, last_used_at, label}
cli_codes  {_id: sha256(code), uid, challenge, expires_at}
artifacts  {_id, owner_uid | null, edit_token_hash | null, tier, latest,
            password: {salt, iterations} | null, title (public only),
            description (public only), key_gen, rotate, first,
            created_at, updated_at, expires_at | null}
versions   {_id: "<id>/<n>", artifact_id, n, size, object, key_gen, created_at}
reports    {_id, artifact_id, reason, key_included, created_at, ip_hash}
limits     {_id: "<scope>/<key>/<window>", count, expires_at}

gs://<bucket>/a/<id>/<n>        link-tier ciphertext or public plaintext
```

Artifact ids are 16 random bytes in base64url (22 chars). Guessing one is not feasible, but an
id alone reveals nothing for the link tier anyway.

## Abuse controls (v0)

- Anonymous artifacts expire after 7 days and are link tier only. An account makes them
  permanent.
- Size caps: 1 MiB per version anonymous, 5 MiB signed in. An artifact keeps its newest 5
  versions (see Older versions), so one artifact holds at most 25 MiB.
- Rate limits in fixed windows stored in `limits`: 10 publishes an hour per IP anonymous,
  60 an hour per account. The client IP comes from `X-Forwarded-For` as set by Firebase Hosting.
- A report button in the viewer chrome. For link-tier artifacts the reporter can tick a box to
  include the key, which is the only way the operator can ever read reported content.
- Expiry is enforced on read. Expired artifacts return 410 and get deleted lazily.

## Sharing with people and teams

Agreed 2026-10-11. A link can leak; a share to a named person or team can't, because its link
carries no key. The artifact is sealed exactly as for the link tier. What changes is how its content
key `K` reaches the reader: instead of riding in the fragment, `K` is wrapped to the reader's public
key and stored on the server as a **grant**. The server holds grants it cannot open.

Tiers after this change: **private** (people and teams only, no key in the link), **link**
(anyone with the full link), **public** (plaintext). Blog posts, when they come, are public.

### Keys

Every account has two P-256 key pairs, generated on the user's device:

- `E`, ECDH, for receiving wrapped keys.
- `S`, ECDSA, for signing team keys.

P-256 rather than X25519 because WebCrypto and Go's standard library both support it everywhere
Madal runs. Public keys are stored on the server in the clear.

### The vault

The private halves of `E` and `S` live on the server inside a **vault**: PKCS#8 bytes sealed with
AES-256-GCM under a random 32-byte vault key `VK`. `VK` is wrapped with a key derived from the
**master password**:

```
password unlock  W = PBKDF2-SHA256(master password, salt16, 600000 iterations, 32 bytes)
wrap             "MDW1" || nonce12 || AES-256-GCM(W, nonce, VK, aad = "madal/v1/vault/" + uid)
```

- Signing in (Google, GitHub or an email link) and unlocking are separate. Sign-in proves who you are to the
  server; only the master password opens the vault. Each browser remembers the unlocked keys
  until "Lock on this browser", so the password is typed once per browser or machine.
- The master password must be at least 12 characters. The server can only check it by stealing
  the vault and guessing offline, which the 600,000 PBKDF2 iterations make slow.
- Forgetting the master password loses the data shared with that account. Nobody can reset it,
  Madal included. The product says so when the vault is created.
- The vault format allows more wraps of `VK` (the server accepts a `passkey` kind). Unlocking
  with a passkey, via the WebAuthn PRF extension, is planned and not offered yet.
- The CLI gets the private keys during `madal login`: it puts a throwaway ECDH public key in the
  sign-in URL, the browser unlocks the vault and wraps the private keys to that key, and the
  wrapped blob comes back through the one-time CLI code. The CLI keeps the keys in the OS keychain.

### Wrapping a key for someone

```
eph            = fresh P-256 key pair
Z              = ECDH(eph.private, recipient.E.public)
W              = HKDF-SHA256(ikm = Z, salt = eph.public || recipient.E.public,
                             info = "madal/v1/wrap/" + context)
wrapped        = "MDK1" || eph.public(65) || nonce12 || AES-256-GCM(W, nonce, K, aad = context)
context        = "<artifact id>/<recipient kind>/<recipient id>"    (grants)
                 "team/<team id>/<member uid>"                       (team keys)
```

The context in both the HKDF info and the AAD means the server can't move a grant to another
artifact or another recipient.

### Teams

- A team has its own `E` pair. Its private key is wrapped (above) to each member's `E`, so adding a
  member is one wrap and gives them every artifact already shared with the team.
- Every change to the team key is a signed **transition**. The admin who makes it signs, with
  their `S`:

  ```
  "madal/v2/teamkey/" + team id + "/" + version + "/" + signer uid + "/" + change + "/"
    + hex(prev) + "/" + public key
  change = "create" | "remove:<uid>" | "resign"
  prev   = SHA-256 of the previous transition's message (empty for "create")
  ```

  Each device remembers the last transition it accepted per team (a file next to the CLI's
  keystore, or browser storage) and refuses an older version (a rollback), a different key at the
  same version (a fork) or a next version whose `prev` doesn't match. A new signer, such as a
  second admin, stops the CLI and the viewer until the user accepts it; the CLI shows the signer's
  fingerprint and takes `--accept-new-key`. A new device starts with no history, so it trusts the
  first transition it sees.
- **Removing a member rotates the team key.** The remover's device makes a new team key, wraps it to
  the remaining members, and re-wraps every team grant from the old key to the new one, then
  deletes the old grants. The removed member keeps what they already opened and nothing new.
- One concept, "team". No nesting, no workspaces in v0.

### Trusting public keys

Each device remembers the public keys it has seen for every person (browser storage, or a file
next to the CLI's keystore) and refuses to share when one changes, until the user accepts it. A
dishonest server could still substitute a key on the very first share between two people. That is
trust on first use. To close it, people can compare **fingerprints**:

```
fingerprint = first 16 bytes of SHA-256("madal/v1/fingerprint" || E_pub || S_pub),
              as 8 groups of 4 uppercase hex digits
```

The CLI prints the other person's fingerprint the first time it shares with them, and the new one
when a key changes. `madal whoami` and the keys page show your own; `madal keys fingerprint EMAIL`
shows anyone's. Go (`internal/keys/fingerprint.go`) and the browser (`keys.js`) compute it alike,
and a test pins both to the same value.

### Inviting people who don't use Madal yet

Sharing with an email that has no keys creates an **invite** instead of a grant. Only the
inviter's device can finish it, because only it holds the artifact (or team) key, so every
`madal` command checks for invites whose invitee has since signed up and set up keys, wraps the
key to them, and deletes the invite. The invitee's first-seen keys are pinned at that moment, the
same trust-on-first-use as any share. Madal sends no email itself: the CLI prints the link for the
user or their agent to pass on.

### Limits and access

- `--expires` deletes an artifact after a time (anonymous artifacts: at most 7 days).
- `--max-opens` stops a link after that many opens. The owner's opens don't count, and the counter
  only runs while a limit is set, from when it was set.
- `share --access only-people|link` switches a non-public artifact between the private and link
  tiers. Old full links stop opening once it's private. Moving to or from **public** isn't allowed:
  public is plaintext, so the honest way is to publish again.

### Deleting an account

`DELETE /api/me`, with the account's email in the body as confirmation, purges every artifact the
account owns (blobs, versions, grants), deletes its received grants, invites by or for it, team
memberships, sharing keys, every token (CLI and browser sessions alike), the user record and the
sign-in record. A team it leaves is deleted if empty; otherwise its longest-standing member becomes
admin if none is left. The server can't rotate team keys, so a team whose key was signed by the
departed admin is re-signed by the next admin's device the first time it uses the team: a new team
key under that admin, for the same members, with every team grant re-wrapped to it.

### Resetting keys

A reset (`madal keys init --replace`, or the keys page) replaces the account's keys and vault. Grants
wrapped to the old key can't be opened. The publishing machine re-wraps the owner's grant on every
artifact it has a key for: straight away when the reset runs there, or at its next `madal login`,
which notices the keys it's handed differ from the ones it held.

### Revoking

Removing a person or team deletes their grant. The CLI matches the name against the artifact's own
grants, so an owner can remove a team they've since left, and it prints exactly which grants went.
Removing a team doesn't remove a member's own direct grant, and the output makes that visible. The
server then stops serving them any version. What they already opened, they may have kept, and the
product says so rather than implying otherwise.

They may also have kept the key. So deleting a grant on a private artifact marks it for
**rotation**, and the next real update uses a new key:

- The server holds the state: `key_gen` (the current generation) and `rotate`. While `rotate` is
  set it only accepts a version at `key_gen + 1`, sent in the `Madal-Key-Gen` header; that version
  moves `key_gen` up and clears `rotate`. Otherwise a version must use the current `key_gen`.
- Before uploading, the publishing device resolves every remaining recipient, checking pinned keys
  and team transitions. If any check fails, it stops before anything changes. Then it re-wraps the
  whole **keyring** to each of them and uploads the version under the new key. Old versions keep
  their old keys and aren't re-encrypted, so remaining readers keep the history. A removed reader
  can't open anything published after their removal, even with the old key in hand.
- A keyring is one of:

  ```
  key(32)                                     generation 0 only, as grants were before rotation
  "MDR1" || count(1) || keys                  generations 0 to count-1
  "MDR2" || first(2, big endian) || count(1) || keys
                                              generations first to first+count-1
  ```

  Each version records its generation and readers pick `keyring[key_gen]`. The `MDR2` form drops
  generations that only deleted versions used. A rotation trims them, so a ring never holds more
  than about one key per kept version. Grants are capped at 4 KiB, which is plenty.
- The owner's grant carries the ring too, so the owner's other machines read the current ring from
  it, not from a local copy that may be stale. That is also how a second machine updates an
  artifact it didn't publish.
- An invite completed later gets the full ring.
- Link-tier artifacts don't rotate, since the key is in every copy of the link. Once a private
  artifact has more than one key, it can't switch to link tier, because a link carries one key.

### Older versions

An artifact keeps its newest 5 versions. Publishing the 6th deletes version 1's record and blob,
and so on, so the link never stops taking updates. The artifact's `first` is the oldest version
kept. Asking for an older one gets a 404 that says it was deleted.

Every kept version stays readable to anyone who can read the artifact. The viewer has a "Version n
of N" menu listing the kept ones. Each pick opens in a new sandboxed frame. If a version has a different password, the viewer
asks for it again. A slow earlier pick never replaces a later one. `madal get <link> --version n`
does the same from the CLI.

## Out of scope for v0

Blog mode, workspaces, comments, live updates, remote MCP, the verifier extension, paid plans and
`install --harness all`. See the task brief.

## Known limits

- The viewer JS comes from the server. A malicious operator could ship JS that leaks the
  fragment. That is the standard limit of browser E2EE. The planned verifier extension is the
  answer, and v0 does not claim to solve it.
- Public-tier OG cards are text only (title and description). Image cards come later.
