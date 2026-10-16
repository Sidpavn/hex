// Getting to the programs on the computer in the staff room, the way a
// player does: the door in the back wall, then the computer, then the icon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/staff_room.dart';

/// Taps the staff room door on the build screen.
Future<void> tapDoor(WidgetTester tester) async {
  final paint = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere((w) => w.painter is DinerPainter);
  final painter = paint.painter! as DinerPainter;
  final c = painter.diner.staffDoor!;
  final v = painter.fit.view.vertex(c.x + 0.5, c.y + 0.5) * painter.fit.s;
  final box = tester.getTopLeft(find.byWidget(paint));
  await tester.tapAt(box + v);
  await _settle(tester);
}

/// Taps the computer in the staff room page.
Future<void> tapComputer(WidgetTester tester, {required Offset at}) async {
  await tester.tapAt(at);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Where the computer is on screen, on the staff room page.
Offset computerAt(WidgetTester tester) {
  final art = DinerArt.instance!;
  final box = tester.getRect(find.byKey(const ValueKey('room-scene')));
  final size = StaffRoomPainter.size(art);
  final unit = box.width / size.width;
  final room = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<StaffRoomPainter>()
      .first
      .room;
  final c = room.computer!.at;
  return box.topLeft + StaffRoomPainter.centre(art, c) * unit;
}

/// Opens the staff room from the build screen.
Future<void> openRoom(WidgetTester tester) => tapDoor(tester);

/// Opens the computer from the staff room page.
Future<void> openComputer(WidgetTester tester) =>
    tapComputer(tester, at: computerAt(tester));

/// From the build screen: door, computer, then the program called [app]
/// (the name of a `DeskApp`, such as 'menu').
Future<void> openApp(WidgetTester tester, String app) async {
  await openRoom(tester);
  await openComputer(tester);
  final icon = find.byKey(ValueKey('app-$app'));
  await tester.ensureVisible(icon);
  await tester.pump();
  await tester.tap(icon);
  await _settle(tester);
}
