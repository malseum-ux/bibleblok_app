#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

#include <string>

// Register the login callback scheme (com.blokzip.bibleblok://login-callback) so Windows opens
// this app after sign-in. Same role as Info.plist (iOS/macOS) and AndroidManifest (Android);
// the URL is also listed in Supabase Redirect URLs. Rewritten on every launch with the current
// executable path so it stays correct if the app is moved.
// (Keep this file ASCII-only: the runner builds with /WX, and non-ASCII source can raise C4819.)
static void RegisterLoginCallbackScheme() {
  const wchar_t* key = L"Software\\Classes\\com.blokzip.bibleblok";
  wchar_t exe[MAX_PATH];
  if (!::GetModuleFileNameW(nullptr, exe, MAX_PATH)) return;
  const std::wstring command = L"\"" + std::wstring(exe) + L"\" \"%1\"";
  const std::wstring name = L"URL:\uC131\uACBD\uACFC\uC124\uAD50";
  ::RegSetKeyValueW(HKEY_CURRENT_USER, key, nullptr, REG_SZ, name.c_str(),
                    static_cast<DWORD>((name.size() + 1) * sizeof(wchar_t)));
  ::RegSetKeyValueW(HKEY_CURRENT_USER, key, L"URL Protocol", REG_SZ, L"", sizeof(wchar_t));
  const std::wstring commandKey = std::wstring(key) + L"\\shell\\open\\command";
  ::RegSetKeyValueW(HKEY_CURRENT_USER, commandKey.c_str(), nullptr, REG_SZ, command.c_str(),
                    static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // If the app is already running, hand the login link to it and exit this new process.
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }
  RegisterLoginCallbackScheme();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"bibleblok_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
