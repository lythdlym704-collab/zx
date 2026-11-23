import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZXApp());
}

class ZXApp extends StatelessWidget {
  const ZXApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ZX Thermal Camera',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF08090D),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFF303B), secondary: Color(0xFFFF7548),
        surface: Color(0xFF15171E),
      ),
    ),
    home: const CameraHome(),
  );
}

enum ThermalMode { red, spectrum, night }

class CameraHome extends StatefulWidget {
  const CameraHome({super.key});
  @override
  State<CameraHome> createState() => _CameraHomeState();
}

class _CameraHomeState extends State<CameraHome> with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  ThermalMode _mode = ThermalMode.red;
  bool _busy = false, _english = false, _recording = false;
  String? _error;
  final List<File> _media = [];

  String t(String ar, String en) => _english ? en : ar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _loadGallery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera({int? index}) async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('No camera available');
      final selected = index == null
          ? _cameras.first
          : _cameras[index % _cameras.length];
      final controller = CameraController(
        selected, ResolutionPreset.high, enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      final old = _camera;
      setState(() { _camera = controller; _error = null; });
      await old?.dispose();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  ColorFilter get _filter {
    switch (_mode) {
      case ThermalMode.red:
        return const ColorFilter.matrix(<double>[
          1.35, .12, .0, 0, 18,
          .15, .48, .0, 0, 0,
          .0, .05, .18, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ThermalMode.spectrum:
        return const ColorFilter.matrix(<double>[
          .2, .0, 1.1, 0, 0,
          .0, 1.1, .15, 0, 0,
          1.1, .0, .1, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ThermalMode.night:
        return const ColorFilter.matrix(<double>[
          .15, .0, .0, 0, 0,
          .0, .9, .0, 0, 24,
          .0, .0, .12, 0, 0,
          0, 0, 0, 1, 0,
        ]);
    }
  }

  Future<Directory> _mediaDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/ZX_Media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadGallery() async {
    final dir = await _mediaDir();
    final items = dir.listSync().whereType<File>().where((f) =>
      f.path.endsWith('.jpg') || f.path.endsWith('.mp4')).toList()
      ..sort((a,b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (mounted) setState(() { _media
      ..clear()
      ..addAll(items); });
  }

  Future<void> _capture() async {
    final c = _camera;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final dir = await _mediaDir();
      final target = File('${dir.path}/ZX_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(shot.path).copy(target.path);
      try { await Gal.putImage(target.path); } catch (_) {}
      await _loadGallery();
      _toast(t('تم حفظ الصورة', 'Photo saved'));
    } catch (e) { _toast('${t('تعذر التصوير', 'Capture failed')}: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _toggleVideo() async {
    final c = _camera;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      if (!_recording) {
        await c.startVideoRecording();
        if (mounted) setState(() => _recording = true);
      } else {
        final video = await c.stopVideoRecording();
        final dir = await _mediaDir();
        final target = File('${dir.path}/ZX_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await File(video.path).copy(target.path);
        await _loadGallery();
        if (mounted) setState(() => _recording = false);
        _toast(t('تم حفظ الفيديو', 'Video saved'));
      }
    } catch (e) {
      _toast('${t('تعذر تسجيل الفيديو', 'Video failed')}: $e');
      if (mounted) setState(() => _recording = false);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording) return;
    final current = _camera?.description;
    final idx = _cameras.indexOf(current!);
    await _camera?.dispose();
    if (mounted) setState(() => _camera = null);
    await _initCamera(index: idx + 1);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), backgroundColor: const Color(0xFF29232A)));
  }

  String _modeName(ThermalMode mode) => switch (mode) {
    ThermalMode.red => t('حراري أحمر', 'Red thermal'),
    ThermalMode.spectrum => t('طيف حراري', 'Spectrum'),
    ThermalMode.night => t('رؤية ليلية', 'Night vision'),
  };

  void _openGallery() {
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      GalleryPage(files: List<File>.from(_media), title: t('معرض ZX', 'ZX Gallery'))));
  }

  @override
  Widget build(BuildContext context) {
    final c = _camera;
    return Directionality(
      textDirection: _english ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF08090D),
          title: const Text('ZX', style: TextStyle(fontWeight: FontWeight.w900,
            letterSpacing: 4, color: Color(0xFFFF3945))),
          actions: [
            IconButton(tooltip: t('تبديل اللغة', 'Switch language'),
              onPressed: () => setState(() => _english = !_english),
              icon: const Icon(Icons.translate)),
            IconButton(tooltip: t('المعرض', 'Gallery'),
              onPressed: _openGallery, icon: const Icon(Icons.photo_library_outlined)),
          ],
        ),
        body: Column(children: [
          Expanded(child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            clipBehavior: Clip.antiAlias, decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF8E202B), width: 1.2),
              color: Colors.black),
            child: Stack(fit: StackFit.expand, children: [
              if (c != null && c.value.isInitialized)
                ColorFiltered(colorFilter: _filter, child: CameraPreview(c))
              else Center(child: _error == null
                ? const CircularProgressIndicator(color: Color(0xFFFF303B))
                : Padding(padding: const EdgeInsets.all(20),
                  child: Text('${t('تعذر تشغيل الكاميرا', 'Camera unavailable')}\n$_error',
                    textAlign: TextAlign.center))),
              Positioned(top: 14, right: 14, child: _tag('ZX • LIVE')),
              Positioned(bottom: 14, left: 14, child: _tag(_modeName(_mode))),
              Positioned(top: 14, left: 14, child: _tag('THERMAL FX')),
              if (_recording) Positioned(bottom: 14, right: 14,
                child: _tag('● REC', red: true)),
            ]),
          )),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: ThermalMode.values.map((m) =>
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(_modeName(m), style: const TextStyle(fontSize: 11)),
                  selected: _mode == m,
                  selectedColor: const Color(0xFF7E202B),
                  onSelected: (_) => setState(() => _mode = m),
                )))).toList())),
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _roundButton(Icons.cameraswitch, t('تبديل', 'Flip'), _switchCamera),
              _roundButton(Icons.photo_camera, t('صورة', 'Photo'), _capture, large: true),
              _roundButton(_recording ? Icons.stop : Icons.videocam,
                _recording ? t('إيقاف', 'Stop') : t('فيديو', 'Video'),
                _toggleVideo, red: _recording),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 10, left: 18, right: 18),
            child: Text(t('تأثير بصري تجريبي — لا يقيس درجة الحرارة الفعلية',
              'Visual simulation — does not measure actual temperature'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11))),
        ]),
      ),
    );
  }

  Widget _tag(String text, {bool red = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.black.withOpacity(.65),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: red ? Colors.red : const Color(0xFFB42A36))),
    child: Text(text, style: TextStyle(color: red ? Colors.redAccent : Colors.white,
      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)));

  Widget _roundButton(IconData icon, String label, VoidCallback action,
      {bool large = false, bool red = false}) => Column(children: [
    InkWell(onTap: _busy ? null : action, borderRadius: BorderRadius.circular(50),
      child: Container(width: large ? 68 : 54, height: large ? 68 : 54,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: red ? const Color(0xFFB51F2D) : const Color(0xFF1B1D25),
          border: Border.all(color: const Color(0xFFFF3945), width: large ? 3 : 1.2)),
        child: Icon(icon, color: Colors.white, size: large ? 30 : 23))),
    const SizedBox(height: 6),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
  ]);
}

class GalleryPage extends StatelessWidget {
  final List<File> files;
  final String title;
  const GalleryPage({super.key, required this.files, required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: files.isEmpty
      ? const Center(child: Text('لا توجد ملفات محفوظة بعد'))
      : GridView.builder(padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: files.length, itemBuilder: (context, i) {
          final f = files[i], video = f.path.endsWith('.mp4');
          return ClipRRect(borderRadius: BorderRadius.circular(12),
            child: Container(color: const Color(0xFF191B22),
              child: video ? Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [const Icon(Icons.play_circle, size: 48, color: Colors.redAccent),
                  Text(f.uri.pathSegments.last, maxLines: 2, textAlign: TextAlign.center)])
                : Image.file(f, fit: BoxFit.cover)));
        }),
  );
}
