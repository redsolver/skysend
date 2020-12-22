import 'dart:async';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path/path.dart' as p;

import 'package:mime_type/mime_type.dart';
import 'package:skynet_send/ansi_pens.dart';
import 'package:skynet_send/config.dart';
import 'package:skynet_send/encrypt_block_stream.dart';

import 'const.dart';

void startEncryptAndUpload(
  File file,
) async {
  print('Using portal ${SkynetConfig.portal}');

  print('Encrypting and uploading file...');
  // print(file.type);

  // Choose the cipher
  final cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

  // Choose some 256-bit secret key
  final secretKey = SecretKey.randomBytes(32);

  // Choose some unique (non-secret) nonce (max 16 bytes).
  // The same (secretKey, nonce) combination should not be used twice!
  final nonce = Nonce.randomBytes(16);

  final totalChunks = (file.lengthSync() / (chunkSize + 32)).abs().toInt() + 1;

  final metadata = {
    'filename': p.basename(file.path),
    'type': mime(file.path),
    'chunksize': chunkSize,
    'totalchunks': totalChunks,
    'filesize': file.lengthSync(),
  };

  //print(metadata);

/*   final md = json.encode(metadata);

  final mdBytes = utf8.encode(md); */

  //int mdL = mdBytes.length;

  // Metadata start (mdL + 32)

  final task = EncryptionUploadTask();

  task.progress.stream.listen((event) {
    print(event);
  });

  final stream = task.encryptStreamInBlocks(
      getStreamOfIOFile(file.openRead()), cipher, secretKey);

  final chunkSkylinks =
      await task.uploadChunkedStreamToSkynet(file.lengthSync(), stream);

  print('Encrypting and uploading chunk index...');

  final links = await cipher.encrypt(
    utf8.encode(json.encode({
      'chunks': chunkSkylinks,
      'chunkNonces': task.chunkNonces,
      'metadata': metadata,
    })),
    secretKey: secretKey,
    nonce: nonce,
  );

  String skylink;

  while (skylink == null) {
    try {
      skylink = await task.uploadFileToSkynet(links);

      if ((skylink ?? '').isEmpty) throw Exception('oops');
    } catch (e, st) {
      print(e);
      print(st);
      print('retry');
    }
  }

  // Encrypt

  final secret =
      base64.encode([...(await secretKey.extract()), ...nonce.bytes]);

  final link = 'https://skysend.hns.${SkynetConfig.portal}/#b-$skylink+$secret';

  print('Secure Download Link for ${greenBold(metadata['filename'])}: $link');
}

Stream<List<int>> getStreamOfIOFile(Stream<List<int>> stream) async* {
  List<int> tmp = [];

  await for (final element in stream) {
    tmp.addAll(element);

    if (tmp.length >= chunkSize) {
      yield tmp.sublist(0, chunkSize);

      tmp.removeRange(0, chunkSize);
    }
  }
  yield tmp;
}
