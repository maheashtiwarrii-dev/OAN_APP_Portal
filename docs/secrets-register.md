# OAN Portal — secrets register (plan task 0.15, S05)

Every secret the portal uses: what it protects, where it is stored, who owns it and when it is rotated.
**No secret value appears in this file, in git, in notes or in logs.** CI scans every push with gitleaks.
Gate 8.0 item 10: every entry is generated fresh for production; nothing is copied from dev.

Updated 16 Oct 2026 (iteration 28). Google sign-in was removed (Q37) and Slack/WhatsApp were removed (Q38), so their
OAuth secrets, signing secrets and tokens are no longer part of the system.

## Application signing keys (stored in `OAN_SECRETS`)

`OAN_SECRETS` is readable only by the packages named in `oan_util.get_secret`'s `ACCESSIBLE BY` clause. The values
are 32 random bytes from `dbms_crypto.randombytes`, created by `oan_util.ensure_secret` at install.

| Name | Protects | Readers | Owner | Rotation |
|---|---|---|---|---|
| `AUDIT_PSEUDONYM_KEY` | HMAC that turns a deleted member's id into a stable pseudonym in the audit log (FR-26, NFR-05) | `oan_audit_pkg` | Privacy contact | Never rotated in place (old pseudonyms must keep matching). A new key per environment; production gets its own at go-live. |
| `UNSUBSCRIBE_KEY` | HMAC on one-click unsubscribe links in e-mails (FR-23, page 44) | `oan_notify_pkg` | Platform Admin | Every 12 months, and immediately if exposed. Older unsubscribe links stop working; members can still change settings on page 42. |

## One-time tokens (no long-term key)

Password reset, e-mail confirmation, e-mail change, organisation invites and CV share links use 32 random bytes per token.
Only the SHA-256 hash is stored (`oan_email_tokens.token_hash`); every token expires (1 hour to 30 days) and is used once.
Nothing to rotate.

## Credentials held outside the database

| Secret | Used by | Stored in | Owner | Rotation |
|---|---|---|---|---|
| ADMIN password (ADB) | Bootstrap and admin scripts (`db/grants/00`, `01`, `40`) | OCI Vault / owner's password manager | Database owner (OAN) | 90 days, and when anyone with access leaves |
| `OAN_DEPLOY` password | Database deployments (proxy into `OAN_DATA`) | OCI Vault; GitHub environment `dev` secret `OAN_DEPLOY_PASSWORD` | Database owner | 90 days |
| `OAN_APP` password | App import, synonyms | OCI Vault; GitHub environment `dev` secret `OAN_APP_PASSWORD` | Database owner | 90 days |
| ADB wallet (mTLS) | SQLcl and CI connections | Local, outside the repository; GitHub secret `OAN_WALLET_ZIP_B64` | Database owner | Download a new wallet after each rotation; rotate the wallet every 12 months |
| SMTP credential | APEX mail for every OAN e-mail (task 0.7) | APEX instance settings (encrypted by APEX), set by `db/grants/40_email_delivery.sql`, which prompts for it | OAN operations | 12 months, and when the OCI user changes |
| APEX session-state checksum salt | URL checksums (session state protection) | Application attribute in `oan-app-portal/application.apx` | Platform Admin | Generate a new salt for production at go-live (the dev value is in git and must not be reused) |
| Synthetic test-account passwords (dev only) | Testing as tester.bala / tester.asha etc. | Product owner only; set with `db/dev/720_set_test_passwords.sql` | Product owner | Whenever testers change; never exist in production |
| LinkedIn OAuth client (off) | Optional LinkedIn sign-in, Build Option `LINKEDIN` excluded | APEX Web Credential, only if it is ever switched on | Platform Admin | 12 months if enabled |
| GenAI credential (off) | AI assistant, gate G-AI | APEX Web Credential, only if G-AI is passed | Platform Admin | 12 months if enabled |

## Rules
- Never paste a secret into a ticket, chat, commit message, `progress.md` or a log line.
- Scripts that need a secret ask for it (`ACCEPT ... HIDE`) or read it from the CI environment; they never print it.
- After any suspected exposure: rotate the secret, record the rotation in the audit log, and review the gitleaks report.
- Rotations are listed in the runbook (task 9.5).
