# nix-actions-runner

GitHub Actions runner image with Nix, for [ARC](https://github.com/actions/actions-runner-controller) runner scale
sets: [GitHub's runner image](https://github.com/actions/runner/pkgs/container/actions-runner), with

- **Nix**, single-user: `/nix` owned by the `runner` user, no daemon, nothing running as root. Builds run without
  Nix's sandbox (`sandbox = false`, `nix.conf`): the pod has no privileges to create its namespaces.
- **The Attic client** (`attic`), to push to our binary cache (sebastka/homelab: `k8s/applications/utils/attic`).

x86_64 only. Published as `ghcr.io/sebastka/nix-actions-runner` (`latest`, and `sha-<commit>`) from `master`, with
SLSA provenance and SBOM attestations, and a keyless cosign signature:

```sh
cosign verify ghcr.io/sebastka/nix-actions-runner:latest \
  --certificate-identity-regexp '^https://github.com/sebastka/nix-actions-runner/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Use

Only for trusted workflows: never on `pull_request` (a fork's code would run in the cluster).

Our cache (`pithos`, private: reads need a token too), from the workflow, with a push token as the secret
`ATTIC_TOKEN`:

```yaml
env:
  NIX_CONFIG: |
    extra-substituters = https://attic.karlsen.app/pithos
    extra-trusted-public-keys = pithos:pir3vRe6RpQrNmkwB6M0F/ydWPDgQqe5v6mABkmCpYc=
    netrc-file = ${{ runner.temp }}/netrc
steps:
  # Reads (Nix): the token in a netrc file, outside the workspace
  - run: |
      install -m 600 /dev/null "${RUNNER_TEMP}/netrc"
      printf 'machine attic.karlsen.app\npassword %s\n' "${ATTIC_TOKEN}" > "${RUNNER_TEMP}/netrc"
    env:
      ATTIC_TOKEN: ${{ secrets.ATTIC_TOKEN }}
  # Pushes (attic)
  - run: attic login karlsen https://attic.karlsen.app "${ATTIC_TOKEN}"
    env:
      ATTIC_TOKEN: ${{ secrets.ATTIC_TOKEN }}
  - run: attic push karlsen:pithos ./result
```

## Updates

All by Renovate (`renovate.json`):

- Base image and actions: tags and digests.
- Attic client: `NIXPKGS_REV`, the nixos-unstable head, daily. Auto-merged once the required checks (`lint`, `build`) passed.
- yamllint: the version the lint job pins.
- Nix: `NIX_VERSION` only. Renovate cannot compute `NIX_SHA256`, so its pull request fails the build until the
  tarball's hash (from https://nixos.org/nix/install) is pushed to it by hand.

## License

[MIT](LICENSE).
