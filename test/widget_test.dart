import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:personal_items_assistant/app/app.dart';

void main() {
  testWidgets('应用首页正常显示', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PersonalItemsApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('个人物品与出门助手'),
      findsOneWidget,
    );

    expect(
      find.text('工程骨架已搭建'),
      findsOneWidget,
    );
  });
}
