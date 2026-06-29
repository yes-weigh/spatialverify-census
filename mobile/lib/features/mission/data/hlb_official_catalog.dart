/// Official HLB layout-map catalog — Census 2027 sample form (§4.4.3).
enum HlbCatalogCategory {
  buildings,
  topography,
  utilities,
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
    // Roads & water (point legend icons — lines use lineFeatureTypes)
    HlbCatalogEntry(id: 'pucca_road', label: 'Pucca road', category: HlbCatalogCategory.topography, glyph: '═', aliases: ['road']),
    HlbCatalogEntry(id: 'kutcha_road', label: 'Kutcha road', category: HlbCatalogCategory.topography, glyph: '≡'),
    HlbCatalogEntry(id: 'street', label: 'Street / lane', category: HlbCatalogCategory.topography, glyph: '—'),
    HlbCatalogEntry(id: 'path', label: 'Pathway', category: HlbCatalogCategory.topography, glyph: '· ·'),
    HlbCatalogEntry(id: 'canal', label: 'Canal', category: HlbCatalogCategory.topography, glyph: '≋'),
    HlbCatalogEntry(id: 'railway', label: 'Railway', category: HlbCatalogCategory.topography, glyph: '⊞'),
    HlbCatalogEntry(id: 'river', label: 'River / stream', category: HlbCatalogCategory.topography, glyph: '〰'),
    HlbCatalogEntry(id: 'pond', label: 'Pond / tank', category: HlbCatalogCategory.topography, glyph: '◯'),
    HlbCatalogEntry(id: 'hill', label: 'Hill', category: HlbCatalogCategory.topography, glyph: '▲'),
    // Water utilities
    HlbCatalogEntry(id: 'well', label: 'Well', category: HlbCatalogCategory.utilities, glyph: 'W'),
    HlbCatalogEntry(id: 'tap', label: 'Tap', category: HlbCatalogCategory.utilities, glyph: 'T'),
    HlbCatalogEntry(id: 'handpump', label: 'Handpump', category: HlbCatalogCategory.utilities, glyph: 'Hp'),
    // Places of worship (separate symbols per manual)
    HlbCatalogEntry(id: 'temple', label: 'Temple / Mandir', category: HlbCatalogCategory.publicPlaces, glyph: '⌂', aliases: ['mandir']),
    HlbCatalogEntry(id: 'mosque', label: 'Mosque', category: HlbCatalogCategory.publicPlaces, glyph: '☪'),
    HlbCatalogEntry(id: 'church', label: 'Church', category: HlbCatalogCategory.publicPlaces, glyph: '✝'),
    HlbCatalogEntry(id: 'gurudwara', label: 'Gurudwara', category: HlbCatalogCategory.publicPlaces, glyph: 'Kh'),
    HlbCatalogEntry(
      id: 'place_of_worship',
      label: 'Place of worship (other)',
      category: HlbCatalogCategory.publicPlaces,
      glyph: '⛪',
    ),
    HlbCatalogEntry(id: 'school', label: 'School', category: HlbCatalogCategory.publicPlaces, glyph: 'Sch'),
    HlbCatalogEntry(id: 'hospital', label: 'Hospital / dispensary', category: HlbCatalogCategory.publicPlaces, glyph: '+'),
    HlbCatalogEntry(id: 'post_office', label: 'Post office', category: HlbCatalogCategory.publicPlaces, glyph: '✉'),
    HlbCatalogEntry(id: 'panchayat', label: 'Panchayat Ghar', category: HlbCatalogCategory.publicPlaces, glyph: 'Pan'),
    HlbCatalogEntry(id: 'market', label: 'Market / bazaar', category: HlbCatalogCategory.commercial, glyph: 'Mk'),
    HlbCatalogEntry(id: 'shop', label: 'Shop', category: HlbCatalogCategory.commercial, glyph: 'Sh'),
    HlbCatalogEntry(id: 'hotel', label: 'Hotel / lodge', category: HlbCatalogCategory.commercial, glyph: 'Ht'),
    HlbCatalogEntry(id: 'office', label: 'Office', category: HlbCatalogCategory.commercial, glyph: 'Of'),
    HlbCatalogEntry(id: 'town_hall', label: 'Town hall', category: HlbCatalogCategory.commercial, glyph: 'TH'),
    HlbCatalogEntry(id: 'court', label: 'Court building', category: HlbCatalogCategory.commercial, glyph: 'Ct'),
    HlbCatalogEntry(id: 'shopping_mall', label: 'Shopping mall', category: HlbCatalogCategory.commercial, glyph: 'Ml'),
    HlbCatalogEntry(id: 'open_space', label: 'Open space / Park', category: HlbCatalogCategory.landOpen, glyph: '▢'),
    HlbCatalogEntry(id: 'field', label: 'Field / agriculture', category: HlbCatalogCategory.landOpen, glyph: 'Fld'),
    HlbCatalogEntry(id: 'vacant_plot', label: 'Vacant plot', category: HlbCatalogCategory.landOpen, glyph: 'Vac'),
    HlbCatalogEntry(id: 'forest_settlement', label: 'Forest settlement', category: HlbCatalogCategory.landOpen, glyph: 'For'),
    HlbCatalogEntry(id: 'estate_boundary', label: 'Estate / plantation', category: HlbCatalogCategory.landOpen, glyph: 'Est'),
    HlbCatalogEntry(
      id: 'building_cluster',
      label: 'Building cluster',
      category: HlbCatalogCategory.landOpen,
      glyph: '▣',
      aliases: ['cluster'],
    ),
    HlbCatalogEntry(
      id: 'isolated_building',
      label: 'Isolated building',
      category: HlbCatalogCategory.landOpen,
      glyph: '▫',
      aliases: ['isolated'],
    ),
    HlbCatalogEntry(
      id: 'adjacent_hlb',
      label: 'Adjacent HLB reference',
      category: HlbCatalogCategory.landOpen,
      glyph: 'HLB',
    ),
    HlbCatalogEntry(id: 'other', label: 'Other feature', category: HlbCatalogCategory.landOpen, glyph: '•'),
  ];

  /// Polylines traced on map or draft layout.
  static const lineFeatureTypes = <String>[
    'pucca_road',
    'kutcha_road',
    'street',
    'canal',
    'path',
    'railway',
    'river',
  ];

  static final Map<String, HlbCatalogEntry> _buildingById = {
    for (final e in buildingEntries) e.id: e,
  };

  static final Map<String, HlbCatalogEntry> _landmarkById = {
    for (final e in landmarkEntries) e.id: e,
    for (final e in landmarkEntries)
      for (final a in e.aliases) a: e,
    'road': landmarkEntries.firstWhere((e) => e.id == 'pucca_road'),
  };

  static const categoryLabels = <HlbCatalogCategory, String>{
    HlbCatalogCategory.buildings: 'Buildings',
    HlbCatalogCategory.topography: 'Roads & water',
    HlbCatalogCategory.utilities: 'Water supply',
    HlbCatalogCategory.publicPlaces: 'Public places',
    HlbCatalogCategory.commercial: 'Commercial',
    HlbCatalogCategory.landOpen: 'Open land & refs',
  };

  static List<HlbCatalogEntry> landmarksInCategory(HlbCatalogCategory category) =>
      landmarkEntries.where((e) => e.category == category).toList();

  static String normalizeLandmarkType(String type) {
    if (type == 'road') return 'pucca_road';
    return _landmarkById[type]?.id ?? type;
  }

  static String normalizeLineType(String type) => normalizeLandmarkType(type);

  static String buildingLabel(String type) =>
      _buildingById[type]?.label ?? type.replaceAll('_', ' ');

  static String landmarkLabel(String type) {
    final normalized = normalizeLandmarkType(type);
    return _landmarkById[normalized]?.label ?? normalized.replaceAll('_', ' ');
  }

  static String? landmarkGlyph(String type) => _landmarkById[normalizeLandmarkType(type)]?.glyph;

  static bool isLandmarkType(String type) => _landmarkById.containsKey(type) || type == 'road';

  static bool isLineFeatureType(String type) => lineFeatureTypes.contains(normalizeLineType(type));

  static String lineFeatureLabel(String type) => landmarkLabel(type);

  static List<HlbCatalogEntry> get lineFeatureEntries =>
      landmarkEntries.where((e) => lineFeatureTypes.contains(e.id)).toList();

  static String legendLine() {
    final buildings = buildingEntries.map((e) => '${e.glyph} ${e.label.split(' ').first}').join('  ');
    return 'Buildings: $buildings';
  }

  static String compactLegendFeatures() =>
      'Roads: pucca ═, kutcha ≡, path ·· | Water: well, tap, handpump | Worship: temple, mosque, church, gurudwara';

  static String guessLandmarkTypeFromLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('gurudwara') || l.contains('gurdwara')) return 'gurudwara';
    if (l.contains('mosque')) return 'mosque';
    if (l.contains('church')) return 'church';
    if (l.contains('temple') || l.contains('mandir')) return 'temple';
    if (l.contains('well')) return 'well';
    if (l.contains('handpump') || l.contains('hand pump')) return 'handpump';
    if (l.contains('tap') || l.contains('water tap')) return 'tap';
    if (l.contains('hlb no') || l.contains('hlb:')) return 'adjacent_hlb';
    if (l.contains('worship')) return 'place_of_worship';
    if (l.contains('school') || l.contains('college')) return 'school';
    if (l.contains('hospital') || l.contains('clinic') || l.contains('dispensary')) return 'hospital';
    if (l.contains('post office') || l.contains('postoffice')) return 'post_office';
    if (l.contains('panchayat') || l.contains('gram panchayat')) return 'panchayat';
    if (l.contains('market') || l.contains('bazaar')) return 'market';
    if (l.contains('shop') || l.contains('store')) return 'shop';
    if (l.contains('canal') || l.contains('irrigation')) return 'canal';
    if (l.contains('path') || l.contains('footpath') || l.contains('trail')) return 'path';
    if (l.contains('kutcha road') || l.contains('kacha road')) return 'kutcha_road';
    if (l.contains('cluster')) return 'building_cluster';
    if (l.contains('isolated')) return 'isolated_building';
    if (l.contains('hotel') || l.contains('lodge')) return 'hotel';
    if (l.contains('office')) return 'office';
    if (l.contains('court')) return 'court';
    if (l.contains('mall')) return 'shopping_mall';
    if (l.contains('river') || l.contains('stream') || l.contains('nala')) return 'river';
    if (l.contains('pond') || l.contains('tank') || l.contains('lake')) return 'pond';
    if (l.contains('hill') || l.contains('mountain')) return 'hill';
    if (l.contains('rail')) return 'railway';
    if (l.contains('road') || l.contains('street') || l.contains('lane')) return 'pucca_road';
    if (l.contains('field') || l.contains('farm') || l.contains('agri')) return 'field';
    if (l.contains('vacant') || l.contains('empty plot')) return 'vacant_plot';
    if (l.contains('forest')) return 'forest_settlement';
    if (l.contains('open') || l.contains('ground') || l.contains('park')) return 'open_space';
    return 'other';
  }
}
