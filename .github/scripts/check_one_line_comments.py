#!/usr/bin/env python3
"""Explanation in code is capped at ONE line; the rest belongs in AGENTS.d - design and each exemption's rationale live in AGENTS.d/020-explanation-in-code-is-capped-at-one-line.md, not here."""

from __future__ import annotations

import argparse
import ast
import io
import json
import re
import subprocess
import sys
import tokenize
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BASELINE_PATH = REPO_ROOT / ".github" / "one-line-comment-baseline.json"

SKIP_PREFIXES: tuple[str, ...] = (
    # The example config is the reference users read and copy: its comments are the product, not explanation of code.
    "ataegina.config.example.sh",
    "coverage/",
    "node_modules/",
)

PRAGMAS: tuple[str, ...] = (
    "shellcheck",
    "bats",
    "noqa",
    "type: ignore",
    "pragma:",
    "ruff:",
    "mypy:",
    "fmt:",
    "DO NOT EDIT",
    "AUTO-GENERATED",
    "SPDX-",
    "Copyright",
    "!/usr/bin",
    "!/bin/sh",
    "-*- coding",
)

GENERATED_MARKERS = re.compile(
    r"DO NOT EDIT|AUTO-?GENERATED|THIS FILE IS GENERATED|@generated|Generated\s*(from|-\s*see)",
    re.IGNORECASE,
)

BASH_EXTS: tuple[str, ...] = (".sh", ".bash", ".bats")
YAML_EXTS: tuple[str, ...] = (".yml", ".yaml")
SHEBANG_RE = re.compile(r"^#!.*\b(bash|sh)\b")
HEREDOC_RE = re.compile(r"<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
BLOCK_SCALAR_RE = re.compile(r"^(\s*)\S.*:\s*[|>][+\-0-9]*\s*(#.*)?$")


def is_skipped(path: str) -> bool:
    """True when `path` is exempt by prefix."""
    return any(path.startswith(p) for p in SKIP_PREFIXES)


def is_generated(text: str) -> bool:
    """True when the first 40 lines claim the file is generated."""
    return bool(GENERATED_MARKERS.search("\n".join(text.split("\n")[:40])))


def has_pragma(lines: list[str]) -> bool:
    """True when any line in the run carries a tooling pragma."""
    return any(p in line for line in lines for p in PRAGMAS)


def _runs(linenos: list[int], lines: list[str]) -> list[tuple[int, str]]:
    """Consecutive comment lines grouped into runs longer than one line."""
    out: list[tuple[int, str]] = []
    run: list[int] = []

    def flush(r: list[int]) -> None:
        if len(r) > 1:
            body = [lines[k - 1] for k in r]
            if not has_pragma(body):
                out.append((r[0], f"comment run spans {len(r)} lines"))

    for n in linenos:
        if run and n == run[-1] + 1:
            run.append(n)
            continue
        flush(run)
        run = [n]
    flush(run)
    return out


def bash_violations(text: str) -> list[tuple[int, str]]:
    """Multi-line standalone `#` comment runs, skipping heredoc bodies where `#` is literal content, not a comment."""
    lines = text.split("\n")
    standalone: list[int] = []
    delim = ""
    for i, raw in enumerate(lines, start=1):
        if delim:
            if raw.strip() == delim:
                delim = ""
            continue
        stripped = raw.strip()
        if stripped.startswith("#"):
            if i > 1 or not SHEBANG_RE.match(raw):
                standalone.append(i)
            continue
        m = HEREDOC_RE.search(raw)
        if m:
            delim = m.group(2)
    return _runs(standalone, lines)


def yaml_violations(text: str) -> list[tuple[int, str]]:
    """Multi-line standalone `#` comment runs, skipping block-scalar bodies (`run: |` scripts) where `#` is literal content, not a YAML comment."""
    lines = text.split("\n")
    standalone: list[int] = []
    in_block = False
    block_parent_indent = 0
    for i, raw in enumerate(lines, start=1):
        if in_block:
            stripped = raw.strip()
            indent = len(raw) - len(raw.lstrip(" "))
            if stripped == "" or indent > block_parent_indent:
                continue
            in_block = False
        m = BLOCK_SCALAR_RE.match(raw)
        if m:
            block_parent_indent = len(m.group(1))
            in_block = True
            continue
        if raw.strip().startswith("#"):
            standalone.append(i)
    return _runs(standalone, lines)


def python_violations(text: str) -> list[tuple[int, str]]:
    """Multi-line docstrings and multi-line standalone comment runs."""
    out: list[tuple[int, str]] = []
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return out
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        body = node.body
        if not body:
            continue
        first = body[0]
        if not (
            isinstance(first, ast.Expr)
            and isinstance(first.value, ast.Constant)
            and isinstance(first.value.value, str)
        ):
            continue
        span = first.end_lineno - first.lineno + 1
        if span > 1:
            name = getattr(node, "name", "<module>")
            out.append((first.lineno, f"docstring spans {span} lines ({name})"))
    lines = text.split("\n")
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError, IndentationError):
        return out
    standalone = sorted(
        t.start[0]
        for t in toks
        if t.type == tokenize.COMMENT and not lines[t.start[0] - 1][: t.start[1]].strip()
    )
    out.extend(_runs(standalone, lines))
    return out


