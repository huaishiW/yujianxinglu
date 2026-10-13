import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/template_repository.dart';
import '../../items/application/location_providers.dart';

class TemplateRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state += 1;
}

final templateRefreshProvider = NotifierProvider<TemplateRefreshNotifier, int>(
  TemplateRefreshNotifier.new,
);

final templateListProvider = FutureProvider.autoDispose
    .family<List<OutgoingTemplate>, String>((ref, keyword) {
      ref.watch(templateRefreshProvider);
      ref.watch(locationBrowserRefreshProvider);
      final repo = ref.watch(templateRepositoryProvider);
      return repo.searchByName(keyword);
    });

final templateDetailProvider = FutureProvider.autoDispose
    .family<TemplateDetail, int>((ref, templateId) {
      ref.watch(templateRefreshProvider);
      ref.watch(locationBrowserRefreshProvider);
      return ref.watch(templateRepositoryProvider).getDetail(templateId);
    });

final templateShortagesProvider = FutureProvider.autoDispose
    .family<List<TemplateQuantityShortage>, int>((ref, templateId) {
      ref.watch(templateRefreshProvider);
      ref.watch(locationBrowserRefreshProvider);
      return ref
          .watch(templateRepositoryProvider)
          .listQuantityShortages(templateId);
    });
