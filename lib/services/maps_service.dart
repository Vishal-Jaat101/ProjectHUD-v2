/// Google Maps / Directions / Places API service for ProjectHUD.
///
/// All REST API calls are centralised here so the rest of the app
/// never touches raw HTTP for map data.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/constants/app_constants.dart';
import '../config/api_keys.dart';
import '../models/navigation_models.dart';

/// Represents a place autocomplete suggestion.
class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final structured =
        json['structured_formatting'] as Map<String, dynamic>? ?? {};
    return PlaceSuggestion(
      placeId: json['place_id'] as String? ?? '',
      mainText: structured['main_text'] as String? ?? '',
      secondaryText: structured['secondary_text'] as String? ?? '',
    );
  }
}

/// Lat/Lng pair returned from place details.
class PlaceLocation {
  final double lat;
  final double lng;
  final String name;
  final String address;

  const PlaceLocation({
    required this.lat,
    required this.lng,
    required this.name,
    required this.address,
  });
}

/// Service layer for Google Maps Platform APIs.
class MapsService {
  MapsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://maps.googleapis.com/maps/api';
  String get _key => googleMapsApiKey;

  bool get isKeyConfigured =>
      googleMapsApiKey.isNotEmpty &&
      googleMapsApiKey != 'PASTE_MAPS_KEY' &&
      googleMapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY';

  // ── Places Autocomplete ───────────────────────────────────────────

