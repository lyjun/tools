#!/usr/bin/env python3
"""Resolve the version range and fetch Claude Code release notes for it.

Owned by the x-cc-release-cfg-sync skill. Replaces what used to be inline prose
with a placeholder range for the agent to fill at run time.

The failure this exists to catch: a version can have a tag whose body is empty,
or a body that says only "Bug fixes and reliability improvements". Fetching then
"succeeds" for every version while several yield nothing to analyse, and the
report that follows implies a coverage it does not have. Those versions are
reported per-version and collapse the run to VERDICT: unavailable.

Output contract (read by the caller):
  every exit path prints exactly one `VERDICT: <ok|unavailable|error>` line
  ok           0  every version in range returned substantive notes
  unavailable  2  ran, but >=1 version has no content to analyse and never will
                  (no tag / empty body / boilerplate-only). Safe to advance
                  .last-reviewed past these: re-fetching them later changes nothing.
  error        1  usage error, unresolvable range, or a fetch failed (403 / network).
                  A fetch failure is deliberately NOT unavailable: those versions do
                  have notes, so reporting them as content-less would mis-describe
                  them and .last-reviewed would then close them off for good.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.github.com/repos/anthropics/claude-code/releases/tags/v{}"
SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAST_REVIEWED = os.path.join(SKILL_DIR, ".last-reviewed")
DEFAULT_SPAN = 5

# Lines that carry no information. A body made only of these is `boilerplate`.
# Only the "What's changed" heading is listed — any other heading is real content,
# so a body whose substance lives in its headings is not discarded.
BOILERPLATE = re.compile(
    r"^\W*(?:#+\s*)?what's changed\W*$"
    r"|^\W*[-*]?\s*bug fixes and reliability improvements\W*$",
    re.IGNORECASE,
)


def verdict(name, message=None):
    """Print the single in-band verdict line and exit with its matching code."""
    if message:
        print(message, file=sys.stderr if name == "error" else sys.stdout)
    print("VERDICT: " + name)
    sys.exit({"ok": 0, "error": 1, "unavailable": 2}[name])


def parse_version(raw, label, embedded=False):
    """Parse a version into (2, 1, 251).

    `embedded` loosens the match to a version *inside* other text, which only
    `claude --version` ("2.1.251 (Claude Code)") needs. Everything else matches
    the whole token: a marker file holding `v2.1.5x` must be rejected, not
    silently read as v2.1.5 — that would review 246 versions instead of erroring.
    """
    if raw is None or not str(raw).strip():
        verdict("error", "{} is empty; both ends of the range must be given".format(label))
    text = str(raw).strip()
    m = (
        re.search(r"(\d+)\.(\d+)\.(\d+)", text)
        if embedded
        else re.match(r"^v?(\d+)\.(\d+)\.(\d+)$", text)
    )
    if not m:
        verdict("error", "{} is not a version: {!r}".format(label, raw))
    return tuple(int(g) for g in m.groups())


def fmt(v):
    return "{}.{}.{}".format(*v)


def installed_version():
    try:
        out = subprocess.run(
            ["claude", "--version"], capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.SubprocessError) as e:
        verdict("error", "could not run `claude --version`: {}".format(e))
    if out.returncode != 0:
        verdict("error", "`claude --version` exited {}: {}".format(out.returncode, out.stderr.strip()))
    return parse_version(out.stdout, "installed version", embedded=True)


def read_last_reviewed():
    try:
        with open(LAST_REVIEWED) as f:
            text = f.read().strip()
    except OSError:
        return None
    return text or None


def fetch(version):
    """Return (status, body). status is one of notes/boilerplate/empty/missing/error."""
    req = urllib.request.Request(
        API.format(version),
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "x-cc-release-cfg-sync",
        },
    )
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        req.add_header("Authorization", "Bearer " + token)

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return "missing", ""
        if e.code in (403, 429):
            return "error", "HTTP {} (rate limited?)".format(e.code)
        return "error", "HTTP {}".format(e.code)
    except (urllib.error.URLError, ValueError, OSError) as e:
        return "error", str(e)

    body = (payload.get("body") or "").strip()
    if not body:
        return "empty", ""
    # Per-body, not per-line: one substantive line anywhere makes the whole body
    # analysable, so a release whose first bullet happens to be the boilerplate
    # sentence still counts. Headings count as content — the "What's changed"
    # header is already absorbed by BOILERPLATE, and skipping every `##` would
    # discard a body whose content lives in its headings.
    for line in body.splitlines():
        line = line.strip()
        if line and not BOILERPLATE.match(line):
            return "notes", body
    return "boilerplate", body


class VerdictParser(argparse.ArgumentParser):
    """argparse exits 2 with no verdict line; 2 is this script's `unavailable` code,
    so a flag given without its value would read as a completed run with gaps."""

    def error(self, message):
        verdict("error", "usage: " + message)


def main():
    ap = VerdictParser(add_help=True)
    ap.add_argument("--from", dest="frm", default=None, help="range start, e.g. v2.1.241")
    ap.add_argument("--to", dest="to", default=None, help="range end; capped at installed")
    # Required: the caller's whole purpose is to read the bodies afterwards, and an
    # optional --out lets a run fetch every version, discard all of it, and still
    # report ok on the counts alone.
    ap.add_argument("--out", required=True, help="directory to write v<version>.md into")
    args = ap.parse_args()

    inst = installed_version()

    frm_src = "--from"
    frm_raw = args.frm
    if frm_raw is None:
        frm_raw = read_last_reviewed()
        frm_src = ".last-reviewed"
    if frm_raw is None:
        frm = (inst[0], inst[1], max(0, inst[2] - DEFAULT_SPAN))
        frm_src = "default (installed - {})".format(DEFAULT_SPAN)
    else:
        # frm_src, not a fixed "--from": a corrupt marker file must name the marker file.
        frm = parse_version(frm_raw, frm_src)

    to_src = "--to"
    if args.to is None:
        to = inst
        to_src = "installed"
    else:
        to = parse_version(args.to, "--to")

    capped = ""
    if to > inst:
        capped = "CAP: requested v{} is above installed v{}; capped".format(fmt(to), fmt(inst))
        to = inst
        to_src = "installed (capped)"

    if frm[:2] != to[:2]:
        verdict(
            "error",
            "range spans different minor versions (v{} -> v{}); this script only "
            "enumerates patch versions. Run it once per minor line, or fall back to "
            "the full CHANGELOG.".format(fmt(frm), fmt(to)),
        )
    if frm == to:
        # Not a usage bug, but the caller must still stop: there is nothing to report on.
        verdict(
            "error",
            "UP TO DATE: v{} has already been reviewed and equals the range end. "
            "Tell the user there is nothing new; do not write a report.".format(fmt(frm)),
        )
    if frm > to:
        verdict("error", "empty range: v{} is not below v{}".format(fmt(frm), fmt(to)))

    # `from` is the last version already reviewed, so the range starts after it.
    versions = ["{}.{}.{}".format(frm[0], frm[1], p) for p in range(frm[2] + 1, to[2] + 1)]

    out_dir = args.out
    try:
        os.makedirs(out_dir, exist_ok=True)
        # makedirs succeeds on an existing unwritable directory, so probe it here
        # rather than letting the first body write die mid-run, after the header
        # has already printed and before any VERDICT line.
        probe = os.path.join(out_dir, ".write-probe")
        with open(probe, "w") as f:
            f.write("")
        os.remove(probe)
    except OSError as e:
        verdict("error", "--out directory {} is not writable: {}".format(out_dir, e))

    print("INSTALLED: v{}".format(fmt(inst)))
    print("FROM:      v{}  (source: {}; range starts at the next patch)".format(fmt(frm), frm_src))
    print("TO:        v{}  (source: {})".format(fmt(to), to_src))
    print("OUT:       {}".format(out_dir))
    if capped:
        print(capped)
    print()

    results = []
    for v in versions:
        status, body = fetch(v)
        detail = ""
        if status == "notes":
            bullets = sum(
                1 for line in body.splitlines() if line.strip()[:2] in ("- ", "* ")
            )
            detail = "{} bytes, {} bullets".format(len(body), bullets)
            try:
                with open(os.path.join(out_dir, "v{}.md".format(v)), "w") as f:
                    f.write(body)
            except OSError as e:
                verdict("error", "cannot write notes for v{}: {}".format(v, e))
        elif status == "boilerplate":
            detail = "body says only: " + " ".join(body.split())[:60]
        elif status == "missing":
            detail = "no release tag (404)"
        elif status == "empty":
            detail = "tag exists, body empty"
        else:
            detail = body
        results.append((v, status, detail))

    print("COVERAGE")
    print("  {:<10} {:<12} {}".format("version", "status", "detail"))
    for v, status, detail in results:
        print("  {:<10} {:<12} {}".format("v" + v, status, detail))
    print()

    usable = [r for r in results if r[1] == "notes"]
    failed = [r for r in results if r[1] == "error"]
    gaps = [r for r in results if r[1] not in ("notes", "error")]
    print("ANALYSABLE: {}/{} versions".format(len(usable), len(results)))
    if gaps:
        print("NO CONTENT: " + ", ".join("v" + v for v, _, _ in gaps))
    if failed:
        print("FETCH FAILED: " + ", ".join("v" + v for v, _, _ in failed))
    if usable:
        # Printed here because this is what the caller reads right before it reads the
        # notes; printing them through Bash in any form overflows the output limit.
        print()
        print("READ: one Read call per file, all in the same message. Do not print them, or")
        print("      any file built from them, through Bash in any form (cat, grep, head, wc):")
        print("      their sizes are in COVERAGE above, and the combined text overflows the")
        print("      Bash output limit, costing a round trip.")
        for v, _, _ in usable:
            print("  " + os.path.join(out_dir, "v{}.md".format(v)))
    print()

    if failed:
        # These versions do have notes; calling them content-less would mis-describe
        # them, and advancing .last-reviewed would then close them off permanently.
        verdict(
            "error",
            "{} version(s) could not be fetched. Do not report them as having no "
            "content and do not advance .last-reviewed past them — retry, or use the "
            "CHANGELOG fallback.".format(len(failed)),
        )
    if not usable:
        verdict("error", "no version in the range returned analysable release notes")
    if gaps:
        verdict(
            "unavailable",
            "the report must state these versions were not analysed, not imply full coverage",
        )
    verdict("ok")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise  # verdict() already printed its line
    except BaseException as exc:  # noqa: BLE001 - a bare traceback would carry no VERDICT
        import traceback

        traceback.print_exc()
        verdict("error", "unhandled {}: {}".format(type(exc).__name__, exc))
