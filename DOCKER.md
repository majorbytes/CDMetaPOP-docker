# Running CDMetaPOP in Docker

This packages CDMetaPOP v3.08 as a reproducible container. The image pins the
same scientific stack as `environment.yml` (Python 3.10, NumPy 2.2.6,
SciPy 1.15.2, pandas 2.3.3), so results match a local conda run.

## Key idea: the data directory

CDMetaPOP reads its inputs from a **data directory** and writes **every run's
output back into that same directory** (folders like
`run0batch0mc0species0/`, plus `summary_popAllTime.csv`, logs, etc.).

The container exposes that directory at **`/data`**. Bind-mount a folder on your
server there and everything — inputs and results — lives on the host and
persists across container restarts and rebuilds.

```
host: <DATA_DIR>            <->   container: /data
      RunVars.csv                       RunVars.csv
      popvars/ patchvars/ ...           popvars/ patchvars/ ...
      output.../  (created by runs)     output.../
```

## Prerequisites

- Docker (Docker Desktop on Windows/Mac, or Docker Engine on Linux).

## Quick start (bundled example)

From this folder (the one containing `Dockerfile`):

```bash
docker compose build
docker compose run --rm cdmetapop
```

`DATA_DIR` defaults to `./data`. Because it starts empty, the container seeds it
with the bundled `example_files/` and runs `RunVars.csv`. When it finishes, look
in `./data/output<timestamp>/` for results.

## Point the data directory at your server storage

Set `DATA_DIR` to any absolute host path. Two ways:

**A `.env` file** (copy `.env.example` to `.env`, then edit):

```ini
DATA_DIR=/srv/cdmetapop/data
RUNVARS=RunVars.csv
OUTPUT_NAME=output
```

```bash
docker compose run --rm cdmetapop
```

**Or inline for one run:**

```bash
DATA_DIR=/srv/cdmetapop/data docker compose run --rm cdmetapop
```

Put your own project inputs in that folder (a `RunVars.csv` and the input trees
it references). To use your own inputs *instead of* the seeded example, either
populate the folder before the first run, or set `SEED_EXAMPLES=0`.

## Choosing scenarios / output name

- `RUNVARS` — the run file to execute, relative to the data dir
  (e.g. `RUNVARS=RunVars_multispecies.csv`, or a subfolder path like
  `RUNVARS=DiseaseExamples/OnePatch_SIDP/RunVars_SIDP.csv`).
- `OUTPUT_NAME` — output folder prefix; CDMetaPOP appends a timestamp.

```bash
RUNVARS=RunVars_AddMyy.csv OUTPUT_NAME=trojanY docker compose run --rm cdmetapop
```

## Ad-hoc / interactive use

The entrypoint runs any command you pass, from `src/`:

```bash
# an interactive shell in the model environment
docker compose run --rm cdmetapop bash

# a fully custom invocation
docker compose run --rm cdmetapop python CDmetaPOP.py /data RunVars.csv myout
```

## Without compose (plain docker)

```bash
docker build -t cdmetapop:3.08 .
docker run --rm -v /srv/cdmetapop/data:/data \
  -e RUNVARS=RunVars.csv -e OUTPUT_NAME=output \
  cdmetapop:3.08
```

## Notes

- **Multi-species / multi-core.** CDMetaPOP uses Python multiprocessing
  (`ncores` in the run file, one process per species). Give Docker enough CPUs
  (Docker Desktop: Settings -> Resources) or cap it with `--cpus`.
- **File ownership on Linux hosts.** The container runs as root, so files it
  writes to a bind mount are root-owned. To get your own UID instead, add to the
  `cdmetapop` service in `docker-compose.yml`:
  `user: "${UID}:${GID}"` and run with
  `UID=$(id -u) GID=$(id -g) docker compose run --rm cdmetapop`.
  (Not an issue on Docker Desktop for Windows/Mac.)
- **Rebuild after changing source.** `docker compose build` again; your `/data`
  contents are untouched by rebuilds.
