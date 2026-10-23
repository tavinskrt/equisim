import type { FirebaseOptions } from 'firebase/app';

/**
 * Configuração do Firebase para a web.
 *
 * **Não é segredo.** São identificadores públicos do projeto, que todo
 * cliente web do Firebase entrega ao navegador; quem protege os dados são as
 * regras do Firestore (`firestore.rules`), que só deixam cada usuário ler e
 * gravar o que é dele. Ver https://firebase.google.com/docs/projects/api-keys.
 *
 * Os mesmos valores do `lib/firebase_options.dart` do aplicativo Flutter, para
 * que os estudos e valuations já gravados continuem do usuário.
 */
export const firebaseWebOptions: FirebaseOptions = {
  apiKey: 'AIzaSyDRXDZJPu-ce2nQOoS2L06xF9yPicSDnmE',
  appId: '1:372895962989:web:8ce3d0d9db2f61004a2c64',
  messagingSenderId: '372895962989',
  projectId: 'equisim-d7128',
  authDomain: 'equisim-d7128.firebaseapp.com',
  storageBucket: 'equisim-d7128.firebasestorage.app',
};
