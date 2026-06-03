# DASDAE Inventory

A proposal for metadata management in DASDAE.

See the [rendered site](https://dasdae.github.io/inventory/) for details.

## Local Development

This repository is a Quarto documentation site for the proposed DASDAE
Inventory metadata model. The main model source of truth is
`specs/dasdae-inventory.yml`; the object reference pages in `References/` are generated from that file.

### Prerequisites

- [Quarto](https://quarto.org/)
- Python 3.10 or newer
- [uv](https://docs.astral.sh/uv/)

### Setup

Install the Python dependencies used by the reference generator:

```bash
uv sync
```

### Regenerate References

After editing `specs/dasdae-inventory.yml`, regenerate the object reference pages:

```bash
uv run python scripts/generate_references.py
```

Review and commit the generated `References/*.qmd` changes with the spec
change.

### Render The Site

Build the Quarto site locally:

```bash
quarto render
```

The rendered site is written to `_site/`.
