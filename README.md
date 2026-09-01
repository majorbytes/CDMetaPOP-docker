# CDMetaPOP-docker

> **Dockerized fork.** This repository packages **CDMetaPOP** to build and run in Docker
> with a persistent, host-mounted data directory. The model source and science are unchanged;
> only container tooling was added. Original project by the Computational Ecology Laboratory,
> University of Montana: https://github.com/ComputationalEcologyLab/CDMetaPOP

The Docker usage guide is below. The original CDMetaPOP README follows after it.

## Running CDMetaPOP in Docker

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

---

======
README
======

---------------------- 
CDMetaPOP 3.00 release
----------------------
  
Welcome to the CDMetaPOP v3.0 release! This release includes installation instructions, version notes, some examples, and technical documentation. 

For the user manual that contains complete documentation, please see the doc/ directory in this repository.
  
Program Contributors: Erin Landguth, Casey Day, Andrew Bearlin, Jason Dunham, Ryan Simmons, Brenna Forrester, Kaeli Davenport, and Travis Seaborn
Link: https://github.com/ComputationalEcologyLab/CDMetaPOP
Version: 3.08 
Python: 3.8
Release Date: 2025.09.18
README Update: 2025.11.7 (ccd)
  
--------
Contents
--------
  
Included in this release are the following:

src -> CDMetaPOP source files

doc -> README.txt, user manual, history, and disclaimer

example_files -> test example files
- RunVars.csv - Runs several scenarios (Variable climate, population introduction) with varying life history parameters.
- RunVars_AddMyy.csv and RunVars_AddFyy.csv - Demonstrates the Trojan Y chromosome control strategy using YY males or YY females, respectively.
- RunVars_multispecies.csv - Demonstrates 2- and 3-species applications, including competition.
- DiseaseExamples
    - Adaptive_Run06 - Demonstrates genetic adaptation to disease via resistance and tolerance.
    - OnePatch_SIDP - SIR simulations to match simple theoretical patterns. 
environment.yml file -> conda environment file to run CDMetaPOP simulations in conda
---------------------------------------
Requirements and Pre-requisite Software
---------------------------------------

1. Baseline Requirements. CDMetaPOP requires the Python3.8.x interpreter, NumPy package, and SciPy package. Remember that Python modules usually require particular Python interpreters, so be sure the version ID for any external Python module or package (e.g. NumPy or others) matches the version of your Python interpreter (normally v3.8.x). To avoid Python installation errors, we highly recommend installing Python from any number of the freely available bundlers that include the NumPy and SciPy packages, e.g., Anaconda (recommended), Canopy, ActiveState.

2. Example Python installation using 'conda'. First, download the Anaconda software at https://www.anaconda.com/download or just the conda package installer. Then open an Anaconda prompt (Windows) or run conda from the terminal (Mac, Linux) and run the following. Make sure the environment.yml file is in your working directory.

`conda env create -f environment.yml`

`conda activate cdmetapop`

`_Run-your-CDMetaPOP-code_` (see example below)

`conda deactivate`

---------------------------
CDMetaPOP v3.0 Installation
--------------------------- 

Linux or Windows: Download the repository from Github. Navigate to the directory on your PC where you wish to install CDMetaPOP, and unpack the zipped repository using a free archive tool like 7Zip (7z.exe), Pkunzip, Unzip, or an equivalent. Seven-Zip (7Z.exe) is highly recommended since it can handle all common formats on Windows, MAC OS X and Linux. On Windows, it is best to set up a project specific modeling subdirectory to perform your modeling outside of any folder that has spaces in its name (like "My Documents").

--------------------------------------
Understanding CDMetaPOP file structure
--------------------------------------
1. In the example_files directory, the included file ‘RunVars.csv’ specifies the parameters that apply to all species that can be changed and used in a sample CDMetaPOP run. Open ‘RunVars.csv’ in your editor of choice. A spreadsheet program like Microsoft Excel allows for easy editing of the tabular values. The location(s) of the 'PopVars' files (one for each species in the simulation) are specified in the first column.

