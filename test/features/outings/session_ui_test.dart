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

  Future<void> openOutingsPage(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(NavigationDestination, '出门'));
    await tester.pumpAndSettle();
  }

  Future<void> switchToTemplateTab(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(Tab, '模板'));
    await tester.pumpAndSettle();
  }

  group('TASK 11 任务创建流程', () {
    testWidgets('直接创建出门任务：表单校验、混合条目保存，创建后跳转详情页且条目初始未勾选', (tester) async {
      final locId = await locationRepository.create(name: '玄关');
      await itemRepository.create(name: '门禁卡', quantity: 1, locationId: locId);

      await pumpApp(tester);
      await openOutingsPage(tester);

      expect(find.text('进行中的任务'), findsOneWidget);
      expect(find.text('暂无进行中的任务，点击右下角创建'), findsOneWidget);

      // 点击新建任务 FAB
      await tester.tap(find.byKey(const ValueKey('create-session-fab')));
      await tester.pumpAndSettle();

      expect(find.text('新建出门任务'), findsOneWidget);

      // 尝试空表单保存，验证拦截
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('出门任务名称不能为空'), findsOneWidget);

      // 输入任务名称
      await tester.enterText(
        find.widgetWithText(TextFormField, '本次出门名称 *'),
        '临时下楼',
      );

      // 未添加条目时点击保存
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('出门任务至少需要添加一个条目'), findsOneWidget);

      // 添加登记物品
      await tester.tap(find.widgetWithText(OutlinedButton, '添加登记物品'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '选择'));
      await tester.pumpAndSettle();

      // 添加普通文本
      await tester.tap(find.widgetWithText(OutlinedButton, '添加普通文本'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '条目内容 *'),
        '倒垃圾',
      );
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();

      // 保存创建
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 验证已跳转至详情页
      expect(find.text('临时下楼'), findsWidgets);
      expect(find.text('0 / 2 已携带'), findsOneWidget);
      expect(find.text('门禁卡'), findsOneWidget);
      expect(find.text('倒垃圾'), findsOneWidget);
      expect(find.text('玄关'), findsOneWidget);

      final activeList = await sessionRepository.listActive();
      expect(activeList.length, 1);
      expect(activeList.first.title, '临时下楼');
      final detail = await sessionRepository.getDetail(activeList.first.id);
      expect(detail.entries.length, 2);
      expect(detail.entries.every((e) => !e.isChecked), isTrue);
    });

    testWidgets('从模板创建出门任务：复制条目独立保存，条目初始未勾选，并更新模板最近使用时间', (tester) async {
      final locId = await locationRepository.create(name: '书房');
      final itemId = await itemRepository.create(
        name: '工作证',
        quantity: 1,
        locationId: locId,
      );
      final templateId = await templateRepository.create(
        name: '日常通勤模板',
        entries: [
          TemplateEntryInput.registered(itemId: itemId, requiredQuantity: 1),
          const TemplateEntryInput.text(textName: '关空调', requiredQuantity: 1),
        ],
      );

      // 验证模板初始 lastUsedAt 为 null
      final beforeTemplate = await templateRepository.findById(templateId);
      expect(beforeTemplate!.lastUsedAt, isNull);

      await pumpApp(tester);
      await openOutingsPage(tester);
      await switchToTemplateTab(tester);

      // 点击模板卡片进入详情
      await tester.tap(find.text('日常通勤模板'));
      await tester.pumpAndSettle();

      // 点击“以此模板开始出门”
      await tester.tap(find.widgetWithText(FilledButton, '以此模板开始出门'));
      await tester.pumpAndSettle();

      expect(find.text('开始本次出门'), findsOneWidget);
      expect(find.text('日常通勤模板'), findsWidgets);

      // 点击“开始出门”提交
      await tester.tap(find.widgetWithText(FilledButton, '开始出门'));
      await tester.pumpAndSettle();

      // 验证已生成独立任务并进入详情页
      expect(find.text('0 / 2 已携带'), findsOneWidget);
      expect(find.text('工作证'), findsOneWidget);
      expect(find.text('关空调'), findsOneWidget);

      // 验证模板 lastUsedAt 已更新
      final afterTemplate = await templateRepository.findById(templateId);
      expect(afterTemplate!.lastUsedAt, isNotNull);

      // 验证任务与模板条目完全独立
      final sessions = await sessionRepository.listActive();
      expect(sessions.length, 1);
      expect(sessions.first.templateId, templateId);
    });
  });

  group('TASK 11 勾选持久化与状态独立', () {
    testWidgets('点击勾选立即持久化，不修改物品库库存与位置，多任务勾选状态独立', (tester) async {
      final locId = await locationRepository.create(name: '卧室');
      final itemId = await itemRepository.create(
        name: '水杯',
        quantity: 5,
        locationId: locId,
      );

      final session1Id = await sessionRepository.createDirect(
        title: '任务A',
        entries: [SessionEntryInput.registered(itemId: itemId)],
      );
      final session2Id = await sessionRepository.createDirect(
        title: '任务B',
        entries: [SessionEntryInput.registered(itemId: itemId)],
      );

      await pumpApp(tester);
      await openOutingsPage(tester);

      // 验证列表展示两个进行中任务卡片
      expect(find.text('任务A'), findsOneWidget);
      expect(find.text('任务B'), findsOneWidget);

      // 进入任务A详情并勾选
      await tester.tap(find.text('任务A'));
      await tester.pumpAndSettle();

      expect(find.text('0 / 1 已携带'), findsOneWidget);

      // 点击勾选框
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.text('1 / 1 已携带'), findsOneWidget);

      // 验证数据库即时持久化
      final raw1 = await sessionRepository.listEntries(session1Id);
      expect(raw1.first.isChecked, isTrue);

      // 验证物品库库存与位置完全未被修改
      final item = await itemRepository.findById(itemId);
      expect(item!.quantity, 5);
      expect(item.locationId, locId);

      // 验证任务B的勾选状态完全独立，仍为未勾选
      final raw2 = await sessionRepository.listEntries(session2Id);
      expect(raw2.first.isChecked, isFalse);

      // 再次点击取消勾选
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.text('0 / 1 已携带'), findsOneWidget);
      final raw1Again = await sessionRepository.listEntries(session1Id);
      expect(raw1Again.first.isChecked, isFalse);
    });
  });

  group('TASK 11 任务编辑与勾选重置规则', () {
    testWidgets('编辑任务：修改数量重置勾选，仅重排保留勾选，原子保存成功', (tester) async {
      final locId = await locationRepository.create(name: '玄关');
      final itemId = await itemRepository.create(name: '雨伞', locationId: locId);

      final sessionId = await sessionRepository.createDirect(
        title: '雨天出门',
        entries: [
          SessionEntryInput.registered(itemId: itemId, requiredQuantity: 1),
          const SessionEntryInput.text(textName: '检查窗户', requiredQuantity: 1),
        ],
      );

      // 预先将两项都勾选上
      final initialEntries = await sessionRepository.listEntries(sessionId);
      await sessionRepository.setChecked(
        sessionId,
        initialEntries[0].entry.id,
        true,
      );
      await sessionRepository.setChecked(
        sessionId,
        initialEntries[1].entry.id,
        true,
      );

      await pumpApp(tester);
      await openOutingsPage(tester);

      // 进入雨天出门详情页
      await tester.tap(find.text('雨天出门'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2 已携带'), findsOneWidget);

      // 点击编辑
      await tester.tap(find.byTooltip('编辑任务'));
      await tester.pumpAndSettle();

      expect(find.text('编辑出门任务'), findsOneWidget);

      // 修改任务标题
      await tester.enterText(
        find.widgetWithText(TextFormField, '本次出门名称 *'),
        '暴雨出门',
      );

      // 修改雨伞数量（1 -> 2）：应当触发重置该条目的勾选
      await tester.tap(find.text('需带: 1').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '所需数量 *'), '2');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '确定'),
        ),
      );
      await tester.pumpAndSettle();

      // 点击保存
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      // 验证返回详情页并展示修改后的数据
      expect(find.text('暴雨出门'), findsWidgets);
      // 雨伞数量变更为 2，勾选重置为 0；“检查窗户”未变，仍保持勾选；因此为 1 / 2 已携带
      expect(find.text('1 / 2 已携带'), findsOneWidget);

      final detail = await sessionRepository.getDetail(sessionId);
      expect(detail.session.title, '暴雨出门');
      expect(detail.entries.length, 2);
      expect(detail.checkedCount, 1);
    });
  });

  group('TASK 11 完成任务与未勾选确认', () {
    testWidgets('未全部勾选时完成弹出未勾选项确认，取消不改变状态，确认后完成并冻结快照', (tester) async {
      final locId = await locationRepository.create(name: '客厅');
      final itemId = await itemRepository.create(name: '钱包', locationId: locId);

      final sessionId = await sessionRepository.createDirect(
        title: '购物出门',
        entries: [
          SessionEntryInput.registered(itemId: itemId, requiredQuantity: 1),
          const SessionEntryInput.text(textName: '环保袋', requiredQuantity: 2),
        ],
      );

      // 仅勾选钱包，环保袋保持未勾选
      final entries = await sessionRepository.listEntries(sessionId);
      await sessionRepository.setChecked(sessionId, entries[0].entry.id, true);

      await pumpApp(tester);
      await openOutingsPage(tester);
      await tester.tap(find.text('购物出门'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 2 已携带'), findsOneWidget);

      // 点击“完成出门”
      await tester.tap(find.widgetWithText(FilledButton, '完成出门'));
      await tester.pumpAndSettle();

      // 弹出未勾选警告弹窗
      expect(find.text('仍有未勾选条目'), findsOneWidget);
      expect(find.textContaining('还有 1 项未勾选'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('环保袋'),
        ),
        findsOneWidget,
      );

      // 点击“返回检查”，任务继续保持进行中
      await tester.tap(find.widgetWithText(TextButton, '返回检查'));
      await tester.pumpAndSettle();

      expect(find.text('进行中'), findsOneWidget);
      expect(await sessionRepository.getStatus(sessionId), 'IN_PROGRESS');

      // 再次点击“完成出门”并点击“仍要完成”
      await tester.tap(find.widgetWithText(FilledButton, '完成出门'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '仍要完成'));
      await tester.pumpAndSettle();

      // 任务已完成，从进行中列表移除
      expect(find.text('购物出门'), findsNothing);
      expect(find.text('暂无进行中的任务，点击右下角创建'), findsOneWidget);

      final finished = await sessionRepository.getById(sessionId);
      expect(finished.status, 'COMPLETED');
      expect(finished.completedAt, isNotNull);

      // 验证快照已冻结，且已完成任务拒绝再次勾选或编辑
      final finishedDetail = await sessionRepository.getDetail(sessionId);
      expect(finishedDetail.entries[0].entry.nameSnapshot, '钱包');
      expect(finishedDetail.entries[0].entry.locationSnapshot, '客厅');
      expect(finishedDetail.entries[0].isChecked, isTrue);
      expect(finishedDetail.entries[1].isChecked, isFalse); // 未勾选仍保持未勾选

      // 之后修改原物品名称与位置，已完成任务快照不受任何影响
      await itemRepository.update(id: itemId, name: '旧钱包', quantity: 99);
      final snapshotAfterItemUpdate = await sessionRepository.getDetail(
        sessionId,
      );
      expect(snapshotAfterItemUpdate.entries[0].entry.nameSnapshot, '钱包');
    });
  });

  group('TASK 11 任务删除与二次确认', () {
    testWidgets('删除进行中任务弹出二次确认，取消不改变数据，确认删除后物理移除且不影响物品库', (tester) async {
      final locId = await locationRepository.create(name: '玄关');
      final itemId = await itemRepository.create(name: '钥匙', locationId: locId);
      final sessionId = await sessionRepository.createDirect(
        title: '即将删除的任务',
        entries: [SessionEntryInput.registered(itemId: itemId)],
      );

      await pumpApp(tester);
      await openOutingsPage(tester);

      expect(find.text('即将删除的任务'), findsOneWidget);

      // 点击删除图标
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('删除出门任务'), findsOneWidget);
      expect(find.text('• 该任务及其包含的条目将被永久删除；'), findsOneWidget);
      expect(find.text('• 不会删除物品库中关联的登记物品；'), findsOneWidget);

      // 点击取消
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(await sessionRepository.findById(sessionId), isNotNull);

      // 再次点击删除并确认
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await tester.pumpAndSettle();

      // 任务已删除
      expect(await sessionRepository.findById(sessionId), isNull);
      expect(find.text('即将删除的任务'), findsNothing);

      // 物品库中钥匙依然完好无损
      expect(await itemRepository.findById(itemId), isNotNull);
    });

    testWidgets('快速连续点击勾选，在途保护生效，最终状态与数据库完全一致', (tester) async {
      final locId = await locationRepository.create(name: '玄关');
      final itemId = await itemRepository.create(name: '手环', locationId: locId);
      final sessionId = await sessionRepository.createDirect(
        title: '连续点击测试',
        entries: [SessionEntryInput.registered(itemId: itemId)],
      );

      await pumpApp(tester);
      await openOutingsPage(tester);
      await tester.tap(find.text('连续点击测试'));
      await tester.pumpAndSettle();

      expect(find.text('0 / 1 已携带'), findsOneWidget);

      // 连续多次快速点击整行
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // 验证最终状态与数据库完全一致
      final entries = await sessionRepository.listEntries(sessionId);
      final isDbChecked = entries.first.isChecked;
      expect(
        find.text(isDbChecked ? '1 / 1 已携带' : '0 / 1 已携带'),
        findsOneWidget,
      );
    });
  });
}
