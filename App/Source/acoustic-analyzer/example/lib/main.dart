import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:permission_handler/permission_handler.dart';
import 'manager.dart';

const double kSampleRate = 44100.0;

void main() {
  runApp(const MaterialApp(
    title: 'AcousticAnalyzerPro',
    debugShowCheckedModeBanner: false,
    home: MainScreen(),
  ));
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ValueNotifier<int> _selectedIndex = ValueNotifier(0);
  bool _isInitialized = false;
  String _error = '';
  final _cal = Manager.instance;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initSoLoud();
  }

  Future<void> _initSoLoud() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        androidAudioAttributes: AndroidAudioAttributes(
          usage: AndroidAudioUsage.voiceCommunication,
          contentType: AndroidAudioContentType.speech,
        ),
      ));
      await session.setActive(true);

      await SoLoud.instance.init(
        channels: Channels.mono,
        sampleRate: 44100,
      );
    } catch (e) {
      debugPrint('SoLoud init error: $e');
    }
  }

  Future<void> _initRecorder() async {
    final statuses = await [
      Permission.microphone,
      Permission.photos,
      Permission.videos,
      Permission.audio,
      Permission.storage,
    ].request();

    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      setState(() => _error = 'Microphone permission denied');
      return;
    }

    try {
      await Recorder.instance.init(
        format: PCMFormat.f32le,
        sampleRate: kSampleRate.toInt(),
        channels: RecorderChannels.mono,
      );
      Recorder.instance.start();
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _error = 'Initialization error: $e');
    }
  }

  @override
  void dispose() {
    Recorder.instance.stop();
    Recorder.instance.deinit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_error.isNotEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(_error, style: const TextStyle(color: Colors.redAccent, fontSize: 18), textAlign: TextAlign.center),
        ),
      );
    } else if (!_isInitialized) {
      content = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.green),
            SizedBox(height: 24),
            Text('INITIALIZING ANALYZER...', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ],
        ),
      );
    } else {
      content = ValueListenableBuilder<int>(
        valueListenable: _selectedIndex,
        builder: (context, index, _) {
          return IndexedStack(
            index: index,
            children: [
              DashboardPage(activeIndex: _selectedIndex),
              SpectrogramPage(activeIndex: _selectedIndex),
              SplMeterPage(activeIndex: _selectedIndex),
              RtaPage(activeIndex: _selectedIndex),
              Rt60Page(activeIndex: _selectedIndex),
              RastiPage(activeIndex: _selectedIndex),
            ],
          );
        },
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: _selectedIndex,
      builder: (context, index, _) {
        return Scaffold(
          backgroundColor: _cal.isWhiteDesign ? Colors.white : const Color(0xFF0A0A0A),
          appBar: AppBar(
            title: Text(
              switch (index) {
                0 => 'DASHBOARD',
                1 => 'SPECTROGRAM',
                2 => 'SOUND LEVEL METER',
                3 => 'REAL TIME ANALYZER',
                4 => 'REVERBERATION TIME',
                5 => 'INTELLIGIBILITY',
                _ => '',
              },
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16),
            ),
            backgroundColor: _cal.isWhiteDesign 
              ? (switch (index) {
                  0 => Colors.blue[50],
                  1 => Colors.cyan[50],
                  2 => Colors.green[50],
                  3 => Colors.orange[50],
                  4 => Colors.red[50],
                  5 => Colors.deepPurple[50],
                  _ => Colors.grey[200],
                })
              : const Color(0xFF1A1A1A),
            foregroundColor: _cal.isWhiteDesign 
              ? (switch (index) {
                  0 => Colors.blue[700],
                  1 => Colors.cyan[800],
                  2 => Colors.green[800],
                  3 => Colors.orange[900],
                  4 => Colors.red[800],
                  5 => Colors.deepPurple[800],
                  _ => Colors.blue,
                })
              : Colors.greenAccent,
            elevation: 2,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsPage())).then((_) => setState(() {})),
              ),
            ],
          ),
          drawer: _buildDrawer(),
          body: Column(
            children: [
              _buildSecondaryStatusBar(),
              Expanded(child: content),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _cal.isWhiteDesign ? Colors.grey[300]! : Colors.white10)),
              boxShadow: _cal.isWhiteDesign ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)] : null,
            ),
            child: Theme(
              data: _cal.isWhiteDesign ? ThemeData.light() : ThemeData.dark().copyWith(canvasColor: const Color(0xFF1A1A1A)),
              child: BottomNavigationBar(
                currentIndex: index,
                backgroundColor: _cal.isWhiteDesign ? Colors.white : const Color(0xFF1A1A1A),
                selectedItemColor: _cal.isWhiteDesign 
                  ? (switch (index) {
                      0 => Colors.blue[700],
                      1 => Colors.cyan[700],
                      2 => Colors.green[700],
                      3 => Colors.orange[800],
                      4 => Colors.red[700],
                      5 => Colors.deepPurple[700],
                      _ => Colors.blue[700],
                    })
                  : Colors.greenAccent,
                unselectedItemColor: _cal.isWhiteDesign ? Colors.black38 : Colors.white24,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                unselectedLabelStyle: const TextStyle(fontSize: 9),
                onTap: (newIndex) => _selectedIndex.value = newIndex,
                items: [
                  _navItem(Icons.dashboard_outlined, 'HOME', Colors.blue, index == 0),
                  _navItem(Icons.waves, 'SPECTRO', Colors.cyan, index == 1),
                  _navItem(Icons.speed, 'SLM', Colors.green, index == 2),
                  _navItem(Icons.bar_chart, 'RTA', Colors.orange, index == 3),
                  _navItem(Icons.timer_outlined, 'RT60', Colors.red, index == 4),
                  _navItem(Icons.record_voice_over, 'RASTI', Colors.deepPurple, index == 5),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  BottomNavigationBarItem _navItem(IconData icon, String label, Color col, bool active) {
    return BottomNavigationBarItem(
      icon: Icon(icon, color: active && _cal.isWhiteDesign ? col : null),
      label: label,
    );
  }

  Widget _buildSecondaryStatusBar() {
    return Container(
      height: 24,
      width: double.infinity,
      color: _cal.isWhiteDesign ? Colors.grey[300] : const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _statusItem(Icons.sd_storage, '82% FREE'),
          _statusItem(Icons.settings_input_antenna, '${kSampleRate.toInt()} Hz'),
          _statusItem(Icons.battery_4_bar, '78%'),
        ],
      ),
    );
  }

  Widget _statusItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 10, color: _cal.isWhiteDesign ? Colors.black26 : Colors.white24),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black26 : Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: _cal.isWhiteDesign ? Colors.white : const Color(0xFF1A1A1A),
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: _cal.isWhiteDesign 
                ? LinearGradient(colors: [Colors.blue[700]!, Colors.blue[400]!], begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
              color: _cal.isWhiteDesign ? null : const Color(0xFF0A0A0A),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Acoustic Analyzer', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Professional Edition', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _drawerItem(Icons.folder_open, 'Measurement Projects (${_cal.projects.length})', () => _showProjectsDialog()),
                _drawerItem(Icons.file_download, 'Export Data (CSV)', () {
                  final csv = _cal.exportToCSV();
                  debugPrint(csv);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV Data Exported to Debug Console')));
                }),
                Divider(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
                _drawerItem(Icons.tune, 'Global Settings', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsPage())).then((_) => setState(() {}));
                }),
                _drawerItem(Icons.info_outline, 'System Diagnostic', () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProjectsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cal.isWhiteDesign ? Colors.white : const Color(0xFF1A1A1A),
        title: Text('SAVED PROJECTS', style: TextStyle(color: _cal.isWhiteDesign ? Colors.blue[800] : Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _cal.projects.length,
            itemBuilder: (c, i) {
              final p = _cal.projects[i];
              return ListTile(
                title: Text('${p.db.toStringAsFixed(1)} dB(${p.weighting})', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black87 : Colors.white)),
                subtitle: Text(p.timestamp.toString().substring(0, 19), style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white24, fontSize: 10)),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('CLOSE', style: TextStyle(color: _cal.isWhiteDesign ? Colors.blue[700] : Colors.greenAccent)))],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: _cal.isWhiteDesign ? Colors.blue[700] : Colors.greenAccent),
      title: Text(title, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black87 : Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

class SpectrogramPage extends StatefulWidget {
  final ValueListenable<int> activeIndex;
  const SpectrogramPage({super.key, required this.activeIndex});
  @override State<SpectrogramPage> createState() => _SpectrogramPageState();
}

class _SpectrogramPageState extends State<SpectrogramPage> {
  final List<Float32List> _history = [];
  static const int _maxHistory = 150;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted || widget.activeIndex.value != 1) return;
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      if (fft.isNotEmpty) {
        setState(() {
          _history.insert(0, Float32List.fromList(fft));
          if (_history.length > _maxHistory) _history.removeLast();
        });
      }
    });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: RepaintBoundary(
        child: CustomPaint(painter: SpectrogramPainter(history: _history), size: Size.infinite),
      ),
    );
  }
}

