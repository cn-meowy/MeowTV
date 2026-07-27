import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MeowTVApp());
    await tester.pump();
    expect(find.text('MeowTV'), findsAny);
  });
}
