/// SettingsScreen — Application configuration and preferences.
///
/// Features:
///   1. API Keys status overview (Google Maps & Gemini).
///   2. Vehicle mode & language selection.
///   3. Hazard consensus threshold setting / info.
///   4. Demo Mode link (moved from Home to settings-only).
///
/// Design system: Asphalt + Signal Amber. No gradients, no glow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../config/api_keys.dart';
import '../../../models/navigation_models.dart';
import '../../setup/providers/setup_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnglish = ref.watch(isEnglishProvider);
    final vehicleMode = ref.watch(vehicleModeProvider);

    final isMapsConfigured = googleMapsApiKey.isNotEmpty &&
        googleMapsApiKey != 'PASTE_MAPS_KEY' &&
        googleMapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY';

    final isGeminiConfigured = geminiApiKey.isNotEmpty &&
        geminiApiKey != 'PASTE_GEMINI_KEY' &&
        geminiApiKey != 'YOUR_GEMINI_API_KEY';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          isEnglish ? 'Settings' : 'सेटिंग्स',
          style: AppTypography.heading2.copyWith(color: AppColors.amber),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // ── 1. API Keys Status ────────────────────────────────────
            Text(
              isEnglish ? 'API KEYS CONFIGURATION' : 'एपीआई कुंजी स्थिति',
              style: AppTypography.caption.copyWith(
                color: AppColors.amber,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ApiKeyStatusRow(
                    title: 'Google Maps API',
                    subtitle: 'Places Search & Directions',
                    isConfigured: isMapsConfigured,
                    placeholderNotice: 'lib/config/api_keys.dart',
                  ),
                  const Divider(color: AppColors.border, height: 24),
                  _ApiKeyStatusRow(
                    title: 'Gemini AI API',
                    subtitle: 'Voice Assistant Understanding',
                    isConfigured: isGeminiConfigured,
                    placeholderNotice: 'lib/config/api_keys.dart',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 2. Preferences ────────────────────────────────────────
            Text(
              isEnglish ? 'PREFERENCES' : 'प्राथमिकताएं',
              style: AppTypography.caption.copyWith(
                color: AppColors.amber,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.language, color: AppColors.amber),
                    title: Text(
                      isEnglish ? 'Language' : 'भाषा',
                      style: AppTypography.body,
                    ),
                    trailing: Text(
                      isEnglish ? 'English (IN)' : 'हिन्दी (IN)',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      ref.read(isEnglishProvider.notifier).state = !isEnglish;
                    },
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    leading: Icon(vehicleMode.icon, color: AppColors.amber),
                    title: Text(
                      isEnglish ? 'Default Vehicle' : 'डिफ़ॉल्ट वाहन',
                      style: AppTypography.body,
                    ),
                    trailing: Text(
                      vehicleMode.label,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      ref.read(vehicleModeProvider.notifier).state =
                          vehicleMode == VehicleMode.bike
                              ? VehicleMode.autoCab
                              : VehicleMode.bike;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 3. Safety Consensus ───────────────────────────────────
            Text(
              isEnglish ? 'SAFETY CONSENSUS' : 'सुरक्षा सहमति नियम',
              style: AppTypography.caption.copyWith(
                color: AppColors.amber,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.verified,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AppConstants.hazardConsensusThreshold}-Rider Consensus Rule',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hazards require 5 independent rider confirmations before fleet-wide broadcast.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // ── 4. Demo Mode Small Link ───────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.panel.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.play_circle_outline,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                title: Text(
                  isEnglish
                      ? 'Demo Mode (Simulated Jaipur Ride)'
                      : 'डेमो मोड (जयपुर सिम्युलेटेड राइड)',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                onTap: () => context.push('/demo'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _ApiKeyStatusRow extends StatelessWidget {
  const _ApiKeyStatusRow({
    required this.title,
    required this.subtitle,
    required this.isConfigured,
    required this.placeholderNotice,
  });

  final String title;
  final String subtitle;
  final bool isConfigured;
  final String placeholderNotice;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isConfigured ? Icons.check_circle : Icons.info_outline,
          color: isConfigured ? AppColors.verified : AppColors.amber,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isConfigured
                          ? AppColors.verified.withOpacity(0.15)
                          : AppColors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isConfigured ? 'LIVE' : 'PLACEHOLDER',
                      style: AppTypography.caption.copyWith(
                        color: isConfigured ? AppColors.verified : AppColors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
              if (!isConfigured) ...[
                const SizedBox(height: 4),
                Text(
                  'Set in $placeholderNotice',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.amber,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
