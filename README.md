# smartctl-exporter-multiarch

Multi-arch container image for [prometheus-community/smartctl_exporter][up]. Upstream publishes its image for
`amd64` only. Its release tarballs already cover `linux/arm64`, so this repo repackages the same binary,
unmodified.

This is a stopgap. Upstream tracks the missing image in [#381][issue], and [#380][pr] proposes the fix. I'll
archive this repo once upstream publishes an arm64 image.

```
ghcr.io/yama6a/smartctl-exporter-multiarch:<tag>
```

The current tag is on the [releases][releases] page. The image is built for `linux/amd64` and `linux/arm64`. The
binary and its flags are unchanged, so the image is a drop-in `image.repository` override on the upstream
[prometheus-smartctl-exporter][chart] Helm chart.

## Versioning

A tag is `<upstream version>-<build revision>`. For example, `v1.2.3-2` is the second build of upstream's
`v1.2.3`, usually because the base image moved for a CVE. Pin the full tag.

Two moving tags also exist:

- `<upstream version>` follows the newest build revision of that upstream release.
- `latest` follows every build.

Renovate reads the `-N` suffix as a semver prerelease and never offers it. Consumers must declare the suffix:

```json5
{
  matchDepNames: ["ghcr.io/yama6a/smartctl-exporter-multiarch"],
  versioning: "regex:^v(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)-(?<build>\\d+)$",
}
```

## How a release happens

A merge to `main` releases. Nobody triggers it by hand.

1. Renovate bumps a pin in `versions.env` and auto-merges it once CI is green.
2. The merge to `main` runs `.github/workflows/build.yaml`.
3. `lib/should_build.sh` fingerprints both pins and the Dockerfile. It compares the result with the
   `build-inputs.json` of the newest release. A match builds nothing, so a pin that changes nothing costs nothing.
4. `lib/publish.sh` takes the next free build revision from the published releases. It pushes one manifest list
   for both architectures.
5. `lib/release.sh` creates the release. The release is the only record of a build revision, so it runs last.

The fingerprint covers both pins in `versions.env`: the upstream release, and the digest-pinned base image that
supplies `smartctl`.

## Local use

```
make guard      # would a build happen?
make build      # both architectures, no push
make publish    # build, push and stage the release assets. Needs GHCR_TOKEN with write:packages
make release    # create the GitHub release. Needs gh
```

`make help` lists every target.

[up]: https://github.com/prometheus-community/smartctl_exporter
[chart]: https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-smartctl-exporter
[issue]: https://github.com/prometheus-community/smartctl_exporter/issues/381
[pr]: https://github.com/prometheus-community/smartctl_exporter/pull/380
[releases]: https://github.com/yama6a/smartctl-exporter-multiarch/releases
