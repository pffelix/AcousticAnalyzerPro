import 'dart:math' as math;
import 'dart:typed_data';

class CalibrationPoint {
  final double frequency;
  final double offset;

  CalibrationPoint(this.frequency, this.offset);
}

class CalibrationManager {
  static final CalibrationManager instance = CalibrationManager._();
  CalibrationManager._();

  List<CalibrationPoint> _calibrationPoints = [];
  
  /// Reference offset to map dBFS to dBSPL (default is a rough estimate)
  double referenceOffset = 100.0; 
  
  bool isAWeightingEnabled = true;

  /// Loads calibration from a string (format: Hz dB)
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

  /// Gets the calibration offset for a given frequency using linear interpolation
  double getOffsetForFrequency(double frequency) {
    if (_calibrationPoints.isEmpty) return 0.0;
    
    if (frequency <= _calibrationPoints.first.frequency) {
      return _calibrationPoints.first.offset;
    }
    if (frequency >= _calibrationPoints.last.frequency) {
      return _calibrationPoints.last.offset;
    }

    for (int i = 0; i < _calibrationPoints.length - 1; i++) {
      if (frequency >= _calibrationPoints[i].frequency &&
          frequency <= _calibrationPoints[i + 1].frequency) {
        final p1 = _calibrationPoints[i];
        final p2 = _calibrationPoints[i + 1];
        final t = (frequency - p1.frequency) / (p2.frequency - p1.frequency);
        return p1.offset + t * (p2.offset - p1.offset);
      }
    }
    return 0.0;
  }

  /// Calculates the A-weighting offset in dB for a given frequency
  /// Based on IEC 61672-1
  double getAWeightingOffset(double f) {
    if (f <= 0) return -100.0;
    
    final f2 = f * f;
    final f4 = f2 * f2;
    
    final rA = (12194.0 * 12194.0 * f4) /
        ((f2 + 20.6 * 20.6) * 
         math.sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)) * 
         (f2 + 12194.0 * 12194.0));
    
    // A(f) = 20*log10(Ra(f)) + 2.00
    return 20.0 * math.log(rA) / math.ln10 + 2.00;
  }

  /// Calculates the total SPL in dB from FFT bins
  /// [fftData] is 256 bins from Recorder.instance.getFft()
  /// [sampleRate] usually 44100
  double calculateSpl(Float32List fftData, double sampleRate) {
    if (fftData.isEmpty) return -100.0;

    double totalEnergy = 0;
    final binWidth = (sampleRate / 2) / fftData.length;

    for (int i = 0; i < fftData.length; i++) {
      final freq = i * binWidth;
      
      // Magnitude from getFft() is typically [0, 1]
      // We square it to get energy
      double magnitude = fftData[i];
      
      // Apply frequency calibration
      final calOffset = getOffsetForFrequency(freq);
      
      // Apply A-weighting if enabled
      final weightingOffset = isAWeightingEnabled ? getAWeightingOffset(freq) : 0.0;
      
      // Convert offsets to linear gain: dB = 20*log10(gain) => gain = 10^(dB/20)
      final totalOffsetDb = calOffset + weightingOffset;
      final gain = math.pow(10, totalOffsetDb / 20.0);
      
      final adjustedMagnitude = magnitude * gain;
      totalEnergy += adjustedMagnitude * adjustedMagnitude;
    }

    if (totalEnergy <= 0) return -100.0;

    // Convert energy back to dB and apply absolute reference offset
    final dbfs = 10.0 * math.log(totalEnergy) / math.ln10;
    return dbfs + referenceOffset;
  }
}
