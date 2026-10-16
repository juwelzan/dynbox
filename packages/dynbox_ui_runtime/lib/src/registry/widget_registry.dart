import '../models/dynamic_ui_models.dart';

/// Callback signature for handling safe allowlisted actions.
typedef ActionHandler = void Function(DynamicAction action);

/// Interface for building concrete visual elements from dynamic components.
///
/// This abstraction decouples pure Dart parsing and model evaluation from
/// the Flutter rendering engine, while allowing complete widget tree construction.
abstract class WidgetRenderer<T> {
  T renderScreen(
    DynamicScreen screen,
    DynamicTheme? theme,
    RenderContext context,
  );
  T renderComponent(
    DynamicComponent component,
    DynamicTheme? theme,
    RenderContext context,
  );
}

/// Evaluation and action dispatch context for component rendering.
class RenderContext {
  final Map<String, bool> featureFlags;
  final Set<String> registeredRoutes;
  final ActionHandler? onAction;
  final int currentDepth;
  static const int maxRenderDepth = 20;

  RenderContext({
    this.featureFlags = const {},
    this.registeredRoutes = const {},
    this.onAction,
    this.currentDepth = 0,
  });

  RenderContext nextLevel() => RenderContext(
    featureFlags: featureFlags,
    registeredRoutes: registeredRoutes,
    onAction: onAction,
    currentDepth: currentDepth + 1,
  );

  bool isFeatureEnabled(String flagName) {
    return featureFlags[flagName] ?? false;
  }

  bool isRouteAllowed(String routeName) {
    return registeredRoutes.contains(routeName);
  }

  void dispatchAction(DynamicAction action) {
    if (action.type == ActionType.navigate &&
        (action.route == null || !isRouteAllowed(action.route!))) {
      throw DynamicUiException(
        'Disallowed or missing navigation target route: "${action.route}"',
      );
    }
    if (action.type == ActionType.openUrl) {
      if (action.url == null) {
        throw const DynamicUiException(
          'Disallowed action: URL must not be null',
        );
      }
      final uri = Uri.tryParse(action.url!);
      if (uri == null || uri.scheme != 'https') {
        throw DynamicUiException(
          'Disallowed action URL (must be HTTPS): "${action.url}"',
        );
      }
    }
    onAction?.call(action);
  }
}

/// Allowlisted widget descriptor defining properties, constraints, and validation rules.
class WidgetDescriptor {
  final ComponentType type;
  final Set<String> requiredProperties;
  final Set<String> supportedProperties;
  final bool allowsChildren;
  final int maxChildren;

  const WidgetDescriptor({
    required this.type,
    this.requiredProperties = const {},
    this.supportedProperties = const {},
    this.allowsChildren = false,
    this.maxChildren = 0,
  });
}

/// Registry of allowlisted built-in widgets.
///
/// Ensures no arbitrary classes, dynamic reflection, or unapproved widgets can be rendered.
class WidgetRegistry {
  static final Map<ComponentType, WidgetDescriptor> _descriptors = {
    ComponentType.text: const WidgetDescriptor(
      type: ComponentType.text,
      requiredProperties: {'text'},
      supportedProperties: {
        'text',
        'style',
        'color',
        'fontSize',
        'textAlign',
        'maxLines',
      },
      allowsChildren: false,
    ),
    ComponentType.container: const WidgetDescriptor(
      type: ComponentType.container,
      supportedProperties: {
        'width',
        'height',
        'color',
        'padding',
        'margin',
        'borderRadius',
        'borderColor',
        'borderWidth',
        'alignment',
      },
      allowsChildren: true,
      maxChildren: 1,
    ),
    ComponentType.row: const WidgetDescriptor(
      type: ComponentType.row,
      supportedProperties: {'mainAxisAlignment', 'crossAxisAlignment'},
      allowsChildren: true,
      maxChildren: 50,
    ),
    ComponentType.column: const WidgetDescriptor(
      type: ComponentType.column,
      supportedProperties: {'mainAxisAlignment', 'crossAxisAlignment'},
      allowsChildren: true,
      maxChildren: 50,
    ),
    ComponentType.padding: const WidgetDescriptor(
      type: ComponentType.padding,
      requiredProperties: {'padding'},
      supportedProperties: {'padding'},
      allowsChildren: true,
      maxChildren: 1,
    ),
    ComponentType.image: const WidgetDescriptor(
      type: ComponentType.image,
      requiredProperties: {'url'},
      supportedProperties: {'url', 'width', 'height', 'fit', 'borderRadius'},
      allowsChildren: false,
    ),
    ComponentType.icon: const WidgetDescriptor(
      type: ComponentType.icon,
      requiredProperties: {'iconName'},
      supportedProperties: {'iconName', 'size', 'color'},
      allowsChildren: false,
    ),
    ComponentType.button: const WidgetDescriptor(
      type: ComponentType.button,
      requiredProperties: {'label'},
      supportedProperties: {
        'label',
        'action',
        'backgroundColor',
        'textColor',
        'iconName',
      },
      allowsChildren: false,
    ),
    ComponentType.sizedBox: const WidgetDescriptor(
      type: ComponentType.sizedBox,
      supportedProperties: {'width', 'height'},
      allowsChildren: true,
      maxChildren: 1,
    ),
    ComponentType.card: const WidgetDescriptor(
      type: ComponentType.card,
      supportedProperties: {'elevation', 'color', 'borderRadius', 'padding'},
      allowsChildren: true,
      maxChildren: 1,
    ),
    ComponentType.divider: const WidgetDescriptor(
      type: ComponentType.divider,
      supportedProperties: {'height', 'thickness', 'color'},
      allowsChildren: false,
    ),
    ComponentType.visibility: const WidgetDescriptor(
      type: ComponentType.visibility,
      supportedProperties: {'condition', 'featureFlag', 'visible'},
      allowsChildren: true,
      maxChildren: 1,
    ),
  };

  static WidgetDescriptor getDescriptor(ComponentType type) {
    final descriptor = _descriptors[type];
    if (descriptor == null) {
      throw DynamicUiException(
        'No registered descriptor for widget type: ${type.value}',
      );
    }
    return descriptor;
  }

  static bool isRegistered(ComponentType type) =>
      _descriptors.containsKey(type);

  static List<ComponentType> get registeredTypes =>
      List.unmodifiable(_descriptors.keys);
}
