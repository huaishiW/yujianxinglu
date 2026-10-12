import '../local/app_database.dart';
import '../local/daos/items_dao.dart';

class ItemRepository {
  const ItemRepository(this._dao);

  final ItemsDao _dao;

  Stream<List<Item>> watchAll() => _dao.watchAll();

  Future<int> add({
    required String name,
    String? category,
    int? locationId,
    bool isEssential = false,
  }) {
    return _dao.insertOne(
      ItemsCompanion.insert(
        name: name,
        category: Value(category),
        locationId: Value(locationId),
        isEssential: Value(isEssential),
      ),
    );
  }

  Future<int> deleteById(int id) => _dao.deleteById(id);
}
