import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';


class FavoritePage extends StatelessWidget {


  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('silentZonesBox');

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 44, 44, 44),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Text(
              'Favourite Zones',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ValueListenableBuilder(
                valueListenable: box.listenable(),
                builder: (context, Box box, _) {
                  final favList = box.values
                      .where((value) =>
                          value is Map &&
                          value['isFavorite'] == true)
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList();

                  if (favList.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.heart_broken_sharp,
                              size: 60, color: Colors.white54),
                          SizedBox(height: 12),
                          Text(
                            'No Favourite Zones Found',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: favList.length,
                    itemBuilder: (context, index) {
                      final zone = favList[index];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orangeAccent.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Zone Name: ',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 16),
                                      ),
                                      Expanded
                                      (
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
                                    children: [
                                      const Text(
                                        'Location: ',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 14),
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
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                Text(
                                  zone['isActive']
                                      ? "status: ON"
                                      : "status: OFF",
                                  style: TextStyle(
                                    color: zone['isActive']
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
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
