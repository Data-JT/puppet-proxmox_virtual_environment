# API tokens

Examples for `pve_api_token`. All attributes are documented in
[REFERENCE.md](../REFERENCE.md#pve_api_token).

The namevar is the full token ID in `user@realm!tokenname` format, the same string used to
authenticate API requests and to assign permissions via `pve_acl`. `pve_api_token` manages token
existence and metadata (`comment`, `expire`, `privsep`).

## Keeping the one-time secret

PVE returns the generated secret only once, during creation. Set `secret_file` to retain it on the
Puppet agent with mode `0600` without exposing it in reports or logs:

```puppet
pve_api_token { 'automation@pve!ci':
  ensure      => present,
  privsep     => true,
  secret_file => '/etc/puppetlabs/puppet/pve-ci-token.secret',
}

pve_acl { '/|automation@pve!ci|PVEAuditor':
  ensure    => present,
  propagate => true,
}
```

The parent directory must already exist and be writable by the Puppet agent. For safety, the
destination cannot be a symbolic link. Without `secret_file`, Puppet still manages token existence
and metadata but deliberately discards the one-time secret and emits a warning.

Because PVE stores only a hash afterwards, a token secret cannot be checked for drift on later
runs. See [Secret drift detection](secret-drift.md).
