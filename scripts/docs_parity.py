#!/usr/bin/env python3
"""Bilingual docs parity and leak gate.

Checks the docs site's language trees against each other:

* Pairing: every ``.md`` under the base language tree (first in --languages)
  must exist at the same relative path in every other language tree, and vice
  versa.  Pages whose frontmatter carries ``annex: true`` (permanent
  single-language appendix) or ``draft: true`` (unfinished) are exempt from
  pairing -- but never from the leak scan.
* Titles: every paired page must carry a frontmatter ``title:`` that exists
  and is non-empty in every language tree.  Titles are *translated* per locale
  on purpose (each tree's nav renders from its own pages' titles), so titles
  that differ across trees are expected and never fail the gate.
* Sync: paired pages whose frontmatter ``sync:`` dates differ produce a WARN
  on stderr but still exit 0.
* Leak scan: every ``.md`` under every language tree (annex and draft pages
  included) and every text asset under ``<docs-dir>/assets/`` (``*.html`` --
  the published architecture diagram among them) is scanned for the
  substrings listed in ``scripts/docs_leak_patterns.txt`` (one per line,
  ``#`` lines are comments).
* Frontmatter shape: a leading ``---`` block that is never closed fails the
  gate loudly -- silently parsing the page body as metadata would let a body
  ``annex: true`` exempt a page from pairing.

Exit code: 0 = clean (WARNs allowed), 1 = missing pair / missing or empty
title / leak pattern hit / unterminated frontmatter.  Pure stdlib; frontmatter
is parsed by splitting the leading ``---`` block into ``key: value`` lines
(no PyYAML).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import NamedTuple

DEFAULT_DOCS_DIR = "docs"
DEFAULT_LANGUAGES = "en,zh"
PATTERNS_FILENAME = "docs_leak_patterns.txt"
ASSETS_DIRNAME = "assets"
ASSETS_GLOB = "*.html"


class FrontmatterError(Exception):
    """A page opens a ``---`` frontmatter block that is never closed."""


class Page(NamedTuple):
    path: Path
    frontmatter: dict
    text: str


def parse_frontmatter(text: str) -> dict:
    """Parse the leading ``---`` block of a Markdown page into a dict.

    Only simple ``key: value`` lines are recognised; everything else in the
    block is ignored.  Returns ``{}`` when the file has no frontmatter block.
    Raises :class:`FrontmatterError` when the opening ``---`` is never closed:
    for a gate the safe semantics is loud, because an unterminated block would
    parse body lines as metadata (a body ``annex: true`` would silently exempt
    a page from pairing).
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    meta = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return meta
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    raise FrontmatterError("frontmatter block opened but never closed")


def collect_pages(lang_dir: Path) -> tuple:
    """Map every ``.md`` under ``lang_dir`` to ``{slug: Page}`` (slug = relative posix path).

    Returns ``(pages, malformed)`` where ``malformed`` lists the slugs whose
    frontmatter block never closes (they are excluded from ``pages`` so the
    pairing check does not cascade; the caller reports them as FAILs).
    """
    pages = {}
    malformed = []
    for path in sorted(lang_dir.rglob("*.md")):
        text = path.read_text(encoding="utf-8")
        slug = path.relative_to(lang_dir).as_posix()
        try:
            meta = parse_frontmatter(text)
        except FrontmatterError:
            malformed.append(slug)
            continue
        pages[slug] = Page(path, meta, text)
    return pages, malformed


def collect_assets(assets_dir: Path) -> list:
    """List the publishable text assets under ``assets_dir`` (``*.html``)."""
    if not assets_dir.is_dir():
        return []
    return sorted(assets_dir.rglob(ASSETS_GLOB))


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
            pages, malformed = collect_pages(lang_dir)
            for slug in malformed:
                err.write(
                    f"FAIL: unterminated frontmatter: {lang}/{slug} "
                    f"(opening '---' never closed; body lines would parse "
                    f"as metadata)\n"
                )
                problems += 1
                ok = False
            trees[lang] = pages

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

    # --- Titles: every paired page must carry a non-empty title in every tree.
    # Titles are translated per locale (each tree's nav renders from its own
    # pages' titles), so differing titles between trees are fine; only a
    # missing or empty title fails.
    for slug in paired:
        for lang in languages:
            title = trees[lang][slug].frontmatter.get("title")
            if title is None or not title.strip():
                err.write(
                    f"FAIL: missing title: {lang}/{slug} "
                    f"(frontmatter title: must exist and be non-empty)\n"
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

    # --- Leak scan (continued): published text assets under docs/assets ---
    assets_scanned = 0
    for path in collect_assets(docs_dir / ASSETS_DIRNAME):
        assets_scanned += 1
        text = path.read_text(encoding="utf-8")
        for pattern in patterns:
            if pattern in text:
                rel = path.relative_to(docs_dir).as_posix()
                err.write(f"FAIL: leak: {rel} contains pattern {pattern!r}\n")
                leaks += 1
                problems += 1
                ok = False
                break

    langs_label = "+".join(languages)
    if ok:
        out.write(
            f"OK: {len(paired)} paired, {len(exempt)} exempt, "
            f"{scanned} pages + {assets_scanned} asset file(s) leak-scanned "
            f"({langs_label})\n"
        )
    else:
        out.write(
            f"FAILED: {problems} problem(s), {len(paired)} paired, "
            f"{len(exempt)} exempt, {leaks} leak(s) in {scanned} pages + "
            f"{assets_scanned} asset file(s) ({langs_label}); "
            f"details on stderr\n"
        )
    return ok


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Bilingual docs parity and leak gate "
        "(exit 0 = clean, warnings allowed; exit 1 = missing pair / "
        "missing or empty title / leak / unterminated frontmatter)."
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
