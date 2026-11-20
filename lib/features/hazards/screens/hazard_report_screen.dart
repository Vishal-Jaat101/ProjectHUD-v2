/// Hazard report bottom sheet overlay.
///
/// Riders can report a hazard via one big tap (when stopped) or by voice.
/// 6 hazard types arranged in a clean 2x3 grid:
///   1. Pothole
///   2. Accident
///   3. Waterlogging
///   4. Road Work
///   5. Police Check
///   6. Speed Breaker
///
/// Consensus rule: Requires 5 independent confirmations before broadcast.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../models/hazard_models.dart';
import '../providers/hazard_providers.dart';
import '../widgets/hazard_icon_widget.dart';

class HazardReportBottomSheet extends ConsumerWidget {
  const HazardReportBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REPORT ROAD HAZARD',
                style: AppTypography.heading2.copyWith(
                  color: AppColors.amber,
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Requires 5 rider confirmations before fleet broadcast.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // 2x3 Grid of Hazards (all targets >= 64dp)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: HazardType.values.map((type) {
              return _HazardButton(
                type: type,
                onTap: () {
                  _submitHazard(context, ref, type);
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Voice report alternative
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.mic_none_rounded,
                  color: AppColors.amber,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Hands-free: Say "Report pothole" or "Report accident"',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submitHazard(BuildContext context, WidgetRef ref, HazardType type) {
    final rideState = ref.read(rideStateProvider);
    final lat = rideState.currentLat != 0 ? rideState.currentLat : 26.8528;
    final lng = rideState.currentLng != 0 ? rideState.currentLng : 75.8084;

    final newReport = HazardReport(
      id: 'HAZ_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      latitude: lat,
      longitude: lng,
      reportedAt: DateTime.now(),
      reportedBy: 'rider_local_device',
      confirmations: 1, // First report = 1 confirmation (needs 4 more)
      denials: 0,
      isVerified: false,
    );

    // Write to Firestore if Firebase is configured
    ref.read(firestoreServiceProvider).reportHazard(
      type: type,
      lat: lat,
      lng: lng,
      anonymisedUserId: 'rider_${DateTime.now().millisecondsSinceEpoch}',
    );

    final currentList = ref.read(seededHazardsProvider);
    ref.read(seededHazardsProvider.notifier).state = [
      ...currentList,
      newReport,
    ];

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${type.label} reported. Waiting for 4 more rider confirmations.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.panel,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _HazardButton extends StatelessWidget {
  const _HazardButton({
    required this.type,
    required this.onTap,
  });

  final HazardType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HazardIconWidget(type: type, size: 48),
            const SizedBox(height: 6),
            Text(
              type.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HazardReportScreen extends StatelessWidget {
  const HazardReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: HazardReportBottomSheet(),
        ),
      ),
    );
  }
}
