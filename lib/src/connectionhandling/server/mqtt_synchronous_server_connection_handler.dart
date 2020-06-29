/*
 * Package : mqtt5_client
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 10/05/2020
 * Copyright :  S.Hamblett
 */

part of mqtt5_server_client;

/// Connection handler that performs server based connections and disconnections
/// to the hostname in a synchronous manner.
class MqttSynchronousServerConnectionHandler
    extends MqttServerConnectionHandler {
  /// Initializes a new instance of the SynchronousMqttConnectionHandler class.
  MqttSynchronousServerConnectionHandler(
    var clientEventBus, {
    @required int maxConnectionAttempts,
  }) : super(maxConnectionAttempts: maxConnectionAttempts) {
    this.clientEventBus = clientEventBus;
    clientEventBus.on<MqttAutoReconnect>().listen(autoReconnect);
    registerForMessage(MqttMessageType.connectAck, connectAckProcessor);
    clientEventBus.on<MqttMessageAvailable>().listen(messageAvailable);
  }

  /// Synchronously connect to the specific Mqtt Connection.
  @override
  Future<MqttConnectionStatus> internalConnect(
      String hostname, int port, MqttConnectMessage connectMessage) async {
    var connectionAttempts = 0;
    MqttLogger.log(
        'SynchronousMqttServerConnectionHandler::internalConnect entered');
    do {
      // Initiate the connection
      MqttLogger.log(
          'SynchronousMqttServerConnectionHandler::internalConnect - '
          'initiating connection try $connectionAttempts');
      connectionStatus.state = MqttConnectionState.connecting;
      if (useWebSocket) {
        if (useAlternateWebSocketImplementation) {
          MqttLogger.log(
              'SynchronousMqttServerConnectionHandler::internalConnect - '
              'alternate websocket implementation selected');
          connection = MqttServerWs2Connection(securityContext, clientEventBus);
        } else {
          MqttLogger.log(
              'SynchronousMqttServerConnectionHandler::internalConnect - '
              'websocket selected');
          connection = MqttServerWsConnection(clientEventBus);
        }
        if (websocketProtocols != null) {
          connection.protocols = websocketProtocols;
        }
      } else if (secure) {
        MqttLogger.log(
            'SynchronousMqttServerConnectionHandler::internalConnect - '
            'secure selected');
        connection = MqttServerSecureConnection(
            securityContext, clientEventBus, onBadCertificate);
      } else {
        MqttLogger.log(
            'SynchronousMqttServerConnectionHandler::internalConnect - '
            'insecure TCP selected');
        connection = MqttServerNormalConnection(clientEventBus);
      }
      connection.onDisconnected = onDisconnected;

      // Connect
      connectTimer = MqttCancellableAsyncSleep(5000);
      try {
        await connection.connect(hostname, port);
      } on Exception {
        // Ignore exceptions in an auto reconnect sequence
        if (autoReconnectInProgress) {
          MqttLogger.log(
              'SynchronousMqttServerConnectionHandler::internalConnect'
              ' exception thrown during auto reconnect - ignoring');
        } else {
          rethrow;
        }
      }
      MqttLogger.log(
          'SynchronousMqttServerConnectionHandler::internalConnect - '
          'connection complete');
      // Transmit the required connection message to the broker.
      MqttLogger.log('SynchronousMqttServerConnectionHandler::internalConnect '
          'sending connect message');
      sendMessage(connectMessage);
      MqttLogger.log(
          'SynchronousMqttServerConnectionHandler::internalConnect - '
          'pre sleep, state = $connectionStatus');
      // We're the sync connection handler so we need to wait for the
      // brokers acknowledgement of the connections
      await connectTimer.sleep();
      MqttLogger.log(
          'SynchronousMqttServerConnectionHandler::internalConnect - '
          'post sleep, state = $connectionStatus');
    } while (connectionStatus.state != MqttConnectionState.connected &&
        ++connectionAttempts < maxConnectionAttempts);
    // If we've failed to handshake with the broker, throw an exception.
    if (connectionStatus.state != MqttConnectionState.connected) {
      if (!autoReconnectInProgress) {
        MqttLogger.log(
            'SynchronousMqttServerConnectionHandler::internalConnect failed');
        if (connectionStatus.reasonCode == MqttConnectReasonCode.notSet) {
          throw MqttNoConnectionException('The maximum allowed connection attempts '
              '({$maxConnectionAttempts}) were exceeded. '
              'The broker is not responding to the connection request message '
              '(Missing Connection Acknowledgement?');
        } else {
          throw MqttNoConnectionException('The maximum allowed connection attempts '
              '({$maxConnectionAttempts}) were exceeded. '
              'The broker is not responding to the connection request message correctly'
              'The reason code is ${mqttConnectReasonCode.asString(connectionStatus.reasonCode)}');
        }
      }
    }
    MqttLogger.log('SynchronousMqttServerConnectionHandler::internalConnect '
        'exited with state $connectionStatus');
    return connectionStatus;
  }
}