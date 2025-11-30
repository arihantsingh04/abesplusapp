import 'dart:ui';
import 'dart:async'; // For debounce
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engines/compute_engines.dart';
import '../services/api_service.dart';
import '../models/weather_model.dart';
import '../widgets/glass_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();

  // Navigation State
  int _tabIndex = 0;
  late PageController _pageController;

  // Location
  double _lat = 28.6139;
  double _lon = 77.2090;

  // Data
  bool _isLoading = true;
  WeatherData? _weather;
  List<ForecastItem> _forecast = [];
  double? _pm25;
  double? _livability;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadSavedLocation();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --- Persistence Logic ---

  Future<void> _loadSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lat = prefs.getDouble('lat') ?? 28.6139;
      _lon = prefs.getDouble('lon') ?? 77.2090;
    });
    _fetchData();
  }

  Future<void> _saveLocation(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lat', lat);
    await prefs.setDouble('lon', lon);
  }

  // --- Logic ---

  Future<void> _handleGPS() async {
    setState(() => _isLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw "Permission denied";
      }
      Position pos = await Geolocator.getCurrentPosition();
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
      });
      await _saveLocation(pos.latitude, pos.longitude);
      await _fetchData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _searchCity({String? query, double? lat, double? lon}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (lat != null && lon != null) {
        setState(() {
          _lat = lat;
          _lon = lon;
        });
        await _saveLocation(lat, lon);
      } else if (query != null && query.isNotEmpty) {
        final coords = await _apiService.getCoordsByCity(query);
        setState(() {
          _lat = coords['lat']!;
          _lon = coords['lon']!;
        });
        await _saveLocation(coords['lat']!, coords['lon']!);
      }
      await _fetchData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "City not found.";
      });
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _apiService.fetchWeather(_lat, _lon),
        _apiService.fetchForecast(_lat, _lon),
        _apiService.fetchPM25(_lat, _lon),
      ]);

      setState(() {
        _weather = results[0] as WeatherData;
        _forecast = results[1] as List<ForecastItem>;
        _pm25 = results[2] as double;
        _livability = computeLivability(
          tempC: _weather!.tempC,
          pm25: _pm25,
          humidity: _weather!.humidity,
        );
      });
    } catch (e) {
      setState(() => _errorMessage = "Connection Error");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getAssetPath() {
    if (_weather == null) return "assets/images/default.png";

    final condition = _weather!.condition.toLowerCase();
    final isNight = _weather!.iconCode.contains('n');

    if (condition.contains('rain') || condition.contains('drizzle')) {
      return "assets/images/rain.png";
    } else if (condition.contains('snow')) {
      return "assets/images/snow.png";
    } else if (condition.contains('cloud')) {
      return isNight
          ? "assets/images/clouds_night.png"
          : "assets/images/clouds_day.png";
    } else if (condition.contains('clear')) {
      return isNight
          ? "assets/images/clear_night.png"
          : "assets/images/clear_day.png";
    } else if (condition.contains('haze') ||
        condition.contains('mist') ||
        condition.contains('smoke') ||
        condition.contains('dust') ||
        condition.contains('fog')) {
      return "assets/images/haze.png";
    }
    return "assets/images/default.png";
  }

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CitySearchSheet(
        apiService: _apiService,
        onCitySelected: (lat, lon) {
          Navigator.pop(context);
          _searchCity(lat: lat, lon: lon);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Dynamic Background
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: Container(
              key: ValueKey(_weather?.condition ?? "default"),
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(_getAssetPath()),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.45),
                    BlendMode.darken,
                  ),
                ),
              ),
            ),
          ),

          // 2. Main Content
          if (_isLoading && _weather == null)
            const Center(
                child: CupertinoActivityIndicator(
                    radius: 20, color: Colors.white))
          else if (_errorMessage != null)
            _buildErrorView()
          else if (_weather != null)
              SafeArea(
                child: PageView(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() => _tabIndex = index);
                  },
                  children: [
                    _buildDashboardTab(),
                    _buildLivabilityTab(),
                    _buildMoreTab(),
                  ],
                ),
              ),

          // 3. Pill Navbar
          if (_weather != null && _errorMessage == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: GlassCard(
                  width: 220,
                  height: 65,
                  borderRadius: BorderRadius.circular(40),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildNavIcon(0, CupertinoIcons.cloud_fill),
                      _buildNavIcon(1, CupertinoIcons.heart_fill),
                      _buildNavIcon(2, CupertinoIcons.square_grid_2x2_fill),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavIcon(int index, IconData icon) {
    final bool isSelected = _tabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _tabIndex = index);
        _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.white54,
          size: 22,
        ),
      ),
    );
  }

  // --- TABS ---

  Widget _buildDashboardTab() {
    // --- CHANGED: Use Indian AQI ---
    final int indAqi = _pm25 != null ? ApiService.pm25ToIndianAQI(_pm25!) : 0;

    return RefreshIndicator(
      onRefresh: _fetchData,
      color: Colors.white,
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _showSearchSheet,
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.location_solid,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _weather!.cityName,
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      const Icon(CupertinoIcons.chevron_down,
                          color: Colors.white70, size: 14),
                    ],
                  ),
                ),
                GlassCard(
                  padding: const EdgeInsets.all(8),
                  borderRadius: BorderRadius.circular(50),
                  onTap: _handleGPS,
                  child: const Icon(CupertinoIcons.location_fill,
                      color: Colors.white, size: 16),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  DateFormat('EEEE, d MMMM').format(DateTime.now()),
                  style: GoogleFonts.poppins(
                      color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Hero
            Column(
              children: [
                Text(
                  "${_weather!.tempC.toStringAsFixed(0)}°",
                  style: GoogleFonts.poppins(
                    fontSize: 110,
                    height: 1.0,
                    fontWeight: FontWeight.w100,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _weather!.condition,
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: Colors.white70,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  "H:${_weather!.tempMax.toStringAsFixed(0)}°  L:${_weather!.tempMin.toStringAsFixed(0)}°",
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 50),

            // Stats Strip
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              borderRadius: BorderRadius.circular(25),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMinimalStatItem(CupertinoIcons.wind,
                      "${_weather!.windSpeed}", "m/s"),
                  _buildMinimalStatItem(CupertinoIcons.drop,
                      "${_weather!.humidity.toStringAsFixed(0)}", "%"),
                  _buildMinimalStatItem(CupertinoIcons.eye,
                      "${(_weather!.visibility / 1000).toStringAsFixed(1)}", "km"),
                  _buildMinimalStatItem(CupertinoIcons.gauge,
                      "${_weather!.pressure.toStringAsFixed(0)}", "hPa"),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // AQI & Score Split
            Row(
              children: [
                Expanded(
                  child: GlassCard(
                    height: 120,
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Icon(Icons.masks,
                                color: Colors.white70, size: 20),
                            Text("AQI",
                                style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Text(
                          _pm25 != null ? "$indAqi" : "--",
                          style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        Text(
                          "IND AQI", // Updated Label
                          style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassCard(
                    height: 120,
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Icon(Icons.favorite_border,
                                color: Colors.white70, size: 20),
                            Text("SCORE",
                                style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        if (_livability != null)
                          Text(
                            _livability!.toStringAsFixed(0),
                            style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: _livability! > 70
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent),
                          )
                        else
                          const Text("--",
                              style: TextStyle(color: Colors.white)),
                        Text(
                          _livability != null && _livability! > 70
                              ? "Excellent"
                              : "Moderate",
                          style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Hourly
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _forecast.length > 8 ? 8 : _forecast.length,
                itemBuilder: (ctx, i) {
                  final item = _forecast[i];
                  return Container(
                    width: 60,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('j').format(item.dt),
                          style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Image.network(
                          "https://openweathermap.org/img/wn/${item.iconCode}.png",
                          width: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "${item.temp.toStringAsFixed(0)}°",
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivabilityTab() {
    // Calculate breakdown scores
    final double tempScore = cTemp(_weather!.tempC);
    final double aqiScore = cAqi(_pm25);
    final double humidityScore = cHumidity(_weather!.humidity);

    // --- CHANGED: Use Indian AQI ---
    final int indAqi = _pm25 != null ? ApiService.pm25ToIndianAQI(_pm25!) : 0;

    // Determine advice text
    String advice = "Data unavailable.";
    if (_livability != null) {
      if (_livability! >= 80) {
        advice = "Conditions are perfect! Great for outdoor activities.";
      } else if (_livability! >= 60) {
        advice = "Good conditions overall, though some sensitivities may apply.";
      } else if (_livability! >= 40) {
        advice = "Moderate conditions. Limit prolonged exertion if sensitive.";
      } else {
        advice = "Conditions are poor. It is recommended to stay indoors.";
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Health & Comfort",
              style: GoogleFonts.poppins(
                  fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Text("Real-time livability analysis",
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white54)),

          const SizedBox(height: 40),

          // Main Score Display
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer Glow
                Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                          colors: [
                            (_livability ?? 0) > 70
                                ? Colors.greenAccent.withOpacity(0.2)
                                : Colors.orangeAccent.withOpacity(0.2),
                            Colors.transparent
                          ],
                          stops: const [0.3, 1.0]
                      )
                  ),
                ),
                GlassCard(
                  width: 180,
                  height: 180,
                  borderRadius: BorderRadius.circular(100),
                  borderWidth: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("${_livability?.toStringAsFixed(0) ?? '--'}",
                          style: GoogleFonts.poppins(
                              fontSize: 64, fontWeight: FontWeight.w200, color: Colors.white)),
                      Text("LIVABILITY",
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54, letterSpacing: 2, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Advice Box
          GlassCard(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                Icon(CupertinoIcons.info_circle, color: Colors.white.withOpacity(0.8), size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    advice,
                    style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.9), fontSize: 14, height: 1.4),
                  ),
                )
              ],
            ),
          ),

          const SizedBox(height: 30),

          Text("Breakdown", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          // Breakdown List
          _buildLivabilityRow("Air Quality", aqiScore, _pm25 != null ? "IND AQI: $indAqi" : "--"),
          const SizedBox(height: 12),
          _buildLivabilityRow("Thermal Comfort", tempScore, "${_weather!.tempC.toStringAsFixed(1)}°C"),
          const SizedBox(height: 12),
          _buildLivabilityRow("Humidity", humidityScore, "${_weather!.humidity.toStringAsFixed(0)}%"),
        ],
      ),
    );
  }

  Widget _buildLivabilityRow(String label, double score, String value) {
    Color barColor = score > 70 ? Colors.greenAccent : (score > 40 ? Colors.orangeAccent : Colors.redAccent);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500)),
              Text(value, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("More",
              style: GoogleFonts.poppins(
                  fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 30),
          _buildOptionTile(CupertinoIcons.settings, "Settings"),
          _buildOptionTile(CupertinoIcons.info, "About SkySense"),
          _buildOptionTile(CupertinoIcons.share, "Share App"),
        ],
      ),
    );
  }

  Widget _buildOptionTile(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 16),
            Text(label, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16)),
            const Spacer(),
            const Icon(CupertinoIcons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimalStatItem(IconData icon, String value, String unit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        Text(
          unit,
          style: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: GlassCard(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              "Connection Failed",
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? "Unknown Error",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            CupertinoButton(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              onPressed: _fetchData,
              child:
              const Text("Retry", style: TextStyle(color: Colors.black)),
            )
          ],
        ),
      ),
    );
  }
}

// --- CITY SEARCH SHEET ---
class _CitySearchSheet extends StatefulWidget {
  final ApiService apiService;
  final Function(double, double) onCitySelected;

  const _CitySearchSheet(
      {required this.apiService, required this.onCitySelected});

  @override
  State<_CitySearchSheet> createState() => _CitySearchSheetState();
}

class _CitySearchSheetState extends State<_CitySearchSheet> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.length > 2) {
        setState(() => _isLoading = true);
        try {
          final results = await widget.apiService.searchCities(query);
          if (mounted) {
            setState(() {
              _suggestions = results;
              _isLoading = false;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _isLoading = false);
        }
      } else {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _isLoading = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text("Find City",
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 15),
          CupertinoSearchTextField(
            controller: _controller,
            placeholder: "Type a city name...",
            style: GoogleFonts.poppins(color: Colors.white),
            placeholderStyle: GoogleFonts.poppins(color: Colors.white54),
            backgroundColor: Colors.white.withOpacity(0.1),
            itemColor: Colors.white70,
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CupertinoActivityIndicator(color: Colors.white)))
          else if (_suggestions.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _suggestions.length,
                separatorBuilder: (c, i) =>
                    Divider(color: Colors.white.withOpacity(0.1), height: 1),
                itemBuilder: (ctx, i) {
                  final city = _suggestions[i];
                  return ListTile(
                    title: Text(city['name'],
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text("${city['state'] ?? ''}, ${city['country']}",
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 12)),
                    onTap: () =>
                        widget.onCitySelected(city['lat'], city['lon']),
                  );
                },
              ),
            )
          else if (_controller.text.length > 2)
              Center(
                child: Text("No cities found",
                    style: GoogleFonts.poppins(color: Colors.white54)),
              ),
        ],
      ),
    );
  }
}