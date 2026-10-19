#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// Abstracao de uma janela Win32 ciente de DPI alto. Feita para ser herdada
// por classes que queiram especializar a renderizacao e o tratamento de
// entrada
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Cria uma janela win32 com |title|, posicionada e dimensionada por |origin| e
  // |size|. Janelas novas sao criadas no monitor padrao. O tamanho da janela e
  // informado ao sistema em pixels fisicos; para manter o tamanho consistente,
  // esta funcao escala a largura e a altura recebidas conforme o monitor padrao.
  // A janela fica invisivel ate |Show| ser chamado. Devolve true se a janela foi
  // criada.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Mostra a janela atual. Devolve true se a janela foi mostrada.
  bool Show();

  // Libera os recursos do sistema associados a janela.
  void Destroy();

  // Insere |content| na arvore de janelas.
  void SetChildContent(HWND content);

  // Devolve o handle da janela, para que o cliente defina icone e outras
  // propriedades. Devolve nullptr se a janela ja foi destruida.
  HWND GetHandle();

  // Se true, fechar esta janela encerra o aplicativo.
  void SetQuitOnClose(bool quit_on_close);

  // Devolve um RECT com os limites da area cliente atual.
  RECT GetClientArea();

 protected:
  // Processa e encaminha as mensagens de janela relevantes de mouse, mudanca de
  // tamanho e DPI. Delega o tratamento a sobrecargas de membro que as classes
  // herdeiras podem tratar.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Chamado quando CreateAndShow e chamado, para a subclasse configurar a janela.
  // A subclasse deve devolver false se a configuracao falhar.
  virtual bool OnCreate();

  // Chamado quando Destroy e chamado.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // Callback do sistema chamado pelo laco de mensagens. Trata a mensagem
  // WM_NCCREATE, enviada quando a area nao cliente esta sendo criada, e liga a
  // escala automatica de DPI dessa area, para que ela responda sozinha a
  // mudancas de DPI. Todas as outras mensagens ficam com o MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Obtem o ponteiro da instancia da classe para |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Atualiza o tema da moldura da janela para acompanhar o tema do sistema.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // handle da janela de nivel superior.
  HWND window_handle_ = nullptr;

  // handle da janela do conteudo hospedado.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
