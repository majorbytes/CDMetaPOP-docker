# Running CDMetaPOP in Docker

> **Try the demo (~30 seconds).** With Docker installed, from this folder run
> `docker compose build` then `docker compose run --rm cdmetapop`. With no
> configuration the container seeds a local `./data/` with the bundled inputs,
> runs a short single-batch example, and writes results to `./data/demo<timestamp>/`.

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

## Quick start (the demo)

From this folder (the one containing `Dockerfile`):

```bash
docker compose build
docker compose run --rm cdmetapop
```

`DATA_DIR` defaults to `./data`. Because it starts empty, the container seeds it
with the bundled `example_files/` and runs the fast demo (`RunVars_demo.csv` — a
single-batch, 5-generation scenario, ~30 s). When it finishes, look in
`./data/demo<timestamp>/` for results, e.g. `summary_popAllTime.csv`.

### Run the full example instead

The upstream example (`RunVars.csv`) runs four scenarios and takes a few minutes:

```bash
RUNVARS=RunVars.csv OUTPUT_NAME=output docker compose run --rm cdmetapop
```

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

## Running as your own user (Linux)

By default the container runs as **root**, so output written to your bind-mounted
data directory comes out owned by `root`. On Linux you usually want it owned by
you. Just tell it your host UID/GID — set them in `.env` (copy from
`.env.example`):

```ini
DOCKER_UID=1000     # your `id -u`
DOCKER_GID=1000     # your `id -g`
```

```bash
docker compose run --rm cdmetapop
# or inline, without editing .env:
DOCKER_UID=$(id -u) DOCKER_GID=$(id -g) docker compose run --rm cdmetapop
```

**How it works.** The image starts as root *inside the container* — which needs
**no root/sudo on the host**; it's provided by the Docker daemon you already use.
The entrypoint seeds the data dir, `chown`s it to your UID/GID, then drops
privileges with `gosu` so the model runs — and writes its output — as you. Because
root does the setup first, an **empty or root-owned data dir is handled
automatically**: no pre-creating the folder, no manual `chown`.

Left unset, `DOCKER_UID`/`DOCKER_GID` mean "stay root" (the original behavior), so
nothing changes for anyone who doesn't set them. None of this is needed on Docker
Desktop for Windows/Mac, where the bind-mount layer already maps ownership to you.

### Why a number and not your username

Use the numeric UID/GID, not a name. At the kernel level, file ownership and
process identity are **numbers**; a username is only a label that `/etc/passwd`
maps to a number — and the container has its *own* `/etc/passwd`. A name would be
looked up **inside the container**, where your username doesn't exist (`unable to
find user ...`), and even if it did it could map to a different number than on your
host. The bind mount records ownership by number, so matching the number is what
actually makes the files come out owned by you. (To have a real *named* non-root
user in the image you'd create one at build time with a pinned UID, e.g.
`useradd -u 1000` — but that just hardcodes the same number and only helps hosts
where you are 1000.)

### SELinux (Rocky/RHEL/Fedora)

These distros ship SELinux enforcing. If a run fails with `Permission denied` on
`/data`, add the `:Z` flag to the volume so Docker relabels the host folder for
container access — change the volume line in `docker-compose.yml` to:

```yaml
      - ${DATA_DIR:-./data}:/data:Z
```

(`:Z` relabels the folder for exclusive use by this container; use `:z` instead
if several containers share the same folder. Harmless no-op on Docker Desktop.)

## Notes

- **Multi-species / multi-core.** CDMetaPOP uses Python multiprocessing
  (`ncores` in the run file, one process per species). Give Docker enough CPUs
  (Docker Desktop: Settings -> Resources) or cap it with `--cpus`.
- **File ownership on Linux hosts.** By default output is root-owned; see
  [Running as your own user (Linux)](#running-as-your-own-user-linux) to have it
  written as you.
- **Rebuild after changing source.** `docker compose build` again; your `/data`
  contents are untouched by rebuilds.
