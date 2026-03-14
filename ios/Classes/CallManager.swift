import CallKit
import Flutter
import AVFoundation

class CallManager: NSObject, CXProviderDelegate {

    static let shared = CallManager()

    var methodChannel: FlutterMethodChannel?
    weak var plugin: SwiftIshimCallkitPlugin?

    private let callController = CXCallController()
    private let provider: CXProvider
    private var activeCalls = [UUID: [String: Any]]()

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = true

        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    // MARK: - Incoming Call

    func reportIncomingCall(uuid: UUID, callerName: String, hasVideo: Bool,
                            extra: [String: Any]) {
        let update = CXCallUpdate()
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false
        update.supportsDTMF = false

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                print("[CallManager] Report incoming call error: \(error.localizedDescription)")
            } else {
                self?.activeCalls[uuid] = extra
                print("[CallManager] Incoming call reported: \(uuid)")
            }
        }
    }

    // MARK: - End Call

    func endCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)

        callController.request(transaction) { error in
            if let error = error {
                print("[CallManager] End call error: \(error.localizedDescription)")
            } else {
                print("[CallManager] End call requested: \(uuid)")
            }
        }
    }

    /// callId ile arama sonlandir (UUID lookup)
    func endCallById(_ callId: String) {
        for (uuid, extra) in activeCalls {
            if extra["callId"] as? String == callId {
                endCall(uuid: uuid)
                return
            }
        }
        print("[CallManager] Call not found for callId: \(callId)")
    }

    // MARK: - CXProviderDelegate

    // Kullanici CallKit'ten KABUL etti
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let uuid = action.callUUID
        let extra = activeCalls[uuid] ?? [:]

        print("[CallManager] Call accepted: \(uuid)")

        // Audio session'i aktif et
        configureAudioSession()

        let arguments: [String: Any] = [
            "uuid": uuid.uuidString,
            "callId": extra["callId"] as? String ?? "",
            "callerName": extra["callerName"] as? String ?? "",
            "callerPhoto": extra["callerPhoto"] as? String ?? "",
            "callType": extra["callType"] as? String ?? "",
            "livekitUrl": extra["livekitUrl"] as? String ?? "",
            "roomName": extra["roomName"] as? String ?? "",
        ]

        // Flutter'a bildir (plugin uzerinden — queue destegi)
        if let plugin = plugin {
            plugin.sendToFlutter("onCallAccepted", arguments: arguments)
        } else {
            methodChannel?.invokeMethod("onCallAccepted", arguments: arguments)
        }

        action.fulfill()
    }

    // Kullanici CallKit'ten REDDETTI veya arama sonlandi
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuid = action.callUUID
        let extra = activeCalls[uuid] ?? [:]
        let callId = extra["callId"] as? String ?? ""

        print("[CallManager] Call ended/rejected: \(uuid)")

        let arguments: [String: Any] = [
            "uuid": uuid.uuidString,
            "callId": callId,
        ]

        // Flutter'a bildir
        if let plugin = plugin {
            plugin.sendToFlutter("onCallEnded", arguments: arguments)
        } else {
            methodChannel?.invokeMethod("onCallEnded", arguments: arguments)
        }

        activeCalls.removeValue(forKey: uuid)
        action.fulfill()
    }

    // Mute toggle
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("[CallManager] Mute toggled: \(action.isMuted)")
        action.fulfill()
    }

    // Provider reset
    func providerDidReset(_ provider: CXProvider) {
        print("[CallManager] Provider did reset")
        activeCalls.removeAll()
    }

    // Audio session started
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("[CallManager] Audio session activated")
    }

    // Audio session stopped
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("[CallManager] Audio session deactivated")
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("[CallManager] Audio session error: \(error)")
        }
    }
}
