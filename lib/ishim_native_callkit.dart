import 'package:flutter/services.dart';

class IshimNativeCallkit {
  static const MethodChannel _channel =
      MethodChannel('com.levent.ishim/callkit');

  /// Native'den gelen event'leri dinle
  /// Events: onCallAccepted, onCallEnded, onCallRejected, onVoIPToken
  static void setCallHandler(
      Future<dynamic> Function(MethodCall) handler) {
    _channel.setMethodCallHandler(handler);
  }

  /// Flutter engine hazir oldugunu native'e bildir
  /// Bu cagridan sonra bekleyen event'ler gonderilir
  static Future<void> notifyFlutterReady() async {
    await _channel.invokeMethod('flutterReady');
  }

  /// Aramayi UUID ile sonlandir (Flutter → Native)
  static Future<void> endCall(String uuid) async {
    await _channel.invokeMethod('endCall', {'uuid': uuid});
  }

  /// Aramayi callId ile sonlandir (Flutter → Native)
  static Future<void> endCallById(String callId) async {
    await _channel.invokeMethod('endCall', {'callId': callId});
  }

  /// VoIP token al (Flutter → Native)
  static Future<String?> getVoIPToken() async {
    return await _channel.invokeMethod<String>('getVoIPToken');
  }
}
