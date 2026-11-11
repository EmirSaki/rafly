/// Sorts school classes by grade first, then by section letter.
int compareClassNames(String a, String b) {
  final gradePattern = RegExp(r'\d+');
  int grade(String value) => int.tryParse(gradePattern.firstMatch(value)?.group(0) ?? '') ?? 999;
  String section(String value) => value.toUpperCase()
      .replaceAll(gradePattern, '')
      .replaceAll(RegExp(r'[^A-ZÇĞİÖŞÜ]'), '');

  final gradeOrder = grade(a).compareTo(grade(b));
  if (gradeOrder != 0) return gradeOrder;
  final sectionOrder = section(a).compareTo(section(b));
  if (sectionOrder != 0) return sectionOrder;
  return a.toUpperCase().compareTo(b.toUpperCase());
}
