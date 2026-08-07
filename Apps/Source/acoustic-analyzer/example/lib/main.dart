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
          1 => 'SPL Meter',
          2 => 'RT60 Prediction',
          3 => 'RASTI Calculation',
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
          BottomNavigationBarItem(
            icon: Icon(Icons.waves),
            label: 'Spectrogram',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.equalizer),
            label: 'SPL Meter',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timer),
            label: 'RT60',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.record_voice_over),
            label: 'RASTI',
          ),
        ],
      ),
    );
  }
}

class SpectrogramPage extends StatefulWidget {
// ... existing SpectrogramPage ...
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
  Timer? _timer;
  final _cal = CalibrationManager.instance;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      
      final fft = Recorder.instance.getFft(alwaysReturnData: true);
      setState(() {
        _db = _cal.calculateSpl(fft, kSampleRate);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showCalibrationDialog() {
    final controller = TextEditingController(text: _cal.referenceOffset.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SPL Calibration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set reference offset to match a known SPL source (e.g. 94dB calibrator).'),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Manual Reference Offset (dB)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                // To calibrate to 94dB:
                // current_db = dbfs + old_offset
                // we want: 94 = dbfs + new_offset
                // so: new_offset = 94 - dbfs
                // dbfs = current_db - old_offset
                final dbfs = _db - _cal.referenceOffset;
                final newOffset = 94.0 - dbfs;
                setState(() {
                  _cal.referenceOffset = newOffset;
                  controller.text = newOffset.toStringAsFixed(1);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calibrated to 94.0 dB')),
                );
              },
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Auto-Calibrate to 94.0 dB'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Sample calibration data: +5dB at 100Hz, -3dB at 10kHz
                const sampleCal = "100 5.0\n1000 0.0\n10000 -3.0";
                _cal.loadCalibrationData(sampleCal);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sample Calibration Loaded')),
                );
              },
              child: const Text('Load Sample .cal Data'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) {
                setState(() => _cal.referenceOffset = val);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Standard SPL range: 30dB (very quiet) to 120dB (painful)
    final double normalized = ((_db - 30) / (120 - 30)).clamp(0.0, 1.0);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Weighting: ', style: TextStyle(color: Colors.white70)),
                ChoiceChip(
                  label: const Text('Z (None)'),
                  selected: !_cal.isAWeightingEnabled,
                  onSelected: (val) => setState(() => _cal.isAWeightingEnabled = !val),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('A-Weight'),
                  selected: _cal.isAWeightingEnabled,
                  onSelected: (val) => setState(() => _cal.isAWeightingEnabled = val),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Text(
              '${_db.toStringAsFixed(1)} dB(${_cal.isAWeightingEnabled ? 'A' : 'Z'})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 64,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
            const SizedBox(height: 40),
            // Visual Meter
            Stack(
              children: [
                Container(
                  height: 40,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: normalized,
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.withOpacity(0.8),
                          Colors.yellow.withOpacity(0.8),
                          Colors.red.withOpacity(0.8),
                        ],
                        stops: const [0.6, 0.8, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('30 dB', style: TextStyle(color: Colors.white54)),
                Text('120 dB', style: TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _showCalibrationDialog,
              icon: const Icon(Icons.settings_input_antenna),
              label: const Text('Calibration Settings'),
            ),
          ],
        ),
      ),
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
    final double stepY = size.height / 256; // 256 frequency bins
    final double binWidth = (kSampleRate / 2.0) / 256.0;

    final paint = Paint();

    // 1. Draw Spectrogram Data
    for (int t = 0; t < history.length; t++) {
      final fft = history[t];
      for (int f = 0; f < fft.length; f++) {
        final freq = f * binWidth;
        final calOffset = _cal.getOffsetForFrequency(freq);
        
        final gain = math.pow(10, calOffset / 20.0);
        final double magnitude = (fft[f] * gain).clamp(0.0, 1.0);
        
        paint.color = _getHeatmapColor(magnitude);

        canvas.drawRect(
          Rect.fromLTWH(
            labelWidth + drawingWidth - (t * stepX) - stepX,
            size.height - (f * stepY) - stepY,
            stepX + 0.5,
            stepY + 0.5,
          ),
          paint,
        );
      }
    }

    // 2. Draw Frequency Axis (Labels and Grid)
    final textStyle = TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold);
    final linePaint = Paint()..color = Colors.white24..strokeWidth = 1;

    final List<int> labels = [100, 500, 1000, 2000, 5000, 10000, 15000, 20000];
    
    for (final hz in labels) {
      final double y = size.height - (hz / (kSampleRate / 2.0) * size.height);
      
      // Draw grid line
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), linePaint);

      // Draw label
      final tp = TextPainter(
        text: TextSpan(text: hz >= 1000 ? '${(hz / 1000).toStringAsFixed(0)}k' : '$hz', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      
      tp.paint(canvas, Offset(labelWidth - tp.width - 5, y - (tp.height / 2)));
    }

    // Y-Axis title
    final titleTp = TextPainter(
      text: const TextSpan(text: 'Hz', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(canvas, Offset(5, 5));
  }

  Color _getHeatmapColor(double magnitude) {
    if (magnitude < 0.1) return Colors.black;
    if (magnitude < 0.3) return Color.lerp(Colors.black, Colors.blue, (magnitude - 0.1) / 0.2)!;
    if (magnitude < 0.5) return Color.lerp(Colors.blue, Colors.green, (magnitude - 0.3) / 0.2)!;
    if (magnitude < 0.8) return Color.lerp(Colors.green, Colors.yellow, (magnitude - 0.5) / 0.3)!;
    return Color.lerp(Colors.yellow, Colors.red, (magnitude - 0.8) / 0.2)!;
  }

  @override
  bool shouldRepaint(covariant SpectrogramPainter oldDelegate) => true;
}

class Rt60Page extends StatefulWidget {
  const Rt60Page({super.key});

  @override
  State<Rt60Page> createState() => _Rt60PageState();
}

class _Rt60PageState extends State<Rt60Page> {
  Timer? _timer;
  String _status = 'Ready';
  double? _rt60;
  bool _isListening = false;

  // Settings
  final double _triggerThreshold = -25.0; // Trigger when sound is louder than this
  final double _noiseFloor = -60.0; // Stop measuring when it hits noise

  void _toggleListening() {
    setState(() {
      _isListening = !_isListening;
      if (_isListening) {
        _status = 'Listening for impulse (clap)...';
        _rt60 = null;
        _startMonitoring();
      } else {
        _status = 'Ready';
        _timer?.cancel();
      }
    });
  }

  void _startMonitoring() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (!mounted) return;

      final double currentDb = Recorder.instance.getVolumeDb();

      if (currentDb > _triggerThreshold) {
        timer.cancel();
        _recordDecay();
      }
    });
  }

  void _recordDecay() {
    setState(() => _status = 'Recording decay...');
    final List<double> values = [];
    final DateTime start = DateTime.now();

    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      final double currentDb = Recorder.instance.getVolumeDb();
      values.add(currentDb);

      // Stop after 1.5 seconds
      if (DateTime.now().difference(start).inMilliseconds > 1500) {
        timer.cancel();
        _calculateRt60(values);
      }
    });
  }

