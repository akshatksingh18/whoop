// Deliberate interface, callback, closure and dynamic distinctions for the audit.
abstract class FixtureContract {
  int compute(int value);
}

class FixtureStore implements FixtureContract {
  FixtureStore();
  @override
  int compute(int value) => value + 1;
}

int throughContract(FixtureContract store) => store.compute(1);
int throughConcrete(FixtureStore store) => store.compute(2);
int namedCallback() => 3;
int consume(int Function() callback) => callback();
int throughClosure() {
  // The anonymous function-value case is intentional audit input.
  // ignore: prefer_function_declarations_over_variables
  final callback = () => namedCallback();
  return callback();
}

int throughDynamic(dynamic receiver) => receiver.compute(4) as int;
int unusedFixtureFunction() => 5;

int documentationOnlyFunction() => 6;

class FixtureDocumentation {
  FixtureDocumentation.named();
  static int methodOnly() => 7;
  static int get getterOnly => 8;
}

/// Links are documentation, not executable calls or callback registrations:
/// [documentationOnlyFunction], [FixtureDocumentation.methodOnly],
/// [FixtureDocumentation.getterOnly], [FixtureDocumentation.named], [namedCallback].
int documentationLinkHost() => 9;

class FixtureParent {
  FixtureParent.named();
}

class FixtureChild extends FixtureParent {
  FixtureChild.named() : super.named();
  FixtureChild.redirected() : this.named();
}

void main() {
  final store = FixtureStore();
  throughContract(store);
  throughConcrete(store);
  consume(namedCallback);
  throughClosure();
  throughDynamic(store);
  FixtureChild.redirected();
}
