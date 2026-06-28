import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Method channel shared with the Dart `PushService`. Created once the
  /// implicit Flutter engine is initialized.
  private var pushChannel: FlutterMethodChannel?

  /// The most recently obtained APNs device token, hex-encoded. Cached so a
  /// token that arrives before the channel exists can be re-delivered once it
  /// does.
  private var apnsToken: String?

  /// Routing payload from a notification tap that arrived before Dart was ready
  /// to handle it (i.e. a cold start launched by the tap). Held until Dart pulls
  /// it via `getInitialNotification`.
  private var pendingTapPayload: [String: Any]?

  /// True once Dart has called `getInitialNotification`, meaning its tap handler
  /// is wired and subsequent (warm) taps can be delivered live.
  private var dartTapReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Present and route notifications natively (no flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The application registrar vends the implicit engine's binary messenger,
    // which is the correct messenger for app-level channels (the root view
    // controller may not exist yet under the UIScene lifecycle).
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "nullfeed/push",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
    pushChannel = channel

    // If a token arrived before the channel existed, deliver it now.
    if let token = apnsToken {
      channel.invokeMethod("onApnsToken", arguments: token)
    }
  }

  // MARK: - Dart -> Native

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermissionAndToken":
      requestPermissionAndRegister { granted in result(granted) }
    case "registerIfAuthorized":
      registerIfAuthorized { registered in result(registered) }
    case "getInitialNotification":
      // Dart pulls the cold-start tap (if any) and signals it's ready for live
      // taps from here on.
      dartTapReady = true
      let payload = pendingTapPayload
      pendingTapPayload = nil
      result(payload)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Requests notification authorization and, if granted, registers with APNs.
  /// Shows the system prompt the first time it's called. `completion` reports
  /// whether authorization was granted.
  private func requestPermissionAndRegister(completion: @escaping (Bool) -> Void) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, error in
      if let error = error {
        NSLog("Notification authorization error: \(error.localizedDescription)")
      }
      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
      completion(granted)
    }
  }

  /// Registers with APNs only if notifications are already authorized, never
  /// prompting. Used on silent session restore so a relaunch refreshes the
  /// token without popping the permission dialog at cold launch. `completion`
  /// reports whether the device was already authorized.
  private func registerIfAuthorized(completion: @escaping (Bool) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let authorized =
        settings.authorizationStatus == .authorized
        || settings.authorizationStatus == .provisional
      if authorized {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
      completion(authorized)
    }
  }

  // MARK: - APNs registration callbacks

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Let Flutter forward the raw token to any registered plugins first.
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsToken = token
    pushChannel?.invokeMethod("onApnsToken", arguments: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    NSLog("Failed to register for remote notifications: \(error.localizedDescription)")
  }

  // MARK: - UNUserNotificationCenterDelegate

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Present notifications while the app is in the foreground.
    // `.banner`/`.list` are iOS 14+; the deployment target is iOS 13, so fall
    // back to the (deprecated-but-functional) `.alert` on older systems.
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  /// Handles a notification tap. Routes live when Dart's handler is ready
  /// (warm/background launch); otherwise caches the payload for Dart to pull on
  /// startup (cold launch).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let payload = routingPayload(from: response.notification.request.content.userInfo)
    if dartTapReady, let channel = pushChannel {
      channel.invokeMethod("onNotificationTap", arguments: payload)
    } else {
      pendingTapPayload = payload
    }
    completionHandler()
  }

  /// Extracts the tap-routing fields the Dart side understands from an APNs
  /// `userInfo` dict. Custom keys are delivered as siblings of `aps`.
  private func routingPayload(from userInfo: [AnyHashable: Any]) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let type = userInfo["type"] as? String { payload["type"] = type }
    if let videoID = userInfo["video_id"] as? String { payload["video_id"] = videoID }
    return payload
  }
}
