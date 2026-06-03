#!/usr/bin/env python3
"""Synchronize the Quarto site title from the DASDAE inventory spec."""

from __future__ import annotations

from pathlib import Path
import re

import yaml


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "specs" / "dasdae-inventory.yml"
QUARTO_PATH = ROOT / "_quarto.yml"


def load_spec() -> dict:
    with SPEC_PATH.open() as file:
        return yaml.safe_load(file)


def site_title(spec: dict) -> str:
    title = str(spec.get("title") or SPEC_PATH.stem)
    proposal_version = str(spec.get("proposal_version") or "").strip()
    if not proposal_version:
        return title
    display_version = proposal_version if proposal_version.startswith("v") else f"v{proposal_version}"
    return f"{title} ({display_version})"


def main() -> None:
    title = site_title(load_spec())
    quarto = QUARTO_PATH.read_text()
    updated = re.sub(
        r"(?m)^website:\n(?P<body>(?:^  .*\n?)*)",
        lambda match: "website:\n"
        + re.sub(
            r'(?m)^  title: .*$',
            f'  title: "{title}"',
            match.group("body"),
            count=1,
        ),
        quarto,
        count=1,
    )
    if updated == quarto and f'  title: "{title}"' not in quarto:
        raise RuntimeError("Could not find website.title in _quarto.yml")
    if updated != quarto:
        QUARTO_PATH.write_text(updated)


if __name__ == "__main__":
    main()
