import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:slinter/pages/home_page.dart';
import 'package:slinter/services/background_service.dart';
import 'package:hive/hive.dart';

class AddZonePage extends StatefulWidget {
  final String userName;

  const AddZonePage({super.key, required this.userName});

  @override
  State<AddZonePage> createState() => _AddZonePageState();
}

class _AddZonePageState extends State<AddZonePage>
    with TickerProviderStateMixin {
  bool _isLocating = false; // ✅ ADD THIS
  bool _isMapReady = false;
  bool _isLiveTracking = false;
  bool _hasLiveAddress = false;
  bool _currentLocationCameraMoveStarted = false;
  Timer? _sliderTimer;
  AnimationController? _mapAnimationController;
  StreamSubscription<Position>? _liveLocationSub;
  final MapController _mapController = MapController();
  late final TileProvider _tileProvider = NetworkTileProvider(
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 500 * 1024 * 1024,
      overrideFreshAge: const Duration(days: 14),
    ),
  );
  final TextEditingController _searchController = TextEditingController();

  List<Marker> markers = [];

  LatLng? selectedPoint;
  double radius = 200;
  String zoneName = "";
  String placeName = "Fetching...";

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sliderTimer?.cancel(); // ✅ ADD THIS
    _liveLocationSub?.cancel();
    _mapAnimationController?.dispose();
    _tileProvider.dispose();
    Future.microtask(syncBackgroundServiceWithZones);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 44, 44, 44),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orangeAccent,
        onPressed: _goToCurrentLocation,
        child: const Icon(Icons.my_location, color: Colors.black),
      ),
      body: Stack(
        children: [
          /// MAP (UNCHANGED)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(15.691222, 79.547750),
              initialZoom: 15,
              maxZoom: 17,
              minZoom: 3,
              onMapReady: () {
                _isMapReady = true;
              },
              onTap: (tapPosition, latLng) async {
                _stopLiveLocationStream();

                setState(() {
                  selectedPoint = latLng;
                  placeName = "Fetching...";
                  markers.clear();
                  markers.add(
                    Marker(
                      point: latLng,
                      height: 80,
                      width: 80,
                      child: const Icon(
                        Icons.location_on,
                        size: 30,
                        color: Colors.red,
                      ),
                    ),
                  );
                });

                Future.microtask(() async {
                  final newPlace = await getPlaceName(
                    latLng.latitude,
                    latLng.longitude,
                  );
                  if (mounted) {
                    setState(() => placeName = newPlace);
                  }
                });
                showRadiusSlider();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.example.slinter',
                tileProvider: _tileProvider,
                keepBuffer: 4,
                panBuffer: 2,
              ),
              CircleLayer(
                circles: selectedPoint == null
                    ? <CircleMarker<Object>>[]
                    : <CircleMarker<Object>>[
                        CircleMarker<Object>(
                          point: selectedPoint!,
                          radius: radius,
                          useRadiusInMeter: true,
                          color: Colors.orangeAccent.withValues(alpha: 0.3),
                          borderStrokeWidth: 2,
                          borderColor: Colors.orangeAccent,
                        ),
                      ],
              ),
              MarkerLayer(markers: markers),
            ],
          ),

          /// 🔍 SEARCH BAR (ONLY ADDITION)
          Positioned(
            top: 20,
            left: 16,
            right: 16,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 16),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: "Search location here",
                  hintStyle: const TextStyle(color: Colors.white),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.orangeAccent,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white),
                    onPressed: () => _searchController.clear(),
                  ),
                  filled: true,
                  fillColor: Colors.black,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _stopLiveLocationStream();
                    _searchLocation(value.trim());
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// SEARCH LOCATION BY NAME
  Future<void> _searchLocation(String query) async {
    try {
      _showSnack("Searching...");

      final osmResults = await _getSearchResults(query);

      if (osmResults.isNotEmpty) {
        if (osmResults.length == 1) {
          _applySearchedLocation(
            latLng: osmResults.first.latLng,
            locationName: osmResults.first.displayName,
          );
        } else {
          _showSearchResults(osmResults);
        }
        return;
      }

      _showSnack("Location not found");
    } catch (_) {
      _showSnack("Search failed");
    }
  }

  Future<List<_SearchResult>> _getSearchResults(String query) async {
    final osmResults = await _searchWithOpenStreetMap(query);
    if (osmResults.isNotEmpty) return osmResults;

    return _searchWithPlatformGeocoder(query);
  }

  Future<List<_SearchResult>> _searchWithOpenStreetMap(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final queryParams = <String, String>{
      'format': 'jsonv2',
      'q': trimmedQuery,
      'limit': '30',
      'addressdetails': '1',
      'namedetails': '1',
      'extratags': '1',
      'dedupe': '1',
    };

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      queryParams,
    );

    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent': 'Slinter/1.0 com.example.slinter',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return [];

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return [];

    final queryTokens = trimmedQuery.toLowerCase().split(RegExp(r'\s+'));
    final normalizedQuery = _normalizeSearchText(trimmedQuery);
    final results = <_SearchResult>[];

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;

      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      if (lat == null || lon == null) continue;

      final displayName = (item['display_name'] ?? trimmedQuery).toString();
      final category = (item['category'] ?? item['class'] ?? '')
          .toString()
          .toLowerCase();
      final type = (item['type'] ?? '').toString().toLowerCase();
      final addresstype = (item['addresstype'] ?? '').toString().toLowerCase();
      final name = _bestSearchName(item, displayName);
      final normalizedName = _normalizeSearchText(name);
      final normalizedDisplay = _normalizeSearchText(displayName);

      if (_isAdministrativeBoundary(category, type, addresstype)) continue;

      final importance =
          double.tryParse(item['importance']?.toString() ?? '') ?? 0;
      final lowerName = displayName.toLowerCase();

      var score = importance * 100;
      if (normalizedName == normalizedQuery) {
        score += 220;
      } else if (normalizedName.startsWith(normalizedQuery)) {
        score += 150;
      } else if (normalizedDisplay.contains(normalizedQuery)) {
        score += 100;
      }

      for (final token in queryTokens) {
        if (token.isNotEmpty && lowerName.contains(token)) score += 15;
      }

      if (_isPrecisePlace(category, type)) {
        score += 45;
      } else if (category == 'place') {
        score += 35;
      }

      final latLng = LatLng(lat, lon);

      results.add(
        _SearchResult(
          latLng: latLng,
          displayName: displayName,
          name: name,
          score: score,
          category: category,
          type: type,
        ),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(8).toList();
  }

  Future<List<_SearchResult>> _searchWithPlatformGeocoder(String query) async {
    try {
      final locations = await locationFromAddress(query);
      return locations
          .map(
            (location) => _SearchResult(
              latLng: LatLng(location.latitude, location.longitude),
              displayName: query,
              name: query,
              score: 0,
              category: 'geocoder',
              type: 'location',
            ),
          )
          .take(3)
          .toList();
    } catch (_) {
      return [];
    }
  }

  bool _isAdministrativeBoundary(
    String category,
    String type,
    String addresstype,
  ) {
    return category == 'boundary' ||
        type == 'administrative' ||
        addresstype == 'boundary';
  }

  bool _isPrecisePlace(String category, String type) {
    return category == 'amenity' ||
        category == 'shop' ||
        category == 'office' ||
        category == 'craft' ||
        category == 'building' ||
        category == 'tourism' ||
        category == 'leisure' ||
        category == 'railway' ||
        category == 'aeroway' ||
        category == 'public_transport' ||
        category == 'healthcare' ||
        category == 'industrial' ||
        {
          'college',
          'university',
          'school',
          'hospital',
          'factory',
          'industrial',
          'company',
          'warehouse',
          'town',
          'village',
          'city',
          'locality',
        }.contains(type);
  }

  String _bestSearchName(Map<String, dynamic> item, String displayName) {
    final namedetails = item['namedetails'];
    if (namedetails is Map) {
      for (final key in ['name', 'name:en', 'official_name', 'short_name']) {
        final value = namedetails[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
    }

    final name = item['name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString();
    }

    return displayName.split(',').first.trim();
  }

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  void _showSearchResults(List<_SearchResult> results) {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Color(0xFF2C2C2C), height: 1),
            itemBuilder: (context, index) {
              final result = results[index];

              return ListTile(
                leading: const Icon(
                  Icons.location_on,
                  color: Colors.orangeAccent,
                ),
                title: Text(
                  result.primaryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  result.secondaryName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _applySearchedLocation(
                    latLng: result.latLng,
                    locationName: result.displayName,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _applySearchedLocation({
    required LatLng latLng,
    required String locationName,
  }) async {
    if (!mounted) return;

    _stopLiveLocationStream();

    setState(() {
      selectedPoint = latLng;
      placeName = locationName;
      markers
        ..clear()
        ..add(
          Marker(
            point: latLng,
            width: 80,
            height: 80,
            child: const Icon(Icons.location_on, color: Colors.red),
          ),
        );
    });

    await _animateCurrentLocationCamera(latLng);
    showRadiusSlider();
  }

  /// Reverse geocoding (UNCHANGED)
  final Map<String, String> _locationCache = {};
  Future<String> getPlaceName(double lat, double lng) async {
    final key = "$lat,$lng";

    // ✅ Return cached result
    if (_locationCache.containsKey(key)) {
      return _locationCache[key]!;
    }

    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final name = "${p.locality}, ${p.administrativeArea}";

        // ✅ Store in cache
        _locationCache[key] = name;

        return name;
      }

      return "Unknown Location";
    } catch (e) {
      return "Unable to fetch location";
    }
  }

  /// Radius selection bottom sheet (UNCHANGED)
  void showRadiusSlider() {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        double tempRadius = radius;

        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setBottom) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Select Radius",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    Slider(
                      inactiveColor: const Color.fromARGB(255, 255, 195, 116),
                      activeColor: Colors.orangeAccent,
                      value: tempRadius,
                      min: 50,
                      max: 1000,
                      divisions: 20,
                      label: "${tempRadius.toInt()} m",
                      onChanged: (value) {
                        setBottom(() => tempRadius = value);
                        setState(() => radius = value);
                      },
                    ),
                    Text(
                      "Selected Radius: ${tempRadius.toInt()} m",
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.black,
                        backgroundColor: Colors.orangeAccent,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        showZoneDetailsPopup();
                      },
                      child: const Text(
                        "Apply Radius",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> animatedMapMove(
    LatLng dest,
    double destZoom, {
    Duration duration = const Duration(milliseconds: 1200),
    Curve curve = Curves.fastOutSlowIn,
  }) async {
    if (!_isMapReady || !mounted) return;

    _mapAnimationController?.dispose();

    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: dest.latitude,
    );

    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: dest.longitude,
    );

    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: destZoom,
    );

    final controller = AnimationController(duration: duration, vsync: this);
    _mapAnimationController = controller;

    final animation = CurvedAnimation(parent: controller, curve: curve);

    controller.addListener(() {
      if (!_isMapReady || !mounted) return;

      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
        if (_mapAnimationController == controller) {
          _mapAnimationController = null;
        }
      }
    });

    await controller.forward();
  }

  Future<void> _animateCurrentLocationCamera(LatLng destination) async {
    if (!_isMapReady || !mounted) return;

    final currentZoom = _mapController.camera.zoom;
    final zoomOut = (currentZoom - 2.5).clamp(5.0, 14.0).toDouble();

    await animatedMapMove(
      _mapController.camera.center,
      zoomOut,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;

    await animatedMapMove(
      destination,
      zoomOut,
      duration: const Duration(milliseconds: 760),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;

    await animatedMapMove(
      destination,
      16,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpMapTo(LatLng latLng) {
    if (!_isMapReady || !mounted) return;

    _mapAnimationController?.dispose();
    _mapAnimationController = null;
    _mapController.move(latLng, 16);
  }

  Future<void> _placeCurrentLocationMarker(
    LatLng latLng, {
    bool moveMap = true,
    bool cinematicMove = false,
    bool updateAddress = false,
  }) async {
    if (!mounted) return;

    setState(() {
      selectedPoint = latLng;
      markers
        ..clear()
        ..add(
          Marker(
            point: latLng,
            width: 60,
            height: 60,
            child: const Icon(Icons.location_on, color: Colors.redAccent),
          ),
        );
    });

    if (moveMap) {
      if (cinematicMove) {
        await _animateCurrentLocationCamera(latLng);
      } else {
        _jumpMapTo(latLng);
      }
    }

    if (updateAddress) {
      Future.microtask(() async {
        final newPlace = await getPlaceName(latLng.latitude, latLng.longitude);
        if (mounted && selectedPoint == latLng) {
          setState(() => placeName = newPlace);
        }
      });
    }
  }

  void _stopLiveLocationStream() {
    _liveLocationSub?.cancel();
    _liveLocationSub = null;
    _isLiveTracking = false;
    _hasLiveAddress = false;
    _currentLocationCameraMoveStarted = false;
  }

  Future<bool> _ensureLocationReady() async {
    await stopBackgroundService();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showSnack("Location permission required");
      return false;
    }

    return true;
  }

  Future<void> _startLiveLocationStream() async {
    if (_isLiveTracking) {
      if (selectedPoint != null) {
        await _animateCurrentLocationCamera(selectedPoint!);
      }
      return;
    }

    if (!await _ensureLocationReady()) return;

    _isLiveTracking = true;
    _hasLiveAddress = false;
    _currentLocationCameraMoveStarted = false;

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      _currentLocationCameraMoveStarted = true;
      await _placeCurrentLocationMarker(
        LatLng(last.latitude, last.longitude),
        cinematicMove: true,
        updateAddress: true,
      );
      _hasLiveAddress = true;
      _scheduleRadiusSlider();
    }

    _liveLocationSub?.cancel();
    _liveLocationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          (position) async {
            final latLng = LatLng(position.latitude, position.longitude);
            final shouldUpdateAddress = !_hasLiveAddress;
            final shouldAnimateCamera = !_currentLocationCameraMoveStarted;
            if (shouldAnimateCamera) {
              _currentLocationCameraMoveStarted = true;
            }

            await _placeCurrentLocationMarker(
              latLng,
              cinematicMove: shouldAnimateCamera,
              updateAddress: shouldUpdateAddress,
            );
            if (shouldUpdateAddress) {
              _hasLiveAddress = true;
              _scheduleRadiusSlider();
            }
          },
          onError: (_) {
            _showSnack("Live location stopped");
            _stopLiveLocationStream();
          },
        );
  }

  Future<void> _goToCurrentLocation() async {
    if (_isLocating) return;
    _isLocating = true;

    try {
      await _startLiveLocationStream();
    } finally {
      _isLocating = false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.black),
      );
  }

  void _scheduleRadiusSlider() {
    _sliderTimer?.cancel(); // cancel previous timer

    _sliderTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || selectedPoint == null) return;
      showRadiusSlider();
    });
  }

  /// Zone details dialog (UNCHANGED)
  void showZoneDetailsPopup() {
    if (!mounted || selectedPoint == null) return;

    showDialog(
      context: context,
      builder: (context) {
        String tempName = zoneName;

        return AlertDialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            "Zone Details",
            style: TextStyle(color: Colors.orangeAccent),
          ),
          content: StatefulBuilder(
            builder: (context, setPopup) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Enter Zone Name",
                      labelStyle: TextStyle(color: Colors.white),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.orangeAccent,
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.orangeAccent,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (value) => tempName = value,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "Location: $placeName",
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Radius: ${radius.toInt()} meters",
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Longitude: ${selectedPoint!.longitude.toStringAsFixed(6)}",
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    "Latitude: ${selectedPoint!.latitude.toStringAsFixed(6)}",
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text("Add"),
              onPressed: () async {
                if (tempName.trim().isEmpty || selectedPoint == null) return;

                final newZone = {
                  'zoneName': tempName,
                  'location': placeName,
                  'latitude': selectedPoint!.latitude,
                  'longitude': selectedPoint!.longitude,
                  'radius': radius,
                  'isActive': true,
                  'isFavorite': false,
                  'userId': Hive.box('profile').get('userId'),
                };

                final box = Hive.box('silentZonesBox');

                /// 🔥 SAVE PERMANENTLY
                await box.add(newZone);
                await syncBackgroundServiceWithZones();
                if (!context.mounted) return;

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => HomePage(userName: widget.userName),
                  ),
                  (route) => false,
                );
                // return success
              },
            ),
          ],
        );
      },
    );
  }
}

class _SearchResult {
  final LatLng latLng;
  final String displayName;
  final String name;
  final double score;
  final String category;
  final String type;

  const _SearchResult({
    required this.latLng,
    required this.displayName,
    required this.name,
    required this.score,
    required this.category,
    required this.type,
  });

  String get primaryName =>
      name.trim().isEmpty ? displayName.split(',').first.trim() : name.trim();

  String get secondaryName {
    final parts = displayName.split(',');
    if (parts.length <= 1) return displayName;
    return parts.skip(1).map((part) => part.trim()).join(', ');
  }

  IconData get icon {
    if (type == 'college' || type == 'university' || type == 'school') {
      return Icons.school;
    }
    if (type == 'hospital' || category == 'healthcare') {
      return Icons.local_hospital;
    }
    if (category == 'shop') return Icons.storefront;
    if (category == 'office' ||
        type == 'company' ||
        type == 'factory' ||
        type == 'industrial') {
      return Icons.business;
    }
    if (category == 'railway' ||
        category == 'aeroway' ||
        category == 'public_transport') {
      return Icons.directions_transit;
    }
    if (category == 'place') return Icons.location_city;
    return Icons.place;
  }
}
