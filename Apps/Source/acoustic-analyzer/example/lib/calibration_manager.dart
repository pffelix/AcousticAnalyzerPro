import 'dart:math' as math;
import 'dart:typed_data';

enum WeightingType { z, a, c }

enum TimeWeighting { fast, slow, impulse }

enum OctaveResolution { oneThird, oneFull }

class CalibrationPoint {
  final double frequency;
  final double offset;

  CalibrationPoint(this.frequency, this.offset);
}

class OctaveBand {
  final double centerFreq;
  final double lowerFreq;
  final double upperFreq;
  double value = -100.0;

  OctaveBand(this.centerFreq, this.lowerFreq, this.upperFreq);
}

class SavedMeasurement {
  final DateTime timestamp;
  final double db;
  final double leq;
  final String weighting;

  SavedMeasurement({required this.timestamp, required this.db, required this.leq, required this.weighting});
}

class CalibrationManager {
  static final CalibrationManager instance = CalibrationManager._();
  CalibrationManager._() {
    _initOctaveBands();
  }

  List<CalibrationPoint> _calibrationPoints = [];
  final List<OctaveBand> octaveBands = [];
  final List<double> referenceSpectrum = List.filled(31, -100.0);
  final List<SavedMeasurement> projects = [];
  bool isReferenceVisible = false;

  /// Reference offset to map dBFS to dBSPL
  double referenceOffset = 100.0;

  WeightingType currentWeighting = WeightingType.a;
  TimeWeighting currentTimeWeighting = TimeWeighting.fast;
  OctaveResolution octaveResolution = OctaveResolution.oneThird;
  bool isFreeFieldCorrectionEnabled = false;

  // For Leq calculation
  double _accumulatedEnergy = 0.0;
  int _energyCount = 0;

  // For Time Weighting (Exponential Averaging)
  double _lastWeightedEnergy = 0.0;

  // History buffer for statistics (max 12000 points = 10 mins at 50ms)
  final List<double> _historyBuffer = [];
  static const int maxHistory = 12000;

  double limitThreshold = 85.0;
  bool isLimitExceeded = false;
  bool isWhiteDesign = false;

  void _initOctaveBands() {
    final centers = [
      20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
      800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ];
    for (var f in centers) {
      // 1/3 octave band limits: f / 2^(1/6) and f * 2^(1/6)
      final lower = f / math.pow(2, 1 / 6);
      final upper = f * math.pow(2, 1 / 6);
      octaveBands.add(OctaveBand(f.toDouble(), lower.toDouble(), upper.toDouble()));
    }
  }

