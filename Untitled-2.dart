import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Global variable to store the login state
bool _isLoggedIn = false;

Future<void> _preloadSharedPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance().timeout(Duration(seconds: 3), onTimeout: () {
      print("SharedPreferences.getInstance() timed out after 3 seconds");
      throw TimeoutException("Failed to initialize SharedPreferences within 3 seconds");
    });
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    print("Preloaded isLoggedIn: $_isLoggedIn");
  } catch (e) {
    print("Error preloading SharedPreferences: $e");
    _isLoggedIn = false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _preloadSharedPreferences();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DeviceConnectionState()),
        ChangeNotifierProvider(create: (context) => SettingsState()),
        ChangeNotifierProvider(create: (context) => ThemeModel()),
      ],
      child: MyApp(),
    ),
  );
}

// ThemeModel for Dark Mode
class ThemeModel extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveThemeMode();
    notifyListeners();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> _saveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    Provider.of<ThemeModel>(context, listen: false)._loadThemeMode();
  }

  @override
  Widget build(BuildContext context) {
    final themeModel = Provider.of<ThemeModel>(context);
    return MaterialApp(
      title: "MECHAMINDS",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(),
        primaryColor: const Color.fromARGB(255, 220, 192, 233),
        scaffoldBackgroundColor: const Color.fromARGB(255, 240, 220, 245),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: const Color.fromARGB(255, 180, 150, 200),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.all(Colors.white),
          trackColor: MaterialStateProperty.resolveWith((states) =>
              states.contains(MaterialState.selected) ? Colors.blue : Colors.grey),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        textTheme: GoogleFonts.poppinsTextTheme().apply(
          bodyColor: Colors.black, // Black text in Dark Mode
          displayColor: Colors.black,
        ),
        primaryColor: Colors.black, // Black primary color
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: Colors.white, // White secondary for contrast
          brightness: Brightness.dark,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white, // White text on buttons
            backgroundColor: Colors.grey[800], // Dark grey background for buttons
            padding: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.all(Colors.black), // Black thumb in Dark Mode
          trackColor: MaterialStateProperty.resolveWith((states) =>
              states.contains(MaterialState.selected) ? Colors.white : Colors.grey[600]),
          thumbIcon: MaterialStateProperty.all(const Icon(Icons.done, color: Colors.black)),
        ),
        cardTheme: CardTheme(
          color: Colors.grey[900], // Darker card background
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 6,
        ),
      ),
      themeMode: themeModel.themeMode,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, AsyncSnapshot<User?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          final isAuthenticated = snapshot.hasData || _isLoggedIn;
          return isAuthenticated ? MainScreen() : WelcomePage();
        },
      ),
      routes: {
        '/welcome': (context) => WelcomePage(),
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignUpPage(),
        '/main': (context) => MainScreen(),
      },
    );
  }
}
// SettingsState Provider
class SettingsState with ChangeNotifier {
  bool _soundEnabled = true;
  double _defaultZoom = 14.0;
  bool _isSatelliteDefault = false;

  bool get soundEnabled => _soundEnabled;
  double get defaultZoom => _defaultZoom;
  bool get isSatelliteDefault => _isSatelliteDefault;

  void setSoundEnabled(bool value) {
    _soundEnabled = value;
    notifyListeners();
  }

  void setDefaultZoom(double value) {
    _defaultZoom = value;
    notifyListeners();
  }

  void setIsSatelliteDefault(bool value) {
    _isSatelliteDefault = value;
    notifyListeners();
  }
}

// SoundAndVibration Utility
class SoundAndVibration {
  static final AudioPlayer _audioPlayer = AudioPlayer();

  static Future<void> playSoundAndVibrate(BuildContext context) async {
    final settingsState = Provider.of<SettingsState>(context, listen: false);
    if (settingsState.soundEnabled) {
      try {
        await _audioPlayer.play(AssetSource('button_click.wav'));
        await Haptics.vibrate(HapticsType.light);
      } catch (e) {
        print("Error playing sound or vibrating: $e");
      }
    }
  }

  static void dispose() {
    _audioPlayer.dispose();
  }
}

// DeviceConnectionState Provider
class DeviceConnectionState with ChangeNotifier {
  bool _isConnected = true;

  bool get isConnected => _isConnected;

  void toggleConnection() {
    _isConnected = !_isConnected;
    notifyListeners();
  }
}

