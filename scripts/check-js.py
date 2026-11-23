#!/usr/bin/env python3
"""Syntax-check the JavaScript held in Swift multi-line strings.

Finds every Swift multi-line string (#\"\"\" ... \"\"\"# or \"\"\" ... \"\"\") under
Sources/, keeps the ones that look like JavaScript, and runs `node --check` on
each. Prints a GitHub error annotation (file and line) for every broken script
and exits 1, so the Build IPA workflow stops before building.

Usage: python3 scripts/check-js.py [Sources]
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = sys.argv[1] if len(sys.argv) > 1 else "Sources"
JS_HINT = re.compile(r"\b(function|const|let|var|document|window|addEventListener)\b|=>")
OPEN = re.compile(r'(#*)"""\s*$')


def strings_in(path):
    """Yield (start_line, text, raw) for each multi-line string literal."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    i = 0
    while i < len(lines):
        match = OPEN.search(lines[i])
        # An opening delimiter ends its line; a closing one starts its line.
        if match and lines[i].strip() != match.group(0).strip():
            hashes = match.group(1)
            close = '"""' + hashes
            body = []
            j = i + 1
            while j < len(lines) and lines[j].strip() != close:
                body.append(lines[j])
                j += 1
            yield i + 2, "\n".join(body), bool(hashes)
            i = j + 1
        else:
            i += 1


def unescape(text):
    """Swift escapes in a non-raw string (\\\\ -> \\, \\" -> ")."""
    text = re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "0", text)  # \(interpolation)
    return text.replace("\\\\", "\x00").replace('\\"', '"').replace("\\n", "\n") \
        .replace("\\t", "\t").replace("\x00", "\\")


def main():
    checked = failed = 0
    for folder, _, files in os.walk(ROOT):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(folder, name)
            for line, text, raw in strings_in(path):
                if raw:
                    hashes = "#" * 1
                    text = re.sub(r"\\" + hashes + r"\((?:[^()]|\([^()]*\))*\)", "0", text)
                else:
                    text = unescape(text)
                if text.lstrip().startswith("<") or not JS_HINT.search(text):
                    continue
                checked += 1
                with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as tmp:
                    tmp.write(text)
                result = subprocess.run(["node", "--check", tmp.name],
                                        capture_output=True, text=True)
                os.unlink(tmp.name)
                if result.returncode != 0:
                    failed += 1
                    err = result.stderr.strip().split("\n")
                    where = re.search(r":(\d+)\s*$", err[0]) if err else None
                    at = line + int(where.group(1)) - 1 if where else line
                    message = next((l for l in err if "Error" in l), err[-1] if err else "syntax error")
                    print(f"::error file={path},line={at}::JavaScript syntax error: {message}")
    print(f"Checked {checked} JavaScript string(s); {failed} with errors.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
