import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/setup/screens/home_screen.dart';
import '../../features/setup/screens/destination_search_screen.dart';
import '../../features/hud/screens/hud_screen.dart';
import '../../features/hud/screens/hud_landscape_screen.dart';
import '../../features/hazards/screens/hazard_report_screen.dart';
import '../../features/demo/screens/demo_screen.dart';
import '../../features/ride_summary/screens/ride_summary_screen.dart';
import '../../features/hud_device/screens/hud_device_screen.dart';
import '../../features/hud_device/screens/hud_simulator_screen.dart';
import '../../features/gig_integration/screens/gig_import_screen.dart';
import '../../features/risk_zones/screens/risk_zones_screen.dart';
import '../../features/explainer/screens/explainer_screen.dart';
import '../../features/voice/screens/voice_assistant_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      builder: (context, state) => const DestinationSearchScreen(),
    ),
    GoRoute(
      path: '/hud',
      name: 'hud',
      builder: (context, state) => const HUDScreen(),
    ),
    GoRoute(
      path: '/hud-landscape',
      name: 'hud-landscape',
      builder: (context, state) => const HUDLandscapeScreen(),
    ),
    GoRoute(
      path: '/hazard-report',
      name: 'hazard-report',
      builder: (context, state) => const HazardReportScreen(),
    ),
    GoRoute(
      path: '/demo',
      name: 'demo',
      builder: (context, state) => const DemoScreen(),
    ),
    GoRoute(
      path: '/ride-summary',
      name: 'ride-summary',
      builder: (context, state) => const RideSummaryScreen(),
    ),
    GoRoute(
      path: '/hud-device',
      name: 'hud-device',
      builder: (context, state) => const HUDDeviceScreen(),
    ),
    GoRoute(
      path: '/hud-simulator',
      name: 'hud-simulator',
      builder: (context, state) => const HUDSimulatorScreen(),
    ),
    GoRoute(
      path: '/gig-import',
      name: 'gig-import',
      builder: (context, state) => const GigImportScreen(),
    ),
    GoRoute(
      path: '/risk-zones',
      name: 'risk-zones',
      builder: (context, state) => const RiskZonesScreen(),
    ),
    GoRoute(
      path: '/explainer',
      name: 'explainer',
      builder: (context, state) => const ExplainerScreen(),
    ),
    GoRoute(
      path: '/voice-assistant',
      name: 'voice-assistant',
      builder: (context, state) => const VoiceAssistantScreen(),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
