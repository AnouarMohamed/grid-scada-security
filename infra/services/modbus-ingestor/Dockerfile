FROM python:3.14-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/src

WORKDIR /app

RUN groupadd --system gridguard \
    && useradd --system --gid gridguard --home-dir /nonexistent --shell /usr/sbin/nologin gridguard

COPY src/ ./src/

USER gridguard

ENTRYPOINT ["python", "-m", "gridguard_modbus_ingestor"]

