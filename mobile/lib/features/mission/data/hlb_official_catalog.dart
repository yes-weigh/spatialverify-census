/// Official HLB layout-map catalog — buildings, topography, places, open land (§4.4.3).
enum HlbCatalogCategory {
  buildings,
  topography,
  publicPlaces,
  commercial,
  landOpen,
}

class HlbCatalogEntry {
  const HlbCatalogEntry({
    required this.id,
    required this.label,
    required this.category,
    this.glyph,
    this.aliases = const [],
  });

  final String id;
  final String label;
  final HlbCatalogCategory category;
  final String? glyph;
  final List<String> aliases;
}

class HlbOfficialCatalog {
  HlbOfficialCatalog._();

  static const buildingEntries = <HlbCatalogEntry>[
    HlbCatalogEntry(id: 'pucca_residential', label: 'Pucca residential', category: HlbCatalogCategory.buildings, glyph: '□'),
    HlbCatalogEntry(id: 'non_residential_pucca', label: 'Pucca non-residential', category: HlbCatalogCategory.buildings, glyph: '▨'),
    HlbCatalogEntry(id: 'kutcha_residential', label: 'Kutcha residential', category: HlbCatalogCategory.buildings, glyph: '△'),
    HlbCatalogEntry(
      id: 'kutcha_non_residential',
      label: 'Kutcha non-residential',
      category: HlbCatalogCategory.buildings,
      glyph: '▲',
    ),
  ];

  static const landmarkEntries = <HlbCatalogEntry>[
    // Topography
    HlbCatalogEntry(id: 'road', label: 'Road', category: HlbCatalogCategory.topography, glyph: '═'),
    HlbCatalogEntry(id: 'street', label: 'Street / lane', category: HlbCatalogCategory.topography, glyph: '—'),
    HlbCatalogEntry(id: 'railway', label: 'Railway', category: HlbCatalogCategory.topography, glyph: '⊞'),
    HlbCatalogEntry(id: 'river', label: 'River / stream', category: HlbCatalogCategory.topography, glyph: '〰'),
    HlbCatalogEntry(id: 'pond', label: 'Pond / tank', category: HlbCatalogCategory.topography, glyph: '◯'),
    HlbCatalogEntry(id: 'hill', label: 'Hill', category: HlbCatalogCategory.topography, glyph: '▲'),
  // Public places
    HlbCatalogEntry(
      id: 'place_of_worship',
      label: 'Place of worship',
      category: HlbCatalogCategory.publicPlaces,
      glyph: '⛪',
      aliases: ['temple'],
    ),
    HlbCatalogEntry(id: 'school', label: 'School', category: HlbCatalogCategory.publicPlaces, glyph: 'Sch'),
    HlbCatalogEntry(id: 'hospital', label: 'Hospital / dispensary', category: HlbCatalogCategory.publicPlaces, glyph: '+'),
    HlbCatalogEntry(id: 'post_office', label: 'Post office', category: HlbCatalogCategory.publicPlaces, glyph: '✉'),
    HlbCatalogEntry(id: 'panchayat', label: 'Panchayat / local office', category: HlbCatalogCategory.publicPlaces, glyph: 'Pan'),
  // Commercial & important buildings
    HlbCatalogEntry(id: 'shop', label: 'Shop', category: HlbCatalogCategory.commercial, glyph: 'Sh'),
    HlbCatalogEntry(id: 'hotel', label: 'Hotel / lodge', category: HlbCatalogCategory.commercial, glyph: 'Ht'),
    HlbCatalogEntry(id: 'office', label: 'Office', category: HlbCatalogCategory.commercial, glyph: 'Of'),
    HlbCatalogEntry(id: 'town_hall', label: 'Town hall', category: HlbCatalogCategory.commercial, glyph: 'TH'),
    HlbCatalogEntry(id: 'court', label: 'Court building', category: HlbCatalogCategory.commercial, glyph: 'Ct'),
    HlbCatalogEntry(id: 'shopping_mall', label: 'Shopping mall', category: HlbCatalogCategory.commercial, glyph: 'Ml'),
  // Land & open spaces
    HlbCatalogEntry(id: 'open_space', label: 'Open space', category: HlbCatalogCategory.landOpen, glyph: '▢'),
    HlbCatalogEntry(id: 'field', label: 'Field / agriculture', category: HlbCatalogCategory.landOpen, glyph: 'Fld'),
    HlbCatalogEntry(id: 'vacant_plot', label: 'Vacant plot', category: HlbCatalogCategory.landOpen, glyph: 'Vac'),
    HlbCatalogEntry(id: 'forest_settlement', label: 'Forest settlement', category: HlbCatalogCategory.landOpen, glyph: 'For'),
    HlbCatalogEntry(id: 'estate_boundary', label: 'Estate / plantation', category: HlbCatalogCategory.landOpen, glyph: 'Est'),
    HlbCatalogEntry(id: 'other', label: 'Other feature', category: HlbCatalogCategory.landOpen, glyph: '•'),
  ];

