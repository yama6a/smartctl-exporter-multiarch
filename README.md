# smartctl-exporter-multiarch

Multi-arch container image for [prometheus-community/smartctl_exporter][up], which upstream publishes for
amd64 only. Their release tarballs already cover `linux/arm64`; this repackages the same binary, unmodified.

A stopgap, not a fork. Tracked upstream in [#381][issue], fix proposed in [#380][pr]. I'll archive this repo
once there's an official arm64 image.

```
ghcr.io/yama6a/smartctl-exporter-multiarch:v0.14.0-1
```

Built for `linux/amd64` and `linux/arm64`. Works as a drop-in `image.repository` override on the upstream
[prometheus-smartctl-exporter][chart] Helm chart, since the binary and its flags are unchanged.

## Versioning

`<upstream version>-<build revision>`. `v0.14.0-2` is our second build of upstream's `v0.14.0`, usually
because the base image moved for a CVE. Pin the full tag.

Two moving tags also exist: `v0.14.0` follows the newest revision of that upstream release, and `latest`
follows everything.

Renovate consumers need the `-N` suffix declared, or it reads as a semver prerelease and is never offered:

```json5
{
  matchDepNames: ["ghcr.io/yama6a/smartctl-exporter-multiarch"],
  versioning: "regex:^v(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)-(?<build>\\d+)$",
}
```

## How a release happens

Nothing here is triggered by hand.

1. Renovate bumps a pin in `versions.env` and auto-merges once CI is green.
2. The merge to `main` runs `.github/workflows/build.yaml`.
3. `lib/should_build.sh` fingerprints the pins plus the Dockerfile and compares against the newest release's
   `build-inputs.json`. Identical means no build, so a churned pin costs nothing.
4. `lib/publish.sh` reads the published releases, takes the next free revision, and pushes one manifest list
   covering both arches.
5. `lib/release.sh` creates the release. That is the only record of a revision, which is why it runs last.

Both pins in `versions.env` feed the fingerprint: the upstream release, and the digest-pinned base image that
supplies `smartctl` itself.

## Local use

```
make guard      # would a build happen?
make build      # both arches, no push
make publish    # build, push, stage assets   (needs GHCR_TOKEN with write:packages)
make release    # create the GitHub release   (needs gh)
```

`make help` lists everything.

[up]: https://github.com/prometheus-community/smartctl_exporter
[chart]: https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-smartctl-exporter
[issue]: https://github.com/prometheus-community/smartctl_exporter/issues/381
[pr]: https://github.com/prometheus-community/smartctl_exporter/pull/380
