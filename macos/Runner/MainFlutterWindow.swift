import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerFolderBookmarks(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// 플러터와 북마크 기능을 잇는 통로 — create(path) · resolve(bookmark)
private func registerFolderBookmarks(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: "bibleblok/bookmarks", binaryMessenger: messenger)
  channel.setMethodCallHandler { call, result in
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "create":
      guard let path = args["path"] as? String else { return result(nil) }
      result(try? FolderBookmarks.create(path: path))
    case "resolve":
      guard let bookmark = args["bookmark"] as? String else { return result(nil) }
      result(FolderBookmarks.resolve(base64: bookmark))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// 저장 폴더 허락 보관 — 보안 범위 북마크 (Mac 앱 샌드박스)
///
/// Mac 앱은 사용자가 고른 폴더에 그 실행 동안만 들어갈 수 있다.
/// 폴더를 고를 때 북마크를 만들어 두고, 다음에 켤 때 북마크로 다시 열어야 같은 폴더를 계속 쓸 수 있다.
/// 플러터 쪽: lib/services/fs/mac_bookmark.dart (채널 이름 bibleblok/bookmarks)
enum FolderBookmarks {
  /// 앱이 켜져 있는 동안 열어 둔 폴더 (닫지 않고 계속 쓴다)
  private static var opened: [URL] = []

  /// 폴더 경로 → 북마크 (base64 글자)
  static func create(path: String) throws -> String {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    return data.base64EncodedString()
  }

  /// 북마크 → 폴더를 다시 열고 경로를 돌려준다. 북마크가 오래됐으면 새 북마크(renewed)도 함께
  static func resolve(base64: String) -> [String: Any]? {
    guard let data = Data(base64Encoded: base64) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
          url.startAccessingSecurityScopedResource()
    else { return nil }
    opened.append(url)
    var out: [String: Any] = ["path": url.path]
    if stale, let renewed = try? create(path: url.path) { out["renewed"] = renewed }
    return out
  }
}
