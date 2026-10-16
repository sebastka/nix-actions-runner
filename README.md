# nix-actions-runner

GitHub Actions runner image with Nix, for [ARC](https://github.com/actions/actions-runner-controller) runner scale
sets: [GitHub's runner image](https://github.com/actions/runner/pkgs/container/actions-runner), with

- **Nix**, single-user: `/nix` owned by the `runner` user, no daemon, nothing running as root. Builds run without
  Nix's sandbox (`sandbox = false`, `nix.conf`): an unprivileged pod cannot create its namespaces.
- **The [Attic](https://github.com/zhaofengli/attic) client** (`attic`), to push to an Attic binary cache.

For `linux/amd64` and `linux/arm64`. Published as `ghcr.io/sebastka/nix-actions-runner` (`latest`, and
`sha-<commit>`) from `master`, with SLSA provenance and SBOM attestations, and a keyless cosign signature:

```sh
cosign verify ghcr.io/sebastka/nix-actions-runner:latest \
  --certificate-identity-regexp '^https://github.com/sebastka/nix-actions-runner/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Use

Only for trusted workflows: never on `pull_request` from forks (a fork's code would run in your cluster, without
Nix's sandbox).

In the runner scale set's values (`gha-runner-scale-set` chart), the image replaces GitHub's. The runner runs as uid
1001, so `runAsNonRoot` works:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/sebastka/nix-actions-runner:latest
        command: ["/home/runner/run.sh"]
        securityContext:
          runAsNonRoot: true
          allowPrivilegeEscalation: false
```

Only cache.nixos.org is configured. Other caches from the workflow, with `NIX_CONFIG`; for an Attic cache, with a
token as the secret `ATTIC_TOKEN`:

```yaml
env:
  NIX_CONFIG: |
    extra-substituters = https://cache.example.com/<cache>
    extra-trusted-public-keys = <cache>:<public key>
    netrc-file = ${{ runner.temp }}/netrc  # Private cache only: reads need the token too
steps:
  # Reads (Nix), private cache only: the token in a netrc file, outside the workspace
  - run: |
      install -m 600 /dev/null "${RUNNER_TEMP}/netrc"
      printf 'machine cache.example.com\npassword %s\n' "${ATTIC_TOKEN}" > "${RUNNER_TEMP}/netrc"
    env:
      ATTIC_TOKEN: ${{ secrets.ATTIC_TOKEN }}
  # Pushes (attic)
  - run: attic login example https://cache.example.com "${ATTIC_TOKEN}"
    env:
      ATTIC_TOKEN: ${{ secrets.ATTIC_TOKEN }}
  - run: attic push example:<cache> ./result
```

## Updates

All by Renovate (`renovate.json`):

- Base image and actions: tags and digests.
- Attic client: `NIXPKGS_REV`, the nixos-unstable head, daily. Auto-merged once the required checks (`lint`,
  `build (amd64)`, `build (arm64)`) passed.
- yamllint: the version the lint job pins.
- Nix: `NIX_VERSION` only. Renovate cannot compute `NIX_SHA256_AMD64` and `NIX_SHA256_ARM64`, so its pull request
  fails the build until the tarballs' hashes (from `https://releases.nixos.org/nix/nix-<version>/install`) are pushed
  to it by hand.

## License

[MIT](LICENSE).