class SplMeterPage extends StatefulWidget {
  final ValueListenable<int> activeIndex;
  const SplMeterPage({super.key, required this.activeIndex});
  @override State<SplMeterPage> createState() => _SplMeterPageState();
}

class _SplMeterPageState extends State<SplMeterPage> {
  double _db = -100.0;
  double _peak = -100.0;
  Timer? _timer;
  final _cal = Manager.instance;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || (widget.activeIndex.value != 2 && widget.activeIndex.value != 0)) return;
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      final current = _cal.calculateSpl(fft, kSampleRate);
      setState(() {
        _db = current;
        if (current > _peak) _peak = current;
      });
    });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  void _resetPeak() {
    setState(() => _peak = -100.0);
    _cal.resetAveraging();
  }

  void _showCalibrationDialog() {
    final controller = TextEditingController(text: _cal.referenceOffset.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('CALIBRATION SETTINGS', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller, style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reference Offset (dB)', labelStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                final dbfs = _db - _cal.referenceOffset;
                final newOffset = 94.0 - dbfs;
                setState(() {
                  _cal.referenceOffset = newOffset;
                  controller.text = newOffset.toStringAsFixed(1);
                });
              },
              icon: const Icon(Icons.auto_fix_high), label: const Text('AUTO-CALIBRATE TO 94.0 dB'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () {
            _cal.referenceOffset = double.tryParse(controller.text) ?? _cal.referenceOffset;
            Navigator.pop(context);
          }, child: const Text('SAVE', style: TextStyle(color: Colors.greenAccent))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double normalized = ((_db - 30) / (120 - 30)).clamp(0.0, 1.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 10),
          _buildTopConfig(),
          const SizedBox(height: 20),
          _buildMainDisplay(),
          const SizedBox(height: 20),
          _buildProfessionalMeter(normalized),
          const SizedBox(height: 20),
          _buildStatsGrid(),
          const SizedBox(height: 20),
          _buildActionFooter(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTopConfig() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _configBadge('WEIGHTING', _cal.currentWeighting.name.toUpperCase(), () {
          setState(() {
            int next = (_cal.currentWeighting.index + 1) % WeightingType.values.length;
            _cal.currentWeighting = WeightingType.values[next];
          });
        }),
        _configBadge('TIME', _cal.currentTimeWeighting.name.toUpperCase(), () {
          setState(() {
            int next = (_cal.currentTimeWeighting.index + 1) % 2;
            _cal.currentTimeWeighting = TimeWeighting.values[next];
          });
        }),
      ],
    );
  }

  Widget _configBadge(String label, String val, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _cal.isWhiteDesign ? Colors.grey[100] : const Color(0xFF151515),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white24, fontSize: 8, fontWeight: FontWeight.bold)),
          Text(val, style: TextStyle(color: _cal.isWhiteDesign ? Colors.blue : Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  Widget _buildMainDisplay() {
    return Column(children: [
      Text(_db.toStringAsFixed(1), style: TextStyle(color: _cal.isWhiteDesign ? Colors.blue : Colors.greenAccent, fontSize: 110, fontWeight: FontWeight.w900, fontFamily: 'monospace', letterSpacing: -5)),
      Text('L${_cal.currentWeighting.name.toUpperCase()}${_cal.currentTimeWeighting.name.substring(0, 1).toUpperCase()}', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black54 : Colors.white70, fontSize: 24, fontWeight: FontWeight.bold)),
      Text('dB', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white12, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildProfessionalMeter(double normalized) {
    return Column(children: [
      Container(
        height: 24, width: double.infinity,
        decoration: BoxDecoration(
          color: _cal.isWhiteDesign ? Colors.grey[200] : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
        ),
        child: Stack(children: [
          FractionallySizedBox(widthFactor: normalized, child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.green, Colors.yellow, Colors.red], stops: [0.6, 0.8, 1.0]), borderRadius: BorderRadius.circular(1)))),
        ]),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('30', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10, fontSize: 10)),
        Text('60', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10, fontSize: 10)),
        Text('90', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10, fontSize: 10)),
        Text('120', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10, fontSize: 10)),
      ])
    ]);
  }

  Widget _buildStatsGrid() {
    final borderColor = _cal.isWhiteDesign ? Colors.black12 : Colors.white10;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cal.isWhiteDesign ? Colors.grey[100] : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_statItem('Lmax', _peak), _statItem('Leq', _cal.getLeq())]),
        Divider(color: borderColor, height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_statItem('L10', _cal.getPercentile(10)), _statItem('L50', _cal.getPercentile(50)), _statItem('L90', _cal.getPercentile(90))]),
      ]),
    );
  }

  Widget _statItem(String label, double val) {
    return Column(children: [
      Text(label, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
      Text(val > -100 ? val.toStringAsFixed(1) : '---', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
    ]);
  }

  Widget _buildActionFooter() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _footerBtn('RESET', Icons.refresh, _resetPeak, Colors.orangeAccent),
      _footerBtn('CAL', Icons.tune, _showCalibrationDialog, Colors.greenAccent),
      _footerBtn('CAPTURE', Icons.camera_alt, () {
        _cal.saveCurrentMeasurement(_db);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Measurement Captured')));
      }, Colors.blueAccent),
    ]);
  }

  Widget _footerBtn(String label, IconData icon, VoidCallback onTap, Color col) {
    return OutlinedButton.icon(
      onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
      style: OutlinedButton.styleFrom(foregroundColor: col, side: BorderSide(color: col.withValues(alpha: 0.2)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    );
  }
}

class RtaPage extends StatefulWidget {
  final ValueListenable<int> activeIndex;
  const RtaPage({super.key, required this.activeIndex});
  @override State<RtaPage> createState() => _RtaPageState();
}

class _RtaPageState extends State<RtaPage> {
  Timer? _timer;
  final _cal = Manager.instance;
  final List<double> _maxHold = List.filled(31, -100.0);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || widget.activeIndex.value != 3) return;
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      _cal.calculateSpl(fft, kSampleRate);
      setState(() {
        for (int i = 0; i < _cal.octaveBands.length; i++) {
          if (_cal.octaveBands[i].value > _maxHold[i]) _maxHold[i] = _cal.octaveBands[i].value;
        }
      });
    });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildRtaControls(),
      Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: CustomPaint(painter: RtaPainter(bands: _cal.octaveBands, maxHold: _maxHold, reference: _cal.isReferenceVisible ? _cal.referenceSpectrum : null), size: Size.infinite))),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildRtaControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          _smallBtn('1/3', _cal.octaveResolution == OctaveResolution.oneThird, () => setState(() => _cal.octaveResolution = OctaveResolution.oneThird)),
          const SizedBox(width: 4),
          _smallBtn('1/1', _cal.octaveResolution == OctaveResolution.oneFull, () => setState(() => _cal.octaveResolution = OctaveResolution.oneFull)),
        ]),
        Row(children: [
          IconButton(icon: Icon(Icons.bookmark_border, color: _cal.isReferenceVisible ? Colors.greenAccent : Colors.white24), onPressed: () => setState(() => _cal.isReferenceVisible = !_cal.isReferenceVisible)),
          IconButton(icon: const Icon(Icons.camera_alt_outlined, color: Colors.blueAccent), onPressed: () => setState(() => _cal.saveReference())),
          IconButton(onPressed: () => setState(() => _maxHold.fillRange(0, 31, -100.0)), icon: const Icon(Icons.refresh, color: Colors.orangeAccent)),
        ]),
      ]),
    );
  }

  Widget _smallBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: active ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.transparent, borderRadius: BorderRadius.circular(4)), child: Text(label, style: TextStyle(color: active ? Colors.greenAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold))),
    );
  }
}

