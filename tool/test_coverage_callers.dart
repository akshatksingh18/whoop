// One tiny resolved fixture; no full repository analysis on the laptop.
import 'dart:io';
import 'package:path/path.dart' as p;
import 'coverage_callers.dart';

Future<void> main() async {
  final root = Directory.current.absolute.path;
  final map = await buildReferenceMap(root, [
    p.join(root, 'tool/coverage_callers_fixture.dart'),
  ]);
  final declarations = (map['declarations'] as List).cast<Map>();
  final references = (map['references'] as List).cast<Map>();
  final unresolved = (map['unresolved'] as List).cast<Map>();
  var checks = 0;
  void check(bool value, String reason) {
    if (!value) throw StateError(reason);
    checks++;
  }

  Map declaration(String name, [String? owner]) => declarations.singleWhere(
    (d) => d['name'] == name && (owner == null || d['enclosing'] == owner),
  );
  final contract = declaration('compute', 'FixtureContract');
  final concrete = declaration('compute', 'FixtureStore');
  check(
    contract['abstract'] == true && concrete['abstract'] == false,
    'Contract and implementation remain distinct',
  );
  check(
    (contract['virtual_dispatch_candidates'] as List).contains(concrete['id']),
    'Contract call records its possible concrete override',
  );
  final fromContract = declaration('throughContract')['id'];
  check(
    references.any(
      (r) =>
          r['from'] == fromContract &&
          (r['target'] as Map)['id'] == contract['id'] &&
          r['relation'] == 'static_call_target',
    ),
    'Static target is the interface, not guessed by name',
  );
  final fromConcrete = declaration('throughConcrete')['id'];
  check(
    references.any(
      (r) =>
          r['from'] == fromConcrete &&
          (r['target'] as Map)['id'] == concrete['id'],
    ),
    'Concrete reference resolves to concrete definition',
  );
  final callback = declaration('namedCallback')['id'];
  check(
    references.any(
      (r) =>
          (r['target'] as Map)['id'] == callback &&
          r['relation'] == 'static_reference_or_tearoff',
    ),
    'Callback tear-off is retained as a reference',
  );
  check(
    references.any((r) => r['relation'] == 'creates_closure'),
    'Anonymous callback ownership is explicit',
  );
  check(
    unresolved.any(
      (r) =>
          r['name'] == 'compute' &&
          r['reason'] == 'dynamic_or_unresolved_method_target',
    ),
    'Dynamic receiver is unresolved instead of matched by name',
  );
  final unused = declaration('unusedFixtureFunction');
  check(
    unused['static_inbound_references'] == 0 &&
        unused['unused_proven'] == false,
    'Zero references is not a deletion verdict',
  );
  check(
    (map['sources'] as List).single['path'] ==
        'tool/coverage_callers_fixture.dart',
    'Artifact paths are repository-relative',
  );
  final parentConstructor = declarations.singleWhere(
    (d) => d['enclosing'] == 'FixtureParent' && d['kind'] == 'constructor',
  );
  check(
    (parentConstructor['virtual_dispatch_candidates'] as List).isEmpty,
    'Named constructors are not virtual overrides',
  );
  check(
    references.any(
      (r) =>
          r['relation'] == 'super_constructor' &&
          (r['target'] as Map)['id'] == parentConstructor['id'],
    ),
    'Super-constructor target is retained',
  );
  check(
    references.any((r) => r['relation'] == 'redirecting_constructor'),
    'Redirected constructor edge is distinct',
  );
  check(
    unresolved.any((r) => r['reason'] == 'function_value_origin_not_expanded'),
    'Function-value origins are explicit limits',
  );
  stdout.writeln(
    '$checks caller-index fixture checks passed. Full app resolution was not run.',
  );
}
