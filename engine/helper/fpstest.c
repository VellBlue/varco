// Test for Varco's FPS limiter: D3D11 window, Present without vsync for 5 s, prints the resulting fps.
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l) { return DefWindowProcA(h, m, w, l); }
int main(void) {
  WNDCLASSA wc = {0}; wc.lpfnWndProc = wp; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "fpstest"; RegisterClassA(&wc);
  HWND hw = CreateWindowA("fpstest", "Varco FPS test", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 640, 360, NULL, NULL, wc.hInstance, NULL);
  DXGI_SWAP_CHAIN_DESC sd = {0}; sd.BufferCount = 2; sd.BufferDesc.Width = 640; sd.BufferDesc.Height = 360; sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.OutputWindow = hw; sd.SampleDesc.Count = 1; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  IDXGISwapChain *sc; ID3D11Device *dev; ID3D11DeviceContext *ctx;
  printf("FPSTEST: start\n"); fflush(stdout);
  HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &sd, &sc, &dev, NULL, &ctx);
  if (FAILED(hr)) { printf("FPSTEST: D3D11 errore %08lx\n", hr); return 1; }
  ID3D11Texture2D *bb; IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void**)&bb);
  ID3D11RenderTargetView *rtv; ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource*)bb, NULL, &rtv);
  LARGE_INTEGER f, t0, t; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&t0); int frames = 0; MSG msg;
  do { while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&msg);
       float c[4] = { (frames % 120) / 120.f, 0.1f, 0.2f, 1 }; ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, c);
       IDXGISwapChain_Present(sc, 0, 0); frames++; QueryPerformanceCounter(&t); if (frames % 100 == 0) { printf("FPSTEST: %d frames, %.2f s\n", frames, (t.QuadPart - t0.QuadPart) / (double)f.QuadPart); fflush(stdout); }
  } while ((t.QuadPart - t0.QuadPart) < 5 * f.QuadPart);
  printf("FPSTEST: %.1f fps in 5 s\n", frames / ((t.QuadPart - t0.QuadPart) / (double)f.QuadPart)); fflush(stdout);
  return 0;
}
