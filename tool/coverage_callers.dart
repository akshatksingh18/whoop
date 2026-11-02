// Resolved static references are evidence for review, never deletion permission.
// Full app resolution belongs on Actions; --fixture is the bounded local probe.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class _Index extends RecursiveAstVisitor<void> {
  _Index(this.root, this.path, this.result);
  final String root, path;
  final ResolvedUnitResult result;
  final declarations = <String, Map<String, Object?>>{};
  final references = <Map<String, Object?>>[];
  final unresolved = <Map<String, Object?>>[];
  final classes = <String, List<String>>{};
  String? owner;

  int line(AstNode n) => result.lineInfo.getLocation(n.offset).lineNumber;
  String relative(String file) =>
      p.relative(file, from: root).replaceAll('\\', '/');
  String? internalId(Element element) {
    final e = element.baseElement;
    final fragment = e.firstFragment;
    final source = fragment.libraryFragment?.source.fullName;
    if (source == null || !p.isWithin(root, source)) return null;
    return '${relative(source)}@${fragment.nameOffset ?? fragment.offset}:${e.kind.displayName}';
  }

  Map<String, Object?> describe(Element element) {
    final e = element.baseElement;
    final id = internalId(e);
    final uri = e.library?.uri;
    return {
      'id': id,
      'name': e.displayName,
      'enclosing': e.enclosingElement?.displayName,
      'kind': e.kind.displayName,
      // Never disclose an absolute host/pub-cache path in an artifact.
      if (uri != null && (uri.scheme == 'dart' || uri.scheme == 'package'))
        'library': uri.toString(),
      'internal': id != null,
    };
  }

  void within(AstNode node, ExecutableElement? e, void Function() visit) {
    final previous = owner;
    final id = e == null ? '$path@${node.offset}:closure' : internalId(e);
    if (id == null) throw StateError('Declaration outside audited source');
    final parent = e?.enclosingElement;
    declarations[id] = {
      'id': id,
      'path': path,
      'line': line(node),
      'end_line': result.lineInfo.getLocation(node.end - 1).lineNumber,
      'name': e?.displayName.isNotEmpty == true ? e!.displayName : '<closure>',
      'kind': e?.kind.displayName ?? 'closure',
      'enclosing': parent?.displayName,
      'owner_type': parent is InterfaceElement ? internalId(parent) : null,
      'abstract': e?.isAbstract ?? false,
      'static': e?.isStatic ?? false,
      'can_dispatch_virtually':
          e is MethodElement || e is PropertyAccessorElement,
      'override_annotation':
          node is Declaration &&
          node.metadata.any((a) => a.name.name == 'override'),
    };
    owner = id;
    visit();
    owner = previous;
  }

  void reference(AstNode node, Element? element, String kind) {
    if (element is! ExecutableElement) return;
    references.add({
      'from': owner ?? '$path:<initializers>',
      'path': path,
      'line': line(node),
      'offset': node.offset,
      'relation': kind,
      'target': describe(element),
    });
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final e = node.declaredFragment?.element;
    if (e != null) {
      classes[internalId(e)!] = [
        for (final t in e.allSupertypes) ?internalId(t.element),
      ];
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) => within(
    node,
    node.declaredFragment?.element,
    () => super.visitMethodDeclaration(node),
  );
  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) => within(
    node,
    node.declaredFragment?.element,
    () => super.visitConstructorDeclaration(node),
  );
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) => within(
    node,
    node.declaredFragment?.element,
    () => super.visitFunctionDeclaration(node),
  );
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is FunctionDeclaration) {
      super.visitFunctionExpression(node);
      return;
    }
    final parent = owner;
    within(node, node.declaredFragment?.element, () {
      references.add({
        'from': parent ?? '$path:<initializers>',
        'path': path,
        'line': line(node),
        'offset': node.offset,
        'relation': 'creates_closure',
        'target': {'id': owner, 'internal': true, 'name': '<closure>'},
      });
      super.visitFunctionExpression(node);
    });
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext() &&
        node.parent is! ConstructorReferenceNode) {
      final parent = node.parent;
      reference(
        node,
        node.element,
        parent is MethodInvocation && identical(parent.methodName, node)
            ? 'static_call_target'
            : 'static_reference_or_tearoff',
      );
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.element is! ExecutableElement) {
      unresolved.add({
        'from': owner ?? '$path:<initializers>',
        'path': path,
        'line': line(node),
        'name': node.methodName.name,
        'reason': node.methodName.element == null
            ? 'dynamic_or_unresolved_method_target'
            : 'function_value_origin_not_expanded',
      });
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    unresolved.add({
      'from': owner ?? '$path:<initializers>',
      'path': path,
      'line': line(node),
      'name': '<function-value>',
      'reason': 'function_value_origin_not_expanded',
    });
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    reference(node, node.constructorName.element, 'constructor');
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    reference(node, node.element, 'super_constructor');
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    reference(node, node.element, 'redirecting_constructor');
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    reference(node, node.element, 'operator_static_target');
    super.visitBinaryExpression(node);
  }
}

