// Every compact macro line prints P · C · F · Fb in that order once any macro
// was logged, so fibre never drops off a row (Akshat, build 86).
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart';

void main() {
  test('all four macros print, missing ones as a dash', () {
    expect(macroParts(protein: 6, carbs: 34, fat: 4), [
      'P 6',
      'C 34',
      'F 4',
      'Fb –',
    ]);
    expect(macroParts(protein: 0, carbs: 11, fat: 0, fibre: 2.4), [
      'P 0',
      'C 11',
      'F 0',
      'Fb 2',
    ]);
  });

  test('nothing logged prints nothing, never a row of zeros', () {
    expect(macroParts(), isEmpty);
    expect(macroLine(kcal: 25), '25 kcal');
    expect(macroLine(), 'No nutrition numbers');
  });

  test('macroLine keeps one decimal and includes fibre', () {
    expect(
      macroLine(kcal: 200, protein: 6.5, carbs: 33, fat: 3.5, fibre: 5),
      '200 kcal · P 6.5 · C 33.0 · F 3.5 · Fb 5.0',
    );
    expect(
      macroLine(kcal: 200, protein: 6.5),
      '200 kcal · P 6.5 · C – · F – · Fb –',
    );
  });
}
