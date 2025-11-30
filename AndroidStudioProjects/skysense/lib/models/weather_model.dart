class WeatherData {
  final double tempC;
  final double tempMin;
  final double tempMax;
  final double feelsLike;
  final double humidity;
  final double pressure;
  final double visibility;
  final double windSpeed;
  final int cloudiness;
  final String condition;
  final String description;
  final String cityName;
  final DateTime sunrise;
  final DateTime sunset;
  final String iconCode; // e.g. "10d"

  WeatherData({
    required this.tempC,
    required this.tempMin,
    required this.tempMax,
    required this.feelsLike,
    required this.humidity,
    required this.pressure,
    required this.visibility,
    required this.windSpeed,
    required this.cloudiness,
    required this.condition,
    required this.description,
    required this.cityName,
    required this.sunrise,
    required this.sunset,
    required this.iconCode,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      tempC: (json['main']['temp'] as num).toDouble(),
      tempMin: (json['main']['temp_min'] as num).toDouble(),
      tempMax: (json['main']['temp_max'] as num).toDouble(),
      feelsLike: (json['main']['feels_like'] as num).toDouble(),
      humidity: (json['main']['humidity'] as num).toDouble(),
      pressure: (json['main']['pressure'] as num).toDouble(),
      visibility: (json['visibility'] as num).toDouble(),
      windSpeed: (json['wind']['speed'] as num).toDouble(),
      cloudiness: (json['clouds']['all'] as num).toInt(),
      condition: (json['weather'] as List).isNotEmpty ? json['weather'][0]['main'] : 'Unknown',
      description: (json['weather'] as List).isNotEmpty ? json['weather'][0]['description'] : '',
      cityName: json['name'] ?? 'Unknown',
      sunrise: DateTime.fromMillisecondsSinceEpoch((json['sys']['sunrise'] as int) * 1000),
      sunset: DateTime.fromMillisecondsSinceEpoch((json['sys']['sunset'] as int) * 1000),
      iconCode: (json['weather'] as List).isNotEmpty ? json['weather'][0]['icon'] : '01d',
    );
  }
}

class ForecastItem {
  final DateTime dt;
  final double temp;
  final String iconCode;
  final String condition;

  ForecastItem({required this.dt, required this.temp, required this.iconCode, required this.condition});

  factory ForecastItem.fromJson(Map<String, dynamic> json) {
    return ForecastItem(
      dt: DateTime.fromMillisecondsSinceEpoch(json['dt'] * 1000),
      temp: (json['main']['temp'] as num).toDouble(),
      iconCode: json['weather'][0]['icon'],
      condition: json['weather'][0]['main'],
    );
  }
}