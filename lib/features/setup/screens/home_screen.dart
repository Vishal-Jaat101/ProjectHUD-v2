/// HomeScreen — main landing screen for ProjectHUD (Real Product Mode).
///
/// Layout (top to bottom):
///   1. App bar: "ProjectHUD" heading + language toggle + Settings icon
///   2. Vehicle mode selector (Bike / Auto-Cab)
///   3. Live Google Places destination card (Search / Selected destination)
///   4. "START RIDE" primary action button
///   5. Recent destinations list
///   6. Bottom feature bar (Settings, BLE HUD, Risk Zones, Phase 3)
///
/// Design system: Asphalt + Signal Amber. No gradients, no glow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../models/navigation_models.dart';
import '../../hud/providers/hud_providers.dart';
import '../providers/setup_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isStartingRide = false;

  Future<void> _startRide(SelectedDestination destination) async {
    setState(() => _isStartingRide = true);

    try {
      // 1. Get current GPS position with permission check
      Position? currentPos;
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            currentPos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 4),
            );
          }
        }
      } catch (_) {
        // Fallback to last known position if timeout
        currentPos = await Geolocator.getLastKnownPosition();
      }

      final originLat = currentPos?.latitude ?? AppConstants.demoStartLat;
      final originLng = currentPos?.longitude ?? AppConstants.demoStartLng;

      // 2. Fetch real Google Directions route
      final vehicleMode = ref.read(vehicleModeProvider);
      final mapsService = ref.read(mapsServiceProvider);
      final route = await mapsService.getDirections(
        originLat: originLat,
        originLng: originLng,
        destLat: destination.lat,
        destLng: destination.lng,
        destinationName: destination.name,
        mode: vehicleMode == VehicleMode.bike ? 'bicycling' : 'driving',
      );

      // 3. Store active route & destination in global providers
      ref.read(activeRouteProvider.notifier).state = route;
      ref.read(hudDestinationProvider.notifier).state = HudDestination(
        name: destination.name,
        lat: destination.lat,
        lng: destination.lng,
      );

      // 4. Initialize ride state
      ref.read(rideStateProvider.notifier).startRide(
            lat: originLat,
            lng: originLng,
            remainingDistanceMeters: route?.totalDistanceMeters ?? 0,
            remainingDurationSeconds: route?.totalDurationSeconds ?? 0,
          );

      if (mounted) {
        context.push('/hud');
      }
    } finally {
      if (mounted) {
        setState(() => _isStartingRide = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleMode = ref.watch(vehicleModeProvider);
    final isEnglish = ref.watch(isEnglishProvider);
    final recentDestinations = ref.watch(recentDestinationsProvider);
    final selectedDestination = ref.watch(selectedDestinationProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. App Bar ──────────────────────────────────────
              _AppBarRow(isEnglish: isEnglish, ref: ref),
              const SizedBox(height: 20),

              // ── 2. Vehicle Mode Selector ────────────────────────
              _VehicleModeSelector(
                selected: vehicleMode,
                onChanged: (mode) {
                  ref.read(vehicleModeProvider.notifier).state = mode;
                },
              ),
              const SizedBox(height: 16),

              // ── 3. Live Google Places Destination Card ─────────
              _WhereToCard(
                isEnglish: isEnglish,
                selectedDestination: selectedDestination,
                onClear: () {
                  ref.read(selectedDestinationProvider.notifier).state = null;
                },
              ),
              const SizedBox(height: 12),

              // ── 4. Start Ride Primary Action Button ─────────────
              _StartRideButton(
                isEnglish: isEnglish,
                isLoading: _isStartingRide,
                hasDestination: selectedDestination != null,
                onPressed: () {
                  if (selectedDestination != null) {
                    _startRide(selectedDestination);
                  } else {
                    context.push('/search');
                  }
                },
              ),
              const SizedBox(height: 16),

              // ── 5. Recent Destinations ──────────────────────────
              Expanded(
                child: _RecentDestinationsList(
                  destinations: recentDestinations,
                  isEnglish: isEnglish,
                  onSelect: (dest) async {
                    // Set as selected destination and initiate details lookup if needed
                    final service = ref.read(mapsServiceProvider);
                    final details = await service.placeDetails(dest.placeId);
                    final lat = details?.lat ?? AppConstants.demoEndLat;
                    final lng = details?.lng ?? AppConstants.demoEndLng;

                    ref.read(selectedDestinationProvider.notifier).state =
                        SelectedDestination(
                      placeId: dest.placeId,
                      name: dest.name,
                      address: dest.address,
                      lat: lat,
                      lng: lng,
                    );
                  },
                ),
              ),

              // ── 6. Bottom Feature Bar (Settings, HUD, Risk, Phase 3) ──
              const _BottomFeatureBar(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── App Bar ─────────────────────────────────────────────────────────────

class _AppBarRow extends StatelessWidget {
  const _AppBarRow({required this.isEnglish, required this.ref});

  final bool isEnglish;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'ProjectHUD',
          style: AppTypography.heading1.copyWith(color: AppColors.amber),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Language toggle button
            GestureDetector(
              onTap: () {
                ref.read(isEnglishProvider.notifier).state = !isEnglish;
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  isEnglish ? 'EN' : 'हिन्दी',
                  style: AppTypography.button.copyWith(
                    color: AppColors.amber,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Settings button
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
              tooltip: isEnglish ? 'Settings' : 'सेटिंग्स',
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Vehicle Mode Selector ───────────────────────────────────────────────

class _VehicleModeSelector extends StatelessWidget {
  const _VehicleModeSelector({
    required this.selected,
    required this.onChanged,
  });

  final VehicleMode selected;
  final ValueChanged<VehicleMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: VehicleMode.values.map((mode) {
        final isSelected = mode == selected;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: mode == VehicleMode.bike ? 8 : 0,
              left: mode == VehicleMode.autoCab ? 8 : 0,
            ),
            child: InkWell(
              onTap: () => onChanged(mode),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.amber : AppColors.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected ? null : Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      mode.icon,
                      size: 24,
                      color: isSelected
                          ? AppColors.background
                          : AppColors.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mode.label,
                      style: AppTypography.button.copyWith(
                        color: isSelected
                          ? AppColors.background
                          : AppColors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── "Where to?" Destination Card ────────────────────────────────────────

class _WhereToCard extends StatelessWidget {
  const _WhereToCard({
    required this.isEnglish,
    required this.selectedDestination,
    required this.onClear,
  });

  final bool isEnglish;
  final SelectedDestination? selectedDestination;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedDestination != null;

    return InkWell(
      onTap: () => context.push('/search'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasSelection ? AppColors.amber : AppColors.border,
            width: hasSelection ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasSelection ? Icons.place_rounded : Icons.search,
              color: AppColors.amber,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: hasSelection
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          selectedDestination!.name,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (selectedDestination!.address.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            selectedDestination!.address,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isEnglish ? 'Where to?' : 'कहाँ जाना है?',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEnglish
                              ? 'Search destination via Google Places'
                              : 'गूगल प्लेसेस द्वारा गंतव्य खोजें',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary.withOpacity(0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
            ),
            if (hasSelection)
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                onPressed: onClear,
              )
            else
              const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.textSecondary,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Start Ride Primary Action Button ────────────────────────────────────

class _StartRideButton extends StatelessWidget {
  const _StartRideButton({
    required this.isEnglish,
    required this.isLoading,
    required this.hasDestination,
    required this.onPressed,
  });

  final bool isEnglish;
  final bool isLoading;
  final bool hasDestination;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.panel,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: hasDestination
                ? BorderSide.none
                : const BorderSide(color: AppColors.border),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.background,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasDestination ? Icons.navigation_rounded : Icons.search,
                    color: AppColors.background,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasDestination
                        ? (isEnglish ? 'START RIDE' : 'राइड शुरू करें')
                        : (isEnglish ? 'SELECT DESTINATION' : 'गंतव्य चुनें'),
                    style: AppTypography.button.copyWith(
                      color: AppColors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Recent Destinations List ────────────────────────────────────────────

class _RecentDestinationsList extends StatelessWidget {
  const _RecentDestinationsList({
    required this.destinations,
    required this.isEnglish,
    required this.onSelect,
  });

  final List<RecentDestination> destinations;
  final bool isEnglish;
  final ValueChanged<RecentDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.history,
              color: AppColors.textSecondary,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              isEnglish ? 'No recent destinations' : 'कोई हालिया गंतव्य नहीं',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isEnglish ? 'Recent Destinations' : 'हालिया गंतव्य',
          style: AppTypography.heading3.copyWith(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.separated(
            itemCount: destinations.length,
            separatorBuilder: (_, __) => const Divider(
              color: AppColors.border,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final dest = destinations[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.amber,
                ),
                title: Text(dest.name, style: AppTypography.body),
                subtitle: Text(
                  dest.address,
                  style: AppTypography.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.textSecondary,
                  size: 14,
                ),
                onTap: () => onSelect(dest),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Bottom Feature Bar ──────────────────────────────────────────────────

class _BottomFeatureBar extends StatelessWidget {
  const _BottomFeatureBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _FeatureButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.push('/settings'),
          ),
          _FeatureButton(
            icon: Icons.bluetooth,
            label: 'HUD',
            onTap: () => context.push('/hud-device'),
          ),
          _FeatureButton(
            icon: Icons.map_outlined,
            label: 'Risk',
            onTap: () => context.push('/risk-zones'),
          ),
          _FeatureButton(
            icon: Icons.insights,
            label: 'Phase 3',
            onTap: () => context.push('/explainer'),
          ),
        ],
      ),
    );
  }
}

class _FeatureButton extends StatelessWidget {
  const _FeatureButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 26),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.caption),
          ],
        ),
      ),
    );
  }
}