  static final Map<String, HlbCatalogEntry> _buildingById = {
    for (final e in buildingEntries) e.id: e,
  };

  static final Map<String, HlbCatalogEntry> _landmarkById = {
    for (final e in landmarkEntries) e.id: e,
    for (final e in landmarkEntries)
      for (final a in e.aliases) a: e,
  };

  static const categoryLabels = <HlbCatalogCategory, String>{
    HlbCatalogCategory.buildings: 'Buildings',
    HlbCatalogCategory.topography: 'Roads & topography',
    HlbCatalogCategory.publicPlaces: 'Public places',
    HlbCatalogCategory.commercial: 'Commercial & offices',
    HlbCatalogCategory.landOpen: 'Open land & special',
  };

  static List<HlbCatalogEntry> landmarksInCategory(HlbCatalogCategory category) =>
      landmarkEntries.where((e) => e.category == category).toList();

  static String normalizeLandmarkType(String type) => _landmarkById[type]?.id ?? type;

  static String buildingLabel(String type) =>
      _buildingById[type]?.label ?? type.replaceAll('_', ' ');

  static String landmarkLabel(String type) {
    final normalized = normalizeLandmarkType(type);
    return _landmarkById[normalized]?.label ?? normalized.replaceAll('_', ' ');
  }

  static String? landmarkGlyph(String type) => _landmarkById[normalizeLandmarkType(type)]?.glyph;

  static bool isLandmarkType(String type) => _landmarkById.containsKey(type);

  static String legendLine() {
    final buildings = buildingEntries.map((e) => '${e.glyph} ${e.label.split(' ').first}').join('  ');
    return 'Buildings: $buildings';
  }

  static String compactLegendFeatures() =>
      'Features: road, river, pond, school, hospital, post office, worship, panchayat, open space, field, vacant';

  /// Infer catalog type from AI/camera label text.
  static String guessLandmarkTypeFromLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('temple') || l.contains('mosque') || l.contains('church') || l.contains('worship')) {
      return 'place_of_worship';
    }
    if (l.contains('school') || l.contains('college')) return 'school';
    if (l.contains('hospital') || l.contains('clinic') || l.contains('dispensary')) return 'hospital';
    if (l.contains('post office') || l.contains('postoffice')) return 'post_office';
    if (l.contains('panchayat') || l.contains('gram panchayat')) return 'panchayat';
    if (l.contains('shop') || l.contains('store') || l.contains('market')) return 'shop';
    if (l.contains('hotel') || l.contains('lodge')) return 'hotel';
    if (l.contains('office')) return 'office';
    if (l.contains('court')) return 'court';
    if (l.contains('mall')) return 'shopping_mall';
    if (l.contains('river') || l.contains('stream') || l.contains('nala')) return 'river';
    if (l.contains('pond') || l.contains('tank') || l.contains('lake')) return 'pond';
    if (l.contains('hill') || l.contains('mountain')) return 'hill';
    if (l.contains('rail')) return 'railway';
    if (l.contains('road') || l.contains('street') || l.contains('lane')) return 'road';
    if (l.contains('field') || l.contains('farm') || l.contains('agri')) return 'field';
    if (l.contains('vacant') || l.contains('empty plot')) return 'vacant_plot';
    if (l.contains('forest')) return 'forest_settlement';
    if (l.contains('open') || l.contains('ground') || l.contains('park')) return 'open_space';
    return 'other';
  }
}
