"""CI-only serial shard runner and fail-closed, source-matched LCOV union.

The Dart JSON reporter (pinned test_core 0.6.16) supplies completion/skip counts.
Loading/setup tests are hidden; a late error still invalidates a completed test.
See https://github.com/dart-lang/test/blob/master/pkgs/test/doc/json_reporter.md.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlparse

try:
    from tool.coverage_shard_plan import inventory
except ModuleNotFoundError:  # Direct invocation from the repository root.
    from coverage_shard_plan import inventory


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(path, root):
    if path.startswith('file:'):
        parsed = urlparse(path)
        if parsed.netloc not in ('', 'localhost'):
            raise ValueError('Remote source URI')
        path = unquote(parsed.path)
        if re.match(r'^/[A-Za-z]:/', path):
            path = path[1:]
    file = Path(path)
    if not file.is_absolute():
        file = root / file
    return file.resolve().relative_to(root.resolve()).as_posix()


def sources(root):
    files = list((root / 'lib').rglob('*.dart'))
    files += list((root / 'packages').glob('*/lib/**/*.dart'))
    files += [root / 'pubspec.yaml', root / 'pubspec.lock']
    files += list((root / 'packages').glob('*/pubspec.yaml'))
    return {f.relative_to(root).as_posix(): digest(f.read_bytes().replace(b'\r\n', b'\n'))
            for f in sorted(files) if f.is_file()}


def validate_plan(plan, root):
    if plan.get('discovery') != inventory(root):
        raise ValueError('Test discovery/content drift')
    expected = [e['path'] for e in plan['discovery']]
    groups = plan['groups']
    if not groups or [g['index'] for g in groups] != list(range(len(groups))):
        raise ValueError('Invalid shard indices')
    actual = [p for g in groups for p in g['files']]
    if (not expected or any(not g['files'] for g in groups)
            or sorted(actual) != sorted(expected) or len(actual) != len(set(actual))):
        raise ValueError('Missing, extra or duplicated test assignment')


def event_summary(text, root, selected):
    tests, completed, suites, late = {}, {}, {}, set()
    final = None
    errors = 0
    for line in text.splitlines():
        event = json.loads(line)
        kind = event['type']
        if final is not None:
            raise ValueError('Events after final completion')
        if kind == 'suite':
            suite = event['suite']
            if suite['id'] in suites or not suite.get('path'):
                raise ValueError('Missing/duplicate suite metadata')
            path = canonical(suite['path'], root)
            if path in suites.values():
                raise ValueError('A test file was loaded more than once')
            suites[suite['id']] = path
        elif kind == 'testStart':
            test = event['test']
            if test['id'] in tests or test['suiteID'] not in suites:
                raise ValueError('Invalid test ownership')
            tests[test['id']] = test
        elif kind == 'testDone':
            key = event['testID']
            if key not in tests or key in completed:
                raise ValueError('Missing/duplicate test completion')
            if event['result'] not in ('success', 'failure', 'error'):
                raise ValueError('Unknown test result')
            if type(event.get('hidden')) is not bool or type(event.get('skipped')) is not bool:
                raise ValueError('Missing visibility/skip evidence')
            if event['hidden'] and (event['result'] != 'success' or event['skipped']):
                raise ValueError('Invalid hidden completion')
            completed[key] = event
        elif kind == 'error':
            errors += 1
            if event['testID'] not in tests:
                raise ValueError('Unowned test error')
            if event['testID'] in completed:
                late.add(event['testID'])
        elif kind == 'done':
            final = event
    if final is None or final.get('success') is not True or set(tests) != set(completed):
        raise ValueError('Test stream failed, cancelled or incomplete')
    if set(suites.values()) != set(selected):
        raise ValueError('Observed suites do not match selected files')
    counts = dict(passed=0, skipped=0, failed=0, hidden=0, errors_seen=errors)
    for key, event in completed.items():
        category = ('failed' if key in late or event['result'] != 'success'
                    else 'hidden' if event['hidden'] else 'skipped' if event['skipped']
                    else 'passed')
        counts[category] += 1
    if counts['failed'] or counts['passed'] + counts['skipped'] == 0:
        raise ValueError('No complete successful visible test set')
    return dict(counts=counts, files_seen=sorted(set(suites.values())), success=True)


def lcov_records(text, root, hashes):
    records, current, summaries = {}, None, {}
    for raw in text.splitlines():
        if raw.startswith('SF:'):
            if current is not None:
                raise ValueError('Unclosed LCOV record')
            current = canonical(raw[3:], root)
            if current not in hashes or not current.endswith('.dart') or current in records:
                raise ValueError('Unmapped or duplicated LCOV source')
            records[current], summaries = {}, {}
        elif raw.startswith('DA:') and current is not None:
            parts = raw[3:].split(',')
            if len(parts) != 2:
                raise ValueError('Unsupported LCOV DA metadata')
            number, hits = map(int, parts)
            if number < 1 or hits < 0 or number in records[current]:
                raise ValueError('Invalid/duplicate LCOV line')
            records[current][number] = hits
        elif raw.startswith(('LF:', 'LH:')) and current is not None:
            key, value = raw.split(':')
            if key in summaries:
                raise ValueError('Duplicate LCOV summary')
            summaries[key] = int(value)
        elif raw == 'end_of_record' and current is not None:
            lines = records[current]
            if (not lines or summaries != dict(LF=len(lines),
                                               LH=sum(v > 0 for v in lines.values()))):
                raise ValueError('Inconsistent LCOV summary')
            current = None
        elif raw.startswith('TN:') and current is None:
            continue
        else:
            raise ValueError('Unsupported or misplaced LCOV entry')
    if current is not None or not records:
        raise ValueError('Empty/truncated LCOV')
    return records


def validate_receipts(plan, plan_hash, receipts, root, commit):
    validate_plan(plan, root)
    if len(receipts) != len(plan['groups']):
        raise ValueError('Missing or extra shard receipts')
    expected_sources = sources(root)
    seen = set()
    for receipt in receipts:
        index = receipt['index']
        if type(index) is not int or index not in range(len(plan['groups'])) or index in seen:
            raise ValueError('Invalid/duplicate shard receipt')
        seen.add(index)
        selected = plan['groups'][index]['files']
        if (receipt.get('commit') != commit or receipt.get('plan_sha256') != plan_hash
                or receipt.get('sources') != expected_sources
                or receipt.get('selected') != selected
                or type(receipt.get('exit_code')) is not int or receipt['exit_code'] != 0
                or receipt.get('success') is not True
                or receipt.get('files_seen') != sorted(selected)):
            raise ValueError('Failed, stale or incomplete shard receipt')
    return expected_sources


def merge(plan_bytes, inputs, root, commit):
    plan = json.loads(plan_bytes)
    paths = sorted(Path(inputs).rglob('receipt.json'))
    receipts = [json.loads(p.read_text()) for p in paths]
    hashes = validate_receipts(plan, digest(plan_bytes), receipts, root, commit)
    combined, totals = {}, dict(passed=0, skipped=0, failed=0, hidden=0, errors_seen=0)
    for path, receipt in zip(paths, receipts):
        events = (path.parent / 'events.json').read_bytes()
        coverage = (path.parent / 'lcov.info').read_bytes()
        if digest(events) != receipt['events_sha256'] or digest(coverage) != receipt['lcov_sha256']:
            raise ValueError('Shard artifact checksum drift')
        result = event_summary(events.decode(), root, receipt['selected'])
        if result['counts'] != receipt['counts'] or result['files_seen'] != receipt['files_seen']:
            raise ValueError('Recorded test outcome mismatch')
        for key in totals:
            totals[key] += result['counts'][key]
        for source, lines in lcov_records(coverage.decode(), root, hashes).items():
            target = combined.setdefault(source, {})
            for number, hits in lines.items():
                target[number] = target.get(number, 0) + hits
    output = []
    for source, lines in sorted(combined.items()):
        output.append('SF:' + source)
        output.extend(f'DA:{n},{v}' for n, v in sorted(lines.items()))
        output += [f'LF:{len(lines)}', f'LH:{sum(v > 0 for v in lines.values())}', 'end_of_record']
    return '\n'.join(output) + '\n', dict(commit=commit, shards=len(receipts),
        test_files=len(plan['discovery']), counts=totals, sources=hashes,
        sources_in_lcov=len(combined), plan_sha256=digest(plan_bytes), verified=True)


def run(plan_bytes, index, root, output, commit):
    # A complete application shard is heavy. Never execute it on the laptop.
    if os.environ.get('CI') != 'true' or os.environ.get('GITHUB_SHA') != commit:
        raise ValueError('Application shards run only on GitHub Actions')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root).decode().strip() != commit:
        raise ValueError('Checkout does not match CI commit')
    plan = json.loads(plan_bytes)
    validate_plan(plan, root)
    selected = plan['groups'][index]['files']
    before = sources(root)
    output.mkdir(parents=True, exist_ok=False)  # Refuse stale output, never erase it.
    event_path, lcov_path = output / 'events.json', output / 'lcov.info'
    command = ['flutter', 'test', '--concurrency=1', '--coverage', '--reporter=expanded',
               '--file-reporter=json:' + str(event_path), '--coverage-path', str(lcov_path),
               *selected]
    receipt = dict(index=index, commit=commit, plan_sha256=digest(plan_bytes),
                   selected=selected, sources=before, success=False)
    try:
        with (output / 'stdout.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
            for line in process.stdout:
                log.write(line)
                if 'loading ' in line or '[E]' in line or 'tests passed' in line:
                    print(line.rstrip(), flush=True)
            receipt['exit_code'] = process.wait()
        if receipt['exit_code'] != 0 or before != sources(root):
            raise ValueError('Shard failed or source changed during execution')
        validate_plan(plan, root)
        events, coverage = event_path.read_bytes(), lcov_path.read_bytes()
        receipt.update(event_summary(events.decode(), root, selected))
        lcov_records(coverage.decode(), root, before)
        receipt.update(events_sha256=digest(events), lcov_sha256=digest(coverage))
    except Exception as error:
        receipt.update(success=False, verification_error=str(error))
        raise
    finally:
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt['counts']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['run', 'merge'])
    parser.add_argument('--plan', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--index', type=int)
    parser.add_argument('--inputs', type=Path)
    args = parser.parse_args()
    root = Path.cwd().resolve()
    commit = os.environ.get('GITHUB_SHA', '')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('CI commit required')
    plan = args.plan.read_bytes()
    if args.operation == 'run':
        if args.index is None or args.index < 0:
            raise ValueError('Nonnegative shard index required')
        run(plan, args.index, root, args.output.resolve(), commit)
    else:
        if args.inputs is None:
            raise ValueError('Shard artifact directory required')
        args.output.mkdir(parents=True, exist_ok=False)
        try:
            merged, report = merge(plan, args.inputs, root, commit)
        except Exception as error:
            (args.output / 'verification-failure.json').write_text(json.dumps(
                dict(commit=commit, verified=False, error=str(error)), indent=2) + '\n')
            raise
        (args.output / 'lcov.info').write_text(merged)
        (args.output / 'shard-verification.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report['counts']))


if __name__ == '__main__':
    main()
