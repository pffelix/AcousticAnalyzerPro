import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:permission_handler/permission_handler.dart';
import 'calibration_manager.dart';

const double kSampleRate = 44100.0;

void main() {
  runApp(const MaterialApp(
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
  int _selectedIndex = 0;
  bool _isInitialized = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
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
        child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 18)),
      );
    } else if (!_isInitialized) {
      content = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing Recorder...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    } else {
      content = IndexedStack(
        index: _selectedIndex,
        children: const [
          SpectrogramPage(),
          SplMeterPage(),
          RtaPage(),
          Rt60Page(),
          RastiPage(),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(switch (_selectedIndex) {
          0 => 'Spectrogram',
          1 => 'SLM (Sound Level Meter)',
          2 => '1/3 Octave RTA',
          3 => 'RT60 Prediction',
          4 => 'RASTI Calculation',
          _ => '',
        }),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
      ),
      body: content,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: Colors.grey[900],
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.white70,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.waves), label: 'Spectro'),
          BottomNavigationBarItem(icon: Icon(Icons.equalizer), label: 'SLM'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'RTA'),
          BottomNavigationBarItem(icon: Icon(Icons.timer), label: 'RT60'),
          BottomNavigationBarItem(icon: Icon(Icons.record_voice_over), label: 'RASTI'),
        ],
      ),
    );
  }
}

class SpectrogramPage extends StatefulWidget {
  const SpectrogramPage({super.key});

  @override
  State<SpectrogramPage> createState() => _SpectrogramPageState();
}