  /// Returns autocomplete suggestions for [query].
  ///
  /// Results are biased toward India and limited to geocode/establishment
  /// types for rider-friendly destinations.
  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    double? lat,
    double? lng,
    int radiusMeters = 50000,
  }) async {
    if (query.trim().isEmpty) return [];

    // Fallback mock places if API key is not configured or offline
    if (!isKeyConfigured) {
      return _getMockJaipurSuggestions(query);
    }

    try {
      final params = <String, String>{
        'input': query,
        'key': _key,
        'components': 'country:in',
        'language': 'en',
      };
      if (lat != null && lng != null) {
        params['location'] = '$lat,$lng';
        params['radius'] = '$radiusMeters';
      }

      final uri = Uri.parse('$_baseUrl/place/autocomplete/json')
          .replace(queryParameters: params);
      final response = await _client.get(uri);

      if (response.statusCode != 200) return _getMockJaipurSuggestions(query);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = json['predictions'] as List<dynamic>? ?? [];

      if (predictions.isEmpty) return _getMockJaipurSuggestions(query);

      return predictions
          .map((p) => PlaceSuggestion.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _getMockJaipurSuggestions(query);
    }
  }

  // ── Place Details ─────────────────────────────────────────────────

  /// Fetches lat/lng and name for a [placeId].
  Future<PlaceLocation?> placeDetails(String placeId) async {
    if (!isKeyConfigured) {
      return _getMockPlaceLocation(placeId);
    }

    try {
      final uri = Uri.parse('$_baseUrl/place/details/json').replace(
        queryParameters: {
          'place_id': placeId,
          'fields': 'geometry,name,formatted_address',
          'key': _key,
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) return _getMockPlaceLocation(placeId);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return _getMockPlaceLocation(placeId);

      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location == null) return _getMockPlaceLocation(placeId);

      return PlaceLocation(
        lat: (location['lat'] as num).toDouble(),
        lng: (location['lng'] as num).toDouble(),
        name: result['name'] as String? ?? '',
        address: result['formatted_address'] as String? ?? '',
      );
    } catch (_) {
      return _getMockPlaceLocation(placeId);
    }
  }

  // ── Directions ────────────────────────────────────────────────────

  /// Fetches a driving route from [originLat],[originLng] to
  /// [destLat],[destLng] via the Directions API.
  Future<RouteData?> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String destinationName,
    String mode = 'driving',
  }) async {
    if (!isKeyConfigured) {
      return _getMockRouteData(destLat, destLng, destinationName);
    }

    try {
      final uri = Uri.parse('$_baseUrl/directions/json').replace(
        queryParameters: {
          'origin': '$originLat,$originLng',
          'destination': '$destLat,$destLng',
          'mode': mode,
          'key': _key,
          'language': 'en',
          'region': 'in',
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        return _getMockRouteData(destLat, destLng, destinationName);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = json['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty) {
        return _getMockRouteData(destLat, destLng, destinationName);
      }

      final route = routes[0] as Map<String, dynamic>;
      final legs = route['legs'] as List<dynamic>? ?? [];
      if (legs.isEmpty) {
        return _getMockRouteData(destLat, destLng, destinationName);
      }

      final leg = legs[0] as Map<String, dynamic>;
      final apiSteps = leg['steps'] as List<dynamic>? ?? [];

      final steps = apiSteps
          .map((s) => NavigationStep.fromDirectionsApi(s as Map<String, dynamic>))
          .toList();

      final polyline =
          route['overview_polyline']?['points'] as String? ?? '';

      return RouteData(
        summary: route['summary'] as String? ?? 'Tonk Road & RIICO Industrial Area',
        totalDistanceMeters:
            (leg['distance']?['value'] as num?)?.toDouble() ?? 3800,
        totalDurationSeconds:
            (leg['duration']?['value'] as num?)?.toDouble() ?? 540,
        steps: steps.isNotEmpty ? steps : _getMockRouteData(destLat, destLng, destinationName).steps,
        encodedPolyline: polyline,
        destinationName: destinationName,
        destinationLat: destLat,
        destinationLng: destLng,
      );
    } catch (_) {
      return _getMockRouteData(destLat, destLng, destinationName);
    }
  }

  List<PlaceSuggestion> _getMockJaipurSuggestions(String query) {
    const allSuggestions = [
      PlaceSuggestion(
        placeId: 'POORNIMA_INST_JPR',
        mainText: 'Poornima Institute of Engineering & Technology',
        secondaryText: 'ISI-2, RIICO Institutional Area, Sitapura, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'JECRC_UNIV_JPR',
        mainText: 'JECRC University',
        secondaryText: 'Plot No. IS-2036, Ramchandrapura Industrial Area, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'SITAPURA_CIRCLE_JPR',
        mainText: 'Sitapura Industrial Area Circle',
        secondaryText: 'Tonk Road, Sitapura, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'WTP_JAIPUR',
        mainText: 'World Trade Park (WTP)',
        secondaryText: 'Jawahar Lal Nehru Marg, Malviya Nagar, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'JAWAHAR_CIRCLE_JPR',
        mainText: 'Jawahar Circle',
        secondaryText: 'Jawahar Lal Nehru Marg, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'MNIT_JAIPUR',
        mainText: 'MNIT Jaipur',
        secondaryText: 'Jawahar Lal Nehru Marg, Malviya Nagar, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'JAIPUR_AIRPORT',
        mainText: 'Jaipur International Airport',
        secondaryText: 'Sanganer, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'JAIPUR_JUNCTION',
        mainText: 'Jaipur Junction Railway Station',
        secondaryText: 'Station Road, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'SINDHI_CAMP_JPR',
        mainText: 'Sindhi Camp Bus Stand',
        secondaryText: 'Station Road, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'DURGAPURA_STN_JPR',
        mainText: 'Durgapura Railway Station',
        secondaryText: 'Tonk Road, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'HAWA_MAHAL_JPR',
        mainText: 'Hawa Mahal',
        secondaryText: 'Badi Chaupar, Old City, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'AMER_FORT_JPR',
        mainText: 'Amer Fort',
        secondaryText: 'Delhi Road, Amer, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'RAJ_MANDIR_JPR',
        mainText: 'Raj Mandir Cinema',
        secondaryText: 'MI Road, Panch Batti, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'RAJA_PARK_JPR',
        mainText: 'Raja Park',
        secondaryText: 'Raja Park Main Market, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'C_SCHEME_JPR',
        mainText: 'C-Scheme (Ahinsa Circle)',
        secondaryText: 'Sardar Patel Marg, C-Scheme, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'VAISHALI_NAGAR_JPR',
        mainText: 'Vaishali Nagar',
        secondaryText: 'Amrapali Circle, Vaishali Nagar, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'MANSAROVAR_METRO_JPR',
        mainText: 'Mansarovar Metro Station',
        secondaryText: 'Rajpath, Mansarovar, Jaipur',
      ),
      PlaceSuggestion(
        placeId: 'JAGATPURA_JPR',
        mainText: 'Jagatpura',
        secondaryText: 'Mahal Road, Jagatpura, Jaipur',
      ),
    ];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return allSuggestions;
    return allSuggestions
        .where((p) =>
            p.mainText.toLowerCase().contains(q) ||
            p.secondaryText.toLowerCase().contains(q))
        .toList();
  }

  PlaceLocation _getMockPlaceLocation(String placeId) {
    const locations = <String, PlaceLocation>{
      'POORNIMA': PlaceLocation(
        lat: 26.8764,
        lng: 75.7640,
        name: 'Poornima Institute',
        address: 'ISI-2, RIICO Institutional Area, Sitapura, Jaipur',
      ),
      'WTP': PlaceLocation(
        lat: 26.8533,
        lng: 75.8049,
        name: 'World Trade Park (WTP)',
        address: 'Jawahar Lal Nehru Marg, Malviya Nagar, Jaipur',
      ),
      'JAWAHAR_CIRCLE': PlaceLocation(
        lat: 26.8402,
        lng: 75.8002,
        name: 'Jawahar Circle',
        address: 'Jawahar Lal Nehru Marg, Jaipur',
      ),
      'MNIT': PlaceLocation(
        lat: 26.8639,
        lng: 75.8107,
        name: 'MNIT Jaipur',
        address: 'Jawahar Lal Nehru Marg, Malviya Nagar, Jaipur',
      ),
      'AIRPORT': PlaceLocation(
        lat: 26.8242,
        lng: 75.8122,
        name: 'Jaipur International Airport',
        address: 'Sanganer, Jaipur',
      ),
      'JUNCTION': PlaceLocation(
        lat: 26.9196,
        lng: 75.7870,
        name: 'Jaipur Junction Railway Station',
        address: 'Station Road, Jaipur',
      ),
      'SINDHI_CAMP': PlaceLocation(
        lat: 26.9228,
        lng: 75.7997,
        name: 'Sindhi Camp Bus Stand',
        address: 'Station Road, Jaipur',
      ),
      'DURGAPURA': PlaceLocation(
        lat: 26.8547,
        lng: 75.7874,
        name: 'Durgapura Railway Station',
        address: 'Tonk Road, Jaipur',
      ),
      'HAWA_MAHAL': PlaceLocation(
        lat: 26.9239,
        lng: 75.8267,
        name: 'Hawa Mahal',
        address: 'Badi Chaupar, Old City, Jaipur',
      ),
      'AMER_FORT': PlaceLocation(
        lat: 26.9855,
        lng: 75.8513,
        name: 'Amer Fort',
        address: 'Delhi Road, Amer, Jaipur',
      ),
      'RAJ_MANDIR': PlaceLocation(
        lat: 26.9155,
        lng: 75.8106,
        name: 'Raj Mandir Cinema',
        address: 'MI Road, Panch Batti, Jaipur',
      ),
      'RAJA_PARK': PlaceLocation(
        lat: 26.8997,
        lng: 75.8183,
        name: 'Raja Park',
        address: 'Raja Park Main Market, Jaipur',
      ),
      'C_SCHEME': PlaceLocation(
        lat: 26.9128,
        lng: 75.8009,
        name: 'C-Scheme (Ahinsa Circle)',
        address: 'Sardar Patel Marg, C-Scheme, Jaipur',
      ),
      'VAISHALI': PlaceLocation(
        lat: 26.9148,
        lng: 75.7479,
        name: 'Vaishali Nagar',
        address: 'Amrapali Circle, Vaishali Nagar, Jaipur',
      ),
      'MANSAROVAR': PlaceLocation(
        lat: 26.8798,
        lng: 75.7507,
        name: 'Mansarovar Metro Station',
        address: 'Rajpath, Mansarovar, Jaipur',
      ),
      'JAGATPURA': PlaceLocation(
        lat: 26.8330,
        lng: 75.8660,
        name: 'Jagatpura',
        address: 'Mahal Road, Jagatpura, Jaipur',
      ),
      'SITAPURA': PlaceLocation(
        lat: 26.8510,
        lng: 75.7890,
        name: 'Sitapura Industrial Area Circle',
        address: 'Tonk Road, Sitapura, Jaipur',
      ),
    };
    for (final entry in locations.entries) {
      if (placeId.contains(entry.key)) return entry.value;
    }
    return const PlaceLocation(
      lat: 26.8528,
      lng: 75.8084,
      name: 'JECRC University',
      address: 'Plot No. IS-2036, Ramchandrapura, Jaipur',
    );
  }

  RouteData _getMockRouteData(double destLat, double destLng, String destName) {
    return RouteData(
      summary: 'RIICO Industrial Area & Tonk Road',
      totalDistanceMeters: 3800,
      totalDurationSeconds: 540,
      destinationName: destName,
      destinationLat: destLat,
      destinationLng: destLng,
      encodedPolyline: '',
      steps: const [
        NavigationStep(
          direction: TurnDirection.straight,
          instruction: 'Depart and continue on RIICO Road',
          distanceMeters: 600,
          durationSeconds: 90,
          startLat: 26.8528,
          startLng: 75.8084,
          endLat: 26.8552,
          endLng: 75.8040,
        ),
        NavigationStep(
          direction: TurnDirection.right,
          instruction: 'Turn right onto Tonk Road',
          distanceMeters: 1600,
          durationSeconds: 240,
          startLat: 26.8552,
          startLng: 75.8040,
          endLat: 26.8630,
          endLng: 75.7830,
        ),
        NavigationStep(
          direction: TurnDirection.slightLeft,
          instruction: 'Slight left onto Sitapura Circle',
          distanceMeters: 1100,
          durationSeconds: 150,
          startLat: 26.8630,
          startLng: 75.7830,
          endLat: 26.8720,
          endLng: 75.7680,
        ),
        NavigationStep(
          direction: TurnDirection.left,
          instruction: 'Turn left towards destination',
          distanceMeters: 500,
          durationSeconds: 60,
          startLat: 26.8720,
          startLng: 75.7680,
          endLat: 26.8764,
          endLng: 75.7640,
        ),
      ],
    );
  }

  /// Cleans up the HTTP client.
  void dispose() {
    _client.close();
  }
}
