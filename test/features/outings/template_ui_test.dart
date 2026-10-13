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
import 'package:personal_items_assistant/data/repositories/template_repository.dart';

void main() {
  late AppDatabase database;
  late GoRouter router;
  late ItemRepository itemRepository;
  late LocationRepository locationRepository;
  late TemplateRepository templateRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    router = createAppRouter();
    itemRepository = ItemRepository(database);
    locationRepository = LocationRepository(database);
    templateRepository = TemplateRepository(database);
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

  Future<void> openOutingsPage(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(NavigationDestination, '出门'));
    await tester.pumpAndSettle();
  }

  Future<void> switchToTemplateTab(WidgetTester tester) async {
    await tester.tap(find.text('模板'));
    await tester.pumpAndSettle();
  }

  group('TASK 10 模板列表与展示', () {
    testWidgets('模板列表展示空状态，点击新建模板进入表单', (tester) async {
      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);

      expect(find.text('暂无出门模板，点击右下角创建'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('create-template-fab')));
      await tester.pumpAndSettle();

      expect(find.text('新建出门模板'), findsOneWidget);
    });

    testWidgets('允许创建同名模板，列表以不同 ID 分别展示', (tester) async {
      final locId = await locationRepository.create(name: '玄关');
      final itemId = await itemRepository.create(
        name: '门禁卡',
        locationId: locId,
      );

      final t1 = await templateRepository.create(
        name: '日常出门',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );
      final t2 = await templateRepository.create(
        name: '日常出门',
        entries: [TemplateEntryInput.text(textName: '戴口罩')],
      );

      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);

      expect(find.byKey(ValueKey('template-card-$t1')), findsOneWidget);
      expect(find.byKey(ValueKey('template-card-$t2')), findsOneWidget);
      expect(find.text('日常出门'), findsNWidgets(2));
    });
  });

  group('TASK 10 模板创建与校验', () {
    testWidgets('拒绝空白名称与空条目提交', (tester) async {
      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);
      await tester.tap(find.byKey(const ValueKey('create-template-fab')));
      await tester.pumpAndSettle();

      // 1. 空名称与空条目点击保存
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('模板名称不能为空'), findsOneWidget);

      // 2. 填写合法名称，但未添加任何条目
      await tester.enterText(
        find.widgetWithText(TextFormField, '模板名称 *'),
        '  通勤准备  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('模板至少需要添加一个条目'), findsOneWidget);

      // 数据库中不应有残留数据
      final templates = await templateRepository.listAll();
      expect(templates, isEmpty);
    });

    testWidgets('创建混合条目的模板并成功保存与刷新列表', (tester) async {
      final locId = await locationRepository.create(name: '卧室');
      final itemId = await itemRepository.create(
        name: '无线耳机',
        quantity: 2,
        locationId: locId,
      );

      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);
      await tester.tap(find.byKey(const ValueKey('create-template-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '模板名称 *'),
        '日常通勤',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '模板描述（可选）'),
        '工作日必备物品',
      );

      // 添加登记物品
      await tester.tap(find.widgetWithText(OutlinedButton, '添加登记物品'));
      await tester.pumpAndSettle();

      expect(find.text('搜索要添加的登记物品...'), findsOneWidget);
      expect(find.text('无线耳机'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '选择'));
      await tester.pumpAndSettle();

      expect(find.text('无线耳机'), findsOneWidget);
      expect(find.text('需带: 1'), findsOneWidget);

      // 添加普通文本
      await tester.tap(find.widgetWithText(OutlinedButton, '添加普通文本'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '条目内容 *'),
        '关好门窗',
      );
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();

      expect(find.text('关好门窗'), findsOneWidget);

      // 再次点击“添加登记物品”，验证“无线耳机”已被置灰禁止重复添加
      await tester.tap(find.widgetWithText(OutlinedButton, '添加登记物品'));
      await tester.pumpAndSettle();
      expect(find.text('已在当前模板中（禁止重复添加）'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      // 点击保存
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 返回列表并刷新
      expect(find.text('日常通勤'), findsOneWidget);
      expect(find.text('2 个条目'), findsOneWidget);

      final all = await templateRepository.listAll();
      expect(all.length, 1);
      final detail = await templateRepository.getDetail(all.first.id);
      expect(detail.template.name, '日常通勤');
      expect(detail.template.description, '工作日必备物品');
      expect(detail.entries.length, 2);
      expect(detail.entries[0].displayName, '无线耳机');
      expect(detail.entries[0].entry.itemId, itemId);
      expect(detail.entries[0].isRegisteredItem, isTrue);
      expect(detail.entries[1].displayName, '关好门窗');
      expect(detail.entries[1].isRegisteredItem, isFalse);
    });
  });

  group('TASK 10 数量不足提示与详情查看', () {
    testWidgets('库存不足时，编辑表单即时提示且详情页高亮警告，但不阻止保存', (tester) async {
      final locId = await locationRepository.create(name: '客厅');
      final itemId = await itemRepository.create(
        name: '口罩',
        quantity: 2, // 库存 2
        locationId: locId,
      );

      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);
      await tester.tap(find.byKey(const ValueKey('create-template-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '模板名称 *'),
        '防护模板',
      );

      // 添加口罩
      await tester.tap(find.widgetWithText(OutlinedButton, '添加登记物品'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '选择'));
      await tester.pumpAndSettle();

      // 修改所需数量为 5
      await tester.tap(find.text('需带: 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '所需数量 *'), '5');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '保存'),
        ),
      );
      await tester.pumpAndSettle();

      // 验证编辑表单中的即时短缺提示
      expect(find.textContaining('库存 2，需带 5，缺少 3（提醒：不影响保存）'), findsOneWidget);

      // 保存模板
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 列表卡片上展示缺货标志
      expect(find.textContaining('1 项缺货'), findsOneWidget);

      // 点击进入模板详情页
      await tester.tap(find.text('防护模板'));
      await tester.pumpAndSettle();

      expect(find.text('模板详情'), findsOneWidget);
      expect(find.text('库存不足提醒（共 1 项数量不足）'), findsOneWidget);
      expect(find.textContaining('口罩：库存 2，需带 5，缺少 3'), findsOneWidget);
      final shortages = await templateRepository.listQuantityShortages(
        (await templateRepository.listAll()).first.id,
      );
      expect(shortages.first.itemId, itemId);

      // 点击“以此模板开始出门”，验证弹出功能将在下一阶段开放的友好提示
      await tester.tap(find.widgetWithText(FilledButton, '以此模板开始出门'));
      await tester.pumpAndSettle();
      expect(find.text('“使用模板创建出门任务”功能将在下一阶段（TASK 11）正式开放'), findsOneWidget);
    });
  });

  group('TASK 10 模板编辑、排序与删除', () {
    testWidgets('编辑模板名称、调整条目所需数量、删除条目', (tester) async {
      final locId = await locationRepository.create(name: '书房');
      final itemId = await itemRepository.create(
        name: '笔记本电脑',
        locationId: locId,
      );
      final templateId = await templateRepository.create(
        name: '出差模板',
        entries: [
          TemplateEntryInput.registered(itemId: itemId, requiredQuantity: 1),
          TemplateEntryInput.text(textName: '身份证', requiredQuantity: 1),
        ],
      );

      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);

      // 点击卡片上的编辑按钮
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('template-card-$templateId')),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('编辑模板'), findsOneWidget);
      expect(find.text('出差模板'), findsOneWidget);

      // 修改名称
      await tester.enterText(
        find.widgetWithText(TextFormField, '模板名称 *'),
        '长途差旅',
      );

      // 删除身份证条目
      final deleteIcons = find.byIcon(Icons.delete_outline);
      await tester.tap(deleteIcons.last);
      await tester.pumpAndSettle();

      expect(find.text('身份证'), findsNothing);

      // 保存编辑
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('长途差旅'), findsOneWidget);
      expect(find.text('1 个条目'), findsOneWidget);

      final detail = await templateRepository.getDetail(templateId);
      expect(detail.template.name, '长途差旅');
      expect(detail.entries.length, 1);
      expect(detail.entries.first.displayName, '笔记本电脑');
    });

    testWidgets('删除模板弹出二次确认，确认后删除且不影响关联登记物品', (tester) async {
      final locId = await locationRepository.create(name: '卧室');
      final itemId = await itemRepository.create(name: '水杯', locationId: locId);
      final templateId = await templateRepository.create(
        name: '运动模板',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );

      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);

      // 点击删除
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('template-card-$templateId')),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('删除出门模板'), findsOneWidget);
      expect(find.text('• 该模板及其包含的条目将被永久删除；'), findsOneWidget);
      expect(find.text('• 不会删除物品库中关联的登记物品；'), findsOneWidget);

      // 取消删除
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(await templateRepository.findById(templateId), isNotNull);

      // 再次点击并确认删除
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('template-card-$templateId')),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await tester.pumpAndSettle();

      // 模板已删除
      expect(await templateRepository.findById(templateId), isNull);
      expect(find.text('运动模板'), findsNothing);

      // 关联的物品依然存在
      expect(await itemRepository.findById(itemId), isNotNull);
    });

    testWidgets('在物品管理中修改物品名称后，切回出门模板能实时显示当前名称', (tester) async {
      final locId = await locationRepository.create(name: '卧室');
      final itemId = await itemRepository.create(
        name: '旧名称雨伞',
        locationId: locId,
      );
      final templateId = await templateRepository.create(
        name: '雨季模板',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );

      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);
      await tester.tap(find.text('雨季模板'));
      await tester.pumpAndSettle();

      expect(find.text('旧名称雨伞'), findsOneWidget);

      // 返回模板列表
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 切换到物品页面修改该物品名称
      await tester.tap(find.widgetWithText(NavigationDestination, '物品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('卧室'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旧名称雨伞'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑物品'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '物品名称 *'),
        '折叠晴雨伞',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 切换回出门页面，再次进入模板详情
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);
      await tester.tap(find.text('雨季模板'));
      await tester.pumpAndSettle();

      expect(find.text('折叠晴雨伞'), findsOneWidget);
      expect(find.text('旧名称雨伞'), findsNothing);
      final detail = await templateRepository.getDetail(templateId);
      expect(detail.template.id, templateId);
    });
  });
}
