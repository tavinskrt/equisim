cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define o alvo do aplicativo. Para mudar o nome, altere BINARY_NAME no
# CMakeLists.txt do topo, e nao o valor daqui, ou o `flutter run` deixa de
# funcionar.
#
# Todo arquivo-fonte novo do aplicativo deve ser acrescentado aqui.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Aplica o conjunto padrao de configuracoes de build. Pode ser removido em
# aplicativos que precisem de configuracoes diferentes.
apply_standard_settings(${BINARY_NAME})

# Acrescenta as definicoes de pre-processador da versao do build.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Desliga as macros do Windows que colidem com funcoes da biblioteca padrao do C++.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Acrescenta as bibliotecas de dependencia e os diretorios de include.
# Dependencias proprias do aplicativo entram aqui.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Executa as etapas do build que cabem a ferramenta do Flutter. Isto nao pode ser removido.
add_dependencies(${BINARY_NAME} flutter_assemble)
