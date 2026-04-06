import 'package:flutter/material.dart';
import '../vocabulary/vocabulary_screen.dart';
import '../../data/words.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(5, (index) {
            final start = index * 20;
            final end = start + 20;
            return _LevelBox(
              level: index + 1,
              wordStart: start + 1,
              wordEnd: end,
              words: commonWords.sublist(start, end),
            );
          }),
        ),
      ),
    );
  }
}

class _LevelBox extends StatelessWidget {
  final int level;
  final int wordStart;
  final int wordEnd;
  final List<String> words;

  const _LevelBox({
    required this.level,
    required this.wordStart,
    required this.wordEnd,
    required this.words,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VocabularyScreen(
            level: level,
            words: words,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 140,
        padding: const EdgeInsets.symmetric(horizontal: 45),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Level $level',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Words $wordStart - $wordEnd',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
