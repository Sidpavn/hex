import 'service.dart';

/// The one thing most worth changing after a day: whatever cost the most,
/// said plainly with what to do about it. Null when nothing stands out.
String? fixFirst(DayReport r) {
  // Each cause is scored in rough coins, so a few lost guests and a pile of
  // thrown-away food can be compared. A lost guest is worth about 10.
  final causes = <(int, String)>[];
  void add(int score, String text) => causes.add((score, text));

  if (r.unpaid > 0) {
    add(
      10000,
      'Wages went unpaid. Keep enough coins back to pay the team, or let '
      'someone go.',
    );
  }
  if (r.loanMissed) {
    add(
      9000,
      'The bank did not get its payment. Keep coins back for it, or pay the '
      'loan down in the Bank.',
    );
  }
  if (r.soldOut >= 2) {
    add(
      r.soldOut * 12,
      '${r.soldOut} guests found their dish sold out. Raise the portions in '
      "Today's portions.",
    );
  }
  if (r.tooDear >= 2) {
    add(
      r.tooDear * 12,
      '${r.tooDear} guests left over the prices. Lower a price in the Menu, '
      'or put a dish on the board outside.',
    );
  }
  if (r.gaveUp >= 2) {
    add(
      r.gaveUp * 12,
      '${r.gaveUp} guests gave up waiting. Add a cook or another machine, or '
      'hang a TV near the tables.',
    );
  }
  if (r.queueFull >= 2) {
    add(
      r.queueFull * 10,
      '${r.queueFull} people walked past a full queue. More tables and seats '
      'will move it along.',
    );
  }
  if (r.spoiled >= 2) {
    add(
      r.spoiled * 6,
      '${r.spoiled} portions arrived spoiled. Change supplier in Today\'s '
      'portions.',
    );
  }
  if (r.leftover > 0 && r.ingredients > 0 && r.leftover * 4 > r.ingredients) {
    add(
      r.leftover,
      'Ingredients worth ${r.leftover} were thrown away. Prepare fewer '
      "portions in Today's portions.",
    );
  }
  if (r.earned + r.tips - r.ingredients - r.wages < 0) {
    add(
      60,
      'The day lost money after ingredients and wages. Raise prices, or '
      'prepare less.',
    );
  }
  if (causes.isEmpty) return null;
  causes.sort((a, b) => b.$1.compareTo(a.$1));
  return causes.first.$2;
}