// Welcome Page
class WelcomePage extends StatefulWidget {
  @override
  _WelcomePageState createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  void initState() {
    super.initState();
    Timer(Duration(seconds: 5), () {
      try {
        Navigator.pushReplacementNamed(context, '/login'); // Updated to navigate to LoginPage
      } catch (e) {
        print("Navigation error: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 209, 175, 224),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/walking_stick.png',
              width: 150,
              height: 150,
              errorBuilder: (context, error, stackTrace) {
                print("Error loading image: $error");
                return Icon(Icons.accessibility, size: 150);
              },
            ),
            SizedBox(height: 20),
            Text(
              "MECHAMINDS",
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// LoginPage
class LoginPage extends StatelessWidget {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  Future<void> _setLoggedIn(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', value);
      _isLoggedIn = value;
    } catch (e) {
      print("Error setting login state: $e");
    }
  }

  Future<void> _signIn(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter email and password")),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _setLoggedIn(true);
      SoundAndVibration.playSoundAndVibrate(context);
      Navigator.pushReplacementNamed(context, '/main');
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case "wrong-password":
          errorMessage = "Incorrect password. Please try again.";
          break;
        case "user-not-found":
          errorMessage = "No user found with this email.";
          break;
        case "invalid-email":
          errorMessage = "Invalid email format.";
          break;
        default:
          errorMessage = "Login failed: ${e.message}";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Login"),
        backgroundColor: const Color.fromARGB(255, 209, 175, 224),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: "Email"),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _signIn(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 209, 175, 224),
                foregroundColor: const Color.fromARGB(255, 175, 166, 166),
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text(
                "Login",
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.black),
              ),
            ),
            SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/signup');
              },
              child: Text("Don't have an account? Sign Up", style: GoogleFonts.poppins()),
            ),
          ],
        ),
      ),
    );
  }
}

// SignUpPage
class SignUpPage extends StatelessWidget {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _setLoggedIn(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', value);
      _isLoggedIn = value;
    } catch (e) {
      print("Error setting login state: $e");
    }
  }

  Future<void> _signUp(BuildContext context) async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }
    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await userCredential.user?.updateDisplayName(name);
      await _setLoggedIn(true);
      SoundAndVibration.playSoundAndVibrate(context);
      Navigator.pushReplacementNamed(context, '/main');
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case "weak-password":
          errorMessage = "Password is too weak. Use at least 6 characters.";
          break;
        case "email-already-in-use":
          errorMessage = "This email is already in use.";
          break;
        case "invalid-email":
          errorMessage = "Invalid email format.";
          break;
        default:
          errorMessage = "Sign-up failed: ${e.message}";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sign Up"),
        backgroundColor: const Color.fromARGB(255, 209, 175, 224),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: "UserName"),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: "Email"),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _signUp(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 209, 175, 224),
                foregroundColor: const Color.fromARGB(255, 175, 166, 166),
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text(
                "Sign Up",
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.black),
              ),
            ),
            SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              child: Text("Already have an account? Login", style: GoogleFonts.poppins()),
            ),
          ],
        ),
      ),
    );
  }
}

