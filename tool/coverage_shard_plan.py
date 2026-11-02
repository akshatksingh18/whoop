"""Plan disjoint serial test-file groups; never executes tests or claims coverage.

Cloud adoption still requires per-run receipts and a source-verified LCOV merger.
The planner is intentionally separate so an unverified merge cannot replace CI.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath


def partition(paths, count, costs=None):
    paths = list(paths)
    if not paths or not 1 <= count <= len(paths):
        raise ValueError('Need one or more files per shard')
    if len(paths) != len(set(paths)):
        raise ValueError('Duplicate test file')
    for path in paths:
        parts = PurePosixPath(path).parts
        if (not path.startswith('test/') or not path.endswith('_test.dart')
                or '\\' in path or '..' in parts or ':' in path
                or str(PurePosixPath(path)) != path):
            raise ValueError('Expected canonical repository test path')
    weights = {}
    for path in paths:
        weight = (costs or {}).get(path, 5.0)
        if isinstance(weight, bool) or not isinstance(weight, (int, float)):
            raise ValueError('Invalid test duration')
        if not math.isfinite(weight) or weight <= 0:
            raise ValueError('Test duration must be finite and positive')
        weights[path] = weight
    groups = [dict(index=i, estimated_seconds=0.0, files=[]) for i in range(count)]
    for path in sorted(paths, key=lambda p: (-weights[p], p)):
        group = min(groups, key=lambda g: (g['estimated_seconds'], g['index']))
        group['files'].append(path)
        group['estimated_seconds'] += weights[path]
    for group in groups:
        group['files'].sort()
    assigned = [p for g in groups for p in g['files']]
    if sorted(assigned) != sorted(paths) or len(assigned) != len(set(assigned)):
        raise ValueError('Incomplete or overlapping partition')
    return groups


def inventory(root):
    root = Path(root).resolve()
    entries = []
    for file in sorted((root / 'test').rglob('*_test.dart')):
        if not file.is_file():
            continue
        if file.is_symlink() or not file.resolve().is_relative_to(root):
            raise ValueError('Test symlinks require explicit discovery review')
        body = file.read_bytes().replace(b'\r\n', b'\n')
        entries.append(dict(path=file.relative_to(root).as_posix(),
                            sha256=hashlib.sha256(body).hexdigest()))
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='.')
    parser.add_argument('--count', type=int, default=3)
    parser.add_argument('--costs', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    entries = inventory(args.root)
    costs = json.loads(args.costs.read_text()) if args.costs else {}
    groups = partition([e['path'] for e in entries], args.count, costs)
    payload = dict(schema=1, plan_only=True, discovery=entries, groups=groups,
                   runtime_verified=False, coverage_merge_verified=False)
    args.output.write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
    print(f'{len(entries)} files assigned once across {len(groups)} planned runners; no tests run')


if __name__ == '__main__':
    main()
