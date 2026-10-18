#!/usr/bin/env python3
"""List lines in a generic skill that name things only one environment has.

Measures, does not judge: each line with a match is printed once, with every match on it
and where each came from; the caller writes one verdict per line.

Usage:
  portability-check.py --config FILE --before OLD --after NEW   # added lines only
  portability-check.py --config FILE --files PATH [PATH ...]    # whole files (audit)

OLD/NEW are a file pair or a directory pair with the same layout.

--config is a YAML file the user keeps outside every skill (this script ships no default):

  companies:
    - name: acme                    # organisation name
      github: [acme-labs]           # GitHub orgs
      code_root: ~/src/acme         # where the org's repos are cloned
      terms: [acm, build01, jdoe]   # abbreviations, host and account names

Only these four keys are accepted; every field is optional but each company needs at least
one. The match list is every value above plus the name of each git repo directly under
code_root, read at run time. Matching is case-insensitive substring.

Output: `HIT <file>:<line> [<source>:<match>, ...] <line text>` per line with matches, then
a CONFIG / REPOS summary, `HITS: N`, and `VERDICT:`. ok = every check ran (hits or not);
unavailable = nothing was really measured (empty match list, a code_root that does not
exist or has no git repos under it, zero lines scanned in --files mode, or before and after identical), so a clean
result would mean nothing; error = bad usage, unreadable input, a malformed config, or
PyYAML missing. Exit codes 0 / 3 / 1 respectively.
"""
import difflib
import os
import re
import sys

# A path with an extension (dir/…/name.ext) — but not the skill's own layout
# or home-relative skill paths, which are portable.
PATH_RE = re.compile(r"(?<![\w$/{.~-])((?:\.{1,2}/)?[\w.-]+(?:/[\w.-]+)+\.[A-Za-z]\w*)")
PORTABLE_PREFIXES = ("references/", "scripts/", "assets/", "./references/", "./scripts/")
# file:line (name.ext:N or name.ext:N-M)
FILELINE_RE = re.compile(r"\b[\w.-]+\.[A-Za-z]\w*:\d+(?:-\d+)?\b")
# A specific user's home directory.
HOME_RE = re.compile(r"(?:/Users/|/home/)[\w.-]+/[\w./-]+")


def die(msg, code=1, verdict="error"):
    print(f"ERROR: {msg}")
    print(f"VERDICT: {verdict}")
    sys.exit(code)


def parse(argv):
    opts = {"config": None, "before": None, "after": None, "files": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--config", "--before", "--after"):
            if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                die(f"{a} needs a value")
            if argv[i + 1] == "":
                die(f"{a} was given an empty value")
            opts[a[2:]] = argv[i + 1]
            i += 2
        elif a == "--files":
            rest = []
            i += 1
            while i < len(argv) and not argv[i].startswith("--"):
                if argv[i] == "":
                    die("--files was given an empty path")
                rest.append(argv[i])
                i += 1
            if not rest:
                die("--files needs at least one path")
            opts["files"] = rest
        else:
            die(f"unknown argument: {a!r}")
    pair = opts["before"] is not None or opts["after"] is not None
    if pair and (opts["before"] is None or opts["after"] is None):
        die("--before and --after must be given together")
    if pair == (opts["files"] is not None):
        die("give either --before/--after or --files, not both or neither")
    return opts


def read_lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        die(f"cannot read {path}: {e}")


def walk(root):
    out = []
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x != "__pycache__"]
        for f in files:
            if not f.endswith(".pyc"):
                out.append(os.path.relpath(os.path.join(d, f), root))
    return sorted(out)


def added_lines(before, after):
    """Yield (display_path, lineno, text) for lines present in after but not before."""
    if os.path.isdir(after):
        if not os.path.isdir(before):
            die("--after is a directory but --before is not")
        pairs = [(os.path.join(before, r), os.path.join(after, r)) for r in walk(after)]
    elif os.path.isfile(after):
        if not os.path.isfile(before):
            die(f"--before is not a file: {before}")
        pairs = [(before, after)]
    else:
        die(f"--after does not exist: {after}")
    if os.path.realpath(before) == os.path.realpath(after):
        die("--before and --after are the same path; copy the file before editing it")
    if all(os.path.exists(b) and read_lines(b) == read_lines(a) for b, a in pairs):
        print("NOTE: before and after have identical content — was the copy taken after editing?")
        print("VERDICT: unavailable")
        sys.exit(3)
    for b, a in pairs:
        print(f"PAIR: {b} -> {a}" + ("" if os.path.exists(b) else " (new file)"))
        old = read_lines(b) if os.path.exists(b) else []
        new = read_lines(a)
        sm = difflib.SequenceMatcher(a=old, b=new, autojunk=False)
        for tag, _, _, j1, j2 in sm.get_opcodes():
            if tag in ("replace", "insert"):
                for j in range(j1, j2):
                    yield a, j + 1, new[j]


def whole_files(paths):
    for p in paths:
        if os.path.isdir(p):
            files = [os.path.join(p, r) for r in walk(p)]
        elif os.path.isfile(p):
            files = [p]
        else:
            die(f"path does not exist: {p}")
        for f in files:
            for n, line in enumerate(read_lines(f), 1):
                yield f, n, line


KEYS = {"name", "github", "code_root", "terms"}


