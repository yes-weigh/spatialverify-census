import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_places_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/landmark_anchor_models.dart';

/// Google Places autocomplete for a numbered control pin.
class PinPlacesAutocompleteField extends StatefulWidget {
  static const inlineWidth = 168.0;

  const PinPlacesAutocompleteField({
    required this.pinNumber,
    required this.value,
    required this.onSelected,
    this.bias,
    this.compact = false,
    this.showPinBadge = true,
    this.initialSearchText = '',
    this.onSearchTextChanged,
    this.onFocusChanged,
    this.overlaySuggestions = false,
    super.key,
  });

  final int pinNumber;
  final PlaceMatchCandidate? value;
  final LatLng? bias;
  final bool compact;
  final bool showPinBadge;
  final String initialSearchText;
  final ValueChanged<PlaceMatchCandidate?> onSelected;
  final ValueChanged<String>? onSearchTextChanged;
  final ValueChanged<bool>? onFocusChanged;
  /// When true, suggestions float above the field (no layout shift).
  final bool overlaySuggestions;

  @override
  State<PinPlacesAutocompleteField> createState() => _PinPlacesAutocompleteFieldState();
}

class _PinPlacesAutocompleteFieldState extends State<PinPlacesAutocompleteField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _places = GooglePlacesService();
  Timer? _debounce;
  List<PlaceAutocompletePrediction> _suggestions = [];
  var _loading = false;
  var _showSuggestions = false;
  OverlayEntry? _overlayEntry;
  double _fieldWidth = 280;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    _syncFromValue();
  }

  @override
  void didUpdateWidget(PinPlacesAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value?.placeId != widget.value?.placeId ||
        oldWidget.initialSearchText != widget.initialSearchText) {
      _syncFromValue();
    }
    if (oldWidget.overlaySuggestions != widget.overlaySuggestions) {
      _hideSuggestionsOverlay();
    }
  }

  void _handleFocusChange() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
    if (!_focusNode.hasFocus) {
      setState(() => _showSuggestions = false);
      _hideSuggestionsOverlay();
    } else if (_suggestions.isNotEmpty) {
      _scheduleOverlayUpdate();
    }
  }

  void _syncFromValue() {
    final v = widget.value;
    if (v != null) {
      final text = v.name.isNotEmpty ? v.name : v.address;
      if (_controller.text != text) {
        _controller.text = text;
      }
      return;
    }
    if (widget.initialSearchText.isNotEmpty && _controller.text != widget.initialSearchText) {
      _controller.text = widget.initialSearchText;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideSuggestionsOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleOverlayUpdate() {
    if (!widget.overlaySuggestions) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateSuggestionsOverlay();
    });
  }

  void _hideSuggestionsOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateSuggestionsOverlay() {
    if (!widget.overlaySuggestions || !_showSuggestions || _suggestions.isEmpty || !mounted) {
      _hideSuggestionsOverlay();
      return;
    }

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: _fieldWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -4),
          child: _buildSuggestionsBox(),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2 || !AppConfig.hasGoogleMaps) {
      setState(() {
        _suggestions = [];
        _loading = false;
        _showSuggestions = false;
      });
      _hideSuggestionsOverlay();
      return;
    }

    setState(() {
      _loading = true;
      _showSuggestions = true;
    });

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _places.autocomplete(input: text, bias: widget.bias);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
      _scheduleOverlayUpdate();
    });
  }

  Future<void> _pickPrediction(PlaceAutocompletePrediction prediction) async {
    setState(() {
      _showSuggestions = false;
      _loading = true;
      _controller.text = prediction.description;
    });
    _hideSuggestionsOverlay();

    final details = await _places.fetchPlaceDetails(prediction.placeId);
    if (!mounted) return;

    setState(() => _loading = false);
    if (details == null) return;

    widget.onSelected(
      PlaceMatchCandidate(
        placeId: details.placeId,
        name: details.name,
        address: details.address,
        location: details.location,
      ),
    );
  }

  Widget _buildSuggestionsBox() {
    return Material(
      elevation: 8,
      color: const Color(0xFF14141E),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
        ),
        constraints: BoxConstraints(maxHeight: widget.compact ? 200 : 180),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
          itemBuilder: (context, index) {
            final item = _suggestions[index];
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(item.description, style: TextStyle(fontSize: widget.compact ? 11 : 12)),
              onTap: () => _pickPrediction(item),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSuggestions({EdgeInsetsGeometry? margin}) {
    if (!_showSuggestions || _suggestions.isEmpty) return const SizedBox.shrink();
    if (widget.overlaySuggestions) return const SizedBox.shrink();

    return Container(
      margin: margin ?? EdgeInsets.only(left: widget.showPinBadge ? 34 : 0, top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF14141E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
      ),
      constraints: BoxConstraints(maxHeight: widget.compact ? 200 : 160),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
        itemBuilder: (context, index) {
          final item = _suggestions[index];
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(item.description, style: TextStyle(fontSize: widget.compact ? 11 : 12)),
            onTap: () => _pickPrediction(item),
          );
        },
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: widget.compact ? 11 : 13),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintText: widget.compact
            ? 'Search place…'
            : 'Search Google Maps for pin ${widget.pinNumber}',
        hintStyle: TextStyle(
          fontSize: widget.compact ? 10 : 12,
          color: AppTheme.textSecondary,
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A28),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(widget.compact ? 6 : 8),
          borderSide: BorderSide.none,
        ),
        suffixIcon: _loading
            ? Padding(
                padding: EdgeInsets.all(widget.compact ? 6 : 10),
                child: SizedBox(
                  width: widget.compact ? 14 : 16,
                  height: widget.compact ? 14 : 16,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : widget.value != null
                ? IconButton(
                    icon: Icon(Icons.close, size: widget.compact ? 16 : 18),
                    onPressed: () {
                      _controller.clear();
                      widget.onSearchTextChanged?.call('');
                      widget.onSelected(null);
                    },
                  )
                : null,
      ),
      onChanged: (text) {
        if (widget.value != null) widget.onSelected(null);
        widget.onSearchTextChanged?.call(text);
        _onChanged(text);
      },
      onTap: () {
        setState(() => _showSuggestions = _suggestions.isNotEmpty);
        _scheduleOverlayUpdate();
      },
    );
  }

  Widget _buildFieldRow() {
    return Row(
      children: [
        if (widget.showPinBadge) ...[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF42A5F5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              '${widget.pinNumber}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: _buildTextField()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          _fieldWidth = constraints.maxWidth;
          final field = widget.overlaySuggestions
              ? CompositedTransformTarget(
                  link: _layerLink,
                  child: _buildTextField(),
                )
              : _buildTextField();

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.overlaySuggestions) _buildSuggestions(),
              field,
              if (!AppConfig.hasGoogleMaps)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Add GOOGLE_MAPS_API_KEY to use autocomplete',
                    style: TextStyle(fontSize: 10, color: Colors.orange),
                  ),
                ),
            ],
          );
        },
      );
    }

    final field = LayoutBuilder(
      builder: (context, constraints) {
        _fieldWidth = constraints.maxWidth;
        return CompositedTransformTarget(
          link: _layerLink,
          child: _buildFieldRow(),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (!AppConfig.hasGoogleMaps)
          Padding(
            padding: EdgeInsets.only(top: 4, left: widget.showPinBadge ? 34 : 0),
            child: const Text(
              'Add GOOGLE_MAPS_API_KEY to use autocomplete',
              style: TextStyle(fontSize: 10, color: Colors.orange),
            ),
          ),
        if (!widget.overlaySuggestions) _buildSuggestions(),
      ],
    );
  }
}
