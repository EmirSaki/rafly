const int reservationsPerColumn = 10;

int reservationPageCount(int loanedCount, int returnedCount) {
  final longest = loanedCount > returnedCount ? loanedCount : returnedCount;
  return ((longest + reservationsPerColumn - 1) ~/ reservationsPerColumn)
      .clamp(1, 1 << 30);
}

List<T> reservationPage<T>(List<T> items, int pageIndex) {
  final start = pageIndex * reservationsPerColumn;
  if (start >= items.length) return [];
  final end = (start + reservationsPerColumn).clamp(0, items.length);
  return items.sublist(start, end);
}
