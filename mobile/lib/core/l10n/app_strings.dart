import 'app_language.dart';

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  bool get isMalayalam => language == AppLanguage.ml;

  String get switchLanguageLabel => switch (language) {
        AppLanguage.en => 'Switch to Malayalam',
        AppLanguage.ml => 'Switch to English',
      };

  String languageChangedSnack(AppLanguage newLanguage) => switch (newLanguage) {
        AppLanguage.en => 'Language set to English',
        AppLanguage.ml => 'ഭാഷ മലയാളത്തിലാക്കി',
      };

  String get reimportHloPdf => switch (language) {
        AppLanguage.en => 'Re-import HLO PDF',
        AppLanguage.ml => 'HLO PDF വീണ്ടും ഇറക്കുമതി ചെയ്യുക',
      };

  String get fineTunePdfOverlay => switch (language) {
        AppLanguage.en => 'Fine-tune PDF overlay',
        AppLanguage.ml => 'PDF ഓവർലേ ഫൈൻ-ട്യൂൺ ചെയ്യുക',
      };

  String get navigateToNwCorner => switch (language) {
        AppLanguage.en => 'Navigate to NW corner',
        AppLanguage.ml => 'വടക്ക്-പടിഞ്ഞാറ് മൂലയിലേക്ക് പോകുക',
      };

  String get hlbLayoutMap => switch (language) {
        AppLanguage.en => 'HLB layout map',
        AppLanguage.ml => 'HLB ലേഔട്ട് മാപ്പ്',
      };

  String get houseListing => switch (language) {
        AppLanguage.en => 'House listing',
        AppLanguage.ml => 'വീടുകളുടെ ലിസ്റ്റ്',
      };

  String get dashboard => switch (language) {
        AppLanguage.en => 'Dashboard',
        AppLanguage.ml => 'ഡാഷ്‌ബോർഡ്',
      };

  String get walkReplay => switch (language) {
        AppLanguage.en => 'Walk replay',
        AppLanguage.ml => 'നടപ്പ് റീപ്ലേ',
      };

  String get coverageGaps => switch (language) {
        AppLanguage.en => 'Coverage gaps',
        AppLanguage.ml => 'കവറേജ് ഗാപ്പുകൾ',
      };

  String get projects => switch (language) {
        AppLanguage.en => 'Projects',
        AppLanguage.ml => 'പ്രോജക്റ്റുകൾ',
      };

  String get downloadHlbMapPdf => switch (language) {
        AppLanguage.en => 'Download HLB map PDF',
        AppLanguage.ml => 'HLB മാപ്പ് PDF ഡൗൺലോഡ് ചെയ്യുക',
      };

  String get pdfExportFailed => switch (language) {
        AppLanguage.en => 'PDF export failed',
        AppLanguage.ml => 'PDF എക്സ്പോർട്ട് പരാജയപ്പെട്ടു',
      };

  String get importHloPdf => switch (language) {
        AppLanguage.en => 'Import HLO PDF',
        AppLanguage.ml => 'HLO PDF ഇറക്കുമതി ചെയ്യുക',
      };

  String get stopNavigation => switch (language) {
        AppLanguage.en => 'Stop navigation',
        AppLanguage.ml => 'നാവിഗേഷൻ നിർത്തുക',
      };

  String get fineTuneLandmarkHint => switch (language) {
        AppLanguage.en => 'Drag symbol to adjust · Save when done',
        AppLanguage.ml => 'ചിഹ്നം വലിച്ച് നീക്കുക · കഴിഞ്ഞാൽ സേവ് ചെയ്യുക',
      };

  String get importBoundaryHint => switch (language) {
        AppLanguage.en => 'Import HLO PDF to place your block on the map',
        AppLanguage.ml => 'നിങ്ങളുടെ ബ്ലോക്ക് മാപ്പിൽ വയ്ക്കാൻ HLO PDF ഇറക്കുമതി ചെയ്യുക',
      };

  String get traceRoadHint => switch (language) {
        AppLanguage.en => 'Trace road/canal — Add point at each bend',
        AppLanguage.ml => 'റോഡ്/കനാൽ വരയ്ക്കുക — ഓരോ വളവിലും പോയിന്റ് ചേർക്കുക',
      };

  String get crosshairHint => switch (language) {
        AppLanguage.en => 'Pan · zoom · rotate — crosshair marks the spot',
        AppLanguage.ml => 'പാൻ · സൂം · റൊട്ടേറ്റ് — ക്രോസ്ഹെയർ സ്ഥാനം കാണിക്കുന്നു',
      };

  String get openMapLayers => switch (language) {
        AppLanguage.en => 'Map layers',
        AppLanguage.ml => 'മാപ്പ് ലെയറുകൾ',
      };

  String get fitBoundary => switch (language) {
        AppLanguage.en => 'Fit boundary on screen',
        AppLanguage.ml => 'ബൗണ്ടറി സ്ക്രീനിൽ ഫിറ്റ് ചെയ്യുക',
      };

  String get placeBuilding => switch (language) {
        AppLanguage.en => 'Place building',
        AppLanguage.ml => 'കെട്ടിടം വയ്ക്കുക',
      };

  String get placeFeature => switch (language) {
        AppLanguage.en => 'Place feature',
        AppLanguage.ml => 'ഫീച്ചർ വയ്ക്കുക',
      };

  String get startRoad => switch (language) {
        AppLanguage.en => 'Start road',
        AppLanguage.ml => 'റോഡ് ആരംഭിക്കുക',
      };

  String get toolBuilding => switch (language) {
        AppLanguage.en => 'Building',
        AppLanguage.ml => 'കെട്ടിടം',
      };

  String get toolFeature => switch (language) {
        AppLanguage.en => 'Feature',
        AppLanguage.ml => 'ഫീച്ചർ',
      };

  String get toolRoad => switch (language) {
        AppLanguage.en => 'Road',
        AppLanguage.ml => 'റോഡ്',
      };

  String get footerSaved => switch (language) {
        AppLanguage.en => 'Footer saved on map',
        AppLanguage.ml => 'ഫൂട്ടർ മാപ്പിൽ സേവ് ചെയ്തു',
      };
}
