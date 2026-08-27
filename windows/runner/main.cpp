#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  if (!window.Create(L"Krishna Imperial MIS", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Keep the window on the screen it opens on.
  //
  // Win32Window scales the requested logical size by the monitor DPI, so on a smaller
  // display (measured: 1536x864) the default 1280x720 becomes 1550x830 and the window
  // opens with its right edge past the screen. Part of the workstation UI is off-screen
  // before the user has touched anything. Clamp to the work area and centre.
  if (HWND hwnd = window.GetHandle()) {
    RECT work{};
    if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0)) {
      RECT frame{};
      ::GetWindowRect(hwnd, &frame);
      const LONG work_width = work.right - work.left;
      const LONG work_height = work.bottom - work.top;
      LONG width = frame.right - frame.left;
      LONG height = frame.bottom - frame.top;
      if (width > work_width) {
        width = work_width;
      }
      if (height > work_height) {
        height = work_height;
      }
      const LONG x = work.left + (work_width - width) / 2;
      const LONG y = work.top + (work_height - height) / 2;
      ::SetWindowPos(hwnd, nullptr, static_cast<int>(x), static_cast<int>(y),
                     static_cast<int>(width), static_cast<int>(height),
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
