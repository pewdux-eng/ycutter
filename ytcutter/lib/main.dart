import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';

void main() {
  runApp(const YTCutterApp());
}

class YTCutterApp extends StatelessWidget {
  const YTCutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Audio Cutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DB954),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _linkController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  String _status = '';
  String? _outputPath;
  bool _isProcessing = false;
  double _progress = 0;

  // ── Time parsing ──────────────────────────────────────────────────────────
  // Accepts: 29.25 / 1.12.03 / 29:25 / 1:12:03
  int? _parseTime(String input) {
    input = input.trim();
    // Replace dots with colons for uniform parsing
    final normalized = input.replaceAll('.', ':');
    final parts = normalized.split(':');
    try {
      if (parts.length == 3) {
        return int.parse(parts[0]) * 3600 +
            int.parse(parts[1]) * 60 +
            int.parse(parts[2]);
      } else if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return null;
  }

  String _secondsToDisplay(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ── Extract YouTube video ID ──────────────────────────────────────────────
  String? _extractVideoId(String url) {
    final patterns = [
      RegExp(r'youtu\.be/([\w-]+)'),
      RegExp(r'youtube\.com/watch\?.*v=([\w-]+)'),
      RegExp(r'youtube\.com/shorts/([\w-]+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  // ── Get audio URL via Cobalt API ─────────────────────────────────────────
  Future<String?> _getAudioUrl(String youtubeUrl) async {
    // Try multiple Cobalt instances for reliability
    final instances = [
      'https://cobalt-api.kwiatekmiki.com',
      'https://api.cobalt.tools',
      'https://cob.froth.zone',
    ];

    for (final instance in instances) {
      try {
        setState(() => _status = '🔍 Fetching audio stream...');
        final response = await http.post(
          Uri.parse(instance),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'url': youtubeUrl,
            'downloadMode': 'audio',
            'audioFormat': 'mp3',
            'audioBitrate': '128',
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final status = data['status'];
          if (status == 'stream' || status == 'redirect' || status == 'tunnel') {
            return data['url'] as String?;
          }
        }
      } catch (e) {
        // Try next instance
        continue;
      }
    }
    return null;
  }

  // ── Download audio file ───────────────────────────────────────────────────
  Future<String?> _downloadAudio(String url) async {
    final dir = await getTemporaryDirectory();
    final rawPath = '${dir.path}/raw_${DateTime.now().millisecondsSinceEpoch}.mp3';

    setState(() => _status = '⬇️ Downloading audio...');

    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    if (response.statusCode != 200) return null;

    final total = response.contentLength ?? 0;
    int received = 0;
    final file = File(rawPath);
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        setState(() {
          _progress = (received / total) * 0.5; // first 50% is download
          _status = '⬇️ Downloading... ${(_progress * 2 * 100).toStringAsFixed(0)}%';
        });
      }
    }

    await sink.close();
    client.close();
    return rawPath;
  }

  // ── Trim + compress with FFmpeg ───────────────────────────────────────────
  Future<String?> _trimAndCompress(String inputPath, int startSec, int endSec) async {
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final duration = endSec - startSec;

    // Target bitrate to keep under 15MB
    const maxSizeMB = 15;
    final targetBitrate = ((maxSizeMB * 8 * 1024) / duration).floor().clamp(32, 128);

    setState(() => _status = '✂️ Trimming and compressing...');

    final command =
        '-y -i "$inputPath" -ss $startSec -t $duration -ar 22050 -ac 1 -b:a ${targetBitrate}k "$outPath"';

    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();

    if (ReturnCode.isSuccess(code)) {
      // Check size
      final file = File(outPath);
      final sizeMB = file.lengthSync() / (1024 * 1024);

      if (sizeMB > maxSizeMB) {
        // Re-encode at lower quality
        final outPath2 = '${dir.path}/clip2_${DateTime.now().millisecondsSinceEpoch}.mp3';
        final lowerBitrate = (targetBitrate * 0.5).floor().clamp(24, 64);
        final cmd2 =
            '-y -i "$inputPath" -ss $startSec -t $duration -ar 16000 -ac 1 -b:a ${lowerBitrate}k "$outPath2"';
        final s2 = await FFmpegKit.execute(cmd2);
        final c2 = await s2.getReturnCode();
        if (ReturnCode.isSuccess(c2)) return outPath2;
      }

      return outPath;
    }

    return null;
  }

  // ── Main process ─────────────────────────────────────────────────────────
  Future<void> _process() async {
    final link = _linkController.text.trim();
    final startText = _startController.text.trim();
    final endText = _endController.text.trim();

    if (link.isEmpty || startText.isEmpty || endText.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }

    final startSec = _parseTime(startText);
    final endSec = _parseTime(endText);

    if (startSec == null || endSec == null) {
      _showError('Invalid time format.\nUse: 29.25 or 1.12.03 or 29:25');
      return;
    }

    if (endSec <= startSec) {
      _showError('End time must be after start time.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _outputPath = null;
      _progress = 0;
      _status = '🚀 Starting...';
    });

    try {
      // Step 1: Get audio stream URL
      final audioUrl = await _getAudioUrl(link);
      if (audioUrl == null) throw Exception('Could not get audio stream. Try again or check the link.');

      // Step 2: Download
      final rawPath = await _downloadAudio(audioUrl);
      if (rawPath == null) throw Exception('Download failed.');
      setState(() => _progress = 0.5);

      // Step 3: Trim + compress
      setState(() => _status = '✂️ Trimming ${_secondsToDisplay(startSec)} → ${_secondsToDisplay(endSec)}...');
      final outPath = await _trimAndCompress(rawPath, startSec, endSec);

      // Cleanup raw download
      try { File(rawPath).deleteSync(); } catch (_) {}

      if (outPath == null) throw Exception('Trimming failed.');

      final sizeMB = File(outPath).lengthSync() / (1024 * 1024);
      setState(() {
        _outputPath = outPath;
        _progress = 1.0;
        _status = '✅ Done! ${sizeMB.toStringAsFixed(1)} MB — ready to share';
        _isProcessing = false;
      });

    } catch (e) {
      setState(() {
        _status = '❌ ${e.toString()}';
        _isProcessing = false;
        _progress = 0;
      });
    }
  }

  void _share() async {
    if (_outputPath == null) return;
    await Share.shareXFiles(
      [XFile(_outputPath!, mimeType: 'audio/mpeg')],
      text: 'Audio clip',
    );
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Oops'),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('YT Audio Cutter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── YouTube Link ──
            _label('YouTube Link'),
            const SizedBox(height: 6),
            TextField(
              controller: _linkController,
              decoration: _inputDecoration('https://youtu.be/...', Icons.link),
              keyboardType: TextInputType.url,
            ),

            const SizedBox(height: 20),

            // ── Start / End ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Start Time'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _startController,
                        decoration: _inputDecoration('29.25', Icons.play_arrow),
                        keyboardType: TextInputType.text,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('End Time'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _endController,
                        decoration: _inputDecoration('1.12.03', Icons.stop),
                        keyboardType: TextInputType.text,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              'Format: 29.25 or 1.12.03 (dots or colons both work)',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),

            const SizedBox(height: 28),

            // ── Process Button ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _process,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isProcessing
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 10),
                          Text('Processing...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      )
                    : const Text('Download & Cut', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),

            const SizedBox(height: 20),

            // ── Progress + Status ──
            if (_isProcessing || _status.isNotEmpty) ...[
              if (_isProcessing) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _outputPath != null
                      ? const Color(0xFFE8F5E9)
                      : _status.startsWith('❌')
                          ? const Color(0xFFFFEBEE)
                          : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    fontSize: 13,
                    color: _outputPath != null
                        ? const Color(0xFF2E7D32)
                        : _status.startsWith('❌')
                            ? Colors.red[700]
                            : Colors.grey[700],
                  ),
                ),
              ),
            ],

            // ── Share Button ──
            if (_outputPath != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share),
                  label: const Text('Share to WhatsApp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
      );

  InputDecoration _inputDecoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF1DB954), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );
}
