# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# GitHub Actions runner with Nix, for ARC (Actions Runner Controller) runner scale sets: GitHub's runner image (its
# layout, /home/runner/run.sh, is what ARC starts), with
# - Nix, single-user: /nix owned by the runner user, no daemon, nothing running as root
# - the Attic client (attic), to push to an Attic binary cache
# For linux/amd64 and linux/arm64.
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:759a1d94a15b05941aba5196974ff43fe15b4cbba29b694b35cbc32a1166b232

# Nix release: version and its tarballs' SHA-256 (one per architecture), all from
# https://releases.nixos.org/nix/nix-<version>/install. NIX_VERSION bumped by Renovate, the hashes by hand in its pull
# request (the build fails until then).
ARG NIX_VERSION=2.35.4
ARG NIX_SHA256_AMD64=ff66236d2f7e2a21f3350e73668e021ac6a8881ef277a38e16e952bfb22718c3
ARG NIX_SHA256_ARM64=14a940a2d0ae5b2c623dc2ca168311c9367fd4bc416f6ded0c1087089d6de934
# Set by BuildKit: amd64 or arm64
ARG TARGETARCH
# nixpkgs commit the Attic client comes from: the nixos-unstable head (bumped by Renovate), already built on
# cache.nixos.org
ARG NIXPKGS_REV=3ec636362e1816bc2f0888fa0fa2c69f1bc9e504

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# xz for Nix's tarball. /nix and /etc/nix created for the runner user, the only one using Nix.
# Users by id (root 0, runner 1001 in the base image): Kubernetes' runAsNonRoot can only check a numeric USER. No
# group for the runner: its supplementary ones (docker, for ARC's dind mode) then still come from /etc/group.
USER 0
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 0755 -o runner -g runner /nix /etc/nix
COPY nix.conf /etc/nix/nix.conf

USER 1001
WORKDIR /home/runner

RUN case "${TARGETARCH}" in \
        amd64) system=x86_64-linux sha256="${NIX_SHA256_AMD64}" ;; \
        arm64) system=aarch64-linux sha256="${NIX_SHA256_ARM64}" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /tmp/nix.tar.xz "https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-${system}.tar.xz" \
    && echo "${sha256}  /tmp/nix.tar.xz" | sha256sum -c - \
    && mkdir /tmp/nix \
    && tar -xJf /tmp/nix.tar.xz -C /tmp/nix --strip-components=1 \
    && /tmp/nix/install --no-daemon --no-channel-add --no-modify-profile \
    && rm -rf /tmp/nix /tmp/nix.tar.xz
ENV PATH=/home/runner/.nix-profile/bin:${PATH}

RUN nix profile add "github:NixOS/nixpkgs/${NIXPKGS_REV}#attic-client" \
    && nix store gc \
    && nix --version \
    && attic --version
