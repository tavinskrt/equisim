---
numero: 157
titulo: Excluir a conta apaga todos os dados dela no Firestore, e exige a senha antes de apagar qualquer coisa
status: aceita
origem: voce
data: 2026-10-29
citacao: >
  Além dos valuations, os estudos também. Tudo relacionado à conta deve ser
  excluído.
afeta:
  - src/data/persistence/account-data.ts
  - src/app/auth.ts
  - src/features/auth/profile-page.tsx
  - src/ui/dialog.tsx
  - test/data/account-data.test.ts
  - test/app/delete-account.test.ts
substitui: []
---

## Contexto

A revisão de segurança de 29/10/2026 achou que "Excluir conta" apagava só o
login do Firebase Auth. Os estudos (`portfolios`), os valuations confirmados
(`valuations`, decisão 150), os estudos do escopo anterior (`backtests`) e a
preferência de tema (`users/{uid}`) ficavam no Firestore, sem dono que os
alcançasse. A LGPD (Lei 13.709/2018, art. 18, VI) dá ao titular o direito de
eliminar os dados tratados com o seu consentimento.

Apagar os dados exige o login, porque as regras do Firestore conferem
`request.auth.uid`. Mas o Firebase só apaga o usuário com login recente
(`requires-recent-login`). Apagar os dados primeiro e depois falhar no login
deixaria uma conta viva e vazia.

## Decisão

A exclusão pede a senha atual e segue esta ordem:

1. reautentica com a senha;
2. apaga, pelo campo `userId`, os documentos de `valuations`, `portfolios` e
   `backtests`, e depois o `users/{uid}`;
3. apaga o login.

Se a senha está errada, nada é apagado. Se a etapa 2 falha, o login fica, a
mensagem diz que a conta continua ativa, e repetir a exclusão apaga o resto.
Depois de excluir, o rascunho do estudo no navegador volta ao estudo vazio.

## Consequências aceitas

A exclusão não é atômica entre coleções: o Firestore não tem transação que
atravesse consultas, e o lote de escrita tem teto de 500 operações. A ordem
acima é o que impede o pior caso, que é dado apagado numa conta que continua de
pé.

A alternativa de apagar no servidor, com a extensão Delete User Data ou uma
função disparada pela exclusão do usuário, foi descartada por ora. As duas
precisam de Cloud Functions, e o projeto está no plano Spark, que não as
permite.

O modo local, sem conta, não muda: os dados dele ficam no navegador, e não há
conta a excluir.