Future<Map<String, Object?>> buildReferenceMap(
  String root,
  List<String> files,
) async {
  if (Platform.environment['CI'] != 'true' && files.length != 1) {
    throw StateError(
      'Only a single-file probe runs locally; full resolution belongs on Actions',
    );
  }
  root = p.normalize(p.absolute(root));
  final collection = AnalysisContextCollection(
    includedPaths: [for (final f in files) p.normalize(p.absolute(f))],
  );
  final declarations = <String, Map<String, Object?>>{};
  final references = <Map<String, Object?>>[],
      unresolved = <Map<String, Object?>>[];
  final classes = <String, List<String>>{};
  final sources = <Map<String, Object?>>[];
  try {
    for (final file in files) {
      final path = p.normalize(p.absolute(file));
      if (!p.isWithin(root, path)) {
        throw ArgumentError('Only repository source is auditable');
      }
      final resolved = await collection
          .contextFor(path)
          .currentSession
          .getResolvedUnit(path);
      if (resolved is! ResolvedUnitResult) {
        throw StateError(
          'Unit did not resolve: ${p.relative(path, from: root)}',
        );
      }
      final index = _Index(
        root,
        p.relative(path, from: root).replaceAll('\\', '/'),
        resolved,
      );
      resolved.unit.accept(index);
      declarations.addAll(index.declarations);
      references.addAll(index.references);
      unresolved.addAll(index.unresolved);
      classes.addAll(index.classes);
      sources.add({
        'path': index.path,
        'sha256': sha256
            .convert(utf8.encode(resolved.content.replaceAll('\r\n', '\n')))
            .toString(),
        'diagnostics': resolved.diagnostics.length,
      });
    }
  } finally {
    await collection.dispose();
  }
  final inbound = <String, int>{};
  final sameName = <String, List<Map<String, Object?>>>{};
  for (final r in references) {
    (r['target'] as Map)['declaration_indexed'] = declarations.containsKey(
      (r['target'] as Map)['id'],
    );
    if ((r['target'] as Map)['id'] case final String id) {
      inbound[id] = (inbound[id] ?? 0) + 1;
    }
  }
  for (final d in declarations.values) {
    (sameName['${d['kind']}:${d['name']}'] ??= []).add(d);
  }
  for (final d in declarations.values) {
    d['static_inbound_references'] = inbound[d['id']] ?? 0;
    d['virtual_dispatch_candidates'] = [
      if (d['owner_type'] != null &&
          d['static'] == false &&
          d['can_dispatch_virtually'] == true)
        for (final other in sameName['${d['kind']}:${d['name']}']!)
          if (other['name'] == d['name'] &&
              other['kind'] == d['kind'] &&
              other['abstract'] == false &&
              (classes[other['owner_type']] ?? const []).contains(
                d['owner_type'],
              ))
            other['id'],
    ];
    d['unused_proven'] = false;
  }
  return {
    'schema': 1,
    'meaning':
        'Resolved static references and interface-dispatch candidates; not runtime reachability or deletion permission',
    'limitations': [
      'Dynamic targets are explicit and unresolved; do not match methods by spelling.',
      'Framework/native callbacks, reflection, exported API and external consumers need manual caller review.',
      'Virtual candidates are possible overrides, not a precise runtime receiver analysis.',
      'Mixin and extension-type override expansion is not complete; their static references remain recorded.',
      'Operator coverage includes binary static targets; implicit VM operations and other operator forms are not complete.',
      'Authored app Dart only; generated localization, tests, package internals and native code are outside this inventory.',
      'Zero direct references never proves redundancy.',
    ],
    'sources': sources,
    'declarations': declarations.values.toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String)),
    'references': references,
    'unresolved': unresolved,
  };
}

Future<void> main(List<String> args) async {
  final fixture = args.contains('--fixture');
  if (!fixture && Platform.environment['CI'] != 'true') {
    throw StateError(
      'Full app resolution runs on Actions; use --fixture for a small local check',
    );
  }
  final root = Directory.current.absolute.path;
  final files = fixture
      ? [p.join(root, 'tool/coverage_callers_fixture.dart')]
      : [
          for (final f in Directory(
            'lib',
          ).listSync(recursive: true, followLinks: false).whereType<File>())
            if (f.path.endsWith('.dart') && !p.split(f.path).contains('l10n'))
              f.absolute.path,
        ];
  files.sort();
  final map = await buildReferenceMap(root, files);
  final head = Process.runSync('git', ['rev-parse', 'HEAD']);
  if (head.exitCode != 0) {
    throw StateError('Cannot anchor caller report to Git');
  }
  map['commit'] = (head.stdout as String).trim();
  map['generated_source_hashes'] = [
    if (Directory('lib/l10n').existsSync())
      for (final f in Directory(
        'lib/l10n',
      ).listSync(followLinks: false).whereType<File>())
        if (f.path.endsWith('.dart'))
          {
            'path': p.relative(f.path, from: root).replaceAll('\\', '/'),
            'sha256': sha256
                .convert(
                  utf8.encode(f.readAsStringSync().replaceAll('\r\n', '\n')),
                )
                .toString(),
          },
  ];
  final at = args.indexOf('--output');
  final output = at < 0 ? 'build/coverage-audit/callers.json' : args[at + 1];
  final dest = File(output).absolute;
  if (!p.isWithin(p.join(root, 'build'), dest.path)) {
    throw ArgumentError('Write audit artifacts only under build/');
  }
  await dest.parent.create(recursive: true);
  await dest.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(map)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'files': files.length,
      'declarations': (map['declarations'] as List).length,
      'static_references': (map['references'] as List).length,
      'unresolved': (map['unresolved'] as List).length,
    }),
  );
}
