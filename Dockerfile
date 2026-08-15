# syntax=docker/dockerfile:1
# Repackages the upstream smartctl_exporter release binary for every arch buildx is asked for. Upstream's own
# Dockerfile copies out of a local .build/<os>-<arch>/ tree that only exists inside their release pipeline;
# fetching the published tarball per TARGETARCH is what lets one buildx run cover amd64 and arm64.

# No default: publish.sh and build.sh always pass it from versions.env, and a bare `docker build` should fail
# rather than quietly produce an image on an unpinned base.
ARG ALPINE_IMAGE
FROM ${ALPINE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/yama6a/smartctl-exporter-multiarch"
LABEL org.opencontainers.image.description="Multi-arch build of prometheus-community/smartctl_exporter"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# Supplies /usr/sbin/smartctl, which the exporter shells out to for every reading.
# No `=<version>` pin: the base image above is pinned by digest, which already fixes the whole package set.
# A second pin here would just be a copy that goes stale on its own.
# hadolint ignore=DL3018
RUN apk add --no-cache smartmontools

# Bare, no leading v: the release URL needs the tag (v0.14.0) and the asset name needs the plain number
# (smartctl_exporter-0.14.0.linux-arm64.tar.gz). BuildKit cannot strip a prefix in a substitution, so
# publish.sh passes the plain number and the `v` is written literally below.
ARG VERSION
ARG TARGETARCH

ADD https://github.com/prometheus-community/smartctl_exporter/releases/download/v${VERSION}/sha256sums.txt /tmp/sha256sums.txt
ADD https://github.com/prometheus-community/smartctl_exporter/releases/download/v${VERSION}/smartctl_exporter-${VERSION}.linux-${TARGETARCH}.tar.gz /tmp/exporter.tar.gz

# The checksum is per-arch, so `ADD --checksum=` cannot express it; grep the release's own sums file instead.
# An empty `expected` means the asset name changed upstream, which must fail loudly rather than skip the check.
RUN set -eux; \
    expected="$(awk -v f="smartctl_exporter-${VERSION}.linux-${TARGETARCH}.tar.gz" '$2 == f {print $1}' /tmp/sha256sums.txt)"; \
    [ -n "$expected" ]; \
    printf '%s  /tmp/exporter.tar.gz\n' "$expected" > /tmp/expected.sha256; \
    sha256sum -c /tmp/expected.sha256; \
    tar -xzf /tmp/exporter.tar.gz -C /tmp; \
    mv /tmp/smartctl_exporter-*/smartctl_exporter /bin/smartctl_exporter; \
    rm -rf /tmp/exporter.tar.gz /tmp/sha256sums.txt /tmp/expected.sha256 /tmp/smartctl_exporter-*

EXPOSE 9633
USER 65534
ENTRYPOINT [ "/bin/smartctl_exporter" ]
