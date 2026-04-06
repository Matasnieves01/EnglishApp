import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/home/home_screen.dart';
import 'screens/vocabulary/vocabulary_screen.dart';

class EnglishLearnerApp extends StatelessWidget {
  const EnglishLearnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'English Learner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/vocabulary',
      builder: (context, state) {
        final Map<String, dynamic> extra = state.extra as Map<String, dynamic>;
        return VocabularyScreen(
          level: extra['level'] as int,
          words: extra['words'] as List<String>,
        );
      },
    ),
  ],
);
