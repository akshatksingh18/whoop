"""Inventory LCOV execution gaps without changing the coverage denominator."""

import argparse
import hashlib
import json
from pathlib import Path


def parse_lcov(text):
    records = {}
    current = None
    for line in text.splitlines():
        if line.startswith("SF:"):
            current = line[3:].replace("\\", "/")
            records.setdefault(current, {})
        elif line.startswith("DA:") and current is not None:
            number, hits, *_ = line[3:].split(",")
            number, hits = int(number), int(hits)
            if number < 1 or hits < 0:
                raise ValueError("Invalid LCOV line or hit count")
            records[current][number] = max(hits, records[current].get(number, 0))
        elif line == "end_of_record":
            current = None
    return records


def ranges(numbers):
    result = []
    for number in sorted(set(numbers)):
        if result and number == result[-1][1] + 1:
            result[-1][1] = number
        else:
            result.append([number, number])
    return result


def inventory(records, repo):
    repo = Path(repo).resolve()
    result = []
    imported = set()
    for path, lines in sorted(records.items()):
        file = Path(path)
        if not file.is_absolute():
            file = repo / file
        file = file.resolve()
        # An artifact may contain SDK/dependency paths. Report only repo source;
        # never follow an artifact path outside the requested repository.
        try:
            relative = file.relative_to(repo).as_posix()
        except ValueError:
            continue
        if not relative.startswith("lib/") or file.suffix != ".dart":
            continue
        imported.add(relative)
        missed = [n for n, hits in lines.items() if hits == 0]
        result.append({
            "path": relative,
            "sha256": hashlib.sha256(file.read_bytes()).hexdigest() if file.exists() else None,
            "generated": file.name.startswith("app_localizations"),
            "instrumented": len(lines),
            "executed": len(lines) - len(missed),
            "uncovered_ranges": ranges(missed),
        })
    absent = []
    for file in sorted((repo / "lib").rglob("*.dart")):
        relative = file.relative_to(repo).as_posix()
        if relative not in imported:
            absent.append({"path": relative, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    handwritten = [r for r in result if not r["generated"]]
    found = sum(r["instrumented"] for r in handwritten)
    hit = sum(r["executed"] for r in handwritten)
    return {
        "meaning": "Executed lines, not manual review, branch correctness or native delivery",
        "handwritten": {"instrumented": found, "executed": hit, "unexecuted": found - hit,
                        "percent": round(100 * hit / found, 2) if found else None},
        "files": result,
        "unimported": absent,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lcov", type=Path)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, default=Path("build/coverage-audit/gaps.json"))
    args = parser.parse_args()
    report = inventory(parse_lcov(args.lcov.read_text(encoding="utf-8")), args.repo)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["handwritten"]))
    print(f"Unimported files: {len(report['unimported'])}; inventory: {args.output}")


if __name__ == "__main__":
    main()
