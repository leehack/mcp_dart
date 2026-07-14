/// Shared report model for MCP inspector commands.
class InspectionReport {
  /// Creates an inspector report.
  const InspectionReport({
    required this.kind,
    required this.target,
    required this.checks,
    this.metadata = const <String, dynamic>{},
    this.inventory = const <String, dynamic>{},
  });

  /// Report type, for example `server` or `client`.
  final String kind;

  /// Human-readable inspected target.
  final String target;

  /// Metadata captured during inspection.
  final Map<String, dynamic> metadata;

  /// Discovered server/client inventory.
  final Map<String, dynamic> inventory;

  /// Checks performed by the inspector.
  final List<InspectionCheck> checks;

  /// Number of passing checks.
  int get passCount => checks.where((check) => check.status == 'pass').length;

  /// Number of informational checks.
  int get infoCount => checks.where((check) => check.status == 'info').length;

  /// Number of warning checks.
  int get warningCount =>
      checks.where((check) => check.status == 'warning').length;

  /// Number of failing checks.
  int get failCount => checks.where((check) => check.status == 'fail').length;

  /// Whether the report has no failing checks.
  bool get passed => failCount == 0;

  /// Converts this report to JSON.
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'target': target,
    'passed': passed,
    'summary': <String, dynamic>{
      'pass': passCount,
      'info': infoCount,
      'warning': warningCount,
      'fail': failCount,
      'total': checks.length,
    },
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (inventory.isNotEmpty) 'inventory': inventory,
    'checks': checks.map((check) => check.toJson()).toList(),
  };
}

/// One inspector finding.
class InspectionCheck {
  /// Creates an inspector check.
  const InspectionCheck({
    required this.id,
    required this.status,
    required this.message,
    this.details,
  });

  /// Stable check identifier.
  final String id;

  /// Check status: `pass`, `info`, `warning`, or `fail`.
  final String status;

  /// Human-readable finding.
  final String message;

  /// Optional structured details.
  final Map<String, dynamic>? details;

  /// Converts this check to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'message': message,
    if (details != null && details!.isNotEmpty) 'details': details,
  };
}

/// Builds inspector checks with consistent status strings.
class InspectionCheckBuilder {
  final List<InspectionCheck> _checks = <InspectionCheck>[];

  /// Recorded checks.
  List<InspectionCheck> get checks => List.unmodifiable(_checks);

  /// Adds a passing check.
  void pass(
    String id,
    String message, {
    Map<String, dynamic>? details,
  }) {
    _add('pass', id, message, details: details);
  }

  /// Adds an informational check.
  void info(
    String id,
    String message, {
    Map<String, dynamic>? details,
  }) {
    _add('info', id, message, details: details);
  }

  /// Adds a warning check.
  void warning(
    String id,
    String message, {
    Map<String, dynamic>? details,
  }) {
    _add('warning', id, message, details: details);
  }

  /// Adds a failing check.
  void fail(
    String id,
    String message, {
    Map<String, dynamic>? details,
  }) {
    _add('fail', id, message, details: details);
  }

  void _add(
    String status,
    String id,
    String message, {
    Map<String, dynamic>? details,
  }) {
    _checks.add(
      InspectionCheck(
        id: id,
        status: status,
        message: message,
        details: details,
      ),
    );
  }
}
