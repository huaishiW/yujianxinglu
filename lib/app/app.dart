import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

class PersonalItemsApp extends StatelessWidget {
  const PersonalItemsApp({super.key, this.router});

  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '个人物品与出门助手',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router ?? appRouter,
    );
  }
}
