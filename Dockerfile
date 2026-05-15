# syntax=docker/dockerfile:1.7

FROM python:3.11-slim-bookworm AS builder

WORKDIR /build

# Build Python wheels once. BuildKit cache mounts keep apt and pip downloads
# between builds on the same machine.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    pkg-config \
    libcairo2-dev \
    libpango1.0-dev \
    libgdk-pixbuf-2.0-dev \
    libffi-dev \
    python3-dev

COPY requirements.txt .

RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --wheel-dir /wheels -r requirements.txt


FROM python:3.11-slim-bookworm AS runtime

WORKDIR /app

# Runtime system libraries for Playwright, image/PDF generation, and healthcheck.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libatspi2.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libffi8 \
    libgbm1 \
    libgdk-pixbuf-2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libwayland-client0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    procps \
    xdg-utils

COPY --from=builder /wheels /wheels
COPY requirements.txt .

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

# Keep Playwright browser binaries in a stable layer that is reused until
# requirements.txt changes.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN --mount=type=cache,target=/root/.cache/ms-playwright \
    playwright install chromium

# Copy project files after dependencies so source changes do not rebuild deps.
COPY . .

# Remove Python cache files to ensure the latest code is used.
RUN find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
RUN find . -type f -name "*.pyc" -delete 2>/dev/null || true

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# MySQL configuration is passed through docker-compose.yml or the command line.
# Do not hardcode it here; use environment variables instead.

# Healthcheck for the bot process.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -f "python.*bot.py" || exit 1

# Start the bot.
CMD ["python", "-u", "bot.py"]
