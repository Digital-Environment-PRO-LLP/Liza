#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

// SetCurrentProcessExplicitAppUserModelID живёт в shell32.lib, который
// шаблонный Flutter-runner явно не линкует.
#pragma comment(lib, "shell32.lib")

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

// AUMID приложения. ДОЛЖЕН совпадать с `AppConfig.appId`, который клиент
// передаёт в flutter_local_notifications_windows (см. background_push.dart).
// Без явной регистрации AUMID у процесса WinRT ToastNotificationManager не
// находит приложение и всплывающие уведомления молча не показываются
// (LABA-1891: «на винде уведомлений нет вовсе»). Одной этой строки мало —
// нужен ещё ярлык в меню Пуск с тем же System.AppUserModel.ID (installer.iss).
constexpr wchar_t kAppUserModelId[] = L"com.prodamus.laba.liza";

// Single-instance + deep-link forwarding.
// При запуске второй копии (например, после клика по liza:// в браузере)
// находим работающее окно Liza, передаём ему URL через WM_COPYDATA
// (см. app_links Windows plugin), выводим его на передний план и
// завершаемся. Так deep-link попадает в уже запущенное приложение, а не
// открывает второе окно.
bool SendAppLinkToInstance(const std::wstring& title) {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());
  if (!hwnd) {
    return false;
  }
  SendAppLink(hwnd);

  WINDOWPLACEMENT place = { sizeof(WINDOWPLACEMENT) };
  GetWindowPlacement(hwnd, &place);
  switch (place.showCmd) {
    case SW_SHOWMAXIMIZED:
      ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ShowWindow(hwnd, SW_NORMAL);
      break;
  }
  SetWindowPos(0, HWND_TOP, 0, 0, 0, 0,
               SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
  SetForegroundWindow(hwnd);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (SendAppLinkToInstance(L"Liza")) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Регистрируем AUMID процесса до создания окна и первого показа toast —
  // иначе WinRT не сопоставит уведомления с приложением (LABA-1891).
  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.CreateAndShow(L"Liza", origin, size)) {
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