  void _calculateRt60(List<double> values) {
    if (values.isEmpty) return;

    // Find the peak
    double peak = -100.0;
    int peakIndex = 0;
    for (int i = 0; i < values.length; i++) {
      if (values[i] > peak) {
        peak = values[i];
        peakIndex = i;
      }
    }

    // Filter data from peak until it drops by 20dB or hits noise floor
    final List<double> decayPoints = [];
    for (int i = peakIndex; i < values.length; i++) {
      decayPoints.add(values[i]);
      if (values[i] < peak - 20 || values[i] < _noiseFloor) break;
    }

    if (decayPoints.length < 5) {
      setState(() {
        _status = 'Signal too short. Try a louder clap.';
        _isListening = false;
      });
      return;
    }

    // Simple Linear Regression for slope (dB per sample)
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    int n = decayPoints.length;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += decayPoints[i];
      sumXY += i * decayPoints[i];
      sumXX += i * i;
    }

    double denominator = (n * sumXX - sumX * sumX);
    if (denominator == 0) return;
    double slope = (n * sumXY - sumX * sumY) / denominator;

    if (slope >= 0) {
      setState(() {
        _status = 'Invalid decay slope detected.';
        _isListening = false;
      });
      return;
    }

    // RT60 = (60 / |slope|) * 10ms
    double rt60Result = (60.0 / slope.abs()) * 0.01;

