# Secret drift detection

How the module detects and enforces secrets that PVE does not return over its API, and how it
keeps them out of logs and reports.

Every secret this module manages is detected and enforced: changing a secret in Hiera, and
nothing else, rotates it on the next run.

## Where secrets are compared

PVE does not return most of these secrets over its API, but it persists them on the node. The
module reads those copies to decide whether the stored secret still matches the declared one.

| Attribute | Compared against |
|---|---|
| `pve_user.password` | `crypt(3)` against `/etc/pve/priv/shadow.cfg` |
| `pve_storage.password` | `/etc/pve/priv/storage/<storage>.pw` |
| `pve_realm.bind_password` | `/etc/pve/priv/realm/<realm>.pw` (or the older `priv/ldap/`) |
| `pve_notification_target.smtp_password` / `.token` / `.secret` | `/etc/pve/priv/notifications.cfg` |
| `pve_storage.encryption_key` | the key fingerprint the API returns |
| `pve_realm.client_key` | the API response itself |
| `pve_sdn_ipam.token`, `pve_sdn_dns.key` | the API response itself |

A secret is sent to PVE only when it no longer matches the stored copy.

`pve_api_token` secrets are the exception: PVE returns a generated token secret once, at
creation, and stores only a hash afterwards, so there is nothing to compare against. See
[API tokens](api-tokens.md).

## Requirements and failure mode

Reading the `/etc/pve/priv` copies requires the Puppet agent to run on the PVE node as root. If a
resource declares such a secret and its store cannot be read, the run fails with an error naming
the attribute and the path. It does not report the resource as in sync: that would silently stop
enforcing the secret precisely where nobody can see it. Resources that declare no node-stored
secret are unaffected.

Secrets that need no on-node access:

- `pve_storage.encryption_key`: PVE records the key's fingerprint in the public `storage.cfg` and
  returns it from the API, so the declared key's fingerprint is compared directly. `autogen` only
  requires that some key exists; it does not regenerate one on every run.
- `pve_realm.client_key`: PVE stores the OpenID client secret in cleartext in
  `/etc/pve/domains.cfg`, which is not under `priv/`, and returns it from the API. That is PVE's
  design, not this module's, but it is worth knowing when deciding where your secrets live.
- `pve_sdn_ipam.token` and `pve_sdn_dns.key`: `/etc/pve/sdn/ipams.cfg` and `dns.cfg` are handed
  back unfiltered by the API, so both are ordinary properties with real drift detection. See
  [Software-defined networking](sdn.md#ipam-and-dns-are-different).

## Secrets in logs and reports

Secret attributes are marked sensitive, so their values are redacted from change notices, from
report events (and therefore from PuppetDB), and from the agent-local `last_run_report.yaml`. The
current value is reported as a fixed placeholder, `[secret managed]`, never as the stored value,
hash or ciphertext: a placeholder that varied between runs would itself read as drift.

Declaring a secret with `Sensitive()` is still worthwhile: it keeps the plaintext out of the
compiled catalog, but redaction no longer depends on it.

## Password changes use pveum

`pve_user.password` is enforced with `pveum passwd` rather than the REST API. PVE marks
`PUT /access/password` `allowtoken: 0`, one of only five endpoints in the entire API to refuse
API-token authentication, so no permission grant can make the REST path work. Creating a user
with a password still goes through `POST /access/users`, which does accept tokens. The change
therefore needs `pveum` on the node and fails on a host where it is not installed.
