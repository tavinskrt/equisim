cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define o alvo do aplicativo. Para mudar o nome, altere BINARY_NAME no
# CMakeLists.txt do topo, e nao o valor daqui, ou o `flutter run` deixa de
# funcionar.
#
# Todo arquivo-fonte novo do aplicativo deve ser acrescentado aqui.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Aplica o conjunto padrao de configuracoes de build. Pode ser removido em
# aplicativos que precisem de configuracoes diferentes.
apply_standard_settings(${BINARY_NAME})

# Acrescenta as definicoes de pre-processador do ID do aplicativo.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Acrescenta as bibliotecas de dependencia. Dependencias proprias do aplicativo entram aqui.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
