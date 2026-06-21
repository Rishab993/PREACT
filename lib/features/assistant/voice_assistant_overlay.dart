import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/api_client.dart';
import '../../providers/app_providers.dart';

class VoiceAssistantOverlay extends ConsumerStatefulWidget {
  const VoiceAssistantOverlay({super.key});

  @override
  ConsumerState<VoiceAssistantOverlay> createState() =>
      _VoiceAssistantOverlayState();
}

class _VoiceAssistantOverlayState extends ConsumerState<VoiceAssistantOverlay>
    with TickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _textCtrl = TextEditingController();

  bool _isRecording = false;
  bool _isThinking = false;
  DateTime? _recordingStart;
  List<_ChatMessage> _messages = [];
  late AnimationController _waveCtrl;
  late AnimationController _thinkCtrl;
  late Animation<double> _waveAnim;
  late Animation<double> _thinkAnim;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _thinkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _waveAnim = Tween(begin: 0.6, end: 1.2).animate(CurvedAnimation(parent: _waveCtrl, curve: Curves.easeInOut));
    _thinkAnim = CurvedAnimation(parent: _thinkCtrl, curve: Curves.easeInOut);

    _tts.setLanguage('en-IN');
    _tts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    if (_isRecording || _isStartingRecording) {
      unawaited(_recorder.stop().catchError((_) => null));
    }
    _waveCtrl.dispose();
    _thinkCtrl.dispose();
    _tts.stop();
    _recorder.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  bool _isStartingRecording = false;
  bool _isStoppingRecording = false;
  String? _recordingPath;

  Future<String> _resolveRecordingPath() async {
    if (kIsWeb) {
      return '${DateTime.now().millisecondsSinceEpoch}.wav';
    }
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isStartingRecording || _isStoppingRecording) return;
    _isStartingRecording = true;
    debugPrint('[VoiceAssistant] Start recording requested.');

    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('[VoiceAssistant] Microphone permission denied.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required'), backgroundColor: AppColors.amber),
          );
        }
        return;
      }
      final path = await _resolveRecordingPath();
      _recordingPath = path;
      debugPrint('[VoiceAssistant] Starting recorder with path: $path');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: path);
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordingStart = DateTime.now();
        });
      }
      debugPrint('[VoiceAssistant] Recorder started successfully.');
    } catch (e) {
      debugPrint('[VoiceAssistant] Error starting recorder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      _isStartingRecording = false;
    }
  }

  Future<void> _toggleRecording() async {
    if (_isStartingRecording || _isStoppingRecording) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _isStoppingRecording) return;
    _isStoppingRecording = true;

    final duration = _recordingStart != null
        ? DateTime.now().difference(_recordingStart!)
        : const Duration(seconds: 1);
    if (duration.inMilliseconds < 500) {
      await Future.delayed(
          Duration(milliseconds: 500 - duration.inMilliseconds));
    }

    debugPrint('[VoiceAssistant] Stop recording requested.');
    String? path;
    try {
      path = await _recorder.stop();
      path ??= _recordingPath;
    } catch (e) {
      debugPrint('[VoiceAssistant] Error stopping recorder: $e');
      path = _recordingPath;
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingStart = null;
        _recordingPath = null;
      });
    }
    _isStoppingRecording = false;

    debugPrint('[VoiceAssistant] Recorder stopped. Result path: $path');
    if (path != null && path.isNotEmpty) {
      await _sendAudio(path);
    } else {
      _showError('Recording failed — please try again.');
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording && !_isStartingRecording) return;
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isStartingRecording = false;
        _isStoppingRecording = false;
        _recordingStart = null;
        _recordingPath = null;
      });
    }
  }

  Future<void> _sendAudio(String path) async {
    setState(() => _isThinking = true);
    final isKn = ref.read(languageProvider).isKannada;

    // Add user message placeholder
    setState(() => _messages.insert(0, _ChatMessage(
      text: isKn ? 'ಧ್ವನಿ ಸಂದೇಶ...' : 'Voice message...',
      isUser: true,
    )));

    int fileSize = 0;
    try {
      Uint8List audioBytes;
      if (kIsWeb) {
        debugPrint('[VoiceAssistant] Web environment. Fetching blob: $path');
        final tempDio = Dio();
        final res = await tempDio.get<List<int>>(
          path,
          options: Options(responseType: ResponseType.bytes),
        );
        if (res.data == null) {
          throw Exception('Failed to download blob data');
        }
        audioBytes = Uint8List.fromList(res.data!);
        fileSize = audioBytes.length;
        debugPrint('[VoiceAssistant] Fetched web blob bytes. Size: $fileSize bytes');
      } else {
        debugPrint('[VoiceAssistant] Native environment. Reading file path: $path');
        final file = io.File(path);
        if (!file.existsSync()) {
          throw Exception('Recorded file does not exist locally.');
        }
        audioBytes = await file.readAsBytes();
        fileSize = audioBytes.length;
        debugPrint('[VoiceAssistant] Read native file bytes. Size: $fileSize bytes');
      }

      final currentRole = ref.read(roleProvider);
      final roleStr = currentRole == AppRole.citizen ? 'citizen' : 'police';

      final formData = FormData.fromMap({
        'audio': MultipartFile.fromBytes(
          audioBytes,
          filename: 'audio.wav',
        ),
        'language': isKn ? 'kn' : 'en',
        'role': roleStr,
      });

      debugPrint('[API Request] POST ${AppEndpoints.chat}');
      debugPrint('[API Request] Headers: Content-Type = multipart/form-data');
      debugPrint('[API Request] Fields: language = ${isKn ? 'kn' : 'en'}, role = $roleStr');
      debugPrint('[API Request] Audio file size: $fileSize bytes');

      // IMPORTANT: Do NOT set contentType manually here.
      // When data is FormData, Dio automatically sets:
      //   Content-Type: multipart/form-data; boundary=<generated>
      // Overriding it loses the boundary parameter and causes 422.
      final response = await ApiClient.instance.post(
        AppEndpoints.chat,
        data: formData,
      );

      debugPrint('[API Response] Status: ${response.statusCode}');
      debugPrint('[API Response] Data: ${response.data}');

      final answerText = response.data['answer_text']?.toString() ??
          'I could not process that. Please try again.';
      final transcript = response.data['transcript']?.toString();

      if (transcript != null) {
        setState(() => _messages[0] = _ChatMessage(text: transcript, isUser: true));
      }

      setState(() {
        _isThinking = false;
        _messages.insert(0, _ChatMessage(text: answerText, isUser: false));
      });

      // TTS playback
      await _tts.speak(answerText);
    } catch (e) {
      debugPrint('[API Error] Audio chat submission failed: $e');

      String fallback;
      if (e is ApiException && e.statusCode == 422) {
        fallback = isKn
            ? 'ದೋಷ 422: ಆಡಿಯೋ ಫಾರ್ಮ್ಯಾಟ್ ತಪ್ಪಾಗಿದೆ.'
            : 'Validation Error (422): Audio format issue. Try speaking again.';
      } else if (e is ApiException && e.statusCode == null) {
        fallback = isKn
            ? 'ಸಂಪರ್ಕ ದೋಷ — ಸರ್ವರ್ ಲಭ್ಯವಿಲ್ಲ.'
            : 'Cannot reach server. Check your connection and try again.';
      } else if (e is ApiException) {
        fallback = 'Server Error (${e.statusCode}): ${e.message}';
      } else {
        fallback = isKn
            ? 'ಕ್ಷಮಿಸಿ, ದೋಷ ಸಂಭವಿಸಿದೆ: $e'
            : 'Error: $e';
      }

      setState(() {
        _isThinking = false;
        _messages.insert(0, _ChatMessage(text: fallback, isUser: false, isError: true));
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _isThinking = false;
      _messages.insert(
          0, _ChatMessage(text: message, isUser: false, isError: true));
    });
  }

  Future<void> _sendText(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _isThinking = true;
      _messages.insert(0, _ChatMessage(text: text, isUser: true));
    });

    final isKn = ref.read(languageProvider).isKannada;
    final currentRole = ref.read(roleProvider);
    final roleStr = currentRole == AppRole.citizen ? 'citizen' : 'police';
    try {
      debugPrint('[API Request] POST ${AppEndpoints.chat}/text');
      debugPrint('[API Request] Payload: text = $text, language = ${isKn ? 'kn' : 'en'}, role = $roleStr');

      // Send as text via chat/text endpoint (using a text param)
      final response = await ApiClient.instance.post(
        '${AppEndpoints.chat}/text',
        data: {'text': text, 'language': isKn ? 'kn' : 'en', 'role': roleStr},
      );
      final answer = response.data['answer_text']?.toString() ?? 'No response.';
      setState(() {
        _isThinking = false;
        _messages.insert(0, _ChatMessage(text: answer, isUser: false));
      });
      await _tts.speak(answer);
    } catch (e) {
      debugPrint('[API Error] Text chat submission failed: $e');

      String fallback;
      if (e is ApiException && e.statusCode == 422) {
        fallback = isKn
            ? 'ದೋಷ 422: ವಿನಂತಿ ಅಮಾನ್ಯವಾಗಿದೆ (ವ್ಯಾಲಿಡೇಶನ್ ದೋಷ).'
            : 'Validation Error (422): Backend rejected the text input or parameters.';
      } else if (e is ApiException) {
        fallback = isKn
            ? 'ಸರ್ವರ್ ದೋಷ (${e.statusCode}): ${e.message}'
            : 'Server Error (${e.statusCode}): ${e.message}';
      } else {
        fallback = isKn
            ? 'ಕ್ಷಮಿಸಿ, ಸಂಪರ್ಕ ದೋಷ ಸಂಭವಿಸಿದೆ. ಸರ್ವರ್ ಲಭ್ಯವಿಲ್ಲ.'
            : 'Backend unavailable. Try: "How many officers for IPL tonight?"';
      }

      setState(() {
        _isThinking = false;
        _messages.insert(0, _ChatMessage(
          text: fallback,
          isUser: false,
          isError: true,
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = ref.watch(voiceOverlayOpenProvider);
    if (!isOpen) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.black54,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
          ),
          child: Column(
            children: [
              _buildHandle(isDark),
              _buildOverlayHeader(isDark),
              Expanded(child: _buildChatHistory(isDark)),
              if (_isThinking) _buildThinkingIndicator(isDark),
              _buildInputRow(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(bool isDark) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
        color: isDark ? AppColors.borderDark : AppColors.borderLight,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildOverlayHeader(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.smart_toy_outlined, color: const Color(0xFF2563EB), size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PREACT Voice Assistant',
                style: TextStyle(
                  color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Ask in English or ಕನ್ನಡ',
                style: TextStyle(
                  color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            await _cancelRecording();
            ref.read(voiceOverlayOpenProvider.notifier).state = false;
            _tts.stop();
          },
          icon: Icon(Icons.close, color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark),
        ),
      ],
    ),
  );

  Widget _buildChatHistory(bool isDark) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none_rounded, color: const Color(0xFF2563EB).withOpacity(0.3), size: 64),
            const SizedBox(height: 12),
            const Text('Tap the mic to ask', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            const SizedBox(height: 8),
            const Text(
              '"How many officers for IPL tonight?"\n"ಇಂದು ಸಂಜೆ ಯಾವ ಜಂಕ್ಷನ್ ಹೆಚ್ಚು ಒತ್ತಡ?"',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        return _buildBubble(msg, isDark);
      },
    );
  }

  Widget _buildBubble(_ChatMessage msg, bool isDark) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isUser
              ? const Color(0xFF2563EB).withOpacity(0.2)
              : msg.isError
                  ? AppColors.red.withOpacity(0.1)
                  : (isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: msg.isUser ? const Radius.circular(4) : const Radius.circular(16),
            bottomLeft: msg.isUser ? const Radius.circular(16) : const Radius.circular(4),
          ),
          border: Border.all(
            color: msg.isUser
                ? const Color(0xFF2563EB).withOpacity(0.3)
                : msg.isError
                    ? AppColors.red.withOpacity(0.3)
                    : (isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isError
                ? AppColors.red
                : (isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
            borderRadius: BorderRadius.circular(16).copyWith(bottomLeft: const Radius.circular(4)),
            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) => _ThinkingDot(index: i, animation: _thinkAnim)),
          ),
        ),
        const SizedBox(width: 8),
        const Text('Thinking...', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    ),
  );

  Widget _buildInputRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type or tap mic to speak...',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (text) {
                _sendText(text);
                _textCtrl.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          // Mic button — tap to start, tap again to stop
          Material(
            color: _isRecording ? AppColors.red : const Color(0xFF2563EB),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _toggleRecording,
              child: AnimatedBuilder(
                animation: _waveAnim,
                builder: (_, __) => Transform.scale(
                  scale: _isRecording ? _waveAnim.value : 1.0,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  _ChatMessage({required this.text, required this.isUser, this.isError = false});
}

class _ThinkingDot extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  const _ThinkingDot({required this.index, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final offset = (animation.value + index * 0.3) % 1.0;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 6,
          height: 6 + (offset > 0.5 ? (1 - offset) * 4 : offset * 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.5 + offset * 0.5),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      },
    );
  }
}
