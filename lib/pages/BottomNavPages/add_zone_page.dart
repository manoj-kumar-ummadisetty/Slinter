import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:slinter/pages/home_page.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class AddZonePage extends StatefulWidget {
  final String userName;

  const AddZonePage({
    super.key,
    required this.userName,
  });
  

  @override
  State<AddZonePage> createState() => _AddZonePageState();
}

class _AddZonePageState extends State<AddZonePage>
with TickerProviderStateMixin
{
  bool _isLocating = false; // ✅ ADD THIS
  Timer? _sliderTimer;

  bool _isSliderScheduled = false;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  

  List<Marker> markers = [];

  LatLng? selectedPoint;
  double radius = 200;
  String zoneName = "";
  String placeName = "Fetching...";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 44, 44, 44),
      floatingActionButton: FloatingActionButton
      (
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
              onTap: (tapPosition, latLng) async {
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

                String newPlace =
                    await getPlaceName(latLng.latitude, latLng.longitude);

                if (!mounted) return;
                setState(() => placeName = newPlace);

                showRadiusSlider();
              },
            ),
            children: [
              TileLayer
              (
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
                        )
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
                style: TextStyle
                (
                  color: Colors.white,
                  fontSize: 16,
                ),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: "Search location here",
                  hintStyle: TextStyle
                  (
                    color: Colors.white,
                  ),
                  prefixIcon: const Icon(Icons.search,color: Colors.orangeAccent,),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear,color: Colors.white,),
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

    // 🔥 STEP 1: Normalize query
    final cleanQuery = query.trim().toLowerCase();

    // 🔥 STEP 2: Get multiple results
    final locations = await locationFromAddress(
      "$cleanQuery, Andhra Pradesh, India",
    );

    if (locations.isEmpty) {
      _showSnack("Location not found");
      return;
    }

    Location? bestMatch;
    double bestScore = -1;

    // 🔥 STEP 3: SCORE EACH LOCATION
    for (var loc in locations.take(5))
    {
      try {
        final placemarks = await placemarkFromCoordinates(
          loc.latitude,
          loc.longitude,
        );

        if (placemarks.isEmpty) continue;

        final place = placemarks.first;

        final locality = (place.locality ?? "").toLowerCase();
        final subLocality = (place.subLocality ?? "").toLowerCase();
        final admin = (place.administrativeArea ?? "").toLowerCase();

        double score = 0;

        // 🎯 Exact match (highest priority)
        if (locality == cleanQuery) score += 100;

        // 🎯 Partial match
        if (locality.contains(cleanQuery)) score += 60;
        if (subLocality.contains(cleanQuery)) score += 40;

        // 🎯 State match (extra boost)
        if (admin.contains("andhra")) score += 20;

        // 🎯 Bonus for closer coordinates (optional tweak)
        // You can later improve this using user location

        if (score > bestScore) {
          bestScore = score;
          bestMatch = loc;
        }
      } catch (_) {}
    }

    // 🔥 STEP 4: fallback
    bestMatch ??= locations.first;

    final latLng = LatLng(bestMatch.latitude, bestMatch.longitude);

    animatedMapMove(latLng, 16);

    setState(() {
      selectedPoint = latLng;
      markers.clear();
      markers.add(
        Marker(
          point: latLng,
          width: 80,
          height: 80,
          child: const Icon(Icons.location_on, color: Colors.red),
        ),
      );
    });

    final newPlace =
        await getPlaceName(latLng.latitude, latLng.longitude);

    if (!mounted) return;

    setState(() => placeName = newPlace);

    showRadiusSlider();
  } catch (e) {
    print("SEARCH ERROR: $e");
    _showSnack("Search failed");
  }
}
  /// Reverse geocoding (UNCHANGED)
  Future<String> getPlaceName(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        Placemark p = placemarks.first;
        return "${p.locality}, ${p.administrativeArea}, ${p.country}";
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
                      inactiveColor:
                          const Color.fromARGB(255, 255, 195, 116),
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
                    )
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void animatedMapMove(LatLng dest, double destZoom)
  {
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

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  Future<void> _goToCurrentLocation() async 
  {
    if (_isLocating) return;
    _isLocating = true;

    try {
      _showSnack("Fetching location...");

      // ✅ Permission
      LocationPermission permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack("Permission denied");
        return;
      }

      // ✅ Get location (simple & reliable)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);

      animatedMapMove(latLng, 16);

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

      final name =
          await getPlaceName(position.latitude, position.longitude);

      setState(() => placeName = name);

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && selectedPoint != null) {
          showRadiusSlider();
        }
      });

    } catch (e) {
      print("LOCATION ERROR: $e");
      _showSnack("Location error");
    } finally {
      _isLocating = false;
    }
  }


  void _showSnack(String message) 
  {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.black,
        ),
      );
  }


  Future<void> _updateMap(Position position) async 
  {
    final latLng = LatLng(position.latitude, position.longitude);

    animatedMapMove(latLng, 16);

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

    final name = await getPlaceName(
      position.latitude,
      position.longitude,
    );

    if (!mounted) return;

    setState(() {
      placeName = name;
    });

    showRadiusSlider();
  }

  void _scheduleRadiusSlider() 
  {
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                        borderSide:
                            BorderSide(color: Colors.orangeAccent, width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: Colors.orangeAccent, width: 2),
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
              style: TextButton.styleFrom(
                foregroundColor: Colors.orangeAccent,
              ),
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton
            (
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
              Navigator.of(context).pushAndRemoveUntil
              (
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