2. The various ‘PopVars’ files define the patch files in the first column. The included ‘PatchVars’ files will also be in the same folder (../example_files/patchvars). ‘ClassVars’ files are in turn specified in the ‘PatchVars’ files and example ‘ClassVars’ files will be in the ../example_files/classvars/ folder. 

3. There will be 5 lines of information in ‘RunVars.csv’: a header line and 4 lines of information corresponding to 4 separate, single-species CDMetaPOP runs. See Table 1 in user manual which contains a breakdown for each column header and the parameters that can be defined. The ‘Input’ in the table listed is for the first row in the file. Make sure you save this file in the same format – a comma delimited file – when you make changes to the parameters. Do not change the ‘Input’ (first row) labeling. Select ‘Yes’ or ‘OK’ for any Excel questions about saving in this format. 'RunVars_multispecies.csv' contains two runs, the first for a 2-species example and the second for a 3-species example.

4. The file structure for basic CDMetaPOP runs is displayed in the figure below.

<img width="361" height="511" alt="FileStructure drawio" src="https://github.com/user-attachments/assets/c3aeecff-26a5-43b7-995e-1fdd57bd8d91" />
 
---------------------
Example CDMetaPOP Run
---------------------

The primary example run ('RunVars.csv') is for 7 patches representing an effective distance matrix calculated using a least-cost path algorithm through riverine distance . To run the following example, follow these steps:

1. Double check that the 3 directories provided in the Git download are in the same directory.

      * doc
      * example_files
      * src 
2. Start the program: For example, if you use python from the command line, then open a terminal window and change your shell directory to the CDMetaPOP src home directory (i.e., > cd C:\"homedirectorylocation"\src). 

3. Launch CDMetaPOP: There are a number of ways to run CDMetaPOP. If you are using a command shell you can run the program by setting your working directory to the location of the src/ folder and typing

    `python CDMetaPOP.py C:/”homedirectorylocation”/example_files/ RunVars.csv output_test`

   Or a short-cut if your example files are located in the same folder level as the src folder:
   
   `python CDMetaPOP.py ../example_files/ RunVars.csv output_test`

   Note that there are 5 arguments here that must be included with spaces in between: 

    1. `python` starts python, for example from the command line. Note that other python environments may have different calls here. In iPython (the IDE distributed with Anaconda) the call is “run”. 
    2. `CDMetaPOP.py` runs CDMetaPOP program. If your working directory is not the src/ folder, then you use the full filepath to the CDMetaPOP.py run instead of just CDMetaPOP.py.
    3. `C:/”homedirectorylocation”/example_files` is the directory location of the input test files. You can point this directory to other project files, for example. We suggest not having any spaces in your directory names. So as projects accumulate you can rename input folders that contain the project specific files (e.g., dataWestslope or dataBullTrout).
    4. `RunVars.csv` is the primary parameter file (comma delimited) which can be renamed (e.g., RunVars_WCT.csv or your_favorite_name.csv). Caution should be taken when going between operating systems and saving this file as a .csv.
    5. `output_test` is the name of the directory that will be created with CDMetaPOP output in the directory specified by the third argument above.

4. Check for successful model run completion: The program will provide step-by-step output in the Shell window. Each row of RunVars.csv will run an independent simulation in sequence for each line in PopVars.csv (batches). Once completed, a simulation time will be printed out and folders run0batch0mc0species0, run0batch0mc1species0,  run0batch1mc0species0, etc. will be created in your CDMetaPOP home directory to store output from the separate runs, batches Monte-Carlo replicates, and species (each line in the RunVars file corresponds to a separate 'run' and each line in the PopVars file corresponds to a separate 'batch'. Monte Carlo runs are specified by 'mc'). These folders are located in the data folder specified in above step. The output folder will have a unique date/time stamp after the name of the output folder in case you want to run multiple CDMetaPOP runs in this same directory. The program will also provide a log file with program steps in your specified output directory. If parameters are such that all species become extinct before the specified generation time, the program will end. The program will provide error and feedback for parameters that are outside of ranges or incorrectly entered.
-------------------------------------------------
Developing your own simulations – Getting started
-------------------------------------------------	

