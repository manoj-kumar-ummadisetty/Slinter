import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:slinter/services/background_service.dart';

class SilentZonesPage extends StatefulWidget {
  final String userName;

  const SilentZonesPage({super.key, required this.userName});

  @override
  State<SilentZonesPage> createState() => _SilentZonesPageState();
}

class _SilentZonesPageState extends State<SilentZonesPage> {
  List<Map<String, dynamic>> zones = [];

  @override
  void initState() {
    super.initState();
    loadZones();
  }

  void loadZones() {
    final box = Hive.box('silentZonesBox');
    final tempZones = <Map<String, dynamic>>[];

    final userId = Hive.box('profile').get('userId');

    for (final entry in box.toMap().entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map && value['userId'] == userId) {
        final zone = Map<String, dynamic>.from(value);
        zone['key'] = key; // ✅ STORE KEY
        tempZones.add(zone);
      }
    }

    tempZones.sort((a, b) {
      final aFav = a['isFavorite'] == true;
      final bFav = b['isFavorite'] == true;
      return aFav == bFav ? 0 : (aFav ? -1 : 1);
    });

    setState(() {
      zones = tempZones;
    });
  }

  void refreshZones() {
    loadZones();
  }

  void _deleteZones(int index) async {
    final box = Hive.box('silentZonesBox');
    await box.delete(zones[index]['key']);
    loadZones();
    await syncBackgroundServiceWithZones();
  }

  void _sortZonesWithAnimation() {
    setState(() {
      zones.sort((a, b) {
        final aFav = a['isFavorite'] == true;
        final bFav = b['isFavorite'] == true;
        if (aFav == bFav) return 0;
        return aFav ? -1 : 1;
      });
    });
  }

  void _deleteZone(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          'Delete Zone?',
          style: TextStyle(color: Colors.orangeAccent),
        ),
        content: const Text(
          'Are you sure you want to delete this silent zone?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _deleteZones(index);
              });

              Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRadius(dynamic radius) {
    final value = radius is num
        ? radius.toDouble()
        : double.tryParse('$radius');
    if (value == null) return 'Unknown';

    return '${value.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 44, 44, 44),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Text(
              'Current Silent Zones',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: zones.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.location_off,
                            color: Colors.white54,
                            size: 60,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No Silent Zones Found',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: zones.length, // ✅ USE zones
                      itemBuilder: (context, index) {
                        final zone = zones[index]; // ✅ USE zones

                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SizeTransition(
                                sizeFactor: animation,
                                axisAlignment: -1,
                                child: child,
                              ),
                            );
                          },
                          child: AnimatedContainer(
                            key: ValueKey(
                              '${zone['key']}_${zone['isFavorite']}',
                            ),
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orangeAccent.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            'Zone Name: ',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              zone['zoneName'],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Location: ',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              zone['location'],
                                              style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Radius: ',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              _formatRadius(zone['radius']),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        onPressed: () async {
                                          setState(() {
                                            zone['isFavorite'] =
                                                !zone['isFavorite'];
                                          });
                                          final box = Hive.box(
                                            'silentZonesBox',
                                          );
                                          await box.put(zone['key'], zone);
                                          Future.delayed(
                                            const Duration(milliseconds: 160),
                                            _sortZonesWithAnimation,
                                          );
                                        },
                                        icon: Icon(
                                          zone['isFavorite']
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: zone['isFavorite']
                                              ? Colors.redAccent
                                              : Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    Text(
                                      zone['isActive'] ? "ON" : "OFF",
                                      style: TextStyle(
                                        color: zone['isActive']
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Switch(
                                      value: zone['isActive'],
                                      inactiveThumbColor: Colors.black12,
                                      inactiveTrackColor: Colors.black,
                                      activeThumbColor: Colors.orangeAccent,
                                      onChanged: (value) async {
                                        setState(() {
                                          zone['isActive'] = value;
                                        });

                                        final box = Hive.box('silentZonesBox');
                                        await box.put(zone['key'], zone);
                                        await syncBackgroundServiceWithZones();
                                      },
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        _deleteZone(index);
                                      },
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
}
