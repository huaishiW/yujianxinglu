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
import 'package:personal_items_assistant/data/repositories/session_repository.dart';
import 'package:personal_items_assistant/data/repositories/template_repository.dart';

void main() {
  late AppDatabase database;
  late GoRouter router;
  late ItemRepository itemRepository;
  late LocationRepository locationRepository;
  late TemplateRepository templateRepository;
  late SessionRepository sessionRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    router = createAppRouter();
    itemRepository = ItemRepository(database);
    locationRepository = LocationRepository(database);
    templateRepository = TemplateRepository(database);
    sessionRepository = SessionRepository(database);
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

  group('TASK 09 物品添加与校验', () {
    testWidgets('在收纳位置内点击添加物品，默认选中当前位置并成功保存', (tester) async {
      final locId = await locationRepository.create(name: '卧室');

      await pumpApp(tester);
      await openItemsPage(tester);

      // 进入卧室
      await tester.tap(find.text('卧室'));
      await tester.pumpAndSettle();

      // 点击“添加物品”
      await tester.tap(find.widgetWithText(TextButton, '添加物品'));
      await tester.pumpAndSettle();

      expect(find.text('添加物品'), findsOneWidget);
      expect(find.text('卧室'), findsWidgets); // 默认选定卧室

      // 输入表单
      await tester.enterText(
        find.widgetWithText(TextFormField, '物品名称 *'),
        '  降噪耳机  ',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '存放数量 *'), '2');
      await tester.enterText(
        find.widgetWithText(TextFormField, '分类（可选）'),
        '电子数码',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '备注（可选）'),
        '黑色头戴式',
      );

      // 保存
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 返回到位置页，当前直接存放的物品区域应显示降噪耳机
      expect(find.text('降噪耳机'), findsOneWidget);
      expect(find.text('数量：2'), findsOneWidget);

      final items = await itemRepository.listByLocation(locId);
      expect(items.length, 1);
      expect(items.first.name, '降噪耳机');
      expect(items.first.quantity, 2);
      expect(items.first.category, '电子数码');
      expect(items.first.note, '黑色头戴式');
    });

    testWidgets('从物品顶层页面点击添加物品，能够通过选择器选定位置', (tester) async {
      final bedroomId = await locationRepository.create(name: '卧室');
      await locationRepository.create(name: '床头柜', parentId: bedroomId);

      await pumpApp(tester);
      await openItemsPage(tester);

      // 在顶层点击 AppBar 上的添加物品按钮
      await tester.tap(find.byTooltip('添加物品'));
      await tester.pumpAndSettle();

      expect(find.text('添加物品'), findsOneWidget);
      expect(find.text('未选择'), findsOneWidget);

      // 点击选择收纳位置
      await tester.tap(find.widgetWithText(ListTile, '所属收纳位置 *'));
      await tester.pumpAndSettle();

      expect(find.text('选择存放位置'), findsOneWidget);
      // 根节点不能直接选定
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '选定此处'))
            .enabled,
        isFalse,
      );

      // 进入卧室
      await tester.tap(find.text('卧室'));
      await tester.pumpAndSettle();

      // 看到床头柜，点击“直接选择”
      await tester.tap(find.widgetWithText(TextButton, '直接选择'));
      await tester.pumpAndSettle();

      expect(find.text('卧室 / 床头柜'), findsOneWidget);

      // 输入名称并提交
      await tester.enterText(
        find.widgetWithText(TextFormField, '物品名称 *'),
        '眼罩',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 查询数据库确认
      final search = await itemRepository.searchByName('眼罩');
      expect(search.length, 1);
      expect(search.first.name, '眼罩');
      expect(
        await itemRepository.fullLocationPath(search.first.id),
        '卧室 / 床头柜',
      );
    });

    testWidgets('空名称、无效数量以及未选择位置提交时被拒绝', (tester) async {
      await pumpApp(tester);
      await openItemsPage(tester);

      await tester.tap(find.byTooltip('添加物品'));
      await tester.pumpAndSettle();

      // 1. 未输入名称直接保存
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('物品名称不能为空'), findsOneWidget);

      // 2. 输入空格名称
      await tester.enterText(
        find.widgetWithText(TextFormField, '物品名称 *'),
        '   ',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('物品名称不能为空'), findsOneWidget);

      // 3. 输入合法名称，但数量改为 0
      await tester.enterText(
        find.widgetWithText(TextFormField, '物品名称 *'),
        '钥匙',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '存放数量 *'), '0');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('物品数量必须是大于或等于 1 的正整数'), findsOneWidget);

      // 4. 改为正常数量，但未选择位置
      await tester.enterText(find.widgetWithText(TextFormField, '存放数量 *'), '1');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('请选择物品所属的收纳位置'), findsOneWidget);
    });

    testWidgets('允许添加多个同名物品，且以不同 ID 分别保存与展示', (tester) async {
      final locId1 = await locationRepository.create(name: '书房');
      final locId2 = await locationRepository.create(name: '玄关');

      final id1 = await itemRepository.create(
        name: '充电线',
        quantity: 1,
        locationId: locId1,
      );
      final id2 = await itemRepository.create(
        name: '充电线',
        quantity: 3,
        locationId: locId2,
      );

      expect(id1, isNot(id2));

      await pumpApp(tester);
      await openItemsPage(tester);

      // 验证搜索页可以查出两条同名记录
      await tester.tap(find.byTooltip('搜索物品'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '充电线');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('search-item-$id1')), findsOneWidget);
      expect(find.byKey(ValueKey('search-item-$id2')), findsOneWidget);
      expect(find.text('数量：1'), findsOneWidget);
      expect(find.text('数量：3'), findsOneWidget);
    });
  });

  group('TASK 09 物品搜索与详情查看', () {
    testWidgets('从首页搜索框点击可直接进入搜索页面', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.widgetWithText(TextField, '搜索物品名称'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '搜索物品名称...'), findsOneWidget);
    });

    testWidgets('中文关键词部分匹配，展示完整路径，点击进入详情', (tester) async {
      final bedroomId = await locationRepository.create(name: '主卧室');
      final drawerId = await locationRepository.create(
        name: '床头左抽屉',
        parentId: bedroomId,
      );
      final itemId = await itemRepository.create(
        name: '便携充电宝',
        quantity: 1,
        locationId: drawerId,
        category: '数码配件',
        note: '支持快充',
      );

      await pumpApp(tester);
      await openItemsPage(tester);

      await tester.tap(find.byTooltip('搜索物品'));
      await tester.pumpAndSettle();

      // 输入部分中文
      await tester.enterText(find.byType(TextField), '充电');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('便携充电宝'), findsOneWidget);
      expect(find.text('数量：1'), findsOneWidget);
      expect(find.text('位置：主卧室 / 床头左抽屉'), findsOneWidget);

      // 点击搜索结果卡片进入详情
      await tester.tap(find.byKey(ValueKey('search-item-$itemId')));
      await tester.pumpAndSettle();

      expect(find.text('物品详情'), findsOneWidget);
      expect(find.text('便携充电宝'), findsOneWidget);
      expect(find.text('物品 ID: $itemId'), findsOneWidget);
      expect(find.text('主卧室 / 床头左抽屉'), findsOneWidget);
      expect(find.text('数码配件'), findsOneWidget);
      expect(find.text('支持快充'), findsOneWidget);
      expect(find.text('创建时间'), findsOneWidget);
    });

    testWidgets('空搜索条件返回全量物品，无匹配时展示空状态', (tester) async {
      final locId = await locationRepository.create(name: '客厅');
      await itemRepository.create(name: '电视遥控器', locationId: locId);

      await pumpApp(tester);
      await openItemsPage(tester);
      await tester.tap(find.byTooltip('搜索物品'));
      await tester.pumpAndSettle();

      // 空搜索时展示全部物品
      expect(find.text('电视遥控器'), findsOneWidget);

      // 搜索不存在的物品
      await tester.enterText(find.byType(TextField), '不存在的物品xyz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('未找到名称包含“不存在的物品xyz”的物品'), findsOneWidget);
    });

    testWidgets('位置浏览页面中的直接物品卡片点击可进入物品详情', (tester) async {
      final locId = await locationRepository.create(name: '书桌');
      final itemId = await itemRepository.create(name: '钢笔', locationId: locId);

      await pumpApp(tester);
      await openItemsPage(tester);
      await tester.tap(find.text('书桌'));
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('direct-item-card-$itemId')), findsOneWidget);

      // 点击直接物品卡片
      await tester.tap(find.byKey(ValueKey('direct-item-card-$itemId')));
      await tester.pumpAndSettle();

      expect(find.text('物品详情'), findsOneWidget);
      expect(find.text('钢笔'), findsOneWidget);
    });
  });

  group('TASK 09 物品编辑与移动位置', () {
    testWidgets('修改物品名称、数量，并清空原有分类与备注', (tester) async {
      final locId = await locationRepository.create(name: '衣柜');
      final itemId = await itemRepository.create(
        name: '旧外套',
        quantity: 1,
        locationId: locId,
        category: '冬装',
        note: '需要干洗',
      );

      await pumpApp(tester);
      await openItemsPage(tester);
      await tester.tap(find.text('衣柜'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('direct-item-card-$itemId')));
      await tester.pumpAndSettle();

      // 进入编辑页
      await tester.tap(find.byTooltip('编辑物品'));
      await tester.pumpAndSettle();

      expect(find.text('编辑物品'), findsOneWidget);
      expect(find.text('旧外套'), findsOneWidget);
      expect(find.text('冬装'), findsOneWidget);

      // 修改名称和数量
      await tester.enterText(
        find.widgetWithText(TextFormField, '物品名称 *'),
        '羽绒服',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '存放数量 *'), '3');

      // 清空分类和备注
      await tester.enterText(find.widgetWithText(TextFormField, '分类（可选）'), '');
      await tester.enterText(find.widgetWithText(TextFormField, '备注（可选）'), '');

      // 保存
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 回到详情页，观察最新数据
      expect(find.text('羽绒服'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('冬装'), findsNothing);
      expect(find.text('需要干洗'), findsNothing);

      // 验证数据库
      final updated = await itemRepository.getById(itemId);
      expect(updated.id, itemId); // ID 不变
      expect(updated.name, '羽绒服');
      expect(updated.quantity, 3);
      expect(updated.category, isNull);
      expect(updated.note, isNull);
    });

    testWidgets('编辑物品时移动位置，旧位置与新位置列表同步更新', (tester) async {
      final oldLocId = await locationRepository.create(name: '书房');
      final newLocId = await locationRepository.create(name: '客厅');
      final itemId = await itemRepository.create(
        name: '剪刀',
        locationId: oldLocId,
      );

      await pumpApp(tester);
      await openItemsPage(tester);
      await tester.tap(find.text('书房'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('direct-item-card-$itemId')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('编辑物品'));
      await tester.pumpAndSettle();

      // 点击更换位置
      await tester.tap(find.widgetWithText(ListTile, '所属收纳位置 *'));
      await tester.pumpAndSettle();

      // 因为初始位置在“书房”，先点击返回上一级回到顶层
      await tester.tap(find.byTooltip('返回上一级'));
      await tester.pumpAndSettle();

      // 选定客厅
      await tester.tap(find.text('客厅'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '选定此处'));
      await tester.pumpAndSettle();

      expect(find.text('客厅'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 详情页位置已变为客厅
      expect(find.text('客厅'), findsWidgets);

      // 检查数据库
      final item = await itemRepository.getById(itemId);
      expect(item.locationId, newLocId);
      expect(await itemRepository.listByLocation(oldLocId), isEmpty);
      expect((await itemRepository.listByLocation(newLocId)).single.id, itemId);
    });
  });

  group('TASK 09 物品安全删除与引用转换', () {
    testWidgets('删除无关联物品成功并刷新界面', (tester) async {
      final locId = await locationRepository.create(name: '杂物间');
      final itemId = await itemRepository.create(
        name: '旧纸箱',
        locationId: locId,
      );

      await pumpApp(tester);
      await openItemsPage(tester);
      await tester.tap(find.text('杂物间'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('direct-item-card-$itemId')));
      await tester.pumpAndSettle();

      // 点击删除
      await tester.tap(find.byTooltip('删除物品'));
      await tester.pumpAndSettle();

      expect(find.text('删除物品确认'), findsOneWidget);
      expect(find.text('该物品未被任何出门模板或任务引用，删除后记录将直接移除。'), findsOneWidget);

      // 取消删除
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(await itemRepository.findById(itemId), isNotNull);

      // 再次点击确认删除
      await tester.tap(find.byTooltip('删除物品'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await tester.pumpAndSettle();

      // 弹窗关闭并返回到杂物间位置页，纸箱已不在直接物品中
      expect(find.text('当前没有直接存放的物品'), findsOneWidget);
      expect(await itemRepository.findById(itemId), isNull);
    });

    testWidgets('删除被模板和进行中任务引用的物品，展示影响说明，确认后正确转换为普通文本', (tester) async {
      final locId = await locationRepository.create(name: '卧室');
      final itemId = await itemRepository.create(
        name: '雨伞',
        quantity: 1,
        locationId: locId,
      );

      // 1. 创建出门模板并引用雨伞
      final templateId = await templateRepository.create(
        name: '雨天出门',
        entries: [
          TemplateEntryInput.registered(itemId: itemId, requiredQuantity: 1),
        ],
      );

      // 2. 创建进行中的出门任务并引用雨伞
      final sessionId = await sessionRepository.createDirect(
        title: '本次下雨出门',
        entries: [
          SessionEntryInput.registered(itemId: itemId, requiredQuantity: 1),
        ],
      );

      // 3. 创建已完成任务并包含雨伞快照
      final completedSessionId = await sessionRepository.createDirect(
        title: '历史雨天出门',
        entries: [
          SessionEntryInput.registered(itemId: itemId, requiredQuantity: 1),
        ],
      );
      await sessionRepository.complete(
        completedSessionId,
        confirmedUnchecked: true,
      );

      await pumpApp(tester);
      await openItemsPage(tester);
      await tester.tap(find.text('卧室'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('direct-item-card-$itemId')));
      await tester.pumpAndSettle();

      // 点击删除
      await tester.tap(find.byTooltip('删除物品'));
      await tester.pumpAndSettle();

      // 确认弹窗展示引用影响
      expect(find.text('删除物品确认'), findsOneWidget);
      expect(find.text('• 出门模板：1 个条目'), findsOneWidget);
      expect(find.text('• 进行中清单：1 个条目'), findsOneWidget);
      expect(find.text('• 已完成历史：1 条记录'), findsOneWidget);
      expect(
        find.textContaining('相关模板和进行中清单的条目仍会保留，并自动转换为普通文本条目'),
        findsOneWidget,
      );

      // 确认删除
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await tester.pumpAndSettle();

      // 物品本身已被删除
      expect(await itemRepository.findById(itemId), isNull);

      // 模板条目转为 TEXT_ITEM
      final templateDetail = await templateRepository.getDetail(templateId);
      expect(templateDetail.entries.length, 1);
      final templateEntry = templateDetail.entries.first;
      expect(templateEntry.entry.itemType, 'TEXT_ITEM');
      expect(templateEntry.entry.itemId, isNull);
      expect(templateEntry.displayName, '雨伞');

      // 进行中任务条目转为 TEXT_ITEM
      final activeDetail = await sessionRepository.getDetail(sessionId);
      expect(activeDetail.entries.length, 1);
      expect(activeDetail.entries.first.entry.itemType, 'TEXT_ITEM');
      expect(activeDetail.entries.first.entry.itemId, isNull);
      expect(activeDetail.entries.first.displayName, '雨伞');

      // 已完成历史条目快照不受影响
      final completedDetail = await sessionRepository.getDetail(
        completedSessionId,
      );
      expect(completedDetail.entries.length, 1);
      expect(completedDetail.entries.first.entry.nameSnapshot, '雨伞');
      expect(completedDetail.entries.first.entry.locationSnapshot, '卧室');
    });
  });
}
