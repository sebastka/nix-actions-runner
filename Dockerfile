# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# GitHub Actions runner with Nix, for ARC (Actions Runner Controller) runner scale sets: GitHub's runner image (its
# layout, /home/runner/run.sh, is what ARC starts), with
# - Nix, single-user: /nix owned by the runner user, no daemon, nothing running as root
# - the Attic client (attic), to push to an Attic binary cache
# For linux/amd64 and linux/arm64.

# Nix itself: its official image (multi-architecture), pinned by tag and digest, bumped by Renovate like the base image.
# Only Nix's own closure is taken, not the image's whole base system: copied into a store of its own under /out (/out/nix,
# with its database), and its path written down for the runner stage.
FROM ghcr.io/nixos/nix:2.35.4@sha256:f159a58f390677f41e8e900a74b6e2f9c7f27b364122ae6acf7a652ce6c551c0 AS nix
RUN nix="$(dirname "$(dirname "$(readlink -f /root/.nix-profile/bin/nix)")")" \
    && nix --extra-experimental-features nix-command copy --no-check-sigs --to /out "${nix}" \
    && echo "${nix}" > /out/nix-path

FROM ghcr.io/actions/actions-runner:2.338.1@sha256:e275409999c37162649aa050ca573f03eab2eabcb3a1e7fcc47548de6b4f9690

# nixpkgs commit the Attic client comes from: the nixos-unstable head (bumped by Renovate), already built on
# cache.nixos.org
ARG NIXPKGS_REV=3ec636362e1816bc2f0888fa0fa2c69f1bc9e504

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# /nix and /etc/nix created for the runner user, the only one using Nix.
# Users by id (root 0, runner 1001 in the base image): Kubernetes' runAsNonRoot can only check a numeric USER. No
# group for the runner: its supplementary ones (docker, for ARC's dind mode) then still come from /etc/group.
USER 0
RUN install -d -m 0755 -o runner -g runner /nix /etc/nix
COPY nix.conf /etc/nix/nix.conf
COPY --from=nix --chown=1001:1001 /out/nix /nix
COPY --from=nix --chown=1001:1001 /out/nix-path /tmp/nix-path

USER 1001
WORKDIR /home/runner

# Nix and the Attic client in the runner's profile (~/.nix-profile): the one profile whose closure ARC's init container
# can seed a persistent /nix with
ENV PATH=/home/runner/.nix-profile/bin:${PATH}
RUN nix="$(cat /tmp/nix-path)" \
    && rm /tmp/nix-path \
    && "${nix}/bin/nix" profile add "${nix}" \
    && nix profile add "github:NixOS/nixpkgs/${NIXPKGS_REV}#attic-client" \
    && nix store gc \
    && nix --version \
    && attic --version
