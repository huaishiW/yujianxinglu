import 'package:flutter/material.dart';

import 'router/app_router.dart';

class PersonalItemsApp extends StatelessWidget {
  const PersonalItemsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '个人物品与出门助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