class _SpectrogramPageState extends State<SpectrogramPage> {
  final List<Float32List> _history = [];
  static const int _maxHistory = 150;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) return;
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      if (fft.isNotEmpty) {
        setState(() {
          _history.insert(0, Float32List.fromList(fft));
          if (_history.length > _maxHistory) {
            _history.removeLast();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: CustomPaint(
        painter: SpectrogramPainter(history: _history),
        size: Size.infinite,
      ),
    );
  }
}

class SplMeterPage extends StatefulWidget {
  const SplMeterPage({super.key});

  @override
  State<SplMeterPage> createState() => _SplMeterPageState();
}

class _SplMeterPageState extends State<SplMeterPage> {
  double _db = -100.0;
  double _peak = -100.0;
  Timer? _timer;
  final _cal = CalibrationManager.instance;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      final current = _cal.calculateSpl(fft, kSampleRate);
      
      setState(() {
        _db = current;
        if (current > _peak) _peak = current;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetPeak() {
    setState(() => _peak = -100.0);
    _cal.resetAveraging();
  }

  void _showCalibrationDialog() {
    final controller = TextEditingController(text: _cal.referenceOffset.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Calibration & Correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reference Offset (dB)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                final dbfs = _db - _cal.referenceOffset;
                final newOffset = 94.0 - dbfs;
                setState(() {
                  _cal.referenceOffset = newOffset;
                  controller.text = newOffset.toStringAsFixed(1);
                });
              },
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Auto-Calibrate to 94.0 dB'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            SwitchListTile(
              title: const Text('Free-field Correction'),
              subtitle: const Text('Compensates for high-frequency pressure build-up.'),
              value: _cal.isFreeFieldCorrectionEnabled,
              onChanged: (val) => setState(() => _cal.isFreeFieldCorrectionEnabled = val),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          TextButton(onPressed: () {
            _cal.referenceOffset = double.tryParse(controller.text) ?? _cal.referenceOffset;
            Navigator.pop(context);
          }, child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double normalized = ((_db - 30) / (120 - 30)).clamp(0.0, 1.0);

    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _weightingToggle(),
                const SizedBox(width: 20),
                _timeWeightingToggle(),
              ],
            ),
            const SizedBox(height: 40),
            Text(
              '${_db.toStringAsFixed(1)}',
              style: const TextStyle(color: Colors.white, fontSize: 90, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
            ),
            Text(
              'dB(${_cal.currentWeighting.name.toUpperCase()}) ${_cal.currentTimeWeighting.name.toUpperCase()}',
              style: const TextStyle(color: Colors.blue, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            _buildMeter(normalized),
            const SizedBox(height: 40),
            _buildStats(),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(onPressed: _resetPeak, icon: const Icon(Icons.refresh), label: const Text('Reset')),
                const SizedBox(width: 20),
                ElevatedButton.icon(onPressed: _showCalibrationDialog, icon: const Icon(Icons.settings), label: const Text('Settings')),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _weightingToggle() {
    return ToggleButtons(
      isSelected: [
        _cal.currentWeighting == WeightingType.z,
        _cal.currentWeighting == WeightingType.a,
        _cal.currentWeighting == WeightingType.c,
      ],
      onPressed: (index) => setState(() => _cal.currentWeighting = WeightingType.values[index]),
      color: Colors.white54,
      selectedColor: Colors.white,
      fillColor: Colors.blue.withOpacity(0.3),
      children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Z')), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('A')), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('C'))],
    );
  }

  Widget _timeWeightingToggle() {
    return ToggleButtons(
      isSelected: [
        _cal.currentTimeWeighting == TimeWeighting.fast,
        _cal.currentTimeWeighting == TimeWeighting.slow,
      ],
      onPressed: (index) => setState(() => _cal.currentTimeWeighting = TimeWeighting.values[index]),
      color: Colors.white54,
      selectedColor: Colors.white,
      fillColor: Colors.orange.withOpacity(0.3),
      children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('FAST')), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('SLOW'))],
    );
  }

  Widget _buildMeter(double normalized) {
    return Container(
      width: 300,
      height: 30,
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(15)),
      child: Stack(
        children: [
          FractionallySizedBox(
            widthFactor: normalized,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.green, Colors.yellow, Colors.red], stops: [0.5, 0.8, 1.0]),
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statItem('Lmax', _peak),
        _statItem('Leq', _cal.getLeq()),
      ],
    );
  }

  Widget _statItem(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
        Text(value > -100 ? value.toStringAsFixed(1) : '---', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class RtaPage extends StatefulWidget {
  const RtaPage({super.key});

  @override
  State<RtaPage> createState() => _RtaPageState();
}

class _RtaPageState extends State<RtaPage> {
  Timer? _timer;
  final _cal = CalibrationManager.instance;
  final List<double> _maxHold = List.filled(31, -100.0);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      _cal.calculateSpl(fft, kSampleRate);
      setState(() {
        for (int i = 0; i < _cal.octaveBands.length; i++) {
          if (_cal.octaveBands[i].value > _maxHold[i]) _maxHold[i] = _cal.octaveBands[i].value;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1/3 Octave RTA (${_cal.currentWeighting.name.toUpperCase()})', style: const TextStyle(color: Colors.white70)),
              IconButton(onPressed: () => setState(() => _maxHold.fillRange(0, 31, -100.0)), icon: const Icon(Icons.refresh, color: Colors.blue)),
            ],
          ),
        ),
        Expanded(child: Padding(padding: const EdgeInsets.all(8.0), child: CustomPaint(painter: RtaPainter(bands: _cal.octaveBands, maxHold: _maxHold), size: Size.infinite))),
      ],
    );
  }
}

class SpectrogramPainter extends CustomPainter {
  final List<Float32List> history;
  final _cal = CalibrationManager.instance;
  SpectrogramPainter({required this.history});

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    const double labelWidth = 55.0;
    final double drawingWidth = size.width - labelWidth;
    final double stepX = drawingWidth / history.length;
    final double stepY = size.height / 256;
    final double binWidth = (kSampleRate / 2.0) / 256.0;

    for (int t = 0; t < history.length; t++) {
      final fft = history[t];
      for (int f = 0; f < fft.length; f++) {
        final freq = f * binWidth;
        final gain = math.pow(10, _cal.getOffsetForFrequency(freq) / 20.0);
        final double magnitude = (fft[f] * gain).clamp(0.0, 1.0);
        canvas.drawRect(Rect.fromLTWH(labelWidth + drawingWidth - (t * stepX) - stepX, size.height - (f * stepY) - stepY, stepX + 0.5, stepY + 0.5), Paint()..color = _getHeatmapColor(magnitude));
      }
    }

    final textStyle = const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold);
    final List<int> labels = [100, 500, 1000, 2000, 5000, 10000, 15000, 20000];
    for (final hz in labels) {
      final double y = size.height - (hz / (kSampleRate / 2.0) * size.height);
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), Paint()..color = Colors.white10);
      TextPainter(text: TextSpan(text: hz >= 1000 ? '${(hz / 1000).toStringAsFixed(0)}k' : '$hz', style: textStyle), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(labelWidth - 45, y - 6));
    }
  }

  Color _getHeatmapColor(double magnitude) {
    if (magnitude < 0.1) return Colors.black;
    if (magnitude < 0.3) return Color.lerp(Colors.black, Colors.blue, (magnitude - 0.1) / 0.2)!;
    if (magnitude < 0.5) return Color.lerp(Colors.blue, Colors.green, (magnitude - 0.3) / 0.2)!;
    if (magnitude < 0.8) return Color.lerp(Colors.green, Colors.yellow, (magnitude - 0.5) / 0.3)!;
    return Color.lerp(Colors.yellow, Colors.red, (magnitude - 0.8) / 0.2)!;
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class RtaPainter extends CustomPainter {
  final List<OctaveBand> bands;
  final List<double> maxHold;
  RtaPainter({required this.bands, required this.maxHold});

  @override
  void paint(Canvas canvas, Size size) {
    const double labelHeight = 30.0;
    const double labelWidth = 40.0;
    final double chartHeight = size.height - labelHeight;
    final double chartWidth = size.width - labelWidth;
    final double barWidth = chartWidth / bands.length;

    for (int db = 30; db <= 120; db += 10) {
      final double y = chartHeight - ((db - 30) / (120 - 30) * chartHeight);
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), Paint()..color = Colors.white10);
      TextPainter(text: TextSpan(text: '$db', style: const TextStyle(color: Colors.white54, fontSize: 8)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(5, y - 5));
    }

    for (int i = 0; i < bands.length; i++) {
      final double x = labelWidth + (i * barWidth);
      final double h = ((bands[i].value - 30) / (120 - 30) * chartHeight).clamp(0, chartHeight);
      canvas.drawRect(Rect.fromLTWH(x + 1, chartHeight - h, barWidth - 2, h), Paint()..color = _getBarColor(bands[i].value));
      final double maxH = ((maxHold[i] - 30) / (120 - 30) * chartHeight).clamp(0, chartHeight);
      canvas.drawLine(Offset(x + 1, chartHeight - maxH), Offset(x + barWidth - 1, chartHeight - maxH), Paint()..color = Colors.red..strokeWidth = 1);
      if (i % 3 == 0) {
        final label = bands[i].centerFreq >= 1000 ? '${(bands[i].centerFreq / 1000).toStringAsFixed(0)}k' : bands[i].centerFreq.toInt().toString();
        TextPainter(text: TextSpan(text: label, style: const TextStyle(color: Colors.white54, fontSize: 8)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(x, chartHeight + 5));
      }
    }
  }

  Color _getBarColor(double db) => db < 50 ? Colors.blue : (db < 80 ? Colors.green : (db < 100 ? Colors.yellow : Colors.red));
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class Rt60Page extends StatefulWidget {
  const Rt60Page({super.key});
  @override State<Rt60Page> createState() => _Rt60PageState();
}

class _Rt60PageState extends State<Rt60Page> {
  Timer? _timer;
  String _status = 'Ready';
  double? _rt60;
  bool _isListening = false;

  void _toggleListening() {
    setState(() {
      _isListening = !_isListening;
      if (_isListening) { _status = 'Listening for impulse...'; _rt60 = null; _startMonitoring(); }
      else { _status = 'Ready'; _timer?.cancel(); }
    });
  }

  void _startMonitoring() {
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (!mounted) return;
      if (Recorder.instance.getVolumeDb() > -25.0) { timer.cancel(); _recordDecay(); }
    });
  }

  void _recordDecay() {
    setState(() => _status = 'Recording decay...');
    final List<double> values = [];
    final DateTime start = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      values.add(Recorder.instance.getVolumeDb());
      if (DateTime.now().difference(start).inMilliseconds > 1500) { timer.cancel(); _calculateRt60(values); }
    });
  }

  void _calculateRt60(List<double> values) {
    if (values.length < 5) return;
    int peakIndex = 0;
    for (int i = 0; i < values.length; i++) if (values[i] > values[peakIndex]) peakIndex = i;
    final List<double> decayPoints = [];
    for (int i = peakIndex; i < values.length; i++) { decayPoints.add(values[i]); if (values[i] < values[peakIndex] - 20) break; }
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    int n = decayPoints.length;
    for (int i = 0; i < n; i++) { sumX += i; sumY += decayPoints[i]; sumXY += i * decayPoints[i]; sumXX += i * i; }
    double slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    if (slope < 0) setState(() { _rt60 = (60.0 / slope.abs()) * 0.01; _status = 'Done'; _isListening = false; });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.timer, size: 80, color: Colors.blue),
      const SizedBox(height: 24),
      Text(_status, style: const TextStyle(color: Colors.white70)),
      if (_rt60 != null) Text('${_rt60!.toStringAsFixed(2)}s', style: const TextStyle(color: Colors.blue, fontSize: 72, fontWeight: FontWeight.bold)),
      const SizedBox(height: 40),
      ElevatedButton(onPressed: _toggleListening, child: Text(_isListening ? 'STOP' : 'START')),
    ]));
  }
}

