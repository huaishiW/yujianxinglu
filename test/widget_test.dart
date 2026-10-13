import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_items_assistant/app/app.dart';
import 'package:personal_items_assistant/app/providers/app_providers.dart';
import 'package:personal_items_assistant/app/router/app_router.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';

void main() {
  late AppDatabase database;
  late GoRouter router;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    router = createAppRouter();
  });

  tearDown(() async {
    router.dispose();
    await database.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: PersonalItemsApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openItemsPage(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
  }

  Future<void> createLocation(WidgetTester tester, String name) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), name);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('三栏一级导航可以切换', (tester) async {
    await pumpApp(tester);

    expect(find.text('个人物品与出门助手'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);

    await openItemsPage(tester);
    expect(find.text('物品'), findsWidgets);
    expect(find.text('收纳位置'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.directions_walk_outlined));
    await tester.pumpAndSettle();
    expect(find.text('出门'), findsWidgets);
    expect(find.text('进行中的任务'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('最近使用的模板'), findsOneWidget);
  });

  testWidgets('位置页显示空状态并创建顶层位置', (tester) async {
    await pumpApp(tester);
    await openItemsPage(tester);

    expect(find.text('还没有收纳位置'), findsOneWidget);

    await createLocation(tester, '卧室');

    expect(find.text('卧室'), findsOneWidget);
  });

  testWidgets('位置页可以进入子位置并显示层级导航', (tester) async {
    await pumpApp(tester);
    await openItemsPage(tester);
    await createLocation(tester, '卧室');

    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();

    expect(find.text('我的收纳位置'), findsOneWidget);
    expect(find.text('当前没有子位置'), findsOneWidget);

    await tester.tap(find.text('新建子位置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '书桌');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('书桌'), findsOneWidget);
    expect(find.text('卧室'), findsWidgets);
  });

  testWidgets('创建同级重名位置显示业务错误且不报告成功', (tester) async {
    await pumpApp(tester);
    await openItemsPage(tester);
    await createLocation(tester, '卧室');

    await tester.tap(find.text('新建位置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '卧室');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('同一层级下已存在同名位置'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('卧室'), findsOneWidget);
  });

  testWidgets('切换一级页面后位置数据仍然存在', (tester) async {
    await pumpApp(tester);
    await openItemsPage(tester);
    await createLocation(tester, '长期保留的位置');

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    expect(find.text('长期保留的位置'), findsOneWidget);
  });
}
