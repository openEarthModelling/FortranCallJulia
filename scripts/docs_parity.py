#!/usr/bin/env python3
"""Bilingual docs parity and leak gate.

Checks the docs site's language trees against each other:

* Pairing: every ``.md`` under the base language tree (first in --languages)
  must exist at the same relative path in every other language tree, and vice
  versa.  Pages whose frontmatter carries ``annex: true`` (permanent
  single-language appendix) or ``draft: true`` (unfinished) are exempt from
  pairing -- but never from the leak scan.
* Title set: the set of frontmatter ``title:`` values of paired pages must be
  identical across language trees.
* Sync: paired pages whose frontmatter ``sync:`` dates differ produce a WARN
  on stderr but still exit 0.
* Leak scan: every ``.md`` under every language tree (annex and draft pages
  included) is scanned for the substrings listed in
  ``scripts/docs_leak_patterns.txt`` (one per line, ``#`` lines are comments).

Exit code: 0 = clean (WARNs allowed), 1 = missing pair / title-set mismatch /
leak pattern hit.  Pure stdlib; frontmatter is parsed by splitting the leading
``---`` block into ``key: value`` lines (no PyYAML).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import NamedTuple

DEFAULT_DOCS_DIR = "docs"
DEFAULT_LANGUAGES = "en,zh"
PATTERNS_FILENAME = "docs_leak_patterns.txt"


class Page(NamedTuple):
    path: Path
    frontmatter: dict
    text: str


def parse_frontmatter(text: str) -> dict:
    """Parse the leading ``---`` block of a Markdown page into a dict.

    Only simple ``key: value`` lines are recognised; everything else in the
    block is ignored.  Returns ``{}`` when the file has no frontmatter block.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    meta = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    return meta


def collect_pages(lang_dir: Path) -> dict:
    """Map every ``.md`` under ``lang_dir`` to ``{slug: Page}`` (slug = relative posix path)."""
    pages = {}
    for path in sorted(lang_dir.rglob("*.md")):
        text = path.read_text(encoding="utf-8")
        slug = path.relative_to(lang_dir).as_posix()
        pages[slug] = Page(path, parse_frontmatter(text), text)
    return pages


def load_patterns(patterns_file: Path) -> list:
    """Read leak patterns: one substring per line, '#' lines and blanks ignored."""
    patterns = []
    for raw in patterns_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def is_exempt(page: Page) -> bool:
    """True when the page's frontmatter marks it annex or draft."""
    for key in ("annex", "draft"):
        if page.frontmatter.get(key, "").lower() == "true":
            return True
    return False


def run_check(docs_dir: Path, languages: list, patterns_file: Path, out, err) -> bool:
    """Run all gate checks; print WARN/FAIL lines to ``err`` and a summary to ``out``.

    Returns True when the gate passes (warnings allowed).
    """
    ok = True
    problems = 0
    patterns = load_patterns(patterns_file)

    trees = {}
    for lang in languages:
        lang_dir = docs_dir / lang
        if not lang_dir.is_dir():
            err.write(f"FAIL: language tree not found: {lang_dir}\n")
            problems += 1
            ok = False
            trees[lang] = {}
        else:
            trees[lang] = collect_pages(lang_dir)

    base, others = languages[0], languages[1:]

    # --- Pairing (annex/draft slugs exempt, in either tree of the pair) ---
    all_slugs = set()
    for lang in languages:
        all_slugs.update(trees[lang])

    paired = []
    exempt = []
    for slug in sorted(all_slugs):
        if any(is_exempt(trees[lang][slug]) for lang in languages if slug in trees[lang]):
            exempt.append(slug)
            continue
        missing_in = [lang for lang in languages if slug not in trees[lang]]
        if missing_in:
            present_in = [lang for lang in languages if slug in trees[lang]]
            err.write(
                f"FAIL: missing pair: {slug} (present: {','.join(present_in)}; "
                f"missing: {','.join(missing_in)})\n"
            )
            problems += 1
            ok = False
        else:
            paired.append(slug)

    # --- Title set: paired pages must carry the same set of titles per tree ---
    title_sets = {lang: set() for lang in languages}
    for slug in paired:
        for lang in languages:
            title = trees[lang][slug].frontmatter.get("title")
            if title is not None:
                title_sets[lang].add(title)
    for lang in others:
        only_base = title_sets[base] - title_sets[lang]
        only_lang = title_sets[lang] - title_sets[base]
        if only_base or only_lang:
            err.write(
                f"FAIL: title set mismatch ({base} vs {lang}): "
                f"only in {base}: {sorted(only_base)}; "
                f"only in {lang}: {sorted(only_lang)}\n"
            )
            problems += 1
            ok = False

    # --- Sync dates: mismatched paired dates WARN but do not fail ---
    for slug in paired:
        base_sync = trees[base][slug].frontmatter.get("sync")
        for lang in others:
            other_sync = trees[lang][slug].frontmatter.get("sync")
            if base_sync != other_sync:
                err.write(
                    f"WARN: {slug} sync stale "
                    f"({base}={base_sync if base_sync else 'none'} "
                    f"{lang}={other_sync if other_sync else 'none'})\n"
                )

    # --- Leak scan: every page in every tree, exemptions included ---
    scanned = 0
    leaks = 0
    for lang in languages:
        for slug, page in sorted(trees[lang].items()):
            scanned += 1
            for pattern in patterns:
                if pattern in page.text:
                    err.write(
                        f"FAIL: leak: {lang}/{slug} contains pattern {pattern!r}\n"
                    )
                    leaks += 1
                    problems += 1
                    ok = False
                    break

    langs_label = "+".join(languages)
    if ok:
        out.write(
            f"OK: {len(paired)} paired, {len(exempt)} exempt, "
            f"{scanned} pages leak-scanned ({langs_label})\n"
        )
    else:
        out.write(
            f"FAILED: {problems} problem(s), {len(paired)} paired, "
            f"{len(exempt)} exempt, {leaks} leak(s) ({langs_label}); "
            f"details on stderr\n"
        )
    return ok


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Bilingual docs parity and leak gate "
        "(exit 0 = clean, warnings allowed; exit 1 = missing pair / "
        "title-set mismatch / leak)."
    )
    parser.add_argument(
        "--docs-dir",
        default=DEFAULT_DOCS_DIR,
        help=f"docs root containing one subdirectory per language (default: {DEFAULT_DOCS_DIR})",
    )
    parser.add_argument(
        "--languages",
        default=DEFAULT_LANGUAGES,
        help=f"comma-separated language trees; the first is the pairing base "
        f"(default: {DEFAULT_LANGUAGES})",
    )
    args = parser.parse_args(argv)

    languages = [lang.strip() for lang in args.languages.split(",") if lang.strip()]
    if len(languages) < 2:
        parser.error("--languages needs at least two comma-separated trees")

    docs_dir = Path(args.docs_dir)
    patterns_file = Path(__file__).resolve().parent / PATTERNS_FILENAME
    if not patterns_file.is_file():
        print(f"FAIL: leak patterns file not found: {patterns_file}", file=sys.stderr)
        return 1

    return 0 if run_check(docs_dir, languages, patterns_file, sys.stdout, sys.stderr) else 1


if __name__ == "__main__":
    sys.exit(main())
