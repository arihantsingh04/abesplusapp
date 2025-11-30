import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/weather_model.dart';

class ApiService {
  // TODO: Replace with your actual OpenWeatherMap API Key
  static const String _owmKey = "a45125e97df800bc3113b4b9159a7312";

  // --- Helper: Convert PM2.5 to INDIAN AQI (Aggressive Scale) ---
  // Adjusted to compensate for lower OWM sensor readings vs local station data.
  // Standard CPCB "Very Poor" starts at 120. This scale starts it at 75.
  static int pm25ToIndianAQI(double pm25) {
    const breaks = [
      {'clow': 0.0,   'chigh': 15.0,   'ilow': 0,   'ihigh': 50},   // Good
      {'clow': 15.1,  'chigh': 35.0,   'ilow': 51,  'ihigh': 100},  // Satisfactory
      {'clow': 35.1,  'chigh': 55.0,   'ilow': 101, 'ihigh': 200},  // Moderate
      {'clow': 55.1,  'chigh': 75.0,   'ilow': 201, 'ihigh': 300},  // Poor
      {'clow': 75.1,  'chigh': 115.0,  'ilow': 301, 'ihigh': 400},  // Very Poor (Target: 90µg -> ~340 AQI)
      {'clow': 115.1, 'chigh': 500.0,  'ilow': 401, 'ihigh': 500},  // Severe
    ];

    for (final bp in breaks) {
      final cl = bp['clow'] as double;
      final ch = bp['chigh'] as double;
      final il = bp['ilow'] as int;
      final ih = bp['ihigh'] as int;

      if (pm25 >= cl && pm25 <= ch) {
        final aqi = ((ih - il) / (ch - cl) * (pm25 - cl) + il).round();
        // ensure within bounds of the bucket
        if (aqi < il) return il;
        if (aqi > ih) return ih;
        return aqi;
      }
    }
    // Extreme fallback
    return 500;
  }

  // 1. Fetch Current Weather
  Future<WeatherData> fetchWeather(double lat, double lon) async {
    final url = Uri.parse(
        "https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&units=metric&appid=$_owmKey");
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return WeatherData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception("Failed to load weather");
    }
  }

  // 2. Fetch Coordinates by City Name
  Future<Map<String, double>> getCoordsByCity(String cityName) async {
    final url = Uri.parse(
        "https://api.openweathermap.org/data/2.5/weather?q=$cityName&appid=$_owmKey");
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'lat': (data['coord']['lat'] as num).toDouble(),
        'lon': (data['coord']['lon'] as num).toDouble(),
      };
    } else {
      throw Exception("City not found");
    }
  }

  // 3. Search City Suggestions
  Future<List<Map<String, dynamic>>> searchCities(String query) async {
    if (query.length < 3) return [];
    final url = Uri.parse(
        "https://api.openweathermap.org/geo/1.0/direct?q=$query&limit=5&appid=$_owmKey");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map<Map<String, dynamic>>((e) => {
          'name': e['name'],
          'country': e['country'],
          'state': e['state'] ?? '',
          'lat': (e['lat'] as num).toDouble(),
          'lon': (e['lon'] as num).toDouble(),
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 4. Fetch Forecast
  Future<List<ForecastItem>> fetchForecast(double lat, double lon) async {
    final url = Uri.parse(
        "https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&units=metric&appid=$_owmKey");
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = data['list'] as List;
      return list.map((e) => ForecastItem.fromJson(e)).toList();
    } else {
      throw Exception("Forecast API Error");
    }
  }

  // 5. Fetch PM2.5 (Raw)
  Future<double> fetchPM25(double lat, double lon) async {
    final url = Uri.parse(
        "https://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=$_owmKey");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final list = json['list'] as List;
        if (list.isNotEmpty) {
          final components = list[0]['components'];
          if (components != null && components['pm2_5'] != null) {
            return (components['pm2_5'] as num).toDouble();
          }
        }
      }
      return 25.0; // fallback
    } catch (e) {
      return 25.0; // fallback
    }
  }
}