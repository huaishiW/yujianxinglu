import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';
import 'package:personal_items_assistant/data/repositories/location_repository.dart';

void main() {
  late AppDatabase database;
  late LocationRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LocationRepository(database);
  });

  tearDown(() => database.close());

  int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<int> insertItem({required String name, required int locationId}) {
    final timestamp = now();
    return database
        .into(database.items)
        .insert(
          ItemsCompanion(
            name: Value(name),
            locationId: Value(locationId),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
  }

  Matcher locationError(LocationRepositoryErrorCode code) {
    return throwsA(
      isA<LocationRepositoryException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
  }

  test('creates and reads a top-level location', () async {
    final id = await repository.create(name: '  卧室  ');

    final location = await repository.getById(id);
    final topLevel = await repository.listTopLevel();

    expect(location.name, '卧室');
    expect(location.parentId, isNull);
    expect(topLevel.map((entry) => entry.id), [id]);
  });

  test('creates a child location and lists direct children', () async {
    final parentId = await repository.create(name: '卧室');
    final childId = await repository.create(name: '书桌', parentId: parentId);

    final children = await repository.listChildren(parentId);

    expect(children.map((entry) => entry.id), [childId]);
    expect(children.single.parentId, parentId);
  });

  test('allows the same name under different parents', () async {
    final bedroomId = await repository.create(name: '卧室');
    final studyId = await repository.create(name: '书房');

    final bedroomDeskId = await repository.create(
      name: '抽屉',
      parentId: bedroomId,
    );
    final studyDeskId = await repository.create(name: '抽屉', parentId: studyId);

    expect(bedroomDeskId, isNot(studyDeskId));
    expect((await repository.getById(bedroomDeskId)).parentId, bedroomId);
    expect((await repository.getById(studyDeskId)).parentId, studyId);
  });

  test('rejects duplicate names under one parent', () async {
    final parentId = await repository.create(name: '卧室');
    await repository.create(name: '抽屉', parentId: parentId);

    await expectLater(
      repository.create(name: '抽屉', parentId: parentId),
      locationError(LocationRepositoryErrorCode.duplicateName),
    );
  });

  test('rejects duplicate top-level names', () async {
    await repository.create(name: '卧室');

    await expectLater(
      repository.create(name: '卧室'),
      locationError(LocationRepositoryErrorCode.duplicateName),
    );
  });

  test('returns a complete path for arbitrarily deep locations', () async {
    final bedroomId = await repository.create(name: '卧室');
    final deskId = await repository.create(name: '书桌', parentId: bedroomId);
    final drawerId = await repository.create(name: '右侧抽屉', parentId: deskId);
    final boxId = await repository.create(name: '蓝色收纳盒', parentId: drawerId);

    expect(await repository.fullPath(boxId), '卧室 / 书桌 / 右侧抽屉 / 蓝色收纳盒');
  });

  test('renames a location without changing its id or item relation', () async {
    final parentId = await repository.create(name: '卧室');
    final locationId = await repository.create(name: '书桌', parentId: parentId);
    final itemId = await insertItem(name: '笔记本电脑', locationId: locationId);

    await repository.rename(locationId, '  工作桌  ');

    final renamed = await repository.getById(locationId);
    final items = await repository.listDirectItems(locationId);
    expect(renamed.name, '工作桌');
    expect(renamed.id, locationId);
    expect(items.single.id, itemId);
    expect(items.single.locationId, locationId);
  });

  test('moves a location to another parent', () async {
    final sourceParentId = await repository.create(name: '卧室');
    final targetParentId = await repository.create(name: '书房');
    final sourceId = await repository.create(
      name: '收纳盒',
      parentId: sourceParentId,
    );

    final moved = await repository.move(
      id: sourceId,
      targetParentId: targetParentId,
    );

    expect(moved, isTrue);
    expect((await repository.getById(sourceId)).parentId, targetParentId);
  });

  test('moves a location to the top level', () async {
    final sourceParentId = await repository.create(name: '卧室');
    final sourceId = await repository.create(
      name: '收纳盒',
      parentId: sourceParentId,
    );

    final moved = await repository.move(id: sourceId, targetParentId: null);

    expect(moved, isTrue);
    expect((await repository.getById(sourceId)).parentId, isNull);
    expect(
      (await repository.listTopLevel()).map((entry) => entry.name),
      contains('收纳盒'),
    );
  });

  test('rejects moving a location to itself', () async {
    final locationId = await repository.create(name: '卧室');

    await expectLater(
      repository.move(id: locationId, targetParentId: locationId),
      locationError(LocationRepositoryErrorCode.cycleMove),
    );
  });

  test('rejects moving a location to a descendant at any depth', () async {
    final rootId = await repository.create(name: '卧室');
    final childId = await repository.create(name: '书桌', parentId: rootId);
    final grandchildId = await repository.create(name: '抽屉', parentId: childId);
    final descendantId = await repository.create(
      name: '收纳盒',
      parentId: grandchildId,
    );

    await expectLater(
      repository.move(id: rootId, targetParentId: descendantId),
      locationError(LocationRepositoryErrorCode.cycleMove),
    );
    expect((await repository.getById(rootId)).parentId, isNull);
  });

  test('rejects moving when the target parent has the same name', () async {
    final sourceParentId = await repository.create(name: '卧室');
    final targetParentId = await repository.create(name: '书房');
    final sourceId = await repository.create(
      name: '收纳盒',
      parentId: sourceParentId,
    );
    await repository.create(name: '收纳盒', parentId: targetParentId);

    await expectLater(
      repository.move(id: sourceId, targetParentId: targetParentId),
      locationError(LocationRepositoryErrorCode.duplicateName),
    );
    expect((await repository.getById(sourceId)).parentId, sourceParentId);
  });

  test('preserves subtree and item relationships after moving', () async {
    final sourceParentId = await repository.create(name: '卧室');
    final targetParentId = await repository.create(name: '书房');
    final sourceId = await repository.create(
      name: '收纳盒',
      parentId: sourceParentId,
    );
    final childId = await repository.create(name: '内层抽屉', parentId: sourceId);
    final itemId = await insertItem(name: '耳机', locationId: childId);

    await repository.move(id: sourceId, targetParentId: targetParentId);

    expect((await repository.getById(sourceId)).parentId, targetParentId);
    expect((await repository.getById(childId)).parentId, sourceId);
    final items = await repository.listDirectItems(childId);
    expect(items.single.id, itemId);
    expect(items.single.locationId, childId);
    expect(await repository.fullPath(childId), '书房 / 收纳盒 / 内层抽屉');
  });

  test('deletes an empty location', () async {
    final locationId = await repository.create(name: '临时位置');

    await repository.deleteEmpty(locationId);

    expect(await repository.findById(locationId), isNull);
  });

  test('rejects deleting a location with child locations', () async {
    final parentId = await repository.create(name: '卧室');
    await repository.create(name: '书桌', parentId: parentId);

    await expectLater(
      repository.deleteEmpty(parentId),
      locationError(LocationRepositoryErrorCode.notEmpty),
    );
  });

  test('rejects deleting a location with direct items', () async {
    final locationId = await repository.create(name: '卧室');
    await insertItem(name: '鼠标', locationId: locationId);

    await expectLater(
      repository.deleteEmpty(locationId),
      locationError(LocationRepositoryErrorCode.notEmpty),
    );
  });

  test('rejects a move to a missing target parent', () async {
    final locationId = await repository.create(name: '收纳盒');

    await expectLater(
      repository.move(id: locationId, targetParentId: 9999),
      locationError(LocationRepositoryErrorCode.parentNotFound),
    );
    expect((await repository.getById(locationId)).parentId, isNull);
  });

  test('keeps data unchanged after failed create and rename', () async {
    final parentId = await repository.create(name: '卧室');
    final originalId = await repository.create(name: '书桌', parentId: parentId);

    await expectLater(
      repository.create(name: '书桌', parentId: parentId),
      locationError(LocationRepositoryErrorCode.duplicateName),
    );
    expect((await repository.listChildren(parentId)).length, 1);

    final otherId = await repository.create(name: '柜子', parentId: parentId);
    await expectLater(
      repository.rename(otherId, '书桌'),
      locationError(LocationRepositoryErrorCode.duplicateName),
    );

    expect((await repository.getById(originalId)).name, '书桌');
    expect((await repository.getById(otherId)).name, '柜子');
  });

  test(
    'distinguishes invalid names and missing locations or parents',
    () async {
      await expectLater(
        repository.create(name: '   '),
        locationError(LocationRepositoryErrorCode.invalidName),
      );

      await expectLater(
        repository.create(name: '子位置', parentId: 9999),
        locationError(LocationRepositoryErrorCode.parentNotFound),
      );

      await expectLater(
        repository.getById(9999),
        locationError(LocationRepositoryErrorCode.locationNotFound),
      );
      await expectLater(
        repository.rename(9999, '新名称'),
        locationError(LocationRepositoryErrorCode.locationNotFound),
      );
      await expectLater(
        repository.deleteEmpty(9999),
        locationError(LocationRepositoryErrorCode.locationNotFound),
      );
    },
  );

  test('returns false when moving to the current parent', () async {
    final parentId = await repository.create(name: '卧室');
    final locationId = await repository.create(name: '书桌', parentId: parentId);

    expect(
      await repository.move(id: locationId, targetParentId: parentId),
      isFalse,
    );
  });
}
