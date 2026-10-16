/// Exception thrown when Dynamic UI document validation fails.
class DynamicUiException implements Exception {
  final String message;
  final String? path;

  const DynamicUiException(this.message, [this.path]);

  @override
  String toString() {
    if (path != null) return 'DynamicUiException at "$path": $message';
    return 'DynamicUiException: $message';
  }
}

/// Allowlisted widget component types.
enum ComponentType {
  text('text'),
  container('container'),
  row('row'),
  column('column'),
  padding('padding'),
  image('image'),
  icon('icon'),
  button('button'),
  sizedBox('sized_box'),
  card('card'),
  divider('divider'),
  visibility('visibility');

  final String value;
  const ComponentType(this.value);

  static ComponentType parse(String val, [String? path]) {
    for (final t in ComponentType.values) {
      if (t.value == val) return t;
    }
    throw DynamicUiException(
      'Unknown or disallowed component type "$val". Supported types: ${ComponentType.values.map((t) => t.value).join(', ')}',
      path,
    );
  }
}

/// Allowlisted user actions.
enum ActionType {
  navigate('navigate'),
  showDialog('show_dialog'),
  openUrl('open_url'),
  toggleFlag('toggle_flag');

  final String value;
  const ActionType(this.value);

  static ActionType parse(String val, [String? path]) {
    for (final a in ActionType.values) {
      if (a.value == val) return a;
    }
    throw DynamicUiException('Unsupported action type "$val"', path);
  }
}

/// Predefined animation types.
enum AnimationType {
  fadeIn('fade_in'),
  slideUp('slide_up'),
  scale('scale');

  final String value;
  const AnimationType(this.value);

  static AnimationType parse(String val, [String? path]) {
    for (final a in AnimationType.values) {
      if (a.value == val) return a;
    }
    throw DynamicUiException('Unsupported animation type "$val"', path);
  }
}

/// Allowlisted icon identifiers.
const Set<String> kAllowlistedIcons = {
  'home',
  'settings',
  'info',
  'person',
  'star',
  'check',
  'close',
  'refresh',
  'arrow_forward',
  'arrow_back',
};

/// Typed immutable Action specification.
class DynamicAction {
  final ActionType type;
  final String? route;
  final String? url;
  final String? dialogTitle;
  final String? dialogMessage;
  final String? flagKey;

  const DynamicAction({
    required this.type,
    this.route,
    this.url,
    this.dialogTitle,
    this.dialogMessage,
    this.flagKey,
  });

  factory DynamicAction.fromJson(Map<String, dynamic> json, [String? path]) {
    final typeStr = json['type'] as String?;
    if (typeStr == null) {
      throw DynamicUiException('Action missing required field "type"', path);
    }
    final type = ActionType.parse(typeStr, path);

    final route = json['route'] as String?;
    final url = json['url'] as String?;
    if (type == ActionType.openUrl) {
      if (url == null || !url.startsWith('https://')) {
        throw DynamicUiException(
          'Action "open_url" requires an HTTPS URL: "$url"',
          path,
        );
      }
    }

    return DynamicAction(
      type: type,
      route: route,
      url: url,
      dialogTitle: json['dialogTitle'] as String?,
      dialogMessage: json['dialogMessage'] as String?,
      flagKey: json['flagKey'] as String?,
    );
  }
}

/// Typed immutable Animation specification.
class DynamicAnimation {
  final AnimationType type;
  final int durationMs;
  final String curve;

  const DynamicAnimation({
    required this.type,
    this.durationMs = 300,
    this.curve = 'easeInOut',
  });

  factory DynamicAnimation.fromJson(Map<String, dynamic> json, [String? path]) {
    final typeStr = json['type'] as String?;
    if (typeStr == null) {
      throw DynamicUiException('Animation missing required field "type"', path);
    }
    final type = AnimationType.parse(typeStr, path);

    final duration = json['durationMs'] as int? ?? 300;
    if (duration < 50 || duration > 2000) {
      throw DynamicUiException(
        'Animation durationMs must be between 50 and 2000 ms, got $duration',
        path,
      );
    }

    final curve = json['curve'] as String? ?? 'easeInOut';

    return DynamicAnimation(type: type, durationMs: duration, curve: curve);
  }
}

