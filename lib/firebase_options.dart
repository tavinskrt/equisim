// Arquivo gerado automaticamente pelo CLI do FlutterFire.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Configurações padrão do [FirebaseOptions] para inicialização do ecossistema Firebase na plataforma corrente.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'O DefaultFirebaseOptions não foi configurado para a plataforma Linux nas configurações atuais.',
        );
      default:
        throw UnsupportedError(
          'O DefaultFirebaseOptions não oferece suporte para a plataforma corrente nas configurações atuais.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDRXDZJPu-ce2nQOoS2L06xF9yPicSDnmE',
    appId: '1:372895962989:web:8ce3d0d9db2f61004a2c64',
    messagingSenderId: '372895962989',
    projectId: 'equisim-d7128',
    authDomain: 'equisim-d7128.firebaseapp.com',
    storageBucket: 'equisim-d7128.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCQbooj0A34as680Cl6ls9KQWltCCDVIxo',
    appId: '1:372895962989:android:d3f1245fd50c954b4a2c64',
    messagingSenderId: '372895962989',
    projectId: 'equisim-d7128',
    storageBucket: 'equisim-d7128.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAsEVSKzDKwYLqkYS-eC9CXSB1p4xMcusM',
    appId: '1:372895962989:ios:901306d235c65c354a2c64',
    messagingSenderId: '372895962989',
    projectId: 'equisim-d7128',
    storageBucket: 'equisim-d7128.firebasestorage.app',
    iosBundleId: 'com.example.simulainvest',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAsEVSKzDKwYLqkYS-eC9CXSB1p4xMcusM',
    appId: '1:372895962989:ios:901306d235c65c354a2c64',
    messagingSenderId: '372895962989',
    projectId: 'equisim-d7128',
    storageBucket: 'equisim-d7128.firebasestorage.app',
    iosBundleId: 'com.example.simulainvest',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDRXDZJPu-ce2nQOoS2L06xF9yPicSDnmE',
    appId: '1:372895962989:web:aa69b7a98399c7b34a2c64',
    messagingSenderId: '372895962989',
    projectId: 'equisim-d7128',
    authDomain: 'equisim-d7128.firebaseapp.com',
    storageBucket: 'equisim-d7128.firebasestorage.app',
  );
}
