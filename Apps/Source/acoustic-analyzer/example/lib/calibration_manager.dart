import 'dart:math' as math;
import 'dart:typed_data';

enum WeightingType { z, a, c }

enum TimeWeighting { fast, slow, impulse }

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

class CalibrationManager {
  static final CalibrationManager instance = CalibrationManager._();
  CalibrationManager._() {
    _initOctaveBands();
  }

  List<CalibrationPoint> _calibrationPoints = [];
  final List<OctaveBand> octaveBands = [];

  /// Reference offset to map dBFS to dBSPL
  double referenceOffset = 100.0;

  WeightingType currentWeighting = WeightingType.a;
  TimeWeighting currentTimeWeighting = TimeWeighting.fast;
  bool isFreeFieldCorrectionEnabled = false;

  // For Leq calculation
  double _accumulatedEnergy = 0.0;
  int _energyCount = 0;

  // For Time Weighting (Exponential Averaging)
  double _lastWeightedEnergy = 0.0;

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
    return dbfs + referenceOffset;
  }

  double getLeq() {
    if (_energyCount == 0) return -100.0;
    final avgEnergy = _accumulatedEnergy / _energyCount;
    return 10.0 * math.log(avgEnergy) / math.ln10 + referenceOffset;
  }
}
