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
  late LocationRepository locationRepository;
  late ItemRepository itemRepository;
  late TemplateRepository templateRepository;
  late SessionRepository sessionRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    router = createAppRouter();
    locationRepository = LocationRepository(database);
    itemRepository = ItemRepository(database);
    templateRepository = TemplateRepository(database);
    sessionRepository = SessionRepository(database);
  });

  tearDown(() async {
    router.dispose();
    await database.close();
  });

  Future<void> pumpHomePage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: PersonalItemsApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首页顶部搜索框点击跳转到物品搜索页面', (tester) async {
    await pumpHomePage(tester);

    expect(find.text('搜索物品名称'), findsOneWidget);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // 验证跳转到了物品搜索页面
    expect(find.text('搜索物品名称...'), findsOneWidget);
    expect(find.text('物品库中暂无物品'), findsOneWidget);
  });

  testWidgets('首页空状态正确展示，并可点击快捷创建', (tester) async {
    await pumpHomePage(tester);

    // 两个空状态卡片
    expect(find.text('当前没有进行中的出门任务'), findsOneWidget);
    expect(find.text('新建本次出门'), findsOneWidget);
    expect(find.text('暂无最近使用的出门模板'), findsOneWidget);
    expect(find.text('创建出门模板'), findsOneWidget);

    // 点击新建本次出门快捷按钮
    await tester.tap(find.text('新建本次出门'));
    await tester.pumpAndSettle();

    expect(find.text('新建出门任务'), findsOneWidget);
  });

  testWidgets('首页展示进行中任务进度，并在勾选后实时更新', (tester) async {
    final locId = await locationRepository.create(name: '玄关');
    final itemId = await itemRepository.create(name: '门禁卡', locationId: locId);

    await sessionRepository.createDirect(
      title: '上班通勤',
      entries: [
        SessionEntryInput.registered(itemId: itemId),
        const SessionEntryInput.text(textName: '工牌'),
      ],
    );

    await pumpHomePage(tester);

    // 验证展示了任务卡片和初始进度
    expect(find.text('上班通勤'), findsOneWidget);
    expect(find.text('0 / 2 已准备'), findsOneWidget);
    expect(find.text('还剩 2 项未勾选'), findsOneWidget);
    expect(find.text('继续检查'), findsOneWidget);

    // 点击卡片进入详情
    await tester.tap(find.text('上班通勤'));
    await tester.pumpAndSettle();

    // 在详情页验证
    expect(find.text('门禁卡'), findsOneWidget);
    expect(find.text('工牌'), findsOneWidget);

    // 勾选一个条目
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    // 返回首页
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // 验证首页进度更新为 1 / 2
    expect(find.text('1 / 2 已准备'), findsOneWidget);
    expect(find.text('还剩 1 项未勾选'), findsOneWidget);
  });

  testWidgets('全部勾选的任务在首页显示全部就绪', (tester) async {
    final sessionId = await sessionRepository.createDirect(
      title: '散步',
      entries: [const SessionEntryInput.text(textName: '钥匙')],
    );

    // 勾选该条目
    final detail = await sessionRepository.getDetail(sessionId);
    await sessionRepository.setChecked(
      sessionId,
      detail.entries.first.entry.id,
      true,
    );

    await pumpHomePage(tester);

    expect(find.text('散步'), findsOneWidget);
    expect(find.text('1 / 1 已准备'), findsOneWidget);
    expect(find.text('全部就绪'), findsOneWidget);
  });

  testWidgets('首页展示最近使用的模板与使用时间，点击可进入模板详情', (tester) async {
    final locId = await locationRepository.create(name: '客厅');
    final itemId = await itemRepository.create(name: '雨伞', locationId: locId);

    // 创建模板
    final templateId = await templateRepository.create(
      name: '雨天出门模板',
      entries: [
        TemplateEntryInput.registered(itemId: itemId),
        const TemplateEntryInput.text(textName: '雨衣'),
      ],
    );

    // 基于模板创建任务以触发 lastUsedAt 更新，并赋予不同标题避免重名干扰
    await sessionRepository.createFromTemplate(templateId, title: '雨天出游任务');

    await pumpHomePage(tester);

    expect(find.text('雨天出门模板'), findsOneWidget);
    expect(find.text('2 项准备事项'), findsOneWidget);
    expect(find.textContaining('上次使用:'), findsOneWidget);

    // 点击模板卡片进入模板详情
    await tester.tap(find.text('雨天出门模板'));
    await tester.pumpAndSettle();

    expect(find.text('模板详情'), findsOneWidget);
    expect(find.text('雨天出门模板'), findsWidgets);
  });

  testWidgets('首页“查看全部”跳转至出门“进行中”页签', (tester) async {
    await pumpHomePage(tester);

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();

    expect(find.text('进行中的任务'), findsOneWidget);
  });

  testWidgets('首页“全部模板”跳转至出门“模板”页签', (tester) async {
    await pumpHomePage(tester);

    await tester.tap(find.text('全部模板'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('create-template-fab')), findsOneWidget);
    expect(find.text('所有模板'), findsOneWidget);
  });
}