class SpectrogramPainter extends CustomPainter {
  final List<Float32List> history;
  final _cal = Manager.instance;
  
  // Cache for calibration gains to avoid repeated heavy math
  static Float32List? _gainCache;
  
  SpectrogramPainter({required this.history});

  void _updateGainCache(double binWidth) {
    _gainCache = Float32List(256);
    for (int i = 0; i < 256; i++) {
      final freq = i * binWidth;
      final offset = _cal.getOffsetForFrequency(freq);
      _gainCache![i] = math.pow(10, offset / 20.0).toDouble();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    
    const double labelWidth = 55.0;
    final double drawingWidth = size.width - labelWidth;
    final double stepX = drawingWidth / history.length;
    final double stepY = size.height / 256;
    final double binWidth = (kSampleRate / 2.0) / 256.0;

    if (_gainCache == null) _updateGainCache(binWidth);

    final paint = Paint();

    for (int t = 0; t < history.length; t++) {
      final fft = history[t];
      final double x = labelWidth + drawingWidth - (t * stepX) - stepX;
      
      for (int f = 0; f < 256; f++) {
        // Boost quiet sounds using power-law scaling (Gamma correction)
        // Magnitude 0.4 power significantly increases sensitivity to low-level signals
        final double rawMagnitude = (fft[f] * _gainCache![f]).clamp(0.0, 1.0);
        final double magnitude = math.pow(rawMagnitude, 0.4).toDouble();
        
        paint.color = _getHeatmapColor(magnitude);

        canvas.drawRect(
          Rect.fromLTWH(x, size.height - (f * stepY) - stepY, stepX + 0.5, stepY + 0.5),
          paint,
        );
      }
    }

    final textStyle = TextStyle(color: _cal.isWhiteDesign ? Colors.black54 : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold);
    final List<int> labels = [100, 500, 1000, 2000, 5000, 10000, 15000, 20000];
    for (final hz in labels) {
      final double y = size.height - (hz / (kSampleRate / 2.0) * size.height);
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), Paint()..color = _cal.isWhiteDesign ? Colors.black.withValues(alpha: 0.05) : Colors.white10);
      TextPainter(text: TextSpan(text: hz >= 1000 ? '${(hz / 1000).toStringAsFixed(0)}k' : '$hz', style: textStyle), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(labelWidth - 45, y - 6));
    }
  }

  Color _getHeatmapColor(double magnitude) {
    if (magnitude < 0.05) return Colors.black;
    if (magnitude < 0.25) return Color.lerp(Colors.black, Colors.blue, (magnitude - 0.05) / 0.2)!;
    if (magnitude < 0.5) return Color.lerp(Colors.blue, Colors.green, (magnitude - 0.25) / 0.25)!;
    if (magnitude < 0.75) return Color.lerp(Colors.green, Colors.yellow, (magnitude - 0.5) / 0.25)!;
    return Color.lerp(Colors.yellow, Colors.red, (magnitude - 0.75) / 0.25)!;
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class RtaPainter extends CustomPainter {
  final List<OctaveBand> bands;
  final List<double> maxHold;
  final List<double>? reference;
  final _cal = Manager.instance;
  RtaPainter({required this.bands, required this.maxHold, this.reference});

  @override
  void paint(Canvas canvas, Size size) {
    const double labelHeight = 32.0;
    const double labelWidth = 40.0;
    final double chartHeight = size.height - labelHeight;
    final double chartWidth = size.width - labelWidth;
    final bool isFullOctave = _cal.octaveResolution == OctaveResolution.oneFull;
    final List<int> indices = [];
    if (isFullOctave) { for (int i = 2; i < bands.length; i += 3) indices.add(i); } else { for (int i = 0; i < bands.length; i++) indices.add(i); }
    final double barWidth = chartWidth / indices.length;

    // 1. Draw Professional Background Grid
    final gridPaint = Paint()..color = (_cal.isWhiteDesign ? Colors.black : Colors.white).withValues(alpha: 0.05)..strokeWidth = 1;
    for (int db = 30; db <= 120; db += 10) {
      final double y = chartHeight - ((db - 30) / (120 - 30) * chartHeight);
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), gridPaint);
      TextPainter(
        text: TextSpan(text: '$db', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black26 : Colors.white24, fontSize: 8, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout()..paint(canvas, Offset(8, y - 6));
    }

    // 2. Draw Bars
    for (int j = 0; j < indices.length; j++) {
      int i = indices[j];
      final double x = labelWidth + (j * barWidth);
      
      if (reference != null) {
        final double refH = ((reference![i] - 30) / (120 - 30) * chartHeight).clamp(0.0, chartHeight);
        canvas.drawLine(Offset(x, chartHeight - refH), Offset(x + barWidth, chartHeight - refH), Paint()..color = _cal.isWhiteDesign ? Colors.black12 : Colors.white12);
      }
      final double h = ((bands[i].value - 30) / (120 - 30) * chartHeight).clamp(0.0, chartHeight);
      canvas.drawRect(Rect.fromLTWH(x + 1.5, chartHeight - h, barWidth - 3, h), Paint()..color = _getBarColor(bands[i].value).withValues(alpha: 0.8));
      final double maxH = ((maxHold[i] - 30) / (120 - 30) * chartHeight).clamp(0.0, chartHeight);
      canvas.drawLine(Offset(x + 1.5, chartHeight - maxH), Offset(x + barWidth - 1.5, chartHeight - maxH), Paint()..color = Colors.redAccent..strokeWidth = 2);
      if (isFullOctave || (j % 3 == 0) || j == indices.length - 1) {
        final label = bands[i].centerFreq >= 1000 ? '${(bands[i].centerFreq / 1000).toInt()}k' : bands[i].centerFreq.toInt().toString();
        TextPainter(text: TextSpan(text: label, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white38, fontSize: 8, fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(x + (barWidth - 40) / 2, chartHeight + 8));
      }
    }
  }

  Color _getBarColor(double db) => db < 60 ? Colors.blueGrey : (db < 85 ? Colors.greenAccent : (db < 105 ? Colors.yellowAccent : Colors.redAccent));
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DecayCurvePainter extends CustomPainter {
  final List<double> data;
  final _cal = Manager.instance;
  DecayCurvePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    const double leftMargin = 40.0;
    const double bottomMargin = 30.0;
    final double chartWidth = size.width - leftMargin - 10;
    final double chartHeight = size.height - bottomMargin - 10;

    final bgColor = _cal.isWhiteDesign ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05);
    final labelStyle = TextStyle(color: _cal.isWhiteDesign ? Colors.black54 : Colors.white54, fontSize: 8);

    // 1. Draw Background Grid & Axis
    final gridPaint = Paint()..color = bgColor..strokeWidth = 1;
    const double minDb = -90.0;
    const double maxDb = 0.0;

    for (double db = minDb; db <= maxDb; db += 30) {
      final y = 10 + chartHeight - ((db - minDb) / (maxDb - minDb) * chartHeight);
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - 10, y), gridPaint);
      
      // Y-Axis Labels (dB)
      TextPainter(
        text: TextSpan(text: '${db.toInt()}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout()..paint(canvas, Offset(leftMargin - 25, y - 5));
    }
    
    // X-Axis Labels (Time)
    for (double t = 0; t <= 1.5; t += 0.5) {
      final x = leftMargin + (t / 1.5 * chartWidth);
      TextPainter(
        text: TextSpan(text: '${t}s', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout()..paint(canvas, Offset(x - 10, size.height - bottomMargin + 5));
    }

    // Axis Titles
    TextPainter(text: TextSpan(text: 'dB', style: labelStyle.copyWith(fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, const Offset(5, 5));
    TextPainter(text: TextSpan(text: 'TIME', style: labelStyle.copyWith(fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(size.width - 40, size.height - bottomMargin + 5));

    if (data.isEmpty) return;

    // 2. Draw Decay Curve
    final paint = Paint()
      ..color = _cal.isWhiteDesign ? Colors.blue : Colors.blueAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final int count = data.length;
    for (int i = 0; i < count; i++) {
      final x = leftMargin + (i / math.max(1.0, count.toDouble()) * chartWidth);
      final val = data[i].clamp(minDb, maxDb);
      final y = 10 + chartHeight - ((val - minDb) / (maxDb - minDb) * chartHeight);
      
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DecayCurvePainter oldDelegate) => true;
}

class Rt60Page extends StatefulWidget {
  final ValueListenable<int> activeIndex;
  const Rt60Page({super.key, required this.activeIndex});
  @override State<Rt60Page> createState() => _Rt60PageState();
}

class _Rt60PageState extends State<Rt60Page> {
  Timer? _timer;
  final _cal = Manager.instance;
  String _status = 'READY';
  double? _rt60, _edt, _t30;
  bool _isListening = false;
  bool _isSweeping = false;
  
  // High-resolution capture: (Timestamp in ms, Level in dB)
  final List<(int, double)> _captureBuffer = [];
  List<double> _chartData = [];
  final Stopwatch _stopwatch = Stopwatch();

  void _toggleListening() {
    setState(() {
      _isListening = !_isListening;
      if (_isListening) {
        _status = 'LISTENING...';
        _rt60 = null; _edt = null; _t30 = null;
        _captureBuffer.clear();
        _chartData = [];
        _startMonitoring();
      } else {
        _status = 'READY';
        _timer?.cancel();
        _stopwatch.stop();
      }
    });
  }

  void _startMonitoring() {
    _stopwatch.reset();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (!mounted) return;
      final db = Recorder.instance.getVolumeDb();
      if (db > -25.0) {
        timer.cancel();
        _recordDecay();
      }
    });
  }

  void _recordDecay() {
    setState(() { _status = 'RECORDING DECAY...'; _captureBuffer.clear(); });
    _stopwatch.reset();
    _stopwatch.start();
    
    _timer = Timer.periodic(const Duration(milliseconds: 5), (timer) {
      final db = Recorder.instance.getVolumeDb();
      final ms = _stopwatch.elapsedMilliseconds;
      _captureBuffer.add((ms, db));
      
      if (ms > 2000) { // Record 2 seconds
        timer.cancel();
        _stopwatch.stop();
        _processCapture();
      }
      setState(() {});
    });
  }

  Future<void> _runSweepTest() async {
    setState(() {
      _isSweeping = true;
      _status = 'PREPARING SWEEP...';
      _rt60 = null;
      _captureBuffer.clear();
      _chartData = [];
    });

    try {
      if (!SoLoud.instance.isInitialized) {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.measurement,
          androidAudioAttributes: AndroidAudioAttributes(
            usage: AndroidAudioUsage.media,
            contentType: AndroidAudioContentType.music,
          ),
        ));
        await session.setActive(true);
        await SoLoud.instance.init(channels: Channels.mono, sampleRate: 44100);
      }

      const double sweepDuration = 3.0;
      const int sampleRate = 44100;
      const double f1 = 20.0;
      const double f2 = 22050.0; // Full sample rate range (Nyquist limit)
      final int numSamples = (sweepDuration * sampleRate).toInt();
      final floatData = Float32List(numSamples);

      final double lnRatio = math.log(f2 / f1);
      for (int i = 0; i < numSamples; i++) {
        final double t = i / sampleRate;
        final double phase = (2.0 * math.pi * f1 * sweepDuration / lnRatio) * 
                           (math.exp(t / sweepDuration * lnRatio) - 1.0);
        double val = math.sin(phase);
        const int fadeSamples = 2205; 
        if (i < fadeSamples) val *= (0.5 * (1.0 - math.cos(math.pi * i / fadeSamples)));
        if (i > numSamples - fadeSamples) val *= (0.5 * (1.0 - math.cos(math.pi * (numSamples - i) / fadeSamples)));
        floatData[i] = val.toDouble();
      }

      final sound = SoLoud.instance.setBufferStream(
        sampleRate: sampleRate,
        channels: Channels.mono,
        format: BufferType.f32le,
        maxBufferSizeBytes: floatData.lengthInBytes,
      );

      SoLoud.instance.addAudioDataStream(sound, floatData.buffer.asUint8List());
      SoLoud.instance.setDataIsEnded(sound);

      // Start Recording for the duration of the sweep + 3s tail
      _captureBuffer.clear();
      _stopwatch.reset();
      _stopwatch.start();
      _timer = Timer.periodic(const Duration(milliseconds: 5), (t) {
        _captureBuffer.add((_stopwatch.elapsedMilliseconds, Recorder.instance.getVolumeDb()));
      });

      setState(() => _status = 'PLAYING SWEEP...');
      final handle = SoLoud.instance.play(sound, volume: 1.0);

      await Future.delayed(Duration(milliseconds: (sweepDuration * 1000).toInt()));
      SoLoud.instance.stop(handle);
      SoLoud.instance.disposeSource(sound);
      
      setState(() => _status = 'CAPTURING TAIL...');
      await Future.delayed(const Duration(milliseconds: 2500));
      
      _timer?.cancel();
      _stopwatch.stop();
      _processCapture();
      
      setState(() {
        _isSweeping = false;
        _status = 'MEASUREMENT COMPLETE';
      });
    } catch (e) {
      setState(() {
        _isSweeping = false;
        _status = 'SWEEP ERROR: $e';
      });
    }
  }

  void _processCapture() {
    if (_captureBuffer.isEmpty) return;

    // 1. Find the termination of excitation
    // For sweeps, the level is constant, so we need the LAST peak
    double maxLvl = -100;
    for (var p in _captureBuffer) { if (p.$2 > maxLvl) maxLvl = p.$2; }
    
    int lastLoudIndex = 0;
    for (int i = 0; i < _captureBuffer.length; i++) {
      if (_captureBuffer[i].$2 > maxLvl - 3.0) lastLoudIndex = i;
    }

    // 2. Extract the tail (starting 30ms after excitation stops to clear hardware lag)
    int decayStartIndex = math.min(lastLoudIndex + 6, _captureBuffer.length - 1);
    final tail = _captureBuffer.sublist(decayStartIndex);
    if (tail.length < 25) return;

    // 3. Robust Noise Floor (Last 10% of tail)
    int noiseStart = (tail.length * 0.9).toInt();
    double noiseEnergySum = 0;
    for (int i = noiseStart; i < tail.length; i++) {
      noiseEnergySum += math.pow(10, tail[i].$2 / 10);
    }
    double noiseFloorEnergy = noiseEnergySum / (tail.length - noiseStart);

    // 4. Schroeder Integration (Noise-Compensated EDC)
    final List<double> energy = tail.map((p) => math.max(math.pow(10, p.$2 / 10) - noiseFloorEnergy, 1e-12).toDouble()).toList();
    final List<double> edc = List.filled(energy.length, 0.0);
    double backwardSum = 0;
    for (int i = energy.length - 1; i >= 0; i--) {
      backwardSum += energy[i];
      edc[i] = backwardSum;
    }
    
    final double maxEnergy = edc[0];
    final List<double> edcDb = edc.map((e) => 10.0 * math.log(math.max(e / maxEnergy, 1e-10)) / math.ln10).toList();

    // 5. Precise Linear Regression on EDC
    double calculateT(double startDrop, double endDrop) {
      int iStart = -1, iEnd = -1;
      for (int i = 0; i < edcDb.length; i++) {
        if (iStart == -1 && edcDb[i] <= -startDrop) iStart = i;
        if (iEnd == -1 && edcDb[i] <= -endDrop) iEnd = i;
      }
      if (iStart == -1 || iEnd == -1 || iEnd <= iStart) return 0.0;

      double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
      int count = 0;
      final int startMs = tail[iStart].$1;
      for (int i = iStart; i <= iEnd; i++) {
        double x = (tail[i].$1 - startMs) / 1000.0; // Accurate time from Stopwatch
        double y = edcDb[i];
        sumX += x; sumY += y; sumXY += x * y; sumXX += x * x;
        count++;
      }
      if (count < 5) return 0.0;
      double slope = (count * sumXY - sumX * sumY) / (count * sumXX - sumX * sumX);
      return slope >= 0 ? 0.0 : (60.0 / slope.abs());
    }

    setState(() {
      _chartData = edcDb;
      _edt = calculateT(0, 10);
      _rt60 = calculateT(5, 25);
      _t30 = calculateT(5, 35);
    });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildInfoPanel('ROOM ACOUSTICS', _status),
          const SizedBox(height: 16),
          _buildDecayChart(),
          const SizedBox(height: 24),
          if (_rt60 != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cal.isWhiteDesign ? Colors.grey[100] : const Color(0xFF151515),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [_miniMetric('EDT', _edt), _miniMetric('T20', _rt60), _miniMetric('T30', _t30)],
              ),
            ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: _buildActionButton(_isListening ? 'STOP' : 'IMPULSE TEST', _isListening ? Colors.redAccent : Colors.blueAccent, _toggleListening)),
              const SizedBox(width: 12),
              Expanded(child: _buildActionButton(_isSweeping ? 'SWEEPING...' : 'SWEEP TEST', _isSweeping ? Colors.orangeAccent : Colors.greenAccent, _isSweeping ? () {} : _runSweepTest)),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDecayChart() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cal.isWhiteDesign ? Colors.grey[100] : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
      ),
      child: CustomPaint(
        painter: DecayCurvePainter(data: _chartData),
      ),
    );
  }

  Widget _buildInfoPanel(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cal.isWhiteDesign ? Colors.grey[100] : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: _cal.isWhiteDesign ? Colors.blue : Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, double? val) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white24, fontSize: 10)),
        Text(
          val != null && val > 0 ? '${val.toStringAsFixed(2)}s' : '---',
          style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, Color col, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: col.withValues(alpha: 0.1),
        foregroundColor: col,
        side: BorderSide(color: col.withValues(alpha: 0.4)),
        minimumSize: const Size(double.infinity, 60),
      ),
      child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }
}

