"""Unit tests for scripts/docs_parity.py (bilingual parity + leak gate).

Each test builds a minimal two-tree docs site under tmp_path and runs the
gate via its CLI entry point, asserting on the exit code and stderr.

The leak tests rely on the pattern ``/home/`` being present in
scripts/docs_leak_patterns.txt (pinned by the docs-tree plan as one of the
three initial patterns).
"""

import sys
from collections.abc import Sequence
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import docs_parity  # noqa: E402


DEFAULT_SYNC = "2026-10-31"


def write_page(docs_dir, lang, rel, title, sync=DEFAULT_SYNC, extra_fm: Sequence[str] = (), body="Ordinary content."):
    """Create docs_dir/lang/rel with the given frontmatter and body."""
    path = docs_dir / lang / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    fm_lines = ["---"]
    if title is not None:
        fm_lines.append(f"title: {title}")
    if sync is not None:
        fm_lines.append(f"sync: {sync}")
    fm_lines.extend(extra_fm)
    fm_lines.append("---")
    text = "\n".join(fm_lines) + f"\n\n{body}\n"
    path.write_text(text, encoding="utf-8")
    return path


def make_clean_site(docs_dir):
    """A minimal fully-paired, clean two-tree site."""
    write_page(docs_dir, "en", "index.md", "Home")
    write_page(docs_dir, "zh", "index.md", "Home")
    write_page(docs_dir, "en", "user/installation.md", "installation")
    write_page(docs_dir, "zh", "user/installation.md", "installation")


def run_gate(docs_dir, capsys):
    rc = docs_parity.main(["--docs-dir", str(docs_dir)])
    captured = capsys.readouterr()
    return rc, captured.err


def test_clean_pair_passes(tmp_path, capsys):
    make_clean_site(tmp_path)
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 0
    assert "WARN" not in err
    assert "FAIL" not in err


def test_missing_pair_fails(tmp_path, capsys):
    make_clean_site(tmp_path)
    write_page(tmp_path, "en", "user/orphan.md", "orphan")
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "user/orphan.md" in err
    assert "missing pair" in err


def test_annex_exempt(tmp_path, capsys):
    make_clean_site(tmp_path)
    # Single-language page with `annex: true` is exempt from pairing...
    write_page(
        tmp_path, "en", "developer/annex-perf.md", "annex-perf",
        extra_fm=["annex: true"],
    )
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 0
    assert "FAIL" not in err
    # ...but NOT exempt from the leak scan.
    write_page(
        tmp_path, "en", "developer/annex-leak.md", "annex-leak",
        extra_fm=["annex: true"], body="Runs from /home/redacted/secret/run.sh",
    )
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "annex-leak.md" in err
    assert "leak" in err
    # Exemption keys only count inside the `---` frontmatter block.
    write_page(
        tmp_path, "en", "developer/fake-annex.md", "fake-annex",
        body="annex: true\nmentioned only in the body",
    )
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "fake-annex.md" in err
    assert "missing pair" in err


def test_draft_exempt(tmp_path, capsys):
    make_clean_site(tmp_path)
    write_page(
        tmp_path, "zh", "user/wip.md", "wip",
        extra_fm=["draft: true"], body="TODO: still writing this page.",
    )
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 0
    assert "FAIL" not in err
    # Draft pages are still scanned for leaks.
    write_page(
        tmp_path, "zh", "user/leaky-draft.md", "leaky-draft",
        extra_fm=["draft: true"], body="ssh node01 for debugging",
    )
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "leaky-draft.md" in err
    assert "leak" in err


def test_leak_pattern_fails(tmp_path, capsys):
    make_clean_site(tmp_path)
    write_page(
        tmp_path, "en", "user/deploy.md", "deploy",
        body="Copy the artifact from /home/redacted/deploy/dist.",
    )
    write_page(tmp_path, "zh", "user/deploy.md", "deploy", body="普通正文。")
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "user/deploy.md" in err
    assert "leak" in err


def test_asset_leak_fails(tmp_path, capsys):
    make_clean_site(tmp_path)
    # A clean text asset under docs/assets must pass (and be counted in the
    # summary line; that line goes to stdout, hence the direct main() call).
    asset = tmp_path / "assets" / "diagram.html"
    asset.parent.mkdir(parents=True, exist_ok=True)
    asset.write_text("<html><body>sanitized diagram</body></html>", encoding="utf-8")
    rc = docs_parity.main(["--docs-dir", str(tmp_path)])
    captured = capsys.readouterr()
    assert rc == 0
    assert "FAIL" not in captured.err
    assert "1 asset file(s) leak-scanned" in captured.out
    # The same asset carrying a leak pattern must FAIL the gate -- published
    # assets are scanned just like pages.
    asset.write_text(
        "<html><body>generated from /home/redacted/site/out.html</body></html>",
        encoding="utf-8",
    )
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "assets/diagram.html" in err
    assert "leak" in err


def test_unterminated_frontmatter_fails(tmp_path, capsys):
    make_clean_site(tmp_path)
    # A leading '---' that is never closed must fail loudly: parsing on would
    # treat body lines as metadata, so a body `annex: true` would silently
    # exempt the page from pairing.
    path = tmp_path / "en" / "user" / "unterminated.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "---\ntitle: unterminated\nsync: 2026-10-31\n\n"
        "annex: true\nonly in the body\n",
        encoding="utf-8",
    )
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "user/unterminated.md" in err
    assert "unterminated frontmatter" in err


def test_stale_sync_warns_not_fails(tmp_path, capsys):
    make_clean_site(tmp_path)
    write_page(tmp_path, "en", "user/stale.md", "stale", sync="2026-10-31")
    write_page(tmp_path, "zh", "user/stale.md", "stale", sync="2026-10-01")
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 0
    assert "WARN" in err
    assert "user/stale.md" in err
    assert "sync stale" in err
    assert "en=2026-10-31" in err
    assert "zh=2026-10-01" in err


def test_title_missing_fails(tmp_path, capsys):
    make_clean_site(tmp_path)
    # Paired slug whose zh title is absent from the frontmatter entirely.
    write_page(tmp_path, "en", "user/notitle.md", "has-title")
    write_page(tmp_path, "zh", "user/notitle.md", None)
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "zh/user/notitle.md" in err
    assert "title" in err
    # An empty title string is just as bad.
    write_page(tmp_path, "zh", "user/notitle.md", "")
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "zh/user/notitle.md" in err
    # A translated (differing) title on a healthy pair must NOT fail:
    # each locale's nav renders from its own pages' titles.
    write_page(tmp_path, "zh", "user/notitle.md", "中文标题")
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 0
    assert "FAIL" not in err


def test_slug_mismatch_detected(tmp_path, capsys):
    make_clean_site(tmp_path)
    # Same page filed under a different filename per tree (hyphen vs
    # underscore): both slugs are unpaired and must be reported.
    write_page(tmp_path, "en", "user/first-call.md", "first-call")
    write_page(tmp_path, "zh", "user/first_call.md", "first-call")
    rc, err = run_gate(tmp_path, capsys)
    assert rc == 1
    assert "first-call.md" in err
    assert "first_call.md" in err
    assert "missing pair" in err