def as_list(v, where):
    if v is None:
        return []
    out = []
    for x in (v if isinstance(v, list) else [v]):
        # YAML 1.1 reads bare no / on / yes as booleans; str() would turn them into "False".
        if isinstance(x, bool) or x is None:
            die(f"{where}: a value was read as {x!r} — quote it (\"no\", \"on\")")
        if not isinstance(x, (str, int, float)):
            die(f"{where}: {x!r} is not a plain value — write a flat list")
        x = str(x).strip()
        if "," in x:
            die(f"{where}: {x!r} contains a comma — write a YAML list: [a, b]")
        out.append(x)
    return out


def load_config(path):
    """Return (sources, notes, summary): sources is a list of (label, term)."""
    if path is None:
        return [], ["no --config given"], {}
    try:
        import yaml
    except ImportError:
        die("PyYAML is not installed (python3 -m pip install pyyaml)")
    try:
        with open(path, encoding="utf-8") as f:
            cfg = yaml.safe_load(f)
    except OSError as e:
        die(f"cannot read {path}: {e}")
    except yaml.YAMLError as e:
        die(f"{path} is not valid YAML: {e}")
    if cfg is None:
        cfg = {}
    if not isinstance(cfg, dict) or set(cfg) - {"companies"}:
        die(f"{path}: top level must be a mapping with only the key 'companies'")
    companies = cfg.get("companies") or []
    if not isinstance(companies, list):
        die(f"{path}: 'companies' must be a list")
    sources, notes = [], []
    summary = {"companies": len(companies), "repos": []}
    if not companies:
        notes.append("'companies' is missing or empty")
    for i, c in enumerate(companies):
        if not isinstance(c, dict):
            die(f"{path}: companies[{i}] must be a mapping")
        bad = set(c) - KEYS
        if bad:
            die(f"{path}: companies[{i}] has unknown key(s): {', '.join(sorted(map(str, bad)))}"
                f" (allowed: {', '.join(sorted(KEYS))})")
        for key in KEYS:
            as_list(c.get(key), f"{path}: companies[{i}].{key}")
        label = str(c.get("name", f"companies[{i}]"))
        for key in ("name", "github", "terms"):
            sources += [(key, v) for v in as_list(c.get(key), key) if v.strip()]
        for root in as_list(c.get("code_root"), "code_root"):
            sources.append(("code_root", root))
            full = os.path.expanduser(root)
            if not os.path.isdir(full):
                notes.append(f"{label}: code_root {root} does not exist — fix or remove it; "
                             "its repo names were not read")
                continue
            try:
                names = sorted(os.listdir(full))
            except OSError as e:
                notes.append(f"{label}: cannot list code_root {root}: {e}")
                continue
            repos = [d for d in names if os.path.exists(os.path.join(full, d, ".git"))]
            if not repos:
                notes.append(f"{label}: code_root {root} has no git repos directly under it — "
                             "is it the right level?")
            for d in repos:
                sources.append(("repo", d))
                summary["repos"].append(d)
        if not any(c.get(k) for k in KEYS):
            die(f"{path}: companies[{i}] has no values")
    for k in ("name", "github", "code_root", "terms", "repo"):
        summary[k] = sum(1 for s, _ in sources if s == k)
    return sources, notes, summary


def main():
    opts = parse(sys.argv[1:])
    sources, notes, summary = load_config(opts["config"])
    # Longest first, so a repo name wins over a term it contains when both match at one spot.
    ordered = sorted(sources, key=lambda s: -len(s[1]))
    lines = (added_lines(opts["before"], opts["after"]) if opts["files"] is None
             else whole_files(opts["files"]))
    hits = 0
    scanned = 0
    for path, n, text in lines:
        scanned += 1
        found = []
        for m in PATH_RE.finditer(text):
            p = m.group(1)
            if not p.startswith(PORTABLE_PREFIXES):
                found.append(f"path:{p}")
        found += [f"file:line:{m.group(0)}" for m in FILELINE_RE.finditer(text)]
        found += [f"home-path:{m.group(0)}" for m in HOME_RE.finditer(text)]
        low = text.lower()
        for label, term in ordered:
            if term.lower() in low:
                found.append(f"{label}:{term}")
        found = list(dict.fromkeys(found))
        if found:
            hits += 1
            print(f"HIT {path}:{n} [{', '.join(found)}] {text.strip()[:160]}")
    print(f"SCANNED_LINES: {scanned}")
    if summary:
        print("CONFIG: " + opts["config"] + " — " + ", ".join(
            f"{k}={summary[k]}" for k in ("companies", "name", "github", "code_root", "terms", "repo")))
        print("MATCH: " + (", ".join(f"{s}:{v}" for s, v in sources if s != "repo") or "(none)"))
        print("REPOS: " + (", ".join(summary["repos"]) or "(none)"))
    print(f"HITS: {hits} line(s)")
    if opts["files"] is not None and scanned == 0:
        notes.append("no lines were scanned")
    if not sources:
        notes.append("match list is empty — names without a path shape "
                     "(repo, host, function names) were not looked for")
    if notes:
        for x in notes:
            print(f"NOTE: {x}")
        print("VERDICT: unavailable")
        sys.exit(3)
    print("VERDICT: ok")
    sys.exit(0)


if __name__ == "__main__":
    main()
