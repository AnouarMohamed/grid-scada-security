FROM python:3.12-slim-bookworm@sha256:782412e85d0f0984994c290652577d4018aff08145c85b262bb63dc0c7522254

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/src

WORKDIR /app

RUN groupadd --system gridguard \
    && useradd --system --gid gridguard --home-dir /nonexistent --shell /usr/sbin/nologin gridguard

COPY infra/services/modbus-ingestor/src/ ./src/
COPY infra/contracts/register-maps/ieee13-demo.json /etc/gridguard/register-map.json

USER gridguard

ENTRYPOINT ["python", "-m", "gridguard_modbus_ingestor"]
