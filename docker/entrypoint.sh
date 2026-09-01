#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# CDMetaPOP container entrypoint.
#
# Behaviour:
#   * With NO arguments -> runs the model:
#         python CDmetaPOP.py "$DATA_DIR" "$RUNVARS" "$OUTPUT_NAME"
#   * With arguments    -> runs them verbatim (e.g. `bash`, or a custom
#         `python CDmetaPOP.py ...` invocation), so the image doubles as a
#         normal CDMetaPOP environment for ad-hoc use.
#
# File ownership (Linux):
#   The image runs as root *inside the container* (this needs no root/sudo on
#   the host -- it is provided by the Docker daemon you already use). When
#   DOCKER_UID is set, the entrypoint seeds and chowns the data directory, then
#   drops privileges with gosu so the model runs -- and writes its output -- as
#   that user. Result: output in the bind-mounted data dir is owned by you, and
#   an empty or root-owned /data is handled automatically (no pre-creating or
#   manual chown needed).
#
# Environment variables (all overridable at `docker run`/compose time):
#   DATA_DIR      data directory inside the container            (default /data)
#   RUNVARS       run-parameter file, relative to DATA_DIR       (default RunVars_demo.csv)
#   OUTPUT_NAME   output folder prefix (a timestamp is appended) (default demo)
#   SEED_EXAMPLES if 1, copy bundled example_files into DATA_DIR
#                 when DATA_DIR is empty                          (default 1)
#   DOCKER_UID    host UID to run the model as (Linux); unset/0 = stay root
#   DOCKER_GID    host GID to run the model as (defaults to DOCKER_UID)
# ---------------------------------------------------------------------------
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
RUNVARS="${RUNVARS:-RunVars_demo.csv}"
OUTPUT_NAME="${OUTPUT_NAME:-demo}"
SEED_EXAMPLES="${SEED_EXAMPLES:-1}"
DOCKER_UID="${DOCKER_UID:-}"
DOCKER_GID="${DOCKER_GID:-}"

mkdir -p "$DATA_DIR"

# Seed a fresh/empty data directory with the bundled example inputs so a first
# run works out of the box. Existing data is never overwritten.
if [ "$SEED_EXAMPLES" = "1" ] && [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
  echo "[entrypoint] '$DATA_DIR' is empty -> seeding bundled example_files."
  cp -r /app/example_files/. "$DATA_DIR"/
fi

# Decide whether to drop privileges. Only possible when we are root and a
# target UID was requested.
RUNNER=()
if [ "$(id -u)" = "0" ] && [ -n "$DOCKER_UID" ] && [ "$DOCKER_UID" != "0" ]; then
  TARGET_GID="${DOCKER_GID:-$DOCKER_UID}"
  echo "[entrypoint] Handing $DATA_DIR to ${DOCKER_UID}:${TARGET_GID} and dropping privileges."
  chown -R "${DOCKER_UID}:${TARGET_GID}" "$DATA_DIR"
  RUNNER=(gosu "${DOCKER_UID}:${TARGET_GID}")
fi

cd /app/src

# Pass-through mode: run whatever was asked for (as the target user if set).
if [ "$#" -gt 0 ]; then
  exec "${RUNNER[@]}" "$@"
fi

if [ ! -f "$DATA_DIR/$RUNVARS" ]; then
  echo "[entrypoint] ERROR: run file not found: $DATA_DIR/$RUNVARS" >&2
  echo "[entrypoint] Put your RunVars file and input trees in the mounted data dir," >&2
  echo "[entrypoint] or set RUNVARS to its path relative to $DATA_DIR." >&2
  exit 1
fi

echo "[entrypoint] Running: python CDmetaPOP.py $DATA_DIR $RUNVARS $OUTPUT_NAME"
exec "${RUNNER[@]}" python CDmetaPOP.py "$DATA_DIR" "$RUNVARS" "$OUTPUT_NAME"
