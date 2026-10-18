#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Cria um console para o processo e redireciona para ele o stdout e o stderr,
// tanto do runner quanto da biblioteca do Flutter.
void CreateAndAttachConsole();

// Recebe um wchar_t* terminado em nulo, codificado em UTF-16, e devolve uma
// std::string em UTF-8. Devolve std::string vazia em caso de falha.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Obtem os argumentos de linha de comando como std::vector<std::string>, em
// UTF-8. Devolve std::vector<std::string> vazio em caso de falha.
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
