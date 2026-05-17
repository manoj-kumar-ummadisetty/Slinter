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
  Timer? _sliderTimer;
  AnimationController? _mapAnimationController;
  StreamSubscription<Position>? _liveLocationSub;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  List<Marker> markers = [];

  LatLng? selectedPoint;
  double radius = 200;
  String zoneName = "";
  String placeName = "Fetching...";

  @override
  void initState() {
    super.initState();
    Future.microtask(stopBackgroundService);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sliderTimer?.cancel(); // ✅ ADD THIS
    _liveLocationSub?.cancel();
    _mapAnimationController?.dispose();
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
              ),
              CircleLayer(
                circles: selectedPoint == null
                    ? <CircleMarker<Object>>[]
                    : <CircleMarker<Object>>[
                        CircleMarker<Object>(
                          point: selectedPoint!,
                          radius: radius,
                          useRadiusInMeter: true,
                          color: Colors.orangeAccent.withOpacity(0.3),
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
                style: TextStyle(color: Colors.white, fontSize: 16),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: "Search location here",
                  hintStyle: TextStyle(color: Colors.white),
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

      final osmResults = await _searchWithOpenStreetMap(query);
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

      _showSnack("Town location not found");
    } catch (e) {
      print("SEARCH ERROR: $e");
      _showSnack("Search failed");
    }
  }

  Future<List<_SearchResult>> _searchWithOpenStreetMap(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final anchor = _isMapReady ? _mapController.camera.center : selectedPoint;
    final queryParams = <String, String>{
      'format': 'jsonv2',
      'q': trimmedQuery,
      'limit': '10',
      'addressdetails': '1',
      'countrycodes': 'in',
      'dedupe': '1',
    };

    if (anchor != null) {
      const delta = 0.7;
      queryParams['viewbox'] =
          '${anchor.longitude - delta},${anchor.latitude + delta},'
          '${anchor.longitude + delta},${anchor.latitude - delta}';
      queryParams['bounded'] = '0';
    }

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
      const placeTypes = {
        'city',
        'town',
        'village',
        'hamlet',
        'suburb',
        'neighbourhood',
        'locality',
        'quarter',
      };
      const amenityTypes = {
        'college',
        'university',
        'school',
        'hospital',
        'clinic',
      };
      const businessCategories = {'shop', 'office', 'craft'};
      const businessTypes = {
        'company',
        'industrial',
        'factory',
        'works',
        'warehouse',
      };
      final isPlace = category == 'place' && placeTypes.contains(type);
      final isAmenity = category == 'amenity' && amenityTypes.contains(type);
      final isBusiness =
          businessCategories.contains(category) || businessTypes.contains(type);
      final isBuilding = category == 'building' && type != 'residential';

      if (category == 'boundary' || type == 'administrative') continue;
      if (!isPlace && !isAmenity && !isBusiness && !isBuilding) continue;

      final importance =
          double.tryParse(item['importance']?.toString() ?? '') ?? 0;
      final lowerName = displayName.toLowerCase();

      var score = importance * 100;
      for (final token in queryTokens) {
        if (token.isNotEmpty && lowerName.contains(token)) score += 15;
      }

      if (isAmenity || isBusiness || isBuilding) {
        score += 35;
      }
      if (isPlace) {
        score += 25;
      }
      if (type == 'university' || type == 'college' || type == 'hospital') {
        score += 20;
      }

      final latLng = LatLng(lat, lon);
      if (anchor != null) {
        final distanceKm =
            Geolocator.distanceBetween(
              anchor.latitude,
              anchor.longitude,
              lat,
              lon,
            ) /
            1000;
        score += (80 - distanceKm).clamp(-80, 80);
      }

      results.add(
        _SearchResult(latLng: latLng, displayName: displayName, score: score),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(6).toList();
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

  void _applySearchedLocation({
    required LatLng latLng,
    required String locationName,
  }) {
    if (!mounted) return;

    _stopLiveLocationStream();
    _jumpMapTo(latLng);

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

    showRadiusSlider();
  }

  /// Reverse geocoding (UNCHANGED)
  Map<String, String> _locationCache = {};
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

  void animatedMapMove(LatLng dest, double destZoom) {
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

    final controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _mapAnimationController = controller;

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );

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

    controller.forward();
  }

  void safeMapMove(LatLng newLatLng) {
    if (!_isMapReady || !mounted) return;

    if (selectedPoint == null) {
      animatedMapMove(newLatLng, 16);
      return;
    }

    double distance = Geolocator.distanceBetween(
      selectedPoint!.latitude,
      selectedPoint!.longitude,
      newLatLng.latitude,
      newLatLng.longitude,
    );

    // ✅ Only move if distance is significant
    if (distance > 30) {
      animatedMapMove(newLatLng, 16);
    }
  }

  void _jumpMapTo(LatLng latLng) {
    if (!_isMapReady || !mounted) return;

    _mapAnimationController?.dispose();
    _mapAnimationController = null;
    _mapController.move(latLng, 16);
  }

  void _placeCurrentLocationMarker(
    LatLng latLng, {
    bool moveMap = true,
    bool updateAddress = false,
  }) {
    if (!mounted) return;

    if (moveMap) {
      _jumpMapTo(latLng);
    }

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
      if (selectedPoint != null) _jumpMapTo(selectedPoint!);
      return;
    }

    if (!await _ensureLocationReady()) return;

    _isLiveTracking = true;
    _hasLiveAddress = false;

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      _placeCurrentLocationMarker(
        LatLng(last.latitude, last.longitude),
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
          (position) {
            final latLng = LatLng(position.latitude, position.longitude);
            final shouldUpdateAddress = !_hasLiveAddress;
            _placeCurrentLocationMarker(
              latLng,
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

  Future<void> _updateMap(Position position) async {
    final latLng = LatLng(position.latitude, position.longitude);

    safeMapMove(latLng);
    setState(() {
      selectedPoint = latLng;
      markers
        ..clear()
        ..add(
          Marker(
            point: latLng,
            width: 60,
            height: 60,
            child: const Icon(
              Icons.location_on,
              color: Colors.redAccent,
              size: 28,
            ),
          ),
        );
    });

    final name = await getPlaceName(position.latitude, position.longitude);

    if (!mounted) return;

    setState(() {
      placeName = name;
    });
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
                print(newZone);

                await initializeService();
                await initBackgroundService();
                if (!mounted) return;

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
  final double score;

  const _SearchResult({
    required this.latLng,
    required this.displayName,
    required this.score,
  });

  String get primaryName => displayName.split(',').first.trim();

  String get secondaryName {
    final parts = displayName.split(',');
    if (parts.length <= 1) return displayName;
    return parts.skip(1).map((part) => part.trim()).join(', ');
  }
}
