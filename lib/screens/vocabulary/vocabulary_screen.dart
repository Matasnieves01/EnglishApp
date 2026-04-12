import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:dart_phonetics/dart_phonetics.dart';

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
with SingleTickerProviderStateMixin{
  static const int _maxAttempts = 3;
  static const Duration _listenForDuration = Duration(seconds: 15);
  static const Duration _pauseForDuration = Duration(seconds: 5);

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  late AnimationController _animController;
  late Animation<Color?> _borderControl;
  late Animation<Color?> _bgColor;

  int _currentWordIndex = 0;
  bool _isListening = false;
  bool _correct = false;
  bool _wrong = false;
  bool _isReplaying = false;
  int _attempts = 0;
  int _wrongPulse = 0;
  String _heard = '';
  int _correctCount = 0;

  String get _currentWord => widget.words[_currentWordIndex];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _borderControl = ColorTween(
      begin: Colors.grey.shade200,
      end: Colors.green.shade300,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _bgColor = ColorTween(
      begin: Colors.white,
      end: Color(0xFFEDF7ED),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _initTts();
    _initSpeech();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    _speakCurrentWord();
  }

  Future<void> _initSpeech() async {
    debugPrint('DEBUG: Initializing Speech...');
    await _speech.initialize(
      onError: (e) {
        debugPrint('DEBUG: Speech Error: ${e.errorMsg}');
        if (e.errorMsg == 'error_no_match' ||
            e.errorMsg == 'error_speech_timeout') {
          return;
        }
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        debugPrint('DEBUG: Speech Status: $status');
        // Only reset when speech recognition is fully completed.
        if (status == 'done' && mounted) {
          setState(() => _isListening = false);
        }
      },
      debugLogging: true,
    );
  }

  Future<void> _speakCurrentWord() async {
    await _tts.speak(_currentWord);
  }

  Future<void> _repeatCurrentWord() async {
    if (!mounted) return;

    setState(() {
      _isReplaying = true;
    });

    await _tts.stop();
    await _speakCurrentWord();

    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted) {
        setState(() {
          _isReplaying = false;
        });
      }
    });
  }

  Future<void> _startListening() async {
    debugPrint('DEBUG: --- Start Listening Process ---');
    
    if (mounted) {
      setState(() {
        _isListening = true;
        _correct = false;
        _wrong = false;
        _wrongPulse = 0;
        _heard = '';
      });
    }

    try {
      await _tts.stop();
      
      // Detener sesión previa si existe de forma más segura
      if (_speech.isListening) {
        await _speech.stop();
      }
      
      // Un pequeño delay para que el hardware del micro se libere
      await Future.delayed(const Duration(milliseconds: 250));

      if (!_speech.isAvailable) {
        debugPrint('DEBUG: Speech not available, re-initializing...');
        final initialized = await _speech.initialize(
          onError: (e) {
            debugPrint('DEBUG: Speech Error: ${e.errorMsg}');
            if (e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout') return;
            if (mounted) setState(() => _isListening = false);
          },
          onStatus: (status) {
            debugPrint('DEBUG: Speech Status: $status');
            if ((status == 'done' || status == 'notListening') && mounted) {
              setState(() => _isListening = false);
            }
          },
        );
        if (!initialized) {
          if (mounted) setState(() => _isListening = false);
          return;
        }
      }

      debugPrint('DEBUG: Calling _speech.listen...');
      await _speech.listen(
        onResult: (result) {
          // Solo procesamos y loagueamos cuando el resultado es final
          if (result.finalResult) {
            debugPrint('DEBUG: Speech Result (Final): "${result.recognizedWords}"');
            if (mounted) {
              final spoken = result.recognizedWords.trim().toLowerCase();
              setState(() {
                _heard = spoken;
                _isListening = false;
              });
              if (spoken.isNotEmpty) {
                _checkAnswer(spoken);
              }
            }
          } else {
            // Log opcional para ver el progreso sin ensuciar tanto
            debugPrint('DEBUG: Partial: "${result.recognizedWords}"');
          }
        },
        localeId: 'en-US',
        listenFor: _listenForDuration,
        pauseFor: const Duration(seconds: 3), // Un poco más corto para mayor respuesta
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation, // Cambiado a dictation para mayor fluidez
          cancelOnError: false,
          partialResults: false,
          onDevice: false,
        ),
      );
    } catch (e) {
      debugPrint('DEBUG: Error in _startListening: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _cancelListening() async {
    debugPrint('DEBUG: Manual listening cancel requested.');
    try {
      await _speech.stop();
      await _speech.cancel();
    } catch (e) {
      debugPrint('DEBUG: Error while canceling listening: $e');
    }
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _checkAnswer(String spokenText) {
    final expected = _currentWord.toLowerCase();
    final spoken = spokenText.toLowerCase();

    //.1 Math match first
    bool isCorrect = spoken == expected || spoken.contains(expected);
    if (!isCorrect) {
      final encoder = DoubleMetaphone();
      final expectedCode = encoder.encode(expected);
      final spokenCode = encoder.encode(spoken);

      if (spokenCode != null && expectedCode != null) {
        isCorrect =
            spokenCode.primary == expectedCode.primary ||
                (expectedCode.alternates?.contains(spokenCode.primary) ?? false) ||
                (spokenCode.alternates?.contains(expectedCode.primary) ?? false);
      }
    }
    if (isCorrect) {
      if (mounted) {
        setState(() {
          _correct = true;
          _wrong = false;
          _attempts = 0;
          _correctCount++;
        });
        _animController.forward();
      }
      Future.delayed(const Duration(milliseconds: 800), _nextWord);
    }else{
      if (mounted) {
        setState(() {
          _wrong = true;
          _attempts++;
          _wrongPulse++;
        });
      }
      if (_attempts >= _maxAttempts) {
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
      });
      _speakCurrentWord();
    } else {
      _showFinished();
    }
  }

  void _showFinished() {
    final double percentage = _correctCount / widget.words.length;
    final bool isExcellent = percentage >= 0.8;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            Icon(
              isExcellent ? Icons.stars : Icons.emoji_events,
              color: Colors.orange,
              size: 60,
            ),
            const SizedBox(height: 16),
            const Text(
              'Level Completed!',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You got $_correctCount out of ${widget.words.length} words correct',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: percentage,
                      backgroundColor: Colors.grey.shade200,
                      color: percentage > 0.7 
                          ? Colors.green.shade400 
                          : (percentage > 0.4 ? Colors.orange.shade400 : Colors.red.shade400),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${(percentage * 100).toInt()}% Score',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Finish'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int remainingAttempts =
        (_maxAttempts - _attempts).clamp(0, _maxAttempts).toInt();

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Repeat the word',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.18, 0),
                  end: Offset.zero,
                ).animate(animation);

                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: slide,
                    child: child,
                  ),
                );
              },
              child: AnimatedBuilder(
                key: ValueKey('$_currentWordIndex-$_wrongPulse'),
                animation: _animController,
                builder: (context, child) {
                  return AnimatedScale(
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
                          padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 32),
                          decoration: BoxDecoration(
                            color: _correct
                                ? _bgColor.value
                                : _wrong
                                    ? const Color(0xFFFFEBEE)
                                : _isReplaying
                                    ? const Color(0xFFF7FAFF)
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _correct
                                  ? (_borderControl.value ?? Colors.green.shade300)
                                  : _wrong
                                      ? Colors.red.shade300
                                  : _isReplaying
                                      ? Colors.blue.shade200
                                      : Colors.grey.shade200,
                              width: _correct || _wrong || _isReplaying ? 1.5 : 0.5,
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
                                  Icon(
                                    Icons.volume_up_outlined,
                                    color: Colors.grey.shade500,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Tap anywhere to hear again',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            /*const SizedBox(height: 16,),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300, width: 0.5),
              ),
              child: const Text(
                ' sfs dv ',
                textAlign: TextAlign.center,
              ),
            ),*/
            const SizedBox(height: 24),
            if (_wrong)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4F4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200, width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      'Pronunciation not clear',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                      ),
                    ),
                    if (_heard.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.shade800,
                          ),
                          children: [
                            const TextSpan(text: 'You said: '),
                            TextSpan(
                              text: _heard,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Remaining attempts: $remainingAttempts',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            // Speak button
            GestureDetector(
              onTap: () {
                debugPrint('DEBUG: Mic button tapped. _isListening: $_isListening');
                if (_isListening) {
                  _cancelListening();
                  return;
                }
                _startListening();
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
                        ? const Icon(
                            key: ValueKey('cancel-recording'),
                            Icons.stop_circle_outlined,
                            color: Colors.white,
                            size: 30,
                          )
                        : const Icon(
                            key: ValueKey('start-mic'),
                            Icons.mic_none,
                            color: Colors.white,
                            size: 32,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isListening ? 'Recording... tap to cancel' : 'Tap to speak',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
