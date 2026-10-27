const workoutContextLabels = {
  'flat': 'Flat route',
  'hills': 'Hills',
  'treadmill': 'Treadmill',
  'heat': 'Felt hot',
  'attention': 'Multitasking',
  'strength': 'Recent strength training',
};
List<String> workoutContext(Object? value) => value is List
    ? (value
          .whereType<String>()
          .where(workoutContextLabels.containsKey)
          .toSet()
          .toList()
        ..sort())
    : [];
List<String> toggleWorkoutContext(List<String> old, String key) {
  final out = old.toSet();
  if (!out.remove(key)) {
    if (const ['flat', 'hills', 'treadmill'].contains(key)) {
      out.removeAll(['flat', 'hills', 'treadmill']);
    }
    out.add(key);
  }
  return workoutContext(out.toList());
}
