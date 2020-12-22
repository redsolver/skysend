import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:skynet_send/config.dart';
import 'package:skynet_send/const.dart';
import 'package:uuid/uuid.dart';
import 'package:http_parser/http_parser.dart';

// String usedPortal = 'siasky.net';
/* List<String> publicPortals = [
  'https://siasky.net', // FAST and CORS
  'https://skyportal.xyz', // FAST and CORS
  // 'https://sialoop.net',// NO CORS
  // 'https://skydrain.net', // SLOW
  // 'https://siacdn.com',// NO CORS
  'https://skynethub.io', // FAST and CORS
]; */

/* String getRandomPortal() {
  return publicPortals[Random().nextInt(publicPortals.length)];
} */

class EncryptionUploadTask {
  int i = 0;

  Map<String, String> chunkNonces = {};

  void setState(String s) {
    progress.add(s);
  }

  final progress = StreamController<String>.broadcast();

  Stream<List<int>> encryptStreamInBlocks(Stream<List<int>> source,
      CipherWithAppendedMac cipher, SecretKey secretKey) async* {
    i = 0;
    int internalI = 0;

    chunkNonces = {};

    // Wait until a new chunk is available, then process it.
    await for (var chunk in source) {
      // print('crypt $internalI');
      internalI++;
      while (i < internalI - 3) {
        await Future.delayed(Duration(milliseconds: 20));
      }

      final chunkNonce = Nonce.randomBytes(16);
      chunkNonces[internalI.toString()] = base64.encode(chunkNonce.bytes);

      yield await cipher.encrypt(
        chunk,
        secretKey: secretKey,
        nonce: chunkNonce,
      );
    }
    // print('done');
  }

  Future<List<String>> uploadChunkedStreamToSkynet(
      int fileSize, Stream<List<int>> byteUploadStream) async {
    final totalChunks = (fileSize / (chunkSize + 32)).abs().toInt() + 1;

    //  print('Total chunks: $totalChunks');

    final uploaderFileId = Uuid().v4();
    //  print('send $uploaderFileId');

    setState('Encrypting and uploading file... (Chunk 1 of $totalChunks)');

    List<String> skylinks = List.generate(totalChunks, (index) => null);

    _uploadChunk(final Uint8List chunk, final int currentI) async {
      // print('_uploadChunk $currentI');

      String skylink;

      // print('up $currentI');

      while (skylink == null) {
        try {
          skylink = await uploadFileToSkynet(chunk);

          if ((skylink ?? '').isEmpty) throw Exception('oops');
        } catch (e, st) {
          print(e);
          print(st);
          print('retry');
        }
      }

      skylinks[currentI] = skylink;
      i++;

      setState(
          'Encrypting and uploading file... ($i/$totalChunks Chunks done)');
/*     setState(
        'Encrypting and uploading file... $i/$totalChunks Chunks uploaded (16 MB each)'); */
    }

    int internalI = 0;

    // TODO Parallel chunk uploading to multiple portals
    await for (final chunk in byteUploadStream) {
      // print('chunk $internalI');

      _uploadChunk(chunk, internalI);

      while (i < internalI - 2) {
        await Future.delayed(Duration(milliseconds: 20));
      }
      internalI++;
    }

    // print('done');

    while (true) {
      await Future.delayed(Duration(milliseconds: 20));
      bool notASingleNull = true;

      for (final val in skylinks) {
        if (val == null) {
          notASingleNull = false;
          break;
        }
      }
      if (notASingleNull) break;
    }
    // print(skylinks);
    return skylinks;
  }

  Future<String> uploadFileToSkynet(List<int> chunk) async {
    var byteStream = new http.ByteStream.fromBytes(chunk);

    var uri = Uri.parse('https://${SkynetConfig.portal}/skynet/skyfile');

    //   print(uri);

    var request = new http.MultipartRequest("POST", uri);

    var multipartFile = new http.MultipartFile(
      'file',
      byteStream,
      chunk.length,
      filename: 'blob',
      contentType: MediaType('application', 'octet-stream'),
    );

    request.files.add(multipartFile);

    var response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final res = await response.stream.transform(utf8.decoder).join();

    final resData = json.decode(res);

    if (resData['skylink'] == null) throw Exception('Skynet Upload Fail');

    return resData['skylink'];
  }
}
