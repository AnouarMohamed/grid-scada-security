FROM influxdb:2.9.1-alpine@sha256:38e81dd3af50d085704d970815210dae3d094c5a8a70d7a8f336716889022ea2

USER root

ARG DASEL_VERSION=3.11.2

RUN set -eux; \
    apk upgrade --no-cache; \
    case "$(apk --print-arch)" in \
        x86_64) arch="amd64"; checksum="1af4fc41087c91dd59ab10aa13dc66a87d291e26b24bdec51480fe96cfd3ccf1" ;; \
        aarch64) arch="arm64"; checksum="6f783edc1ff8e41c6bab901227740209506eecb6d67a87b3b7dda9e762c860a2" ;; \
        *) echo "Unsupported architecture" >&2; exit 1 ;; \
    esac; \
    curl --fail --location --silent --show-error \
        "https://github.com/TomWright/dasel/releases/download/v${DASEL_VERSION}/dasel_linux_${arch}.gz" \
        --output /tmp/dasel.gz; \
    actual="$(sha256sum /tmp/dasel.gz)"; \
    test "${actual%% *}" = "${checksum}"; \
    gzip -dc /tmp/dasel.gz > /usr/local/bin/dasel; \
    chmod 0755 /usr/local/bin/dasel; \
    rm /tmp/dasel.gz; \
    dasel version

USER influxdb
