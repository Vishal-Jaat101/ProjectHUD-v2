/// DestinationSearchScreen — Places autocomplete with debounce.
///
/// Full-screen search overlay. User types a destination, sees
/// autocomplete results from Google Places API, and selects one
/// to begin route planning.
///
/// Design system: Asphalt + Signal Amber. No gradients, no glow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../services/maps_service.dart';
import '../providers/setup_providers.dart';

class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    // Auto-focus the search field on entry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = ref.watch(isEnglishProvider);
    final searchResults = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: AppColors.textPrimary,
                    iconSize: 28,
                    onPressed: () {
                      ref.read(searchQueryProvider.notifier).state = '';
                      context.pop();
                    },
                  ),
                  const SizedBox(width: 4),
                  // Text field
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: AppTypography.body,
                      cursorColor: AppColors.amber,
                      decoration: InputDecoration(
                        hintText: isEnglish
                            ? 'Search destination'
                            : 'गंतव्य खोजें',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                color: AppColors.textSecondary,
                                onPressed: () {
                                  _controller.clear();
                                  ref
                                      .read(searchQueryProvider.notifier)
                                      .state = '';
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.panel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.amber,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (value) {
                        ref.read(searchQueryProvider.notifier).state = value;
                        setState(() {}); // refresh clear button visibility
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Results list ────────────────────────────────────
            Expanded(
              child: searchResults.when(
                data: (suggestions) => _buildResultsList(suggestions),
                loading: () => _buildLoadingState(),
                error: (_, __) => _buildErrorState(isEnglish),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(List<PlaceSuggestion> suggestions) {
    final query = ref.read(searchQueryProvider);

    if (query.trim().length < 2) {
      // Show hint when nothing typed yet.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search,
              color: AppColors.textSecondary,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              ref.read(isEnglishProvider)
                  ? 'Type at least 2 characters'
                  : 'कम से कम 2 अक्षर लिखें',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          ref.read(isEnglishProvider)
              ? 'No results found'
              : 'कोई परिणाम नहीं मिला',
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: suggestions.length,
      separatorBuilder: (_, __) => const Divider(
        color: AppColors.border,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return _SearchResultTile(
          suggestion: suggestion,
          onTap: () => _onSuggestionTapped(suggestion),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.amber),
    );
  }

  Widget _buildErrorState(bool isEnglish) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
          const SizedBox(height: 12),
          Text(
            isEnglish
                ? 'Could not load suggestions'
                : 'सुझाव लोड नहीं हो सके',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _onSuggestionTapped(PlaceSuggestion suggestion) async {
    final service = ref.read(mapsServiceProvider);
    final location = await service.placeDetails(suggestion.placeId);

    if (location == null || !mounted) return;

    // Store as selected destination for navigation
    ref.read(selectedDestinationProvider.notifier).state = SelectedDestination(
      placeId: suggestion.placeId,
      name: location.name.isNotEmpty ? location.name : suggestion.mainText,
      address: location.address.isNotEmpty
          ? location.address
          : suggestion.secondaryText,
      lat: location.lat,
      lng: location.lng,
    );

    // Store as recent destination
    ref.read(recentDestinationsProvider.notifier).add(
          RecentDestination(
            placeId: suggestion.placeId,
            name: location.name.isNotEmpty ? location.name : suggestion.mainText,
            address: location.address.isNotEmpty
                ? location.address
                : suggestion.secondaryText,
            visitedAt: DateTime.now(),
          ),
        );

    // Clear search state
    ref.read(searchQueryProvider.notifier).state = '';

    if (mounted) {
      context.pop();
    }
  }
}

// ── Search Result Tile ──────────────────────────────────────────────────

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.suggestion,
    required this.onTap,
  });

  final PlaceSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: AppColors.amber,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.mainText,
                    style: AppTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (suggestion.secondaryText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      suggestion.secondaryText,
                      style: AppTypography.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