// MainScreen
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    MapScreen(),
    AlertsScreen(),
    SettingsScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    print("Switching to screen index: $index");
    setState(() {
      _selectedIndex = index;
      SoundAndVibration.playSoundAndVibrate(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    print("MainScreen: build called, selectedIndex: $_selectedIndex");
    return Scaffold(
      appBar: AppBar(
        title: Center(
          child: Text(
            "Walking Stick Tracker",
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: SafeArea(child: _screens[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late final MapController mapController;
  LatLng? currentLocation;
  LatLng? stickLocation;
  StreamSubscription<Position>? _positionStream;
  Timer? _gpsTimer;
  String lastUpdated = "Fetching...";
  bool isLoadingStickLocation = true;
  bool _userInteracted = false;
  List<LatLng> routePoints = [];
  String routingProfile = 'foot-walking';
  int stickFetchRetryCount = 0;
  int routeFetchRetryCount = 0;
  static const int maxRetries = 3;

  static const String firebaseUrl = 'https://walking-stick-app-default-rtdb.firebaseio.com/gps_data.json';
  static const String orsApiKey = '5b3ce3597851110001cf6248b008bcf2abcb48f0901453e0351fc38e'; // Verify this key

  // Color palette
  static const Color primaryColor = Color(0xFF7B1FA2); // Purple
  static const Color accentColor = Color(0xFF20B333); // Green
  static const Color buttonGradientStart = Color(0xFF0288D1); // Deep blue
  static const Color buttonGradientEnd = Color(0xFF4FC3F7); // Cyan
  static const Color buttonOverlayColor = Color(0xFF01579B); // Dark blue for press effect
  static const Color iconColor = Color.fromARGB(255, 157, 134, 80); // Light yellow for icons

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    _initializeLocation();
    _startStickLocationUpdates();

    final settingsState = Provider.of<SettingsState>(context, listen: false);
    settingsState.addListener(() {
      if (currentLocation != null && !_userInteracted) {
        mapController.move(currentLocation!, settingsState.defaultZoom);
      }
    });
  }

  Future<void> _initializeLocation() async {
    if (kIsWeb) {
      setState(() {
        currentLocation = const LatLng(9.5313, 6.4521);
        mapController.move(currentLocation!, Provider.of<SettingsState>(context, listen: false).defaultZoom);
      });
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location services are disabled. Please enable them.")),
      );
      setState(() {
        currentLocation = const LatLng(9.5313, 6.4521);
        mapController.move(currentLocation!, Provider.of<SettingsState>(context, listen: false).defaultZoom);
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permissions denied.")),
        );
        setState(() {
          currentLocation = const LatLng(9.5313, 6.4521);
          mapController.move(currentLocation!, Provider.of<SettingsState>(context, listen: false).defaultZoom);
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permissions permanently denied.")),
      );
      setState(() {
        currentLocation = const LatLng(9.5313, 6.4521);
        mapController.move(currentLocation!, Provider.of<SettingsState>(context, listen: false).defaultZoom);
      });
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
        _updateMapPosition();
        _fetchRoute();
      });
    });

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
        mapController.move(currentLocation!, Provider.of<SettingsState>(context, listen: false).defaultZoom);
      });
    } catch (e) {
      print("Error getting initial location: $e");
      setState(() {
        currentLocation = const LatLng(9.5313, 6.4521);
        mapController.move(currentLocation!, Provider.of<SettingsState>(context, listen: false).defaultZoom);
      });
    }
  }

  void _startStickLocationUpdates() {
    fetchStickLocation();
    _gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchStickLocation();
    });
  }

  Future<void> fetchStickLocation() async {
    if (stickFetchRetryCount >= maxRetries) {
      print("❌ Max retries reached for stick location fetch");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to fetch stick location after multiple retries")),
      );
      return;
    }

    try {
      final response = await http.get(Uri.parse(firebaseUrl)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException("Request to Firebase timed out after 15 seconds");
        },
      );
      print('🌐 Stick Location Response: Status=${response.statusCode}, Body=${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty || response.body == 'null') {
          print("⚠️ No stick location data found: Empty or null response");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No stick location data available")),
          );
          return;
        }

        final data = jsonDecode(response.body);
        if (data == null || data is! Map<String, dynamic> || data.isEmpty) {
          print("⚠️ Invalid stick location data: Not a valid map or empty");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid stick location data structure")),
          );
          return;
        }

        final lat = data['latitude'] as double?;
        final lon = data['longitude'] as double?;
        if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
          print("❌ Failed to parse lat/lon or invalid values: lat=$lat, lon=$lon");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid latitude or longitude values")),
          );
          return;
        }

        print("✅ Parsed lat: $lat, lon: $lon");
        setState(() {
          stickLocation = LatLng(lat, lon);
          isLoadingStickLocation = false;
          lastUpdated = TimeOfDay.now().format(context);
          stickFetchRetryCount = 0; // Reset retry count on success
          _updateMapPosition();
          _fetchRoute();
        });
      } else {
        print("❌ Failed to fetch location: ${response.statusCode}, ${response.reasonPhrase}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to fetch stick location: ${response.statusCode} ${response.reasonPhrase}")),
        );
      }
    } catch (e) {
      stickFetchRetryCount++;
      print("❌ Exception fetching stick location (Retry $stickFetchRetryCount/$maxRetries): $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching stick location (Retry $stickFetchRetryCount): $e")),
      );
      if (stickFetchRetryCount < maxRetries) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) fetchStickLocation();
        });
      }
    }
  }

  Future<void> _fetchRoute() async {
    if (currentLocation == null || stickLocation == null) {
      print("⚠️ Cannot fetch route: Missing location data");
      setState(() {
        routePoints = [];
      });
      return;
    }

    if (routeFetchRetryCount >= maxRetries) {
      print("❌ Max retries reached for route fetch");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to fetch route after multiple retries")),
      );
      return;
    }

    try {
      final url = 'https://api.openrouteservice.org/v2/directions/$routingProfile/geojson';
      print("🌐 Fetching route: URL=$url, Profile=$routingProfile");
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Authorization': orsApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'coordinates': [
                [currentLocation!.longitude, currentLocation!.latitude],
                [stickLocation!.longitude, stickLocation!.latitude],
              ],
            }),
          )
          .timeout(const Duration(seconds: 30)); // Increased to 30 seconds

      print('🌐 Route Response: Status=${response.statusCode}, Body=${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['features']?.isEmpty ?? true) {
          print("❌ No route features found in response");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No route found")),
          );
          setState(() {
            routePoints = [];
          });
          return;
        }
        final coordinates = data['features'][0]['geometry']['coordinates'] as List?;
        if (coordinates == null || coordinates.isEmpty) {
          print("❌ Invalid route coordinates");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid route data")),
          );
          setState(() {
            routePoints = [];
          });
          return;
        }
        setState(() {
          routePoints = coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
          routeFetchRetryCount = 0; // Reset retry count on success
        });
      } else {
        String errorMsg = "Failed to fetch route: ${response.statusCode}";
        if (response.statusCode == 401 || response.statusCode == 403) {
          errorMsg = "Invalid or unauthorized ORS API key";
        } else if (response.statusCode == 404) {
          errorMsg = "Route not found for the given locations";
        }
        print("❌ $errorMsg");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
        setState(() {
          routePoints = [];
        });
      }
    } catch (e) {
      routeFetchRetryCount++;
      print("❌ Exception fetching route (Retry $routeFetchRetryCount/$maxRetries): $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching route (Retry $routeFetchRetryCount): $e")),
      );
      if (routeFetchRetryCount < maxRetries) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _fetchRoute();
        });
      } else {
        setState(() {
          routePoints = [];
        });
      }
    }
  }

  void _updateMapPosition() {
    if (_userInteracted) {
      return;
    }

    if (currentLocation != null && stickLocation != null) {
      final bounds = LatLngBounds(currentLocation!, stickLocation!);
      mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
    } else if (currentLocation != null) {
      mapController.move(currentLocation!, mapController.camera.zoom);
    }
  }

  void _toggleRoutingProfile() {
    setState(() {
      routingProfile = routingProfile == 'foot-walking' ? 'driving-car' : 'foot-walking';
      _fetchRoute();
      SoundAndVibration.playSoundAndVibrate(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Routing profile changed to ${routingProfile == 'foot-walking' ? 'Walking' : 'Driving'}"),
          duration: const Duration(seconds: 2),
          backgroundColor: primaryColor,
        ),
      );
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _gpsTimer?.cancel();
    _controller.dispose();
    mapController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    setState(() {
      _userInteracted = true;
      mapController.move(mapController.camera.center, mapController.camera.zoom + 1);
      SoundAndVibration.playSoundAndVibrate(context);
    });
  }

  void _zoomOut() {
    setState(() {
      _userInteracted = true;
      mapController.move(mapController.camera.center, mapController.camera.zoom - 1);
      SoundAndVibration.playSoundAndVibrate(context);
    });
  }

  void _toggleMapStyle() {
    final settingsState = Provider.of<SettingsState>(context, listen: false);
    settingsState.setIsSatelliteDefault(!settingsState.isSatelliteDefault);
    SoundAndVibration.playSoundAndVibrate(context);
  }

  Widget _buildCustomButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
    Color? bgColor,
  }) {
    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Tooltip(
        message: tooltip,
        child: ElevatedButton(
          onPressed: () {
            Haptics.vibrate(HapticsType.light);
            onPressed();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: const Color.fromARGB(255, 86, 83, 73), // Changed to light yellow
            padding: const EdgeInsets.all(12),
            minimumSize: const Size(50, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            elevation: 4,
            shadowColor: Colors.black.withOpacity(0.2),
          ).copyWith(
            backgroundColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.pressed)) {
                return (bgColor ?? buttonGradientEnd).withOpacity(0.8);
              }
              return Colors.transparent;
            }),
            overlayColor: MaterialStateProperty.all(buttonOverlayColor.withOpacity(0.2)),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  bgColor?.withOpacity(0.9) ?? buttonGradientStart,
                  bgColor?.withOpacity(0.7) ?? buttonGradientEnd,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Center(
              child: Icon(icon, size: 22, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = Provider.of<DeviceConnectionState>(context);
    return Stack(
      children: [
        Consumer<SettingsState>(
          builder: (context, settingsState, child) {
            return FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: currentLocation ?? const LatLng(9.5313, 6.4521),
                initialZoom: settingsState.defaultZoom,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                onMapReady: () {
                  if (currentLocation != null && !_userInteracted) {
                    mapController.move(currentLocation!, settingsState.defaultZoom);
                  }
                },
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture) {
                    _userInteracted = true;
                  }
                },
              ),
              children: [
                if (connectionState.isConnected)
                  TileLayer(
                    urlTemplate: settingsState.isSatelliteDefault
                        ? "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                        : "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                    subdomains: const ['a', 'b', 'c'],
                  ),
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 5.0,
                        gradientColors: [primaryColor, accentColor],
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (currentLocation != null)
                      Marker(
                        point: currentLocation!,
                        width: 50,
                        height: 50,
                        child: Icon(Icons.person_pin_circle, color: Colors.red, size: 40, shadows: [
                          const Shadow(blurRadius: 4, color: Colors.black38, offset: Offset(2, 2)),
                        ]),
                      ),
                    if (stickLocation != null)
                      Marker(
                        point: stickLocation!,
                        width: 50,
                        height: 50,
                        child: Image.asset(
                          'assets/walking_stick.png',
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.location_pin,
                            color: accentColor,
                            size: 40,
                            shadows: const [
                              Shadow(blurRadius: 4, color: Colors.black38, offset: Offset(2, 2)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        if (isLoadingStickLocation)
          Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
        Positioned(
          top: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Consumer<SettingsState>(
                builder: (context, settingsState, child) {
                  return _buildCustomButton(
                    onPressed: _toggleMapStyle,
                    icon: settingsState.isSatelliteDefault ? Icons.map : Icons.satellite,
                    tooltip: settingsState.isSatelliteDefault ? "Switch to Street" : "Switch to Satellite",
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildCustomButton(
                onPressed: _toggleRoutingProfile,
                icon: routingProfile == 'foot-walking' ? Icons.directions_walk : Icons.directions_car,
                tooltip: routingProfile == 'foot-walking' ? "Switch to Driving" : "Switch to Walking",
              ),
              const SizedBox(height: 12),
              _buildCustomButton(
                onPressed: _zoomIn,
                icon: Icons.add,
                tooltip: "Zoom In",
              ),
              const SizedBox(height: 12),
              _buildCustomButton(
                onPressed: _zoomOut,
                icon: Icons.remove,
                tooltip: "Zoom Out",
              ),
            ],
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.25,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          snap: true,
          builder: (context, scrollController) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.white.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: primaryColor.withOpacity(0.3), width: 1),
                ),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on, color: accentColor, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                "Location Details",
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            label: "Your Coordinates:",
                            value: currentLocation != null
                                ? "${currentLocation!.latitude.toStringAsFixed(4)}, ${currentLocation!.longitude.toStringAsFixed(4)}"
                                : "Fetching...",
                            icon: Icons.person_pin_circle,
                          ),
                          _buildDetailRow(
                            label: "Stick Coordinates:",
                            value: stickLocation != null
                                ? "${stickLocation!.latitude.toStringAsFixed(4)}, ${stickLocation!.longitude.toStringAsFixed(4)}"
                                : "Fetching...",
                            icon: Icons.location_pin,
                          ),
                          _buildDetailRow(
                            label: "Altitude:",
                            value: "20.0 m",
                            icon: Icons.height,
                          ),
                          _buildDetailRow(
                            label: "Speed:",
                            value: "1.6 m/s",
                            icon: Icons.speed,
                          ),
                          _buildDetailRow(
                            label: "Heading:",
                            value: "177°",
                            icon: Icons.navigation,
                          ),
                          _buildDetailRow(
                            label: "Last Updated:",
                            value: lastUpdated,
                            icon: Icons.access_time,
                          ),
                          _buildStatusRow(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDetailRow({required String label, required String value, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    final connectionState = Provider.of<DeviceConnectionState>(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.network_check, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                "Device Status:",
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connectionState.isConnected ? accentColor : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connectionState.isConnected ? "Connected" : "Disconnected",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: connectionState.isConnected ? accentColor : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
class Alert {
  final String type;
  final String? location;
  final int timestamp;

  Alert({required this.type, this.location, required this.timestamp});

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      type: json['alert_type'],
      location: json['gps_location'],
      timestamp: (json['timestamp'] ?? 0).toInt(),
    );
  }
}

Future<List<Alert>> fetchAlerts() async {
  final response = await http.get(Uri.parse(
      'https://walking-stick-app-default-rtdb.firebaseio.com/alerts.json')); // Replace with your Firebase URL
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data.values.map((e) => Alert.fromJson(e)).toList().reversed.toList();
  } else {
    throw Exception('Failed to load alerts');
  }
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  Future<void> deleteAllAlerts() async {
    try {
      final response = await http.delete(
        Uri.parse('https://walking-stick-app-default-rtdb.firebaseio.com/alerts.json'),
      );

      if (response.statusCode == 200) {
        print("✅ All alerts deleted successfully.");
      } else {
        print("❌ Failed to delete alerts: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Exception while deleting alerts: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("Notifications Center"),
        backgroundColor: const Color.fromARGB(255, 183, 52, 239),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 193, 106, 230),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        "Notifications Center",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Here you'll find all alerts from your walking stick. Emergency notifications will appear in red.",
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active, color: Colors.purple[700]),
                    SizedBox(width: 8),
                    Text(
                      "Notifications",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () async {
                    await deleteAllAlerts();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("All notifications have been marked as read."),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 22, 4, 29),
                  ),
                  child: Text("Mark all as read"),
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Alert>>(
                future: fetchAlerts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(child: Text("No alerts yet"));
                  }

                  final alerts = snapshot.data!;
                  return ListView.builder(
                    itemCount: alerts.length,
                    itemBuilder: (context, index) {
                      final alert = alerts[index];
                      Color color = Colors.blue;
                      IconData icon = Icons.info;

                      if (alert.type == 'low_power') {
                        color = Colors.orange;
                        icon = Icons.warning;
                      } else if (alert.type == 'fall_detected') {
                        color = Colors.red;
                        icon = Icons.error;
                      }

                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(
                            alert.type.replaceAll("_", " ").toUpperCase(),
                            style:
                                TextStyle(fontWeight: FontWeight.bold, color: color),
                          ),
                          subtitle: Text(
                              "Location: ${alert.location ?? 'Unknown'}\nTime: ${DateTime.fromMillisecondsSinceEpoch(alert.timestamp * 1000).toLocal()}"),
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

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  String _selectedZoomPercentage = '75%';
  String _emergencyContact = "";
  bool _isDarkMode = false;

  final Map<String, double> _zoomLevels = {
    '25%': 10.0,
    '50%': 12.0,
    '75%': 14.0,
    '100%': 16.0,
  };

  @override
  void initState() {
    super.initState();
    print("SettingsScreen: initState called");
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModel = Provider.of<ThemeModel>(context, listen: false);
      final settingsState = Provider.of<SettingsState>(context, listen: false);
      setState(() {
        _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
        _emergencyContact = prefs.getString('emergencyContact') ?? "";
        final savedZoom = prefs.getDouble('defaultZoom') ?? 14.0;
        _selectedZoomPercentage = _zoomLevels.entries
            .firstWhere((entry) => entry.value == savedZoom, orElse: () => MapEntry('75%', 14.0))
            .key;
        settingsState.setDefaultZoom(savedZoom);
        final isSatelliteDefault = prefs.getBool('isSatelliteDefault') ?? false;
        settingsState.setIsSatelliteDefault(isSatelliteDefault);
        _isDarkMode = themeModel.themeMode == ThemeMode.dark;
      });
      settingsState.setSoundEnabled(prefs.getBool('soundEnabled') ?? true);
    } catch (e) {
      print("Error loading settings: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load settings")),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsState = Provider.of<SettingsState>(context, listen: false);
      await prefs.setBool('notificationsEnabled', _notificationsEnabled);
      await prefs.setDouble('defaultZoom', settingsState.defaultZoom);
      await prefs.setString('emergencyContact', _emergencyContact);
      await prefs.setBool('isSatelliteDefault', settingsState.isSatelliteDefault);
      await prefs.setBool('soundEnabled', settingsState.soundEnabled);
    } catch (e) {
      print("Error saving settings: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save settings")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print("SettingsScreen: build called");
    final themeModel = Provider.of<ThemeModel>(context);
    final settingsState = Provider.of<SettingsState>(context);
    final isDarkMode = themeModel.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Settings",
          style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 220, 192, 233),
        elevation: 4,
      ),
      body: Container(
        color: isDarkMode ? Colors.black : null,
        decoration: isDarkMode
            ? null
            : BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color.fromARGB(255, 220, 192, 233),
                    const Color.fromARGB(255, 180, 150, 200),
                  ],
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              // Appearance Section
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDarkMode ? Colors.white : Colors.grey,
                    width: isDarkMode ? 1.5 : 1.0, // Thicker border in Dark Mode
                  ),
                ),
                color: isDarkMode ? Colors.grey[900] : null,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.brightness_6, color: isDarkMode ? Colors.white : Colors.blue),
                        title: Text(
                          "Dark Mode",
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.black),
                        ),
                        subtitle: Text(
                          _isDarkMode ? "Enabled" : "Disabled",
                          style: GoogleFonts.poppins(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.grey),
                        ),
                        trailing: Switch(
                          value: _isDarkMode,
                          onChanged: (value) {
                            setState(() {
                              _isDarkMode = value;
                              themeModel.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                              _saveSettings();
                              SoundAndVibration.playSoundAndVibrate(context);
                            });
                          },
                          activeColor: isDarkMode ? Colors.white : Colors.blue,
                          activeTrackColor: isDarkMode ? Colors.grey[300] : Colors.blue[200],
                          inactiveThumbColor: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                          inactiveTrackColor: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Map Settings Section
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDarkMode ? Colors.white : Colors.grey,
                    width: isDarkMode ? 1.5 : 1.0,
                  ),
                ),
                color: isDarkMode ? Colors.grey[900] : null,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.map, color: isDarkMode ? Colors.white : Colors.green),
                        title: Text(
                          "Default Map Style",
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.black),
                        ),
                        subtitle: Text(
                          settingsState.isSatelliteDefault ? "Satellite" : "Street",
                          style: GoogleFonts.poppins(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.grey),
                        ),
                        trailing: Switch(
                          value: settingsState.isSatelliteDefault,
                          onChanged: (value) {
                            settingsState.setIsSatelliteDefault(value);
                            _saveSettings();
                            SoundAndVibration.playSoundAndVibrate(context);
                          },
                          activeColor: isDarkMode ? Colors.white : Colors.green,
                          activeTrackColor: isDarkMode ? Colors.grey[300] : Colors.green[200],
                          inactiveThumbColor: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                          inactiveTrackColor: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.zoom_in, color: isDarkMode ? Colors.white : Colors.green),
                        title: Text(
                          "Default Zoom Level",
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.black),
                        ),
                        subtitle: DropdownButton<String>(
                          value: _selectedZoomPercentage,
                          isExpanded: true,
                          dropdownColor: isDarkMode ? Colors.grey[800] : Colors.white,
                          style: GoogleFonts.poppins(fontSize: 14, color: isDarkMode ? Colors.white : Colors.black),
                          items: _zoomLevels.keys.map((String percentage) {
                            return DropdownMenuItem<String>(
                              value: percentage,
                              child: Text(
                                percentage,
                                style: GoogleFonts.poppins(fontSize: 14, color: isDarkMode ? Colors.white : Colors.black),
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedZoomPercentage = newValue;
                                settingsState.setDefaultZoom(_zoomLevels[newValue]!);
                                _saveSettings();
                                SoundAndVibration.playSoundAndVibrate(context);
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Notifications Section
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDarkMode ? Colors.white : Colors.grey,
                    width: isDarkMode ? 1.5 : 1.0,
                  ),
                ),
                color: isDarkMode ? Colors.grey[900] : null,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: Icon(Icons.notifications, color: isDarkMode ? Colors.white : Colors.orange),
                        title: Text(
                          "Notifications",
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.black),
                        ),
                        subtitle: Text(
                          "Enable/disable notifications",
                          style: GoogleFonts.poppins(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.grey),
                        ),
                        value: _notificationsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _notificationsEnabled = value;
                            _saveSettings();
                            SoundAndVibration.playSoundAndVibrate(context);
                          });
                        },
                        activeColor: isDarkMode ? Colors.white : Colors.orange,
                        activeTrackColor: isDarkMode ? Colors.grey[300] : Colors.orange[200],
                        inactiveThumbColor: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                        inactiveTrackColor: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                      ),
                      SwitchListTile(
                        secondary: Icon(Icons.volume_up, color: isDarkMode ? Colors.white : Colors.orange),
                        title: Text(
                          "Sound Alerts",
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.black),
                        ),
                        subtitle: Text(
                          "Enable/disable sound for alerts",
                          style: GoogleFonts.poppins(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.grey),
                        ),
                        value: settingsState.soundEnabled,
                        onChanged: (value) {
                          settingsState.setSoundEnabled(value);
                          _saveSettings();
                          SoundAndVibration.playSoundAndVibrate(context);
                        },
                        activeColor: isDarkMode ? Colors.white : Colors.orange,
                        activeTrackColor: isDarkMode ? Colors.grey[300] : Colors.orange[200],
                        inactiveThumbColor: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                        inactiveTrackColor: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Emergency Contact Section
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDarkMode ? Colors.white : Colors.grey,
                    width: isDarkMode ? 1.5 : 1.0,
                  ),
                ),
                color: isDarkMode ? Colors.grey[900] : null,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ListTile(
                    leading: Icon(Icons.contact_emergency, color: isDarkMode ? Colors.white : Colors.red),
                    title: Text(
                      "Emergency Contact",
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.black),
                    ),
                    subtitle: Text(
                      _emergencyContact.isEmpty ? "Not set" : _emergencyContact,
                      style: GoogleFonts.poppins(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.grey),
                    ),
                    trailing: Icon(Icons.edit, color: isDarkMode ? Colors.white : Colors.red),
                    onTap: () async {
                      SoundAndVibration.playSoundAndVibrate(context);
                      final newContact = await showDialog<String>(
                        context: context,
                        builder: (context) {
                          String contact = _emergencyContact;
                          return AlertDialog(
                            backgroundColor: isDarkMode ? Colors.grey[800] : Colors.white,
                            title: Text(
                              "Set Emergency Contact",
                              style: GoogleFonts.poppins(
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
                            ),
                            content: TextField(
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: "Phone Number",
                                hintText: "Enter phone number",
                                labelStyle: TextStyle(
                                  color: isDarkMode ? Colors.white70 : Colors.black54,
                                ),
                                hintStyle: TextStyle(
                                  color: isDarkMode ? Colors.white54 : Colors.black54,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: isDarkMode ? Colors.white70 : Colors.grey),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: isDarkMode ? Colors.white : Colors.blue),
                                ),
                              ),
                              style: TextStyle(
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
                              onChanged: (value) {
                                contact = value;
                              },
                            ),
                            actions: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: isDarkMode ? Colors.white : Colors.black,
                                ),
                                onPressed: () {
                                  SoundAndVibration.playSoundAndVibrate(context);
                                  Navigator.pop(context);
                                },
                                child: Text(
                                  "Cancel",
                                  style: GoogleFonts.poppins(),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: isDarkMode ? Colors.white : Colors.black,
                                ),
                                onPressed: () {
                                  if (contact.isEmpty || contact.length < 10) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Please enter a valid phone number")),
                                    );
                                    return;
                                  }
                                  SoundAndVibration.playSoundAndVibrate(context);
                                  Navigator.pop(context, contact);
                                },
                                child: Text(
                                  "Save",
                                  style: GoogleFonts.poppins(),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                      if (newContact != null && newContact.isNotEmpty) {
                        setState(() {
                          _emergencyContact = newContact;
                          _saveSettings();
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ProfileScreen
class ProfileScreen extends StatelessWidget {
  Future<void> _setLoggedIn(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', value);
      _isLoggedIn = value;
    } catch (e) {
      print("Error setting login state: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    print("ProfileScreen: build called");
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text("Profile"),
        backgroundColor: const Color.fromARGB(255, 245, 155, 248),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 255, 255, 255),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color.fromARGB(255, 219, 249, 226),
                        child: Icon(Icons.person, size: 40, color: const Color.fromARGB(255, 32, 179, 51)),
                      ),
                      SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? "User",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            user?.email ?? "No email",
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      SoundAndVibration.playSoundAndVibrate(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Edit Profile feature coming soon!")),
                      );
                    },
                    icon: Icon(Icons.edit),
                    label: Text("Edit Profile"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 245, 155, 248),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Device Information",
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  _buildInfoRow("Device ID", "WS-12345"),
                  _buildInfoRow("Battery Level", "85%"),
                  _buildInfoRow("Last Synced", "2025-04-03 10:30 AM"),
                ],
              ),
            ),
            SizedBox(height: 16),
            FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final emergencyContact = snapshot.data!.getString('emergencyContact') ?? "Not set";
                return Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Emergency Contact",
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      _buildInfoRow("Phone Number", emergencyContact),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                SoundAndVibration.playSoundAndVibrate(context);
                await FirebaseAuth.instance.signOut();
                await _setLoggedIn(false);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/welcome',
                  (Route<dynamic> route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 245, 155, 248),
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text("Logout", style: GoogleFonts.poppins(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 16)),
          Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}