“CDMetaPOP has so many variables and options. Where do I start?” Below, we list some of the critical parameters and processes that will help to tailor the simulations to your own system. For more detail and additional options, see Uesr Manual Section 3 – Input.

**Demographics**

We recommend calibrating demographics prior to incorporating additional complexity to ensure that population growth is behaving as expected in isolation.
* **sizecontrol** (RunVars file) – This parameter determines whether several processes (maturation, growth, fecundity) are determined by the individual’s age or size. When getting started, we recommend **sizecontrol=N**, because these processes can be more easily controlled – primarily via the ClassVars file (see below).
* **popmodel** (Popvars file) – This parameter controls the model of population growth that will be implemented. When starting, we recommend **popmodel = N** (exponential model) for its simplicity.
* Maturation – If **sizecontrol=N**, age-specific probability of maturation can be defined in the **Maturation** column in the ClassVars file. If **sizecontrol=Y**, probability of maturation is controlled as a logistic function of size using the **mature_eqn_slope** and **mature_eqn_int** parameters in the PopVars file.
* Fecundity – If **sizecontrol=N**, age-specific fecundity is defined in the **Fecundity ind** column in the ClassVars file. If **sizecontrol=Y**, fecundity is controlled as a function of size using the **Egg_mean_ans**, **Egg_mean_par1**, and **Egg_mean_par2** parameters in the PopVars file. 
* Growth – Determined by the **growth_option** parameter in PopVars. The simplest option is to use **growth_option=N** to ignore growth altogether (if **sizecontrol=N**), or **growth_option=’known’** will set size based on age and equal to that listed in the **Body Size Mean** column in the ClassVars file. 

**Movement**

There are 4 modes of movement in CDMetaPOP – mating, migration, straying, and dispersal. It is only mandatory to define mating movement, as all others can be turned off by setting their probabilities to 0 in the PatchVars and ClassVars files. Each mode of movement has 5 parameters associated with it. We highlight 2 of these that are needed for basic simulations.
* **matemoveno** (PopVars file) – Defines the movement distribution. The simplest cases are **matemoveno=4**, which will move individuals to random locations, and **matemoveno=6**, which will prevent movement outside of the individual’s current patch.
* **Matemovethresh** (PopVars file) – Defines a movement distance threshold. **matemovethresh=max** will not apply any cap on the distance individuals may move.

**Genetics**

Many options exist for simulating neutral and adaptive genetics in CDMetaPOP. Below, we list a few critical parameters to get started.
* **loci** (PopVars file) – Define number of loci to track.
* **Alleles** (PopVars file) – Define number of alleles to track per locus.
* **Genes Initialize** (PatchVars file) – Determine whether initial allele assignment will be **random**, or based on an allele frequency file (see example files folder), which can vary by patch.

**Outputs**

Below, we suggest some key metrics that can serve as a starting point for evaluating simulation outcomes.
* **N_initial** (summary_popAllTime.csv) – Helpful for evaluating population size over time.*
* **EggLayEvents** and **Births** (summary_popAllTime.csv) – Helpful for evaluating fecundity and reproduction.
* **He**, **Ho** (summary_popAllTime.csv) – Simple heterozygosity measures over time.
* **N_Initial_Age** (summary_classAllTime.csv) – Provides population size by age.
* **AgeSize_Mean** (summary_classAllTime.csv) – Provides mean size at age to check the growth model.


Happy Simulations!

Computational Ecology Laboratory
The University of Montana
32 Campus Drive
Missoula MT, 59812-1002
computationalecologylab@gmail.com