def surface_of(rel: str, text: str) -> str:
    """Which scanner a path belongs to: bash, yaml, python, or none."""
    if rel.endswith(BASH_EXTS):
        return "bash"
    if rel.endswith(YAML_EXTS):
        return "yaml"
    if rel.endswith(".py"):
        return "python"
    if "." not in Path(rel).name and SHEBANG_RE.match(text.split("\n", 1)[0]):
        return "bash"
    return ""


def scan(paths: list[str]) -> tuple[dict[str, list[tuple[int, str]]], int]:
    """Violations per path plus the number of files actually scanned."""
    found: dict[str, list[tuple[int, str]]] = {}
    scanned = 0
    for rel in paths:
        if is_skipped(rel):
            continue
        full = REPO_ROOT / rel
        if not full.is_file():
            continue
        try:
            text = full.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        surface = surface_of(rel, text)
        if not surface or is_generated(text):
            continue
        scanned += 1
        hits = {
            "bash": bash_violations,
            "yaml": yaml_violations,
            "python": python_violations,
        }[surface](text)
        if hits:
            found[rel] = hits
    return found, scanned


def all_source_paths() -> list[str]:
    """Every tracked path; surface_of filters them down."""
    out = subprocess.run(
        ["git", "ls-files"], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    ).stdout
    return [p for p in out.split("\n") if p]


def _regressions(counts: dict[str, int], baseline: dict[str, int], found: dict) -> list[str]:
    """Lines describing every path whose count exceeds its baselined allowance."""
    out: list[str] = []
    for path, n in sorted(counts.items()):
        allowed = baseline.get(path, 0)
        if n > allowed:
            out.append(f"  {path}: {n} > {allowed} allowed")
            for lineno, why in found[path][:4]:
                out.append(f"      {path}:{lineno}  {why}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()

    paths = args.files or all_source_paths()
    found, scanned = scan(paths)
    counts = {p: len(v) for p, v in found.items()}

    if args.write_baseline:
        BASELINE_PATH.write_text(
            json.dumps({"files": dict(sorted(counts.items()))}, indent=2) + "\n",
            encoding="utf-8",
        )
        print(
            f"one-line-comments: baseline written - {len(counts)} file(s)/"
            f"{sum(counts.values())} violation(s) over {scanned} scanned file(s)."
        )
        return 0

    if not scanned:
        print("one-line-comments: no files matched - refusing to pass vacuously", file=sys.stderr)
        return 2
    if not BASELINE_PATH.exists():
        print(f"one-line-comments: missing baseline at {BASELINE_PATH}.", file=sys.stderr)
        print("Generate it once with: --write-baseline", file=sys.stderr)
        return 2

    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8")).get("files", {})
    regressions = _regressions(counts, baseline, found)
    if regressions:
        print("one-line-comments: explanation in code is capped at ONE line.\n")
        print("\n".join(regressions))
        print(
            "\nA run of standalone comment lines is ONE line, and a python docstring is one line.\n"
            "Move the rest into an AGENTS.d/ rule or a doc. Heredoc bodies and runs carrying a\n"
            "shellcheck / bats / noqa pragma are exempt.\n"
            f"\nScanned {scanned} file(s). Baseline: {BASELINE_PATH.relative_to(REPO_ROOT)}"
        )
        return 1

    total = sum(counts.values())
    baseline_total = sum(baseline.values())
    print(
        f"one-line-comments: OK - {scanned} file(s) scanned, {total} baselined "
        f"violation(s) remaining (baseline {baseline_total})."
    )
    if total < baseline_total:
        print(
            "  A count went DOWN. Refresh the baseline so it cannot creep back: "
            "python3 .github/scripts/check_one_line_comments.py --write-baseline"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
