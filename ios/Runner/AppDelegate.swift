import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BibleblokICloudFolder") {
      ICloudFolder.register(messenger: registrar.messenger())
    }
  }
}

/// iCloud Drive 의 "성경과설교" 폴더 — 플러터 쪽: lib/services/fs/fs_native.dart (채널 bibleblok/icloud)
enum ICloudFolder {
  static let containerId = "iCloud.com.blokzip.bibleblok"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bibleblok/icloud", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "documentsPath" else { return result(FlutterMethodNotImplemented) }
      // iCloud 폴더 찾기는 시간이 걸릴 수 있어 화면 밖에서 한다
      DispatchQueue.global(qos: .userInitiated).async {
        let path = documentsPath()
        DispatchQueue.main.async { result(path) }
      }
    }
  }

  /// iCloud Drive 의 성경과설교 폴더 경로 (iCloud 에 로그인하지 않았으면 nil)
  /// 다른 기기에서 올라온 파일이 아직 이 기기에 없으면 내려받기를 시작하고 잠시(최대 10초) 기다린다
  static func documentsPath() -> String? {
    let fm = FileManager.default
    guard let container = fm.url(forUbiquityContainerIdentifier: containerId) else { return nil }
    let docs = container.appendingPathComponent("Documents", isDirectory: true)
    try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
    var pending = notDownloaded(in: docs)
    pending.forEach { try? fm.startDownloadingUbiquitousItem(at: $0) }
    let deadline = Date().addingTimeInterval(10)
    while !pending.isEmpty && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.5)
      pending = notDownloaded(in: docs)
    }
    return docs.path
  }

  /// 아직 이 기기에 내려받지 않은 파일들
  private static func notDownloaded(in dir: URL) -> [URL] {
    let key = URLResourceKey.ubiquitousItemDownloadingStatusKey
    guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [key]) else { return [] }
    var out: [URL] = []
    for case let url as URL in e {
      if let status = try? url.resourceValues(forKeys: [key]).ubiquitousItemDownloadingStatus, status == .notDownloaded {
        out.append(url)
      }
    }
    return out
  }
}
