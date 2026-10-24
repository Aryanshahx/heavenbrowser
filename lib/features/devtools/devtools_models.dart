class DevToolsConsoleEntry {
  const DevToolsConsoleEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source = '',
    this.line = 0,
  });

  final DateTime timestamp;
  final String level; // log, info, warn, warning, error, input, result
  final String message;
  final String source;
  final int line;

  bool get isError => level == 'error';
  bool get isWarning => level == 'warn' || level == 'warning';
}

class DevToolsNetworkEntry {
  const DevToolsNetworkEntry({
    required this.url,
    required this.method,
    required this.type,
    required this.status,
    required this.durationMs,
    this.transferBytes = 0,
  });

  final String url;
  final String method;
  final String type; // fetch, xhr, script, css, img, media, doc
  final int status; // 200, 404, 0 (opaque)
  final int durationMs;
  final int transferBytes;
}

class DevToolsDomNode {
  const DevToolsDomNode({
    required this.nodeId,
    required this.tag,
    required this.idAttr,
    required this.classAttr,
    required this.textPreview,
    required this.depth,
    required this.childCount,
  });

  final int nodeId;
  final String tag;
  final String idAttr;
  final String classAttr;
  final String textPreview;
  final int depth;
  final int childCount;

  factory DevToolsDomNode.fromMap(Map<Object?, Object?> m) {
    return DevToolsDomNode(
      nodeId: (m['nodeId'] as num?)?.toInt() ?? 0,
      tag: m['tag']?.toString() ?? 'div',
      idAttr: m['id']?.toString() ?? '',
      classAttr: m['cls']?.toString() ?? '',
      textPreview: m['txt']?.toString() ?? '',
      depth: (m['depth'] as num?)?.toInt() ?? 0,
      childCount: (m['children'] as num?)?.toInt() ?? 0,
    );
  }
}

class DevToolsInspectedElement {
  const DevToolsInspectedElement({
    required this.nodeId,
    required this.tag,
    required this.selector,
    required this.outerHtml,
    required this.inlineStyle,
    required this.dimensions,
    required this.attributes,
    required this.computedStyles,
  });

  final int nodeId;
  final String tag;
  final String selector;
  final String outerHtml;
  final String inlineStyle;
  final String dimensions;
  final Map<String, String> attributes;
  final Map<String, String> computedStyles;

  factory DevToolsInspectedElement.fromMap(Map<Object?, Object?> m) {
    final Map<String, String> attrs = <String, String>{};
    if (m['attributes'] is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> e
          in (m['attributes']! as Map<Object?, Object?>).entries) {
        if (e.key != null) {
          attrs[e.key.toString()] = e.value?.toString() ?? '';
        }
      }
    }
    final Map<String, String> comp = <String, String>{};
    if (m['computedStyles'] is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> e
          in (m['computedStyles']! as Map<Object?, Object?>).entries) {
        if (e.key != null) {
          comp[e.key.toString()] = e.value?.toString() ?? '';
        }
      }
    }
    return DevToolsInspectedElement(
      nodeId: (m['nodeId'] as num?)?.toInt() ?? 0,
      tag: m['tag']?.toString() ?? 'div',
      selector: m['selector']?.toString() ?? '',
      outerHtml: m['outerHtml']?.toString() ?? '',
      inlineStyle: m['inlineStyle']?.toString() ?? '',
      dimensions: m['dimensions']?.toString() ?? '0 × 0',
      attributes: attrs,
      computedStyles: comp,
    );
  }
}
