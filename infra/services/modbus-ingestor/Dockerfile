FROM python:3.14-slim-trixie@sha256:caaf356f40667c496d405780745b9ac25771c189a51dfcc42430d531ea09f8a2

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/src

WORKDIR /app

RUN apt-get update \
    && apt-get upgrade --yes \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system gridguard \
    && useradd --system --gid gridguard --home-dir /nonexistent --shell /usr/sbin/nologin gridguard

COPY infra/services/modbus-ingestor/src/ ./src/
COPY infra/contracts/register-maps/ieee13-demo.json /etc/gridguard/register-map.json

USER gridguard

ENTRYPOINT ["python", "-m", "gridguard_modbus_ingestor"]
