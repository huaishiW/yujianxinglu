import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_items_assistant/app/app.dart';
import 'package:personal_items_assistant/app/providers/app_providers.dart';
import 'package:personal_items_assistant/app/router/app_router.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';
import 'package:personal_items_assistant/data/repositories/item_repository.dart';
import 'package:personal_items_assistant/data/repositories/location_repository.dart';

void main() {
  late AppDatabase database;
  late GoRouter router;
  late ItemRepository itemRepository;
  late LocationRepository locationRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    router = createAppRouter();
    itemRepository = ItemRepository(database);
    locationRepository = LocationRepository(database);
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

  Finder locationActionButton(int locationId) {
    return find.descendant(
      of: find.byKey(ValueKey('location-card-$locationId')),
      matching: find.byIcon(Icons.more_vert),
    );
  }

  Future<void> openLocationAction(
    WidgetTester tester,
    int locationId,
    String action,
  ) async {
    await tester.tap(locationActionButton(locationId));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('三栏一级导航可以切换', (tester) async {
    await pumpApp(tester);

    expect(find.text('玉简行录'), findsOneWidget);
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

  testWidgets('空名称创建被拒绝并保留输入弹窗', (tester) async {
    await pumpApp(tester);
    await openItemsPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('位置名称不能为空'), findsOneWidget);
    expect(find.text('新建顶层位置'), findsOneWidget);
  });

  testWidgets('重命名当前位置后标题和路径立即更新', (tester) async {
    final locationId = await locationRepository.create(name: '卧室');

    await pumpApp(tester);
    await openItemsPage(tester);
    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '主卧');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final renamed = await locationRepository.getById(locationId);
    expect(renamed.name, '主卧');
    expect(find.text('主卧'), findsWidgets);
    expect(find.text('卧室'), findsNothing);
  });

  testWidgets('逐层浏览只显示当前位置的直接物品', (tester) async {
    final rootId = await locationRepository.create(name: '卧室');
    final childId = await locationRepository.create(
      name: '书桌',
      parentId: rootId,
    );
    await itemRepository.create(name: '根位置物品', quantity: 2, locationId: rootId);
    await itemRepository.create(name: '子位置物品', locationId: childId);

    await pumpApp(tester);
    await openItemsPage(tester);
    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();

    expect(find.text('根位置物品'), findsOneWidget);
    expect(find.text('数量：2'), findsOneWidget);
    expect(find.text('子位置物品'), findsNothing);

    await tester.tap(find.text('书桌'));
    await tester.pumpAndSettle();
    expect(find.text('子位置物品'), findsOneWidget);
    expect(find.text('根位置物品'), findsNothing);
  });

  testWidgets('系统返回键从子层级返回上一级', (tester) async {
    final rootId = await locationRepository.create(name: '卧室');
    await locationRepository.create(name: '书桌', parentId: rootId);

    await pumpApp(tester);
    await openItemsPage(tester);
    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书桌'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('卧室'), findsWidgets);
    expect(find.text('书桌'), findsOneWidget);
    expect(find.text('我的收纳位置'), findsOneWidget);
  });

  testWidgets('移动位置确认取消时不改变数据', (tester) async {
    final bedroomId = await locationRepository.create(name: '卧室');
    final studyId = await locationRepository.create(name: '书房');
    final boxId = await locationRepository.create(
      name: '收纳盒',
      parentId: bedroomId,
    );

    await pumpApp(tester);
    await openItemsPage(tester);
    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();
    await openLocationAction(tester, boxId, '移动');

    expect(find.text('选择移动目标'), findsOneWidget);
    await tester.tap(find.text('书房'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择此处'));
    await tester.pumpAndSettle();

    expect(find.text('确认移动位置'), findsOneWidget);
    expect(find.text('卧室 / 收纳盒'), findsOneWidget);
    expect(find.text('书房 / 收纳盒'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect((await locationRepository.getById(boxId)).parentId, bedroomId);
    expect((await locationRepository.getById(boxId)).parentId, isNot(studyId));
  });

  testWidgets('移动位置到另一个父位置后保留子树关系', (tester) async {
    final bedroomId = await locationRepository.create(name: '卧室');
    final studyId = await locationRepository.create(name: '书房');
    final boxId = await locationRepository.create(
      name: '收纳盒',
      parentId: bedroomId,
    );
    final drawerId = await locationRepository.create(
      name: '内层抽屉',
      parentId: boxId,
    );
    await itemRepository.create(name: '耳机', locationId: drawerId);

    await pumpApp(tester);
    await openItemsPage(tester);
    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();
    await openLocationAction(tester, boxId, '移动');

    await tester.tap(find.text('书房'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择此处'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移动'));
    await tester.pumpAndSettle();

    expect((await locationRepository.getById(boxId)).parentId, studyId);
    expect((await locationRepository.getById(drawerId)).parentId, boxId);
    expect(await locationRepository.fullPath(drawerId), '书房 / 收纳盒 / 内层抽屉');
    expect(find.text('书房'), findsWidgets);
    expect(find.text('收纳盒'), findsWidgets);
  });

  testWidgets('自身位置不能作为移动目标', (tester) async {
    final rootId = await locationRepository.create(name: '卧室');
    await locationRepository.create(name: '书桌', parentId: rootId);

    await pumpApp(tester);
    await openItemsPage(tester);
    await openLocationAction(tester, rootId, '移动');

    expect(find.text('不能移动到自身或其后代'), findsOneWidget);
    expect(find.text('选择此处'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect((await locationRepository.getById(rootId)).parentId, isNull);
  });

  testWidgets('移动到根目录后 parentId 为 null', (tester) async {
    final bedroomId = await locationRepository.create(name: '卧室');
    final boxId = await locationRepository.create(
      name: '收纳盒',
      parentId: bedroomId,
    );

    await pumpApp(tester);
    await openItemsPage(tester);
    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();
    await openLocationAction(tester, boxId, '移动');

    await tester.tap(find.text('选择此处'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移动'));
    await tester.pumpAndSettle();

    expect((await locationRepository.getById(boxId)).parentId, isNull);
    expect(find.text('我的收纳位置'), findsOneWidget);
    expect(find.text('收纳盒'), findsWidgets);
  });

  testWidgets('删除空位置成功且删除确认取消不改变数据', (tester) async {
    final locationId = await locationRepository.create(name: '临时位置');

    await pumpApp(tester);
    await openItemsPage(tester);
    await openLocationAction(tester, locationId, '删除');
    expect(find.text('删除收纳位置'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await locationRepository.findById(locationId), isNotNull);

    await openLocationAction(tester, locationId, '删除');
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(await locationRepository.findById(locationId), isNull);
    expect(find.text('还没有收纳位置'), findsOneWidget);
  });

  testWidgets('非空位置删除被拒绝且页面不提前移除', (tester) async {
    final locationId = await locationRepository.create(name: '卧室');
    await locationRepository.create(name: '书桌', parentId: locationId);

    await pumpApp(tester);
    await openItemsPage(tester);
    await openLocationAction(tester, locationId, '删除');
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(find.text('该位置仍包含子位置或物品，无法删除'), findsOneWidget);
    expect(await locationRepository.findById(locationId), isNotNull);
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

  testWidgets('返回物品页面时重新读取最新位置数据', (tester) async {
    await pumpApp(tester);
    await openItemsPage(tester);
    expect(find.text('还没有收纳位置'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await locationRepository.create(name: '切换期间创建的位置');

    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    expect(find.text('切换期间创建的位置'), findsOneWidget);
  });
}