    setState(() {
      _rt60 = rt60Result;
      _status = 'Measurement Complete';
      _isListening = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.av_timer, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 40),
          if (_rt60 != null) ...[
            const Text('Estimated RT60', style: TextStyle(color: Colors.white54, fontSize: 14)),
            Text('${_rt60!.toStringAsFixed(2)}s',
                style: const TextStyle(color: Colors.blue, fontSize: 72, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Text(_getRoomDescription(_rt60!), style: const TextStyle(color: Colors.green, fontSize: 18)),
          ],
          const SizedBox(height: 60),
          ElevatedButton.icon(
            onPressed: _toggleListening,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isListening ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            icon: Icon(_isListening ? Icons.stop : Icons.mic),
            label: Text(_isListening ? 'STOP' : 'START LISTENING'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Tip: Press start and make a loud impulse (clap or pop a balloon) to measure reverb.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _getRoomDescription(double rt) {
    if (rt < 0.3) return "Very Dry (Recording Studio)";
    if (rt < 0.6) return "Dry (Living Room)";
    if (rt < 1.0) return "Normal (Office/Classroom)";
    if (rt < 1.5) return "Live (Large Hall)";
    return "Very Reverberant (Cathedral/Empty Warehouse)";
  }
}

class RastiPage extends StatefulWidget {
  const RastiPage({super.key});

  @override
  State<RastiPage> createState() => _RastiPageState();
}

class _RastiPageState extends State<RastiPage> {
  Timer? _timer;
  String _status = 'Ready';
  double? _rasti;
  bool _isMeasuring = false;
  
  // RASTI standard modulation frequencies
  final List<double> _modFreqs = [0.7, 1.0, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.2];

  void _startMeasurement() {
    setState(() {
      _isMeasuring = true;
      _status = 'Step 1: Measuring ambient noise...';
    });

    // 1. Measure background noise for 1 second to get SNR baseline
    double noiseSum = 0;
    int noiseCount = 0;
    
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      noiseSum += Recorder.instance.getVolumeDb();
      noiseCount++;
      
      if (noiseCount >= 20) { // 1 second
        timer.cancel();
        double avgNoise = noiseSum / noiseCount;
        _listenForImpulse(avgNoise);
      }
    });
  }

  void _listenForImpulse(double noiseFloor) {
    setState(() => _status = 'Step 2: Listening for loud impulse (clap)...');
    
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      final double currentDb = Recorder.instance.getVolumeDb();
      
      if (currentDb > noiseFloor + 25) { // Significant impulse detected
        timer.cancel();
        _recordDecay(noiseFloor, currentDb);
      }
    });
  }

  void _recordDecay(double noiseFloor, double peakDb) {
    setState(() => _status = 'Step 3: Calculating decay and MTF...');
    final List<double> decayValues = [];
    final DateTime start = DateTime.now();
    
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      decayValues.add(Recorder.instance.getVolumeDb());
      
      if (DateTime.now().difference(start).inMilliseconds > 1200) {
        timer.cancel();
        _computeRasti(decayValues, noiseFloor, peakDb);
      }
    });
  }

  void _computeRasti(List<double> decay, double noiseFloor, double peakDb) {
    // 1. Calculate RT60 from decay (Simple slope)
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    int n = decay.length > 50 ? 50 : decay.length; // First 500ms
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += decay[i];
      sumXY += i * decay[i];
      sumXX += i * i;
    }
    double slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    double rt60 = (60.0 / slope.abs()) * 0.01;
    
    // 2. Calculate effective SNR
    // We assume the signal (speech) would be around 65dB in a real scenario,
    // but here we use the measured peak vs noise for the specific room state.
    double snr = peakDb - noiseFloor;

    // 3. Calculate Transmission Index (TI) for each modulation frequency
    List<double> tis = [];
    for (double fm in _modFreqs) {
      // Modulation Transfer Function due to reverberation
      double mRev = 1.0 / math.sqrt(1.0 + math.pow(2 * math.pi * fm * rt60 / 13.8, 2));
      
      // Modulation Transfer Function due to noise
      double mNoise = 1.0 / (1.0 + math.pow(10, -snr / 10.0));
      
      double mTotal = mRev * mNoise;
      
      // Convert to Apparent SNR
      double snrApp = 10.0 * math.log(mTotal / (1.0 - mTotal).clamp(0.0001, 1.0)) / math.ln10;
      
      // Clip to [-15, 15] range and normalize to [0, 1]
      double ti = (snrApp + 15.0) / 30.0;
      tis.add(ti.clamp(0.0, 1.0));
    }

    // 4. RASTI is the arithmetic mean of TI values
    double rastiResult = tis.reduce((a, b) => a + b) / tis.length;

    setState(() {
      _rasti = rastiResult;
      _isMeasuring = false;
      _status = 'Measurement Complete';
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Icon(Icons.record_voice_over, size: 80, color: Colors.purple),
          const SizedBox(height: 24),
          const Text(
            'Speech Transmission Index (RASTI)',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 40),
          
          if (_rasti != null) ...[
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CircularProgressIndicator(
                    value: _rasti,
                    strokeWidth: 15,
                    backgroundColor: Colors.grey[900],
                    color: _getRastiColor(_rasti!),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      _rasti!.toStringAsFixed(2),
                      style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _getRastiQualitiy(_rasti!),
                      style: TextStyle(color: _getRastiColor(_rasti!), fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 60),
          
          ElevatedButton.icon(
            onPressed: _isMeasuring ? null : _startMeasurement,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            ),
            icon: _isMeasuring 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.play_arrow),
            label: Text(_isMeasuring ? 'MEASURING...' : 'START RASTI TEST'),
          ),
          
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How to test:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('1. Stay quiet for the noise floor measurement.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text('2. Make a loud clap when prompted.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text('3. The app calculates speech intelligibility based on echo and noise.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRastiColor(double val) {
    if (val < 0.3) return Colors.red;
    if (val < 0.45) return Colors.orange;
    if (val < 0.6) return Colors.yellow;
    if (val < 0.75) return Colors.lightGreen;
    return Colors.green;
  }

  String _getRastiQualitiy(double val) {
    if (val < 0.3) return "Bad";
    if (val < 0.45) return "Poor";
    if (val < 0.6) return "Fair";
    if (val < 0.75) return "Good";
    return "Excellent";
  }
}
