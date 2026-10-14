# template

A template repository for research projects that combine a data pipeline (Python/R/etc.), a LaTeX paper, and per-issue LaTeX reports, developed with [Claude Code](https://claude.com/claude-code).

## Repository structure

```
code/
  scripts/           # all code (.py, .R, .do, .ipynb, .sh, .sql, .jl, .m, .cpp, .c, .stan)
  analysis/outputs/  # committed deliverable figures/tables referenced by paper/ or reports/
  analysis/input/    # gitignored
  analysis/interm/   # gitignored
  build/             # gitignored working directory (input/interm/outputs)
  gcp-shared-config/ # gitignored credentials mount
  Dockerfile, docker-compose.yaml, requirements.txt
paper/               # the LaTeX paper (main.tex \input-ing introduction/, literature/, theory/, data/, methods/, conclusion/)
reports/             # one report.tex + report.pdf per closed issue, plus the running context.md log
references/          # read-only guidance carried over from prior projects — never edit
.claude/             # Claude Code settings, hooks, and permissions for this repo
```

## Running the code

Everything runs inside the project container:

```
cd code
docker compose up --build
```

This starts a Jupyter environment (`jupyter/datascience-notebook` base image) with `code/scripts`, `code/build`, and `code/analysis` mounted in. Add new Python/R/etc. dependencies to `code/requirements.txt` and `code/Dockerfile`.

## Working with KLC (Kellogg Linux Cluster)

Workflow: (1) connect and work on KLC, with JupyterLab reached through SSH; (2) test code locally in a container that recreates the KLC environment, or process samples there when KLC is unavailable; (3) run on KLC; (4) commit and push from KLC when needed, and keep a log of the files available there.

Setup: copy `code/scripts/klc/klc.config.local.example` to `klc.config.local` (gitignored; user, host, optional key/password). The repo is cloned on KLC at `~/<repo name>` (`KLC_REMOTE_DIR`) with a read-only/read-write deploy key; data lives in that clone's `code/build/input/` (`KLC_DATA_DIR`).

```
bash code/scripts/klc/klc-ssh.sh connect|run '<cmd>'|status|close   # shared SSH connection (opens itself if credentials are stored)
bash code/scripts/klc/klc-jupyter.sh start|status|stop              # JupyterLab on KLC; prints the localhost link
python3 code/scripts/klc/klc_manifest.py                            # refresh the file list + change log
docker compose --profile klc run --rm klc-sim python scripts/<script>.py   # LOCAL test container
```

- **Docker is local only.** `klc-sim` (RHEL 8 / Python 3.13 / KLC shared-environment versions, see `code/Dockerfile.klc`) is for testing code before running it on KLC or processing samples when KLC is unavailable. Never run Docker on KLC.
- **Commits made on KLC** carry a `Run in KLC (host: ...)` line, added by the `prepare-commit-msg` hook. On a fresh KLC clone enable it with `git config core.hooksPath code/scripts/klc/hooks`.
- **File log:** `code/build/input/klc/klc_manifest.csv` lists the files available on KLC; `klc_file_log.csv` records when each was first seen, modified or removed (refreshed by `klc_manifest.py`). `code/build/input/klc/samples/` holds local samples (contents gitignored).
- Analysis scripts read only `DATA_ROOT`: the local samples in `klc-sim`, the full data on KLC.

## The paper

`paper/main.tex` assembles the paper from per-section files (`introduction/`, `literature/`, `theory/`, `data/`, `methods/`, `conclusion/`) and `paper/references.bib`. Compile with `latexmk -pdf paper/main.tex`. Figures/tables the paper references must live in `code/analysis/outputs/`, not directly in `paper/`.

## Working with Claude Code

This repo is meant to be driven through Claude Code, with the full conventions documented in [CLAUDE.md](CLAUDE.md). The short version:

1. Every task starts as a GitHub issue, then a linked branch.
2. Work is delivered as `reports/<topic>_<scope>_report.tex` + compiled `.pdf`.
3. Before closing the issue: push the branch, post a summary comment, and append an entry to `reports/context.md` (a running log of durable project context, auto-loaded into every Claude Code session).
4. Closing the issue (`gh issue close`) ends the Claude Code session — a hook enforces this, so it's the last step, not something to do mid-task.
5. **Merging the branch/PR into `main` is done by the user**, not by Claude.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