class RastiPage extends StatefulWidget {
  final ValueListenable<int> activeIndex;
  const RastiPage({super.key, required this.activeIndex});
  @override State<RastiPage> createState() => _RastiPageState();
}

class _RastiPageState extends State<RastiPage> {
  Timer? _timer;
  final _cal = Manager.instance;
  String _status = 'READY';
  double? _rasti;
  bool _isMeasuring = false;

  void _startMeasurement() {
    setState(() { _isMeasuring = true; _status = 'MEASURING NOISE...'; });
    int count = 0; double noiseSum = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (widget.activeIndex.value != 5) { timer.cancel(); return; }
      noiseSum += Recorder.instance.getVolumeDb();
      if (++count >= 20) { timer.cancel(); _listenForImpulse(noiseSum / 20); }
    });
  }

  void _listenForImpulse(double noiseFloor) {
    setState(() => _status = 'WAIT FOR CLAP...');
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (Recorder.instance.getVolumeDb() > noiseFloor + 25) { timer.cancel(); _recordDecay(noiseFloor, Recorder.instance.getVolumeDb()); }
    });
  }

  void _recordDecay(double noiseFloor, double peakDb) {
    setState(() => _status = 'ANALYZING DECAY...');
    final List<double> decay = [];
    final DateTime start = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      decay.add(Recorder.instance.getVolumeDb());
      if (DateTime.now().difference(start).inMilliseconds > 1200) { timer.cancel(); _computeRasti(decay, noiseFloor, peakDb); }
    });
  }

  void _computeRasti(List<double> decay, double noiseFloor, double peakDb) {
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    int n = math.min(50, decay.length);
    for (int i = 0; i < n; i++) { sumX += i; sumY += decay[i]; sumXY += i * decay[i]; sumXX += i * i; }
    double slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    double rt60 = (60.0 / slope.abs()) * 0.01;
    double snr = peakDb - noiseFloor;
    double tiSum = 0;
    for (double fm in [0.7, 1.0, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.2]) {
      double mRev = 1.0 / math.sqrt(1.0 + math.pow(2 * math.pi * fm * rt60 / 13.8, 2));
      double mNoise = 1.0 / (1.0 + math.pow(10, -snr / 10.0));
      double snrApp = 10.0 * math.log((mRev * mNoise) / (1.0 - mRev * mNoise).clamp(0.0001, 1.0)) / math.ln10;
      tiSum += ((snrApp + 15.0) / 30.0).clamp(0.0, 1.0);
    }
    setState(() { _rasti = tiSum / 9; _isMeasuring = false; _status = 'COMPLETE'; });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildInfoPanel('SPEECH TRANSMISSION INDEX (RASTI)', _status),
          const SizedBox(height: 60),
          if (_rasti != null) _buildRastiGauge(),
          const SizedBox(height: 60),
          _buildActionButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cal.isWhiteDesign ? Colors.grey[100] : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: _cal.isWhiteDesign ? Colors.purple : Colors.purpleAccent, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildRastiGauge() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: CircularProgressIndicator(
                value: _rasti,
                strokeWidth: 20,
                backgroundColor: _cal.isWhiteDesign ? Colors.grey[200] : const Color(0xFF1A1A1A),
                color: _getRastiColor(_rasti!),
              ),
            ),
            Text(
              _rasti!.toStringAsFixed(2),
              style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white, fontSize: 48, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          _getRastiQuality(_rasti!).toUpperCase(),
          style: TextStyle(color: _getRastiColor(_rasti!), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 4),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final col = Colors.purpleAccent;
    return ElevatedButton(
      onPressed: _isMeasuring ? null : _startMeasurement,
      style: ElevatedButton.styleFrom(
        backgroundColor: col.withValues(alpha: 0.1),
        foregroundColor: _cal.isWhiteDesign ? Colors.purple : col,
        side: BorderSide(color: col.withValues(alpha: 0.4)),
        minimumSize: const Size(double.infinity, 60),
      ),
      child: Text(_isMeasuring ? 'MEASURING...' : 'RUN RASTI TEST', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }
  Color _getRastiColor(double val) => val < 0.3 ? Colors.red : (val < 0.45 ? Colors.orange : (val < 0.6 ? Colors.yellow : (val < 0.75 ? Colors.lightGreen : Colors.greenAccent)));
  String _getRastiQuality(double val) => val < 0.3 ? "Bad" : (val < 0.45 ? "Poor" : (val < 0.6 ? "Fair" : (val < 0.75 ? "Good" : "Excellent")));
}

class DashboardPage extends StatefulWidget {
  final ValueListenable<int> activeIndex;
  const DashboardPage({super.key, required this.activeIndex});
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _timer;
  final _cal = Manager.instance;
  double _db = -100.0;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || widget.activeIndex.value != 0) return;
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      setState(() => _db = _cal.calculateSpl(fft, kSampleRate));
    });
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 24),
          Text('SYSTEM OVERVIEW', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black26 : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 12),
          _quickGrid(),
        ],
      ),
    );
  }
  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _cal.isWhiteDesign ? [Colors.grey[100]!, Colors.white] : [const Color(0xFF1A1A1A), const Color(0xFF0A0A0A)],
          begin: Alignment.topLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (_cal.isWhiteDesign ? Colors.blue : Colors.greenAccent).withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text('CURRENT LEVEL', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${_db.toStringAsFixed(1)}',
            style: TextStyle(color: _cal.isWhiteDesign ? Colors.blue : Colors.greenAccent, fontSize: 80, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
          ),
          Text(
            'dB(${_cal.currentWeighting.name.toUpperCase()})',
            style: TextStyle(color: _cal.isWhiteDesign ? Colors.black54 : Colors.white54, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _quickGrid() {
    return GridView.count(
      crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
      children: [
        _smallStat('Leq', '${_cal.getLeq().toStringAsFixed(1)} dB'),
        _smallStat('Lmax', '${_cal.getPercentile(0).toStringAsFixed(1)} dB'),
        _smallStat('Weighting', _cal.currentWeighting.name.toUpperCase()),
        _smallStat('Sample Rate', '${kSampleRate.toInt()} Hz'),
      ],
    );
  }

  Widget _smallStat(String label, String val) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cal.isWhiteDesign ? Colors.grey[100] : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cal.isWhiteDesign ? Colors.black12 : Colors.white10),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black38 : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _cal = Manager.instance;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cal.isWhiteDesign ? Colors.white : const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('SYSTEM SETTINGS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)), 
        backgroundColor: _cal.isWhiteDesign ? Colors.grey[200] : const Color(0xFF1A1A1A), 
        foregroundColor: _cal.isWhiteDesign ? Colors.blue : Colors.greenAccent
      ),
      body: ListView(children: [
        _section('VISUAL DESIGN'),
        SwitchListTile(
          title: Text('White Design', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white)),
          subtitle: const Text('Light theme for outdoor readability'),
          value: _cal.isWhiteDesign,
          activeColor: Colors.blue,
          onChanged: (v) => setState(() => _cal.isWhiteDesign = v),
        ),
        _section('MEASUREMENT CONFIG'), 
        _settingTile('Frequency Weighting', _cal.currentWeighting.name.toUpperCase(), () {}), 
        _settingTile('Time Weighting', _cal.currentTimeWeighting.name.toUpperCase(), () {}), 
        SwitchListTile(title: Text('Free-field Correction', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white)), value: _cal.isFreeFieldCorrectionEnabled, activeColor: _cal.isWhiteDesign ? Colors.blue : Colors.greenAccent, onChanged: (v) => setState(() => _cal.isFreeFieldCorrectionEnabled = v)), 
        _section('ALARM & LIMITS'), 
        _settingTile('Limit Threshold', '${_cal.limitThreshold} dB', () {}), 
        _section('DATA MANAGEMENT'), 
        ListTile(title: const Text('Clear Measurement History', style: TextStyle(color: Colors.redAccent)), onTap: () => _cal.resetAveraging()), 
        ListTile(title: Text('Auto-save Logs', style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white)), trailing: Switch(value: false, onChanged: (v) {})),
      ]),
    );
  }

  Widget _section(String title) => Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text(title, style: TextStyle(color: _cal.isWhiteDesign ? Colors.grey : Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)));
  Widget _settingTile(String title, String val, VoidCallback onTap) => ListTile(title: Text(title, style: TextStyle(color: _cal.isWhiteDesign ? Colors.black : Colors.white)), subtitle: Text(val, style: TextStyle(color: _cal.isWhiteDesign ? Colors.blue : Colors.greenAccent)), trailing: Icon(Icons.chevron_right, color: _cal.isWhiteDesign ? Colors.black12 : Colors.white24), onTap: onTap);
}
