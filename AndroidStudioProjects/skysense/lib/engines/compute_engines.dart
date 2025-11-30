import 'dart:math';

// --- Component Comfort Mappings (0-100) ---

/// A - AQI (PM2.5) -> Comfort
/// Uses EPA-style breakpoints with linear interpolation.
double cAqi(double? pm25) {
  if (pm25 == null) return 50.0; // Neutral fallback
  if (pm25 <= 12.0) return 100.0;
  if (pm25 <= 35.4) return _interpolate(pm25, 12.0, 100.0, 35.4, 70.0);
  if (pm25 <= 55.4) return _interpolate(pm25, 35.4, 70.0, 55.4, 40.0);
  if (pm25 <= 150.4) return _interpolate(pm25, 55.4, 40.0, 150.4, 10.0);
  return 0.0;
}

/// B - Temperature (°C) -> Comfort
/// Ideal: 18-26°C. Piecewise linear degradation.
double cTemp(double tempC) {
  if (tempC >= 18.0 && tempC <= 26.0) return 100.0;
  if (tempC < 18.0) {
    if (tempC <= -10.0) return 0.0;
    return _interpolate(tempC, -10.0, 0.0, 18.0, 100.0);
  }
  // tempC > 26
  if (tempC >= 45.0) return 0.0;
  return _interpolate(tempC, 26.0, 100.0, 45.0, 0.0);
}

/// C - Humidity (%) -> Comfort
/// Ideal: 40-60%.
double cHumidity(double rh) {
  if (rh >= 40.0 && rh <= 60.0) return 100.0;
  if (rh < 40.0) return _interpolate(rh, 0.0, 0.0, 40.0, 100.0);
  // rh > 60
  if (rh >= 100.0) return 0.0;
  return _interpolate(rh, 60.0, 100.0, 100.0, 0.0);
}

/// D - UV Index -> Comfort
/// Buckets with interpolation.
double cUV(double? uv) {
  if (uv == null) return 50.0;
  if (uv <= 2.0) return 100.0;
  if (uv <= 5.0) return _interpolate(uv, 2.0, 100.0, 5.0, 70.0); // 3-5 range
  if (uv <= 7.0) return _interpolate(uv, 5.0, 70.0, 7.0, 40.0);  // 6-7 range
  if (uv <= 10.0) return _interpolate(uv, 7.0, 40.0, 10.0, 10.0); // 8-10 range
  return 0.0;
}

/// E - Pollen -> Comfort
/// Simple category mapping.
double cPollen(String? category) {
  if (category == null) return 50.0;
  switch (category.toLowerCase()) {
    case 'low': return 100.0;
    case 'moderate': return 70.0;
    case 'high': return 30.0;
    case 'very_high':
    case 'very high': return 0.0;
    default: return 50.0;
  }
}

/// F - Noise (dB) -> Comfort
double cNoise(double? db) {
  if (db == null) return 50.0;
  if (db < 55.0) return 100.0;
  if (db <= 70.0) return _interpolate(db, 55.0, 100.0, 70.0, 50.0);
  if (db <= 85.0) return _interpolate(db, 70.0, 50.0, 85.0, 10.0);
  return 0.0;
}

/// G - Precipitation Probability (%) -> Comfort
/// Inverse linear mapping.
double cPrecip(double? probPercent) {
  if (probPercent == null) return 100.0; // Assume no rain if unknown
  if (probPercent <= 0.0) return 100.0;
  if (probPercent >= 100.0) return 0.0;
  return _interpolate(probPercent, 0.0, 100.0, 100.0, 0.0);
}

// --- Main Aggregation ---

/// Calculates overall livability (0-100) based on health-focused weights.
double computeLivability({
  required double tempC,
  required double? pm25,
  required double humidity,
  double? uvIndex,
  String? pollenCat,
  double? noiseDb,
  double? precipProbPercent,
}) {
  // 1. Compute Component Comforts
  final double aqiScore = cAqi(pm25);
  final double tempScore = cTemp(tempC);
  final double humidScore = cHumidity(humidity);
  final double uvScore = cUV(uvIndex);
  final double pollenScore = cPollen(pollenCat);
  final double noiseScore = cNoise(noiseDb);
  final double precipScore = cPrecip(precipProbPercent);

  // 2. Weights (Sum = 1.0)
  const double wAqi = 0.35;
  const double wTemp = 0.20;
  const double wHum = 0.10;
  const double wUv = 0.10;
  const double wPollen = 0.10;
  const double wNoise = 0.05;
  const double wPrecip = 0.10;

  double base = (wAqi * aqiScore) +
      (wTemp * tempScore) +
      (wHum * humidScore) +
      (wUv * uvScore) +
      (wPollen * pollenScore) +
      (wNoise * noiseScore) +
      (wPrecip * precipScore);

  // 3. Penalties for Extremes
  double penalty = 0.0;
  if (tempC >= 40.0) penalty += 10.0;
  if (pm25 != null && pm25 > 250.0) penalty += 15.0;

  // 4. Final Calculation
  return max(0.0, min(100.0, base - penalty));
}

/// Linear interpolation helper
double _interpolate(double x, double x1, double y1, double x2, double y2) {
  return y1 + ((x - x1) * (y2 - y1) / (x2 - x1));
}