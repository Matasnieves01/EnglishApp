import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:dart_phonetics/dart_phonetics.dart';

// ─── Mic error types ────────────────────────────────────────────────────────
enum _MicError {
  none,
  permission,    // User denied microphone permission
  busy,          // Mic already in use by another app
  audio,         // Audio session / hardware error
  network,       // Cloud STT unreachable
  noMatch,       // Spoke but nothing recognized
  timeout,       // Silence timeout
  unknown,       // Any other error
}

extension _MicErrorX on _MicError {
  String get message {
    switch (this) {
      case _MicError.permission:
        return 'Microphone permission denied. Please enable it in Settings.';
      case _MicError.busy:
        return 'Microphone is in use by another app. Close it.';
      case _MicError.audio:
        return 'Audio hardware error. Restart the app.';
      case _MicError.network:
        return 'No internet connection for speech recognition.';
      case _MicError.noMatch:
        return 'Could not understand. Try speaking more clearly.';
      case _MicError.timeout:
        return 'No speech detected. Tap the mic.';
      case _MicError.unknown:
        return 'Unexpected microphone error. Tap the mic.';
      case _MicError.none:
        return '';
    }
  }


  /// Returns true for errors that require the user to act outside the app.
  bool get requiresSettings => this == _MicError.permission;
}

// ─── Screen ─────────────────────────────────────────────────────────────────
class VocabularyScreen extends StatefulWidget {
  final int level;
  final List<String> words;

  const VocabularyScreen({
    super.key,
    required this.level,
    required this.words,
  });

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen>
    with SingleTickerProviderStateMixin {
  // ── Constants ──────────────────────────────────────────────────────────────
  static const int _maxAttempts = 3;
  static const Duration _listenFor = Duration(seconds: 15);
  static const Duration _pauseFor = Duration(seconds: 3);

  // ── Services ───────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _animController;
  late Animation<Color?> _borderAnim;
  late Animation<Color?> _bgAnim;

  // ── State ──────────────────────────────────────────────────────────────────
  int _currentWordIndex = 0;
  bool _isListening = false;
  bool _speechReady = false;      // true once initialize() succeeds
  bool _initializing = false;     // guard: prevents double-init races
  bool _correct = false;
  bool _wrong = false;
  bool _isReplaying = false;
  int _attempts = 0;
  int _wrongPulse = 0;
  String _heard = '';
  _MicError _micError = _MicError.none;

  // Tracks which words were answered correctly / incorrectly.
  final List<String> _correctWords = [];
  final List<String> _wrongWords = [];

  String get _currentWord => widget.words[_currentWordIndex];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _initTts();
    _initSpeech();
  }

  @override
  void dispose() {
    _animController.dispose();
    _tts.stop();
    // Only call stop/cancel if the engine is actually running.
    if (_speech.isListening) _speech.stop();
    super.dispose();
  }

