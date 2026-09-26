# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Repackages the upstream smartctl_exporter release binary for each arch. Upstream's Dockerfile copies from a
# build tree that exists only in their release pipeline, so this one downloads the release tarball per TARGETARCH.

# No default, so a bare `docker build` fails instead of building on an unpinned base. The scripts pass versions.env.
ARG ALPINE_IMAGE
FROM ${ALPINE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/yama6a/smartctl-exporter-multiarch"
LABEL org.opencontainers.image.description="Multi-arch build of prometheus-community/smartctl_exporter"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# smartctl, which the exporter runs for every reading. The digest-pinned base already fixes its version.
RUN apk add --no-cache smartmontools

# The version without its leading v. The asset name needs the bare number, and BuildKit cannot strip a prefix,
# so the release URL below adds the `v` back.
ARG VERSION
ARG TARGETARCH

ADD https://github.com/prometheus-community/smartctl_exporter/releases/download/v${VERSION}/sha256sums.txt /tmp/sha256sums.txt
ADD https://github.com/prometheus-community/smartctl_exporter/releases/download/v${VERSION}/smartctl_exporter-${VERSION}.linux-${TARGETARCH}.tar.gz /tmp/exporter.tar.gz

# The checksum differs per arch, so `ADD --checksum=` cannot hold it. The release's sums file does.
# An empty `expected` means upstream renamed the asset, so the build fails instead of skipping the check.
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
