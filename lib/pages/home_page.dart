import 'package:flutter/material.dart';
import 'package:slinter/pages/BottomNavPages/add_zone_page.dart';
import 'package:slinter/pages/BottomNavPages/favorite_page.dart';
import 'package:slinter/pages/BottomNavPages/silent_zones_page.dart';
import 'package:slinter/pages/get_started_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  final String userName;
  const HomePage({super.key, required this.userName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late String _userName;
  late List<Widget> pages;

  Menus currentIndex = Menus.home;

  @override
  void initState() {
    super.initState();

    _userName = widget.userName;

    pages = [
      SilentZonesPage(userName: _userName),
      AddZonePage(userName: _userName),
      FavoritePage(),
    ];
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _userName);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Text(
              'Edit Name',
              style: TextStyle(color: Colors.orangeAccent),
            ),
            SizedBox(width: 8),
            Icon(Icons.edit, color: Colors.orangeAccent, size: 22),
          ],
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: Colors.grey.shade900,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.white,
            ),
           onPressed: () async 
           {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('userName', newName);

                setState(() {
                  _userName = newName;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope
    (
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GetStartedPage(userName: _userName),
          ),
        );
        return false; // prevents app from closing
      },
      child: Scaffold(
        backgroundColor: Color.fromARGB(255, 44, 44, 44),
        appBar: AppBar(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadiusGeometry.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          backgroundColor: Colors.black,
          automaticallyImplyLeading: false,
          title: Text(
            'Slinter',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            Builder(
              builder: (context) {
                return IconButton(
                  onPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                  icon:
                      const Icon(Icons.more_vert, color: Colors.white),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: Drawer(
          backgroundColor: Colors.black87,
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(height: 46),
                const Icon(
                  Icons.person,
                  color: Colors.orangeAccent,
                  size: 40,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 20),
                    GestureDetector(
                      onTap: _showEditNameDialog,
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: IndexedStack(
          index: currentIndex.index,
          children: pages,
        ),
        bottomNavigationBar: SafeArea(
          child: MyBottomNavigationBar(
            currentIndex: currentIndex,
            onTap: (value) {
              setState(() {
                currentIndex = value;
              });
            },
          ),
        ),
      ),
    );
  }
}

enum Menus {
  home,
  addzone,
  favorite,
}

class MyBottomNavigationBar extends StatelessWidget {
  final Menus currentIndex;
  final ValueChanged<Menus> onTap;
  const MyBottomNavigationBar(
      {super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      child: Stack(
        children: [
          Positioned(
            top: 17,
            left: 0,
            right: 0,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: IconButton(
                      onPressed: () {
                        onTap(Menus.home);
                      },
                      icon: Icon(Icons.home),
                      iconSize: 28,
                      color: currentIndex == Menus.home
                          ? Colors.orange
                          : Colors.white,
                    ),
                  ),
                  Spacer(),
                  Expanded(
                    child: IconButton(
                      onPressed: () {
                        onTap(Menus.favorite);
                      },
                      icon: Icon(Icons.favorite),
                      iconSize: 28,
                      color: currentIndex == Menus.favorite
                          ? Colors.orange
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: () {
                onTap(Menus.addzone);
              },
              child: Container(
                height: 64,
                width: 64,
                decoration: const BoxDecoration(
                  color: Colors.orangeAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Icon(
                  Icons.add,
                  size: 36,
                  color: currentIndex == Menus.addzone
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
