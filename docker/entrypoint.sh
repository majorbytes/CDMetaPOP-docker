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
# Environment variables (all overridable at `docker run`/compose time):
#   DATA_DIR      data directory inside the container            (default /data)
#   RUNVARS       run-parameter file, relative to DATA_DIR       (default RunVars.csv)
#   OUTPUT_NAME   output folder prefix (a timestamp is appended) (default output)
#   SEED_EXAMPLES if 1, copy bundled example_files into DATA_DIR
#                 when DATA_DIR is empty                          (default 1)
# ---------------------------------------------------------------------------
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
RUNVARS="${RUNVARS:-RunVars_demo.csv}"
OUTPUT_NAME="${OUTPUT_NAME:-demo}"
SEED_EXAMPLES="${SEED_EXAMPLES:-1}"

mkdir -p "$DATA_DIR"

# Seed a fresh/empty data directory with the bundled example inputs so a first
# run works out of the box. Existing data is never overwritten.
if [ "$SEED_EXAMPLES" = "1" ] && [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
  echo "[entrypoint] '$DATA_DIR' is empty -> seeding bundled example_files."
  cp -r /app/example_files/. "$DATA_DIR"/
fi

cd /app/src

# Pass-through mode: run whatever was asked for.
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

if [ ! -f "$DATA_DIR/$RUNVARS" ]; then
  echo "[entrypoint] ERROR: run file not found: $DATA_DIR/$RUNVARS" >&2
  echo "[entrypoint] Put your RunVars file and input trees in the mounted data dir," >&2
  echo "[entrypoint] or set RUNVARS to its path relative to $DATA_DIR." >&2
  exit 1
fi

echo "[entrypoint] Running: python CDmetaPOP.py $DATA_DIR $RUNVARS $OUTPUT_NAME"
exec python CDmetaPOP.py "$DATA_DIR" "$RUNVARS" "$OUTPUT_NAME"
