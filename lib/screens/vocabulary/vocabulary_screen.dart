import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

class _VocabularyScreenState extends State<VocabularyScreen> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  int _currentWordIndex = 0;
  bool _isListening = false;
  bool _correct = false;
  bool _wrong = false;
  int _attempts = 0;
  String _heard = '';

  String get _currentWord => widget.words[_currentWordIndex];

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    _speakCurrentWord();
  }

  Future<void> _initSpeech() async {
    print('DEBUG: Initializing Speech...');
    await _speech.initialize(
      onError: (e) {
        print('DEBUG: Speech Error: ${e.errorMsg}');
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        print('DEBUG: Speech Status: $status');
        if (status == 'notListening' && mounted) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  Future<void> _speakCurrentWord() async {
    await _tts.speak(_currentWord);
  }

  Future<void> _startListening() async {
    print('DEBUG: --- Start Listening Process ---');
    
    if (mounted) {
      setState(() {
        _isListening = true;
        _correct = false;
        _wrong = false;
        _heard = '';
      });
    }

    try {
      await _tts.stop();
      // Thoroughly reset any previous session
      await _speech.stop();
      await _speech.cancel();
      
      // Reduced delay for snappier activation
      await Future.delayed(const Duration(milliseconds: 500));

      if (!_speech.isAvailable) {
        print('DEBUG: Speech not available, re-initializing...');
        final initialized = await _speech.initialize(
          onError: (e) {
            print('DEBUG: Speech Error: ${e.errorMsg}');
            if (mounted) setState(() => _isListening = false);
          },
          onStatus: (status) {
            print('DEBUG: Speech Status: $status');
            if ((status == 'notListening' || status == 'done') && mounted) {
              setState(() => _isListening = false);
            }
          },
        );
        if (!initialized) {
          print('DEBUG: Initialization failed.');
          if (mounted) setState(() => _isListening = false);
          return;
        }
      }

      print('DEBUG: Calling _speech.listen...');
      await _speech.listen(
        onResult: (result) {
          print('DEBUG: Speech Result: "${result.recognizedWords}" (Final: ${result.finalResult})');
          if (result.finalResult && mounted) {
            final spoken = result.recognizedWords.trim().toLowerCase();
            setState(() {
              _heard = spoken;
              _isListening = false;
            });
            if (spoken.isNotEmpty) {
              _checkAnswer(spoken);
            } else {
              print('DEBUG: Heard nothing (empty result).');
            }
          }
        },
        localeId: 'en-US',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          cancelOnError: false,
          partialResults: true,
          onDevice: true,
        ),
      );
    } catch (e) {
      print('DEBUG: Error in _startListening: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  void _checkAnswer(String spoken) {
    final expected = _currentWord.toLowerCase();
    if (spoken == expected || spoken.contains(expected)) {
      if (mounted) {
        setState(() {
          _correct = true;
          _attempts = 0;
        });
      }
      Future.delayed(const Duration(milliseconds: 800), _nextWord);
    } else {
      if (mounted) {
        setState(() {
          _wrong = true;
          _attempts++;
        });
      }

      if (_attempts >= 3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('The word was: $_currentWord. Moving to next...'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        Future.delayed(const Duration(milliseconds: 2000), _nextWord);
      }
    }
  }

  void _nextWord() {
    if (!mounted) return;
    if (_currentWordIndex < widget.words.length - 1) {
      setState(() {
        _currentWordIndex++;
        _correct = false;
        _wrong = false;
        _attempts = 0;
        _heard = '';
      });
      _speakCurrentWord();
    } else {
      _showFinished();
    }
  }

  void _showFinished() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Congratulations!'),
        content: const Text('You have completed this level.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context); // Go back to Home
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _correct
                      ? Colors.green.shade300
                      : _wrong
                          ? Colors.red.shade300
                          : Colors.grey.shade200,
                  width: _correct || _wrong ? 1.5 : 0.5,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _currentWord,
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Replay button
                  GestureDetector(
                    onTap: _speakCurrentWord,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.volume_up_outlined,
                          color: Colors.grey.shade500,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tap to hear again',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_wrong)
              Column(
                children: [
                  if (_heard.isNotEmpty)
                    Text(
                      'You said: $_heard',
                      style: const TextStyle(fontSize: 14, color: Colors.red),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Attempts: $_attempts / 3',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            const Spacer(),
            // Speak button
            GestureDetector(
              onTap: () {
                print('DEBUG: Mic button tapped. _isListening: $_isListening');
                if (!_isListening) {
                  _startListening();
                }
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _isListening ? Colors.grey.shade300 : Colors.black,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isListening ? 'Listening...' : 'Tap to speak',
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