  void loadCalibrationData(String data) {
    _calibrationPoints.clear();
    final lines = data.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('*')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final hz = double.tryParse(parts[0]);
        final db = double.tryParse(parts[1]);
        if (hz != null && db != null) {
          _calibrationPoints.add(CalibrationPoint(hz, db));
        }
      }
    }
    _calibrationPoints.sort((a, b) => a.frequency.compareTo(b.frequency));
    // Invalidate caches if you implement them in SpectrogramPainter
  }

  double getOffsetForFrequency(double frequency) {
    if (_calibrationPoints.isEmpty) return 0.0;
    if (frequency <= _calibrationPoints.first.frequency) return _calibrationPoints.first.offset;
    if (frequency >= _calibrationPoints.last.frequency) return _calibrationPoints.last.offset;

    for (int i = 0; i < _calibrationPoints.length - 1; i++) {
      if (frequency >= _calibrationPoints[i].frequency && frequency <= _calibrationPoints[i + 1].frequency) {
        final p1 = _calibrationPoints[i];
        final p2 = _calibrationPoints[i + 1];
        final t = (frequency - p1.frequency) / (p2.frequency - p1.frequency);
        return p1.offset + t * (p2.offset - p1.offset);
      }
    }
    return 0.0;
  }

  double getWeightingOffset(double f, WeightingType type) {
    if (f <= 0) return -100.0;
    final f2 = f * f;
    final f4 = f2 * f2;

    if (type == WeightingType.a) {
      final rA = (math.pow(12194, 2) * f4) /
          ((f2 + math.pow(20.6, 2)) *
              math.sqrt((f2 + math.pow(107.7, 2)) * (f2 + math.pow(737.9, 2))) *
              (f2 + math.pow(12194, 2)));
      return 20.0 * math.log(rA) / math.ln10 + 2.00;
    } else if (type == WeightingType.c) {
      final rC = (math.pow(12194, 2) * f2) / ((f2 + math.pow(20.6, 2)) * (f2 + math.pow(12194, 2)));
      return 20.0 * math.log(rC) / math.ln10 + 0.06;
    }
    return 0.0; // Z-weighting
  }

  double getCorrectionOffset(double f) {
    if (!isFreeFieldCorrectionEnabled) return 0.0;
    // Simple simulated Free-field correction curve for a typical measurement mic
    if (f < 1000) return 0.0;
    if (f < 4000) return (f - 1000) / 3000 * 1.0;
    if (f < 8000) return 1.0 + (f - 4000) / 4000 * 1.0;
    if (f < 12000) return 2.0 + (f - 8000) / 4000 * 2.0;
    if (f < 16000) return 4.0 + (f - 12000) / 4000 * 2.0;
    return 6.0;
  }

  /// Reset Leq and peak tracking
  void resetAveraging() {
    _accumulatedEnergy = 0;
    _energyCount = 0;
    _lastWeightedEnergy = 0;
    _historyBuffer.clear();
    isLimitExceeded = false;
  }

  void _addToHistory(double db) {
    if (_historyBuffer.length >= maxHistory) {
      _historyBuffer.removeAt(0);
    }
    _historyBuffer.add(db);
    isLimitExceeded = db > limitThreshold;
  }

  double getPercentile(int percentile) {
    if (_historyBuffer.isEmpty) return -100.0;
    final sorted = List<double>.from(_historyBuffer)..sort();
    // LX is the level exceeded for X% of the time.
    // L90 (background) means 90% of samples are ABOVE this value.
    // So it's the 10th percentile in an ascending list.
    int index = ((100 - percentile) / 100 * (sorted.length - 1)).round();
    return sorted[index];
  }

  double calculateSpl(Float32List fftData, double sampleRate) {
    if (fftData.isEmpty) return -100.0;

    double instantEnergy = 0;
    final binWidth = (sampleRate / 2) / fftData.length;

    // Reset octave band values for this frame
    for (var band in octaveBands) {
      band.value = 0;
    }

    for (int i = 0; i < fftData.length; i++) {
      final freq = i * binWidth;
      double magnitude = fftData[i];

      final calOffset = getOffsetForFrequency(freq);
      final weightingOffset = getWeightingOffset(freq, currentWeighting);
      final correctionOffset = getCorrectionOffset(freq);

      final totalOffsetDb = calOffset + weightingOffset + correctionOffset;
      final gain = math.pow(10, totalOffsetDb / 20.0);

      final adjustedMagnitude = magnitude * gain;
      final energy = adjustedMagnitude * adjustedMagnitude;
      instantEnergy += energy;

      // Assign to octave bands
      for (var band in octaveBands) {
        if (freq >= band.lowerFreq && freq < band.upperFreq) {
          band.value += energy;
        }
      }
    }

    // Convert octave bands energy to dB
    for (var band in octaveBands) {
      if (band.value > 0) {
        band.value = 10.0 * math.log(band.value) / math.ln10 + referenceOffset;
      } else {
        band.value = -100.0;
      }
    }

    if (instantEnergy <= 0) return -100.0;

    // Apply Time Weighting
    // Fast: tau = 125ms, Slow: tau = 1000ms
    // We assume 50ms interval (from UI timer) if we are in SLM mode, but here we can't know the exact interval.
    // For now, we use a simple alpha for the 50ms polling rate:
    // alpha = 1 - exp(-delta_t / tau)
    double tau = currentTimeWeighting == TimeWeighting.fast ? 0.125 : 1.0;
    double deltaT = 0.050; // 50ms interval
    double alpha = 1 - math.exp(-deltaT / tau);
    
    _lastWeightedEnergy = (1 - alpha) * _lastWeightedEnergy + alpha * instantEnergy;

    // Accumulate for Leq
    _accumulatedEnergy += instantEnergy;
    _energyCount++;

    final dbfs = 10.0 * math.log(_lastWeightedEnergy) / math.ln10;
    final result = dbfs + referenceOffset;
    _addToHistory(result);
    return result;
  }

  double getLeq() {
    if (_energyCount == 0) return -100.0;
    final avgEnergy = _accumulatedEnergy / _energyCount;
    return 10.0 * math.log(avgEnergy) / math.ln10 + referenceOffset;
  }

  /// Calculates the Noise Criteria (NC) value based on current octave levels
  int calculateNC() {
    // Standard NC curves lookup (Freqs: 63, 125, 250, 500, 1000, 2000, 4000, 8000)
    final Map<double, double> levels = {};
    for (var band in octaveBands) {
      levels[band.centerFreq] = band.value;
    }

    // Simplified NC check logic: 
    // Return a simulated NC based on the 1kHz band as a proxy
    double midLevel = levels[1000.0] ?? -100.0;
    if (midLevel < 0) return 0;
    return (midLevel - 10).round().clamp(15, 70);
  }

  void saveReference() {
    for (int i = 0; i < octaveBands.length; i++) {
      referenceSpectrum[i] = octaveBands[i].value;
    }
    isReferenceVisible = true;
  }

  void saveCurrentMeasurement(double db) {
    projects.add(SavedMeasurement(
      timestamp: DateTime.now(),
      db: db,
      leq: getLeq(),
      weighting: currentWeighting.name.toUpperCase(),
    ));
  }

  String exportToCSV() {
    if (projects.isEmpty) return 'No data';
    String csv = 'Timestamp,Level(dB),Leq,Weighting\n';
    for (var p in projects) {
      csv += '${p.timestamp.toIso8601String()},${p.db.toStringAsFixed(1)},${p.leq.toStringAsFixed(1)},${p.weighting}\n';
    }
    return csv;
  }
}