class RastiPage extends StatefulWidget {
  const RastiPage({super.key});
  @override State<RastiPage> createState() => _RastiPageState();
}

class _RastiPageState extends State<RastiPage> {
  Timer? _timer;
  String _status = 'Ready';
  double? _rasti;
  bool _isMeasuring = false;

  void _startMeasurement() {
    setState(() { _isMeasuring = true; _status = 'Measuring Noise...'; });
    int count = 0; double noiseSum = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      noiseSum += Recorder.instance.getVolumeDb();
      if (++count >= 20) { timer.cancel(); _listenForImpulse(noiseSum / 20); }
    });
  }

  void _listenForImpulse(double noiseFloor) {
    setState(() => _status = 'Wait for clap...');
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (Recorder.instance.getVolumeDb() > noiseFloor + 25) { timer.cancel(); _recordDecay(noiseFloor, Recorder.instance.getVolumeDb()); }
    });
  }

  void _recordDecay(double noiseFloor, double peakDb) {
    setState(() => _status = 'Analyzing...');
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
    setState(() { _rasti = tiSum / 9; _isMeasuring = false; _status = 'Complete'; });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.record_voice_over, size: 80, color: Colors.purple),
      Text(_status, style: const TextStyle(color: Colors.white70)),
      if (_rasti != null) Text(_rasti!.toStringAsFixed(2), style: const TextStyle(color: Colors.purple, fontSize: 72, fontWeight: FontWeight.bold)),
      const SizedBox(height: 40),
      ElevatedButton(onPressed: _isMeasuring ? null : _startMeasurement, child: const Text('TEST RASTI')),
    ]));
  }
}
