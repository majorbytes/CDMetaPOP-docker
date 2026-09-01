# ---------------------------------------------------------------------------
# CDMetaPOP v3.08 — reproducible container image
#
# The model is a pure-Python (NumPy/SciPy/pandas) individual-based, spatially
# explicit eco-evolutionary simulation. It reads a data directory containing a
# RunVars.csv plus the referenced input trees (popvars/, patchvars/, ...) and
# writes each run's output back INTO that same data directory. Mount a host
# folder at /data so both inputs and results live on the host and persist.
# ---------------------------------------------------------------------------
FROM python:3.10-slim

# 3.10 matches the pinned conda environment (python 3.10.20 in environment.yml).
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencies first, so edits to source don't invalidate the wheel-install layer.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Application source and the bundled example inputs (used to seed an empty
# data directory and to smoke-test the image).
COPY src/ ./src/
COPY example_files/ ./example_files/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Persistent data directory. Bind-mount a host path here (see docker-compose.yml
# / DOCKER.md). Inputs are read from here and all output folders are written here.
ENV DATA_DIR=/data \
    RUNVARS=RunVars_demo.csv \
    OUTPUT_NAME=demo \
    SEED_EXAMPLES=1
RUN mkdir -p /data
VOLUME ["/data"]

# CDmetaPOP.py resolves its sibling modules relative to the working directory,
# so it must run from src/.
WORKDIR /app/src

ENTRYPOINT ["entrypoint.sh"]
