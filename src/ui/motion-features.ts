import { domAnimation } from 'motion/react';

/**
 * Os recursos do `LazyMotion` num pedaço próprio do build: a primeira pintura
 * não espera por eles, e o que é `m.*` só começa a animar quando chegam.
 */
export default domAnimation;
