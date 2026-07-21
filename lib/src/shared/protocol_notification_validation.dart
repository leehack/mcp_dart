import 'package:mcp_dart/src/types/json_rpc.dart';

typedef ProtocolNotificationValidator = void Function(
  Object protocol,
  JsonRpcNotification notification,
);

final Expando<ProtocolNotificationValidator> _notificationValidators =
    Expando<ProtocolNotificationValidator>(
  'mcp_dart.protocol.notificationValidator',
);

/// Installs package-internal outgoing-notification validation for [protocol].
void writeProtocolNotificationValidator(
  Object protocol,
  ProtocolNotificationValidator validator,
) {
  _notificationValidators[protocol] = validator;
}

/// Runs package-internal outgoing-notification validation for [protocol].
void validateProtocolNotification(
  Object protocol,
  JsonRpcNotification notification,
) {
  _notificationValidators[protocol]?.call(protocol, notification);
}