/// Typed immutable Component Properties.
class ComponentProperties {
  final String? text;
  final double? fontSize;
  final String? fontWeight;
  final String? color;
  final String? backgroundColor;
  final double? padding;
  final double? margin;
  final double? width;
  final double? height;
  final double? borderRadius;
  final double? elevation;
  final String? imageUrl;
  final String? icon;
  final DynamicAction? action;
  final DynamicAnimation? animation;

  const ComponentProperties({
    this.text,
    this.fontSize,
    this.fontWeight,
    this.color,
    this.backgroundColor,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderRadius,
    this.elevation,
    this.imageUrl,
    this.icon,
    this.action,
    this.animation,
  });

  static final RegExp _colorRegex = RegExp(
    r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  );

  factory ComponentProperties.fromJson(
    Map<String, dynamic>? json, [
    String? path,
  ]) {
    if (json == null) return const ComponentProperties();

    final color = json['color'] as String?;
    if (color != null && !_colorRegex.hasMatch(color)) {
      throw DynamicUiException(
        'Invalid color hex format "$color". Expected #RRGGBB or #AARRGGBB',
        path,
      );
    }

    final bgColor = json['backgroundColor'] as String?;
    if (bgColor != null && !_colorRegex.hasMatch(bgColor)) {
      throw DynamicUiException(
        'Invalid backgroundColor format "$bgColor"',
        path,
      );
    }

    final imageUrl = (json['imageUrl'] ?? json['url']) as String?;
    if (imageUrl != null && !imageUrl.startsWith('https://')) {
      throw DynamicUiException(
        'Image URL must start with https://, got "$imageUrl"',
        path,
      );
    }

    final icon = (json['icon'] ?? json['iconName']) as String?;
    if (icon != null && !kAllowlistedIcons.contains(icon)) {
      throw DynamicUiException(
        'Unknown or unapproved icon "$icon". Supported: ${kAllowlistedIcons.join(', ')}',
        path,
      );
    }

    final actionJson = json['action'] as Map<String, dynamic>?;
    final action = actionJson != null
        ? DynamicAction.fromJson(actionJson, '$path.action')
        : null;

    final animJson = json['animation'] as Map<String, dynamic>?;
    final animation = animJson != null
        ? DynamicAnimation.fromJson(animJson, '$path.animation')
        : null;

    return ComponentProperties(
      text: json['text'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      fontWeight: json['fontWeight'] as String?,
      color: color,
      backgroundColor: bgColor,
      padding: (json['padding'] as num?)?.toDouble(),
      margin: (json['margin'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      borderRadius: (json['borderRadius'] as num?)?.toDouble(),
      elevation: (json['elevation'] as num?)?.toDouble(),
      imageUrl: imageUrl,
      icon: icon,
      action: action,
      animation: animation,
    );
  }
}

/// Typed immutable Component node in the UI AST.
class DynamicComponent {
  final String? id;
  final ComponentType type;
  final bool visible;
  final String? visibleIf;
  final ComponentProperties properties;
  final DynamicComponent? child;
  final List<DynamicComponent> children;

  const DynamicComponent({
    this.id,
    required this.type,
    this.visible = true,
    this.visibleIf,
    this.properties = const ComponentProperties(),
    this.child,
    this.children = const [],
  });

  factory DynamicComponent.fromJson(
    Map<String, dynamic> json, {
    String path = 'component',
    int depth = 0,
    int maxDepth = 15,
  }) {
    if (depth > maxDepth) {
      throw DynamicUiException(
        'Maximum nesting depth ($maxDepth) exceeded at "$path"',
        path,
      );
    }

    final typeStr = json['type'] as String?;
    if (typeStr == null) {
      throw DynamicUiException('Missing required field "type"', path);
    }
    final type = ComponentType.parse(typeStr, path);

    final id = json['id'] as String?;
    final visible = json['visible'] as bool? ?? true;
    final visibleIf = json['visibleIf'] as String?;

    final propsJson = json['properties'] as Map<String, dynamic>?;
    final properties = ComponentProperties.fromJson(
      propsJson,
      '$path.properties',
    );

    DynamicComponent? child;
    final childJson = json['child'] as Map<String, dynamic>?;
    if (childJson != null) {
      child = DynamicComponent.fromJson(
        childJson,
        path: '$path.child',
        depth: depth + 1,
        maxDepth: maxDepth,
      );
    }

    final childrenList = <DynamicComponent>[];
    final childrenRaw = json['children'] as List<dynamic>?;
    if (childrenRaw != null) {
      if (childrenRaw.length > 50) {
        throw DynamicUiException(
          'Exceeded maximum children limit of 50 at "$path"',
          path,
        );
      }
      for (var i = 0; i < childrenRaw.length; i++) {
        final cJson = childrenRaw[i];
        if (cJson is Map<String, dynamic>) {
          childrenList.add(
            DynamicComponent.fromJson(
              cJson,
              path: '$path.children[$i]',
              depth: depth + 1,
              maxDepth: maxDepth,
            ),
          );
        }
      }
    }

    return DynamicComponent(
      id: id,
      type: type,
      visible: visible,
      visibleIf: visibleIf,
      properties: properties,
      child: child,
      children: childrenList,
    );
  }
}

/// Typed immutable Screen definition.
class DynamicScreen {
  final String title;
  final DynamicComponent root;

  const DynamicScreen({required this.title, required this.root});

  factory DynamicScreen.fromJson(
    Map<String, dynamic> json, [
    String path = 'screen',
  ]) {
    final title = json['title'] as String?;
    if (title == null || title.isEmpty) {
      throw DynamicUiException('Screen missing required field "title"', path);
    }
    final rootJson = json['root'] as Map<String, dynamic>?;
    if (rootJson == null) {
      throw DynamicUiException('Screen missing required field "root"', path);
    }

    return DynamicScreen(
      title: title,
      root: DynamicComponent.fromJson(rootJson, path: '$path.root'),
    );
  }
}

/// Global theme tokens.
class DynamicTheme {
  final String? primaryColor;
  final String? backgroundColor;
  final String? textColor;

  const DynamicTheme({this.primaryColor, this.backgroundColor, this.textColor});

  factory DynamicTheme.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DynamicTheme();
    return DynamicTheme(
      primaryColor: json['primaryColor'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
    );
  }
}

/// Typed immutable root document for a Dynamic UI bundle.
class DynamicUiDocument {
  final int schemaVersion;
  final String configId;
  final int revision;
  final String? minAppVersion;
  final DynamicTheme theme;
  final List<String> routes;
  final Map<String, bool> featureFlags;
  final Map<String, DynamicScreen> screens;

  const DynamicUiDocument({
    required this.schemaVersion,
    required this.configId,
    required this.revision,
    this.minAppVersion,
    this.theme = const DynamicTheme(),
    this.routes = const [],
    this.featureFlags = const {},
    required this.screens,
  });

  factory DynamicUiDocument.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'] as int?;
    if (version == null || version != 1) {
      throw DynamicUiException(
        'Unsupported or missing schemaVersion: $version. Expected 1.',
      );
    }

    final configId = json['configId'] as String?;
    if (configId == null || configId.isEmpty) {
      throw const DynamicUiException('Missing required field "configId".');
    }

    final revision = json['revision'] as int?;
    if (revision == null || revision < 1) {
      throw DynamicUiException(
        'Invalid or missing "revision": $revision. Must be >= 1.',
      );
    }

    final minAppVer = json['minAppVersion'] as String?;
    final theme = DynamicTheme.fromJson(json['theme'] as Map<String, dynamic>?);

    final routes =
        (json['routes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        [];

    final flags = <String, bool>{};
    if (json['featureFlags'] is Map) {
      final rawFlags = json['featureFlags'] as Map;
      for (final k in rawFlags.keys) {
        if (rawFlags[k] is bool) {
          flags[k.toString()] = rawFlags[k] as bool;
        }
      }
    }

    final screensMap = <String, DynamicScreen>{};
    final screensRaw = json['screens'] as Map<String, dynamic>?;
    if (screensRaw == null || screensRaw.isEmpty) {
      throw const DynamicUiException(
        'Document must define at least one screen in "screens".',
      );
    }

    for (final entry in screensRaw.entries) {
      if (entry.value is Map<String, dynamic>) {
        screensMap[entry.key] = DynamicScreen.fromJson(
          entry.value as Map<String, dynamic>,
          'screens.${entry.key}',
        );
      }
    }

    return DynamicUiDocument(
      schemaVersion: version,
      configId: configId,
      revision: revision,
      minAppVersion: minAppVer,
      theme: theme,
      routes: routes,
      featureFlags: flags,
      screens: screensMap,
    );
  }
}
