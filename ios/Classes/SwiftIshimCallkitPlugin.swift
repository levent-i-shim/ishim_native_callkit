import Flutter
import PushKit
import CallKit
import CommonCrypto

public class SwiftIshimCallkitPlugin: NSObject, FlutterPlugin, PKPushRegistryDelegate {

    private var methodChannel: FlutterMethodChannel?
    private var pushRegistry: PKPushRegistry?
    private var currentVoIPToken: String?
    private var isFlutterReady = false
    private var pendingCallEvents: [[String: Any]] = []

    // MARK: - FlutterPlugin Protocol

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.levent.ishim/callkit",
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftIshimCallkitPlugin()
        instance.methodChannel = channel
        CallManager.shared.methodChannel = channel
        CallManager.shared.plugin = instance
        registrar.addMethodCallDelegate(instance, channel: channel)

        // PushKit baslatma
        instance.setupPushKit()

        print("[IshimCallkit] Plugin registered successfully")
    }

    // MARK: - Flutter → Native Method Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "endCall":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            // UUID veya callId ile calisabilir
            if let uuidString = args["uuid"] as? String, let uuid = UUID(uuidString: uuidString) {
                CallManager.shared.endCall(uuid: uuid)
            } else if let callId = args["callId"] as? String, !callId.isEmpty {
                CallManager.shared.endCallById(callId)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "UUID or callId required", details: nil))
                return
            }
            result(nil)

        case "getVoIPToken":
            result(currentVoIPToken)

        case "flutterReady":
            isFlutterReady = true
            // Bekleyen event'leri gonder
            flushPendingEvents()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - PushKit Setup

    private func setupPushKit() {
        pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry?.delegate = self
        pushRegistry?.desiredPushTypes = [.voIP]
        print("[IshimCallkit] PushKit setup complete")
    }

    // MARK: - PKPushRegistryDelegate

    // VoIP token guncellendi
    public func pushRegistry(_ registry: PKPushRegistry,
                             didUpdate pushCredentials: PKPushCredentials,
                             for type: PKPushType) {
        guard type == .voIP else { return }

        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        currentVoIPToken = token
        print("[IshimCallkit] VoIP token: \(token)")

        // Token'i Flutter'a gonder
        sendToFlutter("onVoIPToken", arguments: ["token": token])
    }

    // VoIP push geldi — KRITIK: CallKit HEMEN gosterilmeli (iOS requirement)
    public func pushRegistry(_ registry: PKPushRegistry,
                             didReceiveIncomingPushWith payload: PKPushPayload,
                             for type: PKPushType,
                             completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }

        let data = payload.dictionaryPayload
        print("[IshimCallkit] VoIP push received: \(data)")

        let callId = data["callId"] as? String ?? ""
        let callerName = data["callerName"] as? String ?? "Bilinmeyen"
        let callerPhoto = data["callerPhoto"] as? String ?? data["callerPhotoUrl"] as? String ?? ""
        let callType = data["callType"] as? String ?? "voice"
        let livekitUrl = data["livekitUrl"] as? String ?? ""
        let roomName = data["roomName"] as? String ?? ""

        guard !callId.isEmpty else {
            print("[IshimCallkit] Empty callId, ignoring push")
            completion()
            return
        }

        // UUID olustur — callId'den deterministik UUID
        let uuid = uuidFromCallId(callId)
        let hasVideo = callType == "video"

        let extra: [String: Any] = [
            "callId": callId,
            "callerName": callerName,
            "callerPhoto": callerPhoto,
            "callType": callType,
            "livekitUrl": livekitUrl,
            "roomName": roomName,
        ]

        // CallKit HEMEN goster — Flutter engine beklenmez
        CallManager.shared.reportIncomingCall(
            uuid: uuid,
            callerName: callerName,
            hasVideo: hasVideo,
            extra: extra
        )

        completion()
    }

    // iOS 10 compatibility (completion handler olmadan)
    public func pushRegistry(_ registry: PKPushRegistry,
                             didReceiveIncomingPushWith payload: PKPushPayload,
                             for type: PKPushType) {
        pushRegistry(registry, didReceiveIncomingPushWith: payload, for: type) {}
    }

    // PushKit invalidation
    public func pushRegistry(_ registry: PKPushRegistry,
                             didInvalidatePushTokenFor type: PKPushType) {
        print("[IshimCallkit] VoIP token invalidated")
        currentVoIPToken = nil
    }

    // MARK: - Helpers

    /// callId'den deterministik UUID olustur
    private func uuidFromCallId(_ callId: String) -> UUID {
        // callId'nin MD5 hash'inden UUID olustur
        let data = callId.data(using: .utf8)!
        var digest = [UInt8](repeating: 0, count: 16)
        _ = data.withUnsafeBytes { bytes in
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        // Version 3 UUID format
        digest[6] = (digest[6] & 0x0F) | 0x30
        digest[8] = (digest[8] & 0x3F) | 0x80
        return NSUUID(uuidBytes: digest) as UUID
    }

    /// Flutter'a event gonder (engine hazir degilse kuyrukla)
    func sendToFlutter(_ method: String, arguments: [String: Any]) {
        if isFlutterReady {
            DispatchQueue.main.async { [weak self] in
                self?.methodChannel?.invokeMethod(method, arguments: arguments)
            }
        } else {
            var event = arguments
            event["_method"] = method
            pendingCallEvents.append(event)
            print("[IshimCallkit] Event queued (Flutter not ready): \(method)")
        }
    }

    /// Bekleyen event'leri Flutter'a gonder
    private func flushPendingEvents() {
        guard isFlutterReady else { return }
        let events = pendingCallEvents
        pendingCallEvents.removeAll()

        for var event in events {
            if let method = event.removeValue(forKey: "_method") as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.methodChannel?.invokeMethod(method, arguments: event)
                }
            }
        }
        print("[IshimCallkit] Flushed \(events.count) pending events")
    }
}
