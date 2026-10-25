import type { RandomSource } from '../../src/core';

/**
 * Embaralha [items] no lugar, como o `List.shuffle(random)` do Dart: Fisher–
 * Yates do fim para o começo, com um `nextInt(length)` por troca.
 *
 * Reproduzir o algoritmo, e não só "embaralhar", é o que faz a mesma semente
 * sortear as mesmas carteiras que as ferramentas em Dart sorteavam.
 */
export function shuffle<T>(items: T[], random: RandomSource): T[] {
  let length = items.length;
  while (length > 1) {
    const pos = random.nextInt(length);
    length -= 1;
    const tmp = items[length]!;
    items[length] = items[pos]!;
    items[pos] = tmp;
  }
  return items;
}
