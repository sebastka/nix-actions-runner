# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# GitHub Actions runner with Nix, for ARC (Actions Runner Controller) runner scale sets: GitHub's runner image (its
# layout, /home/runner/run.sh, is what ARC starts), with
# - Nix, single-user: /nix owned by the runner user, no daemon, nothing running as root
# - the Attic client (attic), to push to our binary cache
# x86_64 only.
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807

# Nix release: version and its tarball's SHA-256, both from https://nixos.org/nix/install. NIX_VERSION bumped by
# Renovate, NIX_SHA256 by hand in its pull request (the build fails until then).
ARG NIX_VERSION=2.35.3
ARG NIX_SHA256=6ce3ce3703fdc241b560cba401c5d338042122fe5b1a81e07bf1a623f259eba0
# nixpkgs commit the Attic client comes from: the nixos-unstable head (bumped by Renovate), already built on
# cache.nixos.org
ARG NIXPKGS_REV=55bfb4d7437bd4e09ab7cba58a43bd68eb310044

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

RUN curl -fsSL -o /tmp/nix.tar.xz "https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-x86_64-linux.tar.xz" \
    && echo "${NIX_SHA256}  /tmp/nix.tar.xz" | sha256sum -c - \
    && mkdir /tmp/nix \
    && tar -xJf /tmp/nix.tar.xz -C /tmp/nix --strip-components=1 \
    && /tmp/nix/install --no-daemon --no-channel-add --no-modify-profile \
    && rm -rf /tmp/nix /tmp/nix.tar.xz
ENV PATH=/home/runner/.nix-profile/bin:${PATH}

RUN nix profile add "github:NixOS/nixpkgs/${NIXPKGS_REV}#attic-client" \
    && nix store gc \
    && nix --version \
    && attic --version
