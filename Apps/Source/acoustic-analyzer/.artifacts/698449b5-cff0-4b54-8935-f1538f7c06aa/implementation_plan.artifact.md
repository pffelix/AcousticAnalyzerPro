# Microphone Calibration and dB(A) Integration

This plan implements a microphone calibration database loader and calculates A-weighted Sound Pressure Level (dB(A)) using FFT data from `flutter_recorder`.

## User Review Required

> [!IMPORTANT]
> The dB(A) calculation will be performed in the Dart layer using FFT data because the native `getVolumeDb()` does not support frequency weighting or custom calibration curves.
> This might have a slight performance impact compared to native calculation, but it allows for full frequency-dependent calibration.

## Proposed Changes

### [Component] Calibration and Weighting Logic

#### [NEW] [calibration_manager.dart](file:///C:/Users/Felix/Code/Github/AcousticAnalyzer/Apps/Source/acoustic-analyzer/example/lib/calibration_manager.dart)
- Create a `CalibrationManager` class to load and parse `.cal` files (format: `Hz dB`).
- Implement linear interpolation to get calibration offsets for any frequency.
- Implement A-weighting coefficient calculation ($R_A(f)$).

### [Component] UI Integration

#### [MODIFY] [main.dart](file:///C:/Users/Felix/Code/Github/AcousticAnalyzer/Apps/Source/acoustic-analyzer/example/lib/main.dart)
- Update `_SplMeterPageState` to:
    - Include a "Load Calibration" button.
    - Calculate SPL(A) by summing calibrated and weighted FFT bin energies.
    - Display "dB(A)" instead of "dB" when active.
    - Provide a toggle between Z-weighting (flat) and A-weighting.

## Verification Plan

### Manual Verification
- Load a sample calibration file and verify the SPL value changes accordingly.
- Compare dB(Z) and dB(A) with a known sound source (A-weighting should significantly reduce low-frequency values).
- Verify that the SPL meter still updates in real-time.