  // ── Animation setup ────────────────────────────────────────────────────────
  void _setupAnimation() {
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _borderAnim = ColorTween(
      begin: Colors.grey.shade200,
      end: Colors.green.shade300,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _bgAnim = ColorTween(
      begin: Colors.white,
      end: const Color(0xFFEDF7ED),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  // ── TTS ────────────────────────────────────────────────────────────────────
  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    _speakCurrentWord();
  }

  Future<void> _speakCurrentWord() async => _tts.speak(_currentWord);

  Future<void> _repeatCurrentWord() async {
    if (!mounted) return;
    setState(() => _isReplaying = true);
    await _tts.stop();
    await _speakCurrentWord();
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted) setState(() => _isReplaying = false);
    });
  }

  // ── Speech initializer (safe, idempotent) ──────────────────────────────────
  Future<bool> _initSpeech() async {
    if (_speechReady) return true;        // Already good → skip
    if (_initializing) return false;      // In progress → skip

    if (mounted) setState(() => _initializing = true);
    debugPrint('STT: initializing…');

    try {
      final ok = await _speech.initialize(
        onError: _onSpeechError,
        onStatus: _onSpeechStatus,
        debugLogging: true,
      );

      if (!mounted) return false;

      if (ok) {
        setState(() {
          _speechReady = true;
          _micError = _MicError.none;
        });
        debugPrint('STT: ready');
      } else {
        // initialize() returned false → likely a permanent permission issue.
        setState(() => _micError = _MicError.permission);
        debugPrint('STT: initialization failed (permission?)');
      }
      return ok;
    } catch (e) {
      debugPrint('STT: initialization exception → $e');
      if (mounted) setState(() => _micError = _MicError.unknown);
      return false;
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  // ── STT callbacks ──────────────────────────────────────────────────────────
  void _onSpeechError(dynamic error) {
    // `error` is SpeechRecognitionError with fields: errorMsg, permanent.
    final msg = (error as dynamic).errorMsg as String? ?? '';
    debugPrint('STT error: $msg (permanent: ${error.permanent})');

    _MicError mapped;
    switch (msg) {
      case 'error_permission':
      case 'error_audio_record_permission':
        mapped = _MicError.permission;
        // Permission errors invalidate the session → force re-init next time.
        _speechReady = false;
        break;
      case 'error_busy':
      case 'error_recognizer_busy':
        mapped = _MicError.busy;
        break;
      case 'error_audio':
      case 'error_audio_focus':
        mapped = _MicError.audio;
        break;
      case 'error_network':
      case 'error_network_timeout':
        mapped = _MicError.network;
        break;
      case 'error_no_match':
      // Not really an error — just nothing was understood.
        mapped = _MicError.noMatch;
        break;
      case 'error_speech_timeout':
        mapped = _MicError.timeout;
        break;
      default:
        mapped = _MicError.unknown;
    }

    if (mounted) {
      setState(() {
        _isListening = false;
        _micError = mapped;
      });
    }
  }

  void _onSpeechStatus(String status) {
    debugPrint('STT status: $status');
    // Both 'done' and 'notListening' mark the end of a session.
    if ((status == 'done' || status == 'notListening') && mounted) {
      setState(() => _isListening = false);
    }
  }

  // ── Start listening ────────────────────────────────────────────────────────
  Future<void> _startListening() async {
    debugPrint('STT: mic button tapped');

    // Ensure the engine is ready.
    if (!_speechReady) {
      final ok = await _initSpeech();
      if (!ok) return; // Error already set in _initSpeech.
    }

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _correct = false;
      _wrong = false;
      _wrongPulse = 0;
      _heard = '';
      _micError = _MicError.none;
    });

    try {
      await _tts.stop();

      // Stop any leftover session defensively.
      if (_speech.isListening) {
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      await _speech.listen(
        onResult: _onSpeechResult,
        localeId: 'en-US',
        listenFor: _listenFor,
        pauseFor: _pauseFor,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
          partialResults: false,
          onDevice: false,
        ),
      );
    } catch (e) {
      debugPrint('STT: listen() exception → $e');
      if (mounted) {
        setState(() {
          _isListening = false;
          _micError = _MicError.unknown;
        });
      }
    }
  }

  // ── Cancel listening ───────────────────────────────────────────────────────
  Future<void> _cancelListening() async {
    debugPrint('STT: manual cancel');
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (e) {
      debugPrint('STT: cancel exception → $e');
    }
    if (mounted) setState(() => _isListening = false);
  }

  // ── Result handler ─────────────────────────────────────────────────────────
  void _onSpeechResult(dynamic result) {
    if (!(result.finalResult as bool)) {
      debugPrint('STT partial: "${result.recognizedWords}"');
      return;
    }

    final spoken = (result.recognizedWords as String).trim().toLowerCase();
    debugPrint('STT final: "$spoken"');

    if (!mounted) return;
    setState(() {
      _heard = spoken;
      _isListening = false;
      _micError = _MicError.none;
    });

    if (spoken.isNotEmpty) {
      _checkAnswer(spoken);
    } else {
      // Engine returned a final result with an empty string.
      setState(() => _micError = _MicError.noMatch);
    }
  }

  // ── Answer logic ───────────────────────────────────────────────────────────
  void _checkAnswer(String spokenText) {
    final expected = _currentWord.toLowerCase();
    final spoken = spokenText.toLowerCase();

    bool isCorrect = spoken == expected || spoken.contains(expected);

    if (!isCorrect) {
      try {
        final encoder = DoubleMetaphone();
        final expectedCode = encoder.encode(expected);
        final spokenCode = encoder.encode(spoken);

        if (spokenCode != null && expectedCode != null) {
          isCorrect =
              spokenCode.primary == expectedCode.primary ||
                  (expectedCode.alternates?.contains(spokenCode.primary) ?? false) ||
                  (spokenCode.alternates?.contains(expectedCode.primary) ?? false);
        }
      } catch (e) {
        debugPrint('Phonetics error: $e');
      }
    }

    if (isCorrect) {
      _correctWords.add(_currentWord);
      setState(() {
        _correct = true;
        _wrong = false;
        _attempts = 0;
      });
      _animController.forward();
      Future.delayed(const Duration(milliseconds: 800), _nextWord);
    } else {
      setState(() {
        _wrong = true;
        _attempts++;
        _wrongPulse++;
      });

      if (_attempts >= _maxAttempts) {
        _wrongWords.add(_currentWord);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('The correct answer was: $_currentWord'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        Future.delayed(const Duration(milliseconds: 800), _nextWord);
      }
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _nextWord() {
    if (!mounted) return;
    _animController.reset();

    if (_currentWordIndex < widget.words.length - 1) {
      setState(() {
        _currentWordIndex++;
        _correct = false;
        _wrong = false;
        _attempts = 0;
        _heard = '';
        _wrongPulse = 0;
        _micError = _MicError.none;
      });
      _speakCurrentWord();
    } else {
      _showFinished();
    }
  }

  // ── Finished dialog ────────────────────────────────────────────────────────
  void _showFinished() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResultsDialog(
        totalWords: widget.words.length,
        correctWords: List.unmodifiable(_correctWords),
        wrongWords: List.unmodifiable(_wrongWords),
        onFinish: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final int remaining = (_maxAttempts - _attempts).clamp(0, _maxAttempts);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('Level ${widget.level}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // ── Progress ────────────────────────────────────────────────────
            Text(
              '${_currentWordIndex + 1}/${widget.words.length}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_currentWordIndex + 1) / widget.words.length,
              backgroundColor: Colors.grey.shade200,
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
            ),

            const Spacer(),

            // ── Instruction ─────────────────────────────────────────────────
            Text(
              'Repeat the word',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            // ── Word card ────────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.18, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: AnimatedBuilder(
                key: ValueKey('$_currentWordIndex-$_wrongPulse'),
                animation: _animController,
                builder: (context, _) => AnimatedScale(
                  scale: _isReplaying ? 1.03 : 1.0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _repeatCurrentWord,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 100, horizontal: 32),
                        decoration: BoxDecoration(
                          color: _correct
                              ? _bgAnim.value
                              : _wrong
                              ? const Color(0xFFFFEBEE)
                              : _isReplaying
                              ? const Color(0xFFF7FAFF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _correct
                                ? (_borderAnim.value ?? Colors.green.shade300)
                                : _wrong
                                ? Colors.red.shade300
                                : _isReplaying
                                ? Colors.blue.shade200
                                : Colors.grey.shade200,
                            width:
                            _correct || _wrong || _isReplaying ? 1.5 : 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _isReplaying
                                  ? Colors.blue.withValues(alpha: 0.10)
                                  : Colors.black.withValues(alpha: 0.04),
                              blurRadius: _isReplaying ? 14 : 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              _currentWord,
                              style: const TextStyle(
                                fontSize: 60,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.volume_up_outlined,
                                    color: Colors.grey.shade500, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'Tap anywhere to hear again',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Feedback area ────────────────────────────────────────────────
            if (_micError != _MicError.none)
              _MicErrorBanner(
                error: _micError,
              )
            else if (_wrong)
              _WrongAnswerBanner(
                heard: _heard,
                remaining: remaining,
              ),

            const Spacer(),

            // ── Mic button ───────────────────────────────────────────────────
            GestureDetector(
              onTap: () {
                if (_isListening) {
                  _cancelListening();
                } else {
                  _startListening();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _isListening ? Colors.red.shade600 : Colors.black,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _isListening
                        ? const Icon(Icons.stop_circle_outlined,
                        key: ValueKey('stop'),
                        color: Colors.white,
                        size: 30)
                        : const Icon(Icons.mic_none,
                        key: ValueKey('mic'),
                        color: Colors.white,
                        size: 32),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isListening
                  ? 'Recording… tap to cancel'
                  : _initializing
                  ? 'Preparing microphone…'
                  : 'Tap to speak',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Results dialog ──────────────────────────────────────────────────────────
class _ResultsDialog extends StatelessWidget {
  final int totalWords;
  final List<String> correctWords;
  final List<String> wrongWords;
  final VoidCallback onFinish;

  const _ResultsDialog({
    required this.totalWords,
    required this.correctWords,
    required this.wrongWords,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final int correctCount = correctWords.length;
    final double pct = totalWords > 0 ? correctCount / totalWords : 0;
    final bool isExcellent = pct >= 0.8;

    final Color progressColor = pct > 0.7
        ? Colors.green.shade400
        : pct > 0.4
            ? Colors.orange.shade400
            : Colors.red.shade400;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(
                isExcellent ? Icons.stars_rounded : Icons.emoji_events_rounded,
                color: Colors.orange.shade400,
                size: 52,
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Level completed!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'You got $correctCount out of $totalWords words correct',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ScorePill(
                    count: correctCount,
                    label: 'Correct',
                    background: const Color(0xFFEAF3DE),
                    countColor: const Color(0xFF3B6D11),
                    labelColor: const Color(0xFF639922),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ScorePill(
                    count: wrongWords.length,
                    label: 'Wrong',
                    background: const Color(0xFFFCEBEB),
                    countColor: const Color(0xFFA32D2D),
                    labelColor: const Color(0xFFE24B4A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.grey.shade100,
                  color: progressColor,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(pct * 100).toInt()}% score',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                Text('$correctCount / $totalWords',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 22),
            if (correctWords.isNotEmpty) ...[
              _SectionLabel(label: 'Correct', color: const Color(0xFF639922)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: correctWords
                    .map((w) => _WordChip(
                          word: w,
                          background: const Color(0xFFEAF3DE),
                          textColor: const Color(0xFF3B6D11),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
            ],
            if (wrongWords.isNotEmpty) ...[
              _SectionLabel(label: 'Needs practice', color: const Color(0xFFE24B4A)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: wrongWords
                    .map((w) => _WordChip(
                          word: w,
                          background: const Color(0xFFFCEBEB),
                          textColor: const Color(0xFFA32D2D),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onFinish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  'Finish',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small reusable widgets ──────────────────────────────────────────────────
class _ScorePill extends StatelessWidget {
  final int count;
  final String label;
  final Color background;
  final Color countColor;
  final Color labelColor;

  const _ScorePill({
    required this.count,
    required this.label,
    required this.background,
    required this.countColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: countColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: labelColor),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  final String word;
  final Color background;
  final Color textColor;

  const _WordChip({
    required this.word,
    required this.background,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        word,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

// ─── Error banner widget ──────────────────────────────────────────────────────
class _MicErrorBanner extends StatelessWidget {
  final _MicError error;

  const _MicErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    final bool isPermission = error.requiresSettings;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isPermission ? Icons.mic_off : Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error.message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Wrong answer banner widget ───────────────────────────────────────────────
class _WrongAnswerBanner extends StatelessWidget {
  final String heard;
  final int remaining;

  const _WrongAnswerBanner({required this.heard, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Text(
            'Pronunciation not clear',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade700),
          ),
          if (heard.isNotEmpty) ...[
            const SizedBox(height: 6),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(fontSize: 14, color: Colors.red.shade800),
                children: [
                  const TextSpan(text: 'You said: '),
                  TextSpan(
                    text: heard,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Remaining attempts: $remaining',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700),
          ),
        ],
      ),
    );
  }
}