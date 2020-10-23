import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:filesize/filesize.dart';
import 'package:skynet_send/config.dart';

class DownloadTask {
  CipherWithAppendedMac cipher;
  SecretKey secretKey;
  Map chunkIndex;
  Map metadata;

  final progress = StreamController<String>.broadcast();

  Future<void> downloadAndDecryptMetadata(
    String skylink,
    String key,
  ) async {
    final res = await http.get('${SkynetConfig.dlPortal}/$skylink');

    final cryptParts = base64.decode(key);

    cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

    secretKey = SecretKey(cryptParts.sublist(0, 32));

    final nonce = Nonce(cryptParts.sublist(32, 32 + 16));

    final decryptedChunkIndex = await cipher.decrypt(
      res.bodyBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    chunkIndex = json.decode(utf8.decode(decryptedChunkIndex));

   // print(chunkIndex);

    metadata = chunkIndex['metadata'];

    return;
  }

  void setDLState(String s) {
    progress.add(s);
  }

  // List<Uint8List> chunks = [];

  int chunksLength = 0;

  final chunkCtrl = StreamController<Uint8List>();

  void downloadAndDecryptFile() async {
   // print('onDownloadStart');

    int i = 0;

    final int totalChunks = metadata['totalchunks'];

    //   querySelector('.upload-section-active').style.display = '';

    setDLState('Downloading and decrypting chunk 1 of $totalChunks...');

    int iDone = 0;

    for (final chunkSkylink in chunkIndex['chunks']) {
      final currentI = i;

     // print('dl $currentI');

      final chunkNonce = Nonce(
          base64.decode(chunkIndex['chunkNonces'][(currentI + 1).toString()]));

      http
          .get(
        '${SkynetConfig.dlPortal}/$chunkSkylink',
      )
          .then((chunkRes) async {
      //  print('dcrypt $currentI');

        final decryptedChunk = await cipher.decrypt(
          chunkRes.bodyBytes,
          secretKey: secretKey,
          nonce: chunkNonce,
        );

        while (chunksLength < currentI) {
          await Future.delayed(Duration(milliseconds: 20));
        }
      //  print('done $currentI');

        chunkCtrl.add(decryptedChunk);
        chunksLength++;

        if (currentI == totalChunks - 1) {
          chunkCtrl.add(null);
          return;
        } else {
          setDLState(
              'Downloading and decrypting chunk ${currentI + 2} of $totalChunks...');
        }
        iDone++;
      });

      await Future.delayed(Duration(milliseconds: 100));

      while (i > iDone + 4) {
        await Future.delayed(Duration(milliseconds: 20));
      }

      i++;
    }

    return;
  }
}
