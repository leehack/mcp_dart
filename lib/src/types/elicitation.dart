import '../shared/json_schema/json_schema.dart';
import 'json_rpc.dart';

/// Legacy alias for [JsonSchema] used in elicitation requests.
typedef ElicitationInputSchema = JsonSchema;

/// Elicitation mode: 'form' for in-band structured data, 'url' for out-of-band interaction.
enum ElicitationMode {
  /// In-band structured data collection with optional schema validation.
  /// Data is exposed to the client.
  form,

  /// Out-of-band interaction via URL navigation.
  /// Data (other than the URL itself) is NOT exposed to the client.
  url,
}

/// Parameters for the `elicitation/create` request.
///
/// Supports two modes:
/// - **Form mode**: Collects structured data directly through the MCP client
/// - **URL mode**: Directs users to external URLs for sensitive interactions
class ElicitRequestParams {
  /// The mode of elicitation. Defaults to 'form' if omitted (for backwards compatibility).
  final ElicitationMode? mode;

  /// A human-readable message explaining why the interaction is needed.
  final String message;

  /// The JSON Schema defining what type of input to collect.
  /// Required for form mode, not used for URL mode.
  final ElicitationInputSchema? requestedSchema;

  /// The URL that the user should navigate to.
  /// Required for URL mode, not used for form mode.
  final String? url;

  /// A unique identifier for the elicitation.
  /// Required for URL mode to correlate with completion notifications.
  final String? elicitationId;

  const ElicitRequestParams({
    this.mode,
    required this.message,
    this.requestedSchema,
    this.url,
    this.elicitationId,
  });

  /// Creates form mode elicitation parameters.
  const ElicitRequestParams.form({
    required this.message,
    required ElicitationInputSchema this.requestedSchema,
  })  : mode = ElicitationMode.form,
        url = null,
        elicitationId = null;

  /// Creates URL mode elicitation parameters.
  const ElicitRequestParams.url({
    required this.message,
    required String this.url,
    required String this.elicitationId,
  })  : mode = ElicitationMode.url,
        requestedSchema = null;

  factory ElicitRequestParams.fromJson(Map<String, dynamic> json) {
    final modeStr = json['mode'] as String?;
    ElicitationMode? mode;
    if (modeStr != null) {
      mode = ElicitationMode.values.byName(modeStr);
    }
    return ElicitRequestParams(
      mode: mode,
      message: json['message'] as String,
      requestedSchema: json['requestedSchema'] != null
          ? JsonSchema.fromJson(json['requestedSchema'] as Map<String, dynamic>)
          : null,
      url: json['url'] as String?,
      elicitationId: json['elicitationId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (mode != null) 'mode': mode!.name,
        'message': message,
        if (requestedSchema != null)
          'requestedSchema': requestedSchema!.toJson(),
        if (url != null) 'url': url,
        if (elicitationId != null) 'elicitationId': elicitationId,
      };

  /// Whether this is a form mode elicitation.
  bool get isFormMode => mode == null || mode == ElicitationMode.form;

  /// Whether this is a URL mode elicitation.
  bool get isUrlMode => mode == ElicitationMode.url;
}

/// Request sent from server to client to elicit user input
class JsonRpcElicitRequest extends JsonRpcRequest {
  /// The elicit parameters
  final ElicitRequestParams elicitParams;

  JsonRpcElicitRequest({
    required super.id,
    required this.elicitParams,
    super.meta,
  }) : super(method: Method.elicitationCreate, params: elicitParams.toJson());

  factory JsonRpcElicitRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for elicit request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcElicitRequest(
      id: json['id'],
      elicitParams: ElicitRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `elicitation/create` response
class ElicitResult implements BaseResultData {
  /// The action taken by the user: 'accept', 'decline', or 'cancel'
  final String action;

  /// The submitted form data (only present when action is 'accept')
  final Map<String, dynamic>? content;

  /// The URL that the user should navigate to (only present when action is 'accept' in URL mode)
  final String? url;

  /// A unique identifier for the elicitation (only present when action is 'accept' in URL mode)
  final String? elicitationId;

  /// Optional metadata
  @override
  final Map<String, dynamic>? meta;

  const ElicitResult({
    required this.action,
    this.content,
    this.url,
    this.elicitationId,
    this.meta,
  });

  factory ElicitResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ElicitResult(
      action: json['action'] as String,
      content: json['content'] as Map<String, dynamic>?,
      url: json['url'] as String?,
      elicitationId: json['elicitationId'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'action': action,
        if (content != null) 'content': content,
        if (url != null) 'url': url,
        if (elicitationId != null) 'elicitationId': elicitationId,
      };

  /// Helper to check if the user accepted the input
  bool get accepted => action == 'accept';

  /// Helper to check if the user declined the input
  bool get declined => action == 'decline';

  /// Helper to check if the user cancelled the input
  bool get cancelled => action == 'cancel';
}

/// Parameters for the `notifications/elicitation/complete` notification.
///
/// Sent by servers when an out-of-band interaction started by URL mode
/// elicitation is completed.
class ElicitationCompleteParams {
  /// The unique identifier for the elicitation, matching the original request.
  final String elicitationId;

  const ElicitationCompleteParams({required this.elicitationId});

  factory ElicitationCompleteParams.fromJson(Map<String, dynamic> json) {
    return ElicitationCompleteParams(
      elicitationId: json['elicitationId'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'elicitationId': elicitationId};
}

/// Notification sent from server to client when URL mode elicitation completes.
///
/// This allows clients to react programmatically when an out-of-band
/// interaction (started via URL mode elicitation) is completed.
class JsonRpcElicitationCompleteNotification extends JsonRpcNotification {
  /// The notification parameters containing the elicitation ID.
  final ElicitationCompleteParams completeParams;

  JsonRpcElicitationCompleteNotification({
    required this.completeParams,
    super.meta,
  }) : super(
          method: Method.notificationsElicitationComplete,
          params: completeParams.toJson(),
        );

  factory JsonRpcElicitationCompleteNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException(
        "Missing params for elicitation complete notification",
      );
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcElicitationCompleteNotification(
      completeParams: ElicitationCompleteParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Data structure for URLElicitationRequiredError (-32042).
///
/// Contains a list of URL mode elicitations that must be completed
/// before the original request can be retried.
class URLElicitationRequiredErrorData {
  /// List of elicitations that are required to complete.
  /// All elicitations MUST be URL mode and have an elicitationId.
  final List<ElicitRequestParams> elicitations;

  const URLElicitationRequiredErrorData({required this.elicitations});

  factory URLElicitationRequiredErrorData.fromJson(Map<String, dynamic> json) {
    final elicitationsList = json['elicitations'] as List<dynamic>? ?? [];
    return URLElicitationRequiredErrorData(
      elicitations: elicitationsList
          .map((e) => ElicitRequestParams.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'elicitations': elicitations.map((e) => e.toJson()).toList(),
      };
}
