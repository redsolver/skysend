import 'dart:convert';
import 'dart:html';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

import 'package:http/http.dart' as http;

import 'package:http_parser/http_parser.dart';

import 'package:uuid/uuid.dart';

const chunkSize = 1000 * 1000 * 16; // 16 MB

List<String> publicPortals = [
  'https://siasky.net', // FAST and CORS
  'https://skyportal.xyz', // FAST and CORS
  // 'https://sialoop.net',// NO CORS
  // 'https://skydrain.net', // SLOW
  // 'https://siacdn.com',// NO CORS
  'https://skynethub.io', // FAST and CORS
];

void main() {
  /*  try { */
  String hash = window.location.hash;

  if (hash.startsWith('#')) {
    hash = hash.substring(1);
  }

  if (hash.isNotEmpty) {
    if (hash.startsWith(RegExp(r'[0-9]'))) {
      setState('Redirecting to old version...');

      window.location.href =
          'https://siasky.net/CACxu3qIoxiXQdyDBmrcS7dkC4sGzz4NrXpReKnehKEwFQ/index.html#$hash';
      return;
    }

    // hash = hash.substring(1);
    setState('Downloading file index...');

    final lengthSep = hash.indexOf('-');

    final version = hash.substring(0, lengthSep);

    hash = hash.substring(lengthSep + 1);

    final sep = hash.indexOf('+');

    final skylink = hash.substring(0, sep);
    final key = hash.substring(sep + 1);
/* 
    print(skylink);
    print(key); */

    downloadAndDecrypt(
      skylink,
      key,
    );
  }
  //var input = window.document.querySelector('#upload');

  FileUploadInputElement fileselect =
      window.document.querySelector('#fileselect');

  fileselect.addEventListener("change", (e) {
    FileList files = fileselect.files;
    if (files.length < 1) throw Exception(); // TODO

    setState('Loading file...');

    File file = files.first;

    // file.slice()
    encryptAndUpload(
      file,
    );
  });
}

Stream<List<int>> getStreamOfFile(File file) async* {
  final reader = FileReader();

  int start = 0;
  while (start < file.size) {
    final end = start + chunkSize > file.size ? file.size : start + chunkSize;
    final blob = file.slice(start, end);
    reader.readAsArrayBuffer(blob);
    await reader.onLoad.first;
    yield reader.result;
    start += chunkSize;
  }
}

void setState(String s) {
  querySelector('#output').setInnerHtml(s, validator: TrustedNodeValidator());
}

class TrustedNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(element, attributeName, value) => true;
}

void downloadAndDecrypt(
  String skylink,
  String key,
) async {
  print(skylink);

  final portal = 'https://siasky.net';

  final res = await http.get('$portal/$skylink');

  final cryptParts = base64.decode(key);

  final cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

  final secretKey = SecretKey(cryptParts.sublist(0, 32));

  final nonce = Nonce(cryptParts.sublist(32, 32 + 16));

  setState('Decrypting file index...');

  final decryptedChunkIndex = await cipher.decrypt(
    res.bodyBytes,
    secretKey: secretKey,
    nonce: nonce,
  );

  final Map chunkIndex = json.decode(utf8.decode(decryptedChunkIndex));

  print(chunkIndex);

  final Map metadata = chunkIndex['metadata'];

  List<Uint8List> chunks = [];

  int i = 0;

  final int totalChunks = metadata['totalchunks'];
  setState('Downloading and decrypting chunk 1 of $totalChunks...');

  for (final chunkSkylink in chunkIndex['chunks']) {
    i++;

    final currentI = i;

    http
        .get(
      '$portal/$chunkSkylink',
    )
        .then((chunkRes) async {
      final decryptedChunk = await cipher.decrypt(
        chunkRes.bodyBytes,
        secretKey: secretKey,
        nonce: nonce,
      );

      while (chunks.length < currentI - 1) {
        await Future.delayed(Duration(milliseconds: 20));
      }

      chunks.add(decryptedChunk);

      if (currentI == totalChunks) {
        final blob = Blob(chunks, metadata['type']);

        downloadBlob(blob, metadata['filename']);
      } else {
        setState(
            'Downloading and decrypting chunk ${currentI + 1} of $totalChunks...');
      }
    });

    await Future.delayed(Duration(seconds: 1));
  }
}

void downloadBlob(Blob blob, String filename) {
  setState('<a id="downloadLink">Save File ${filename}</a>');

  window.document.querySelector("#downloadLink")
    ..setAttribute('href', Url.createObjectUrlFromBlob(blob))
    ..setAttribute('download', filename);
}

int i = 0;

Stream<List<int>> encryptStreamInBlocks(Stream<List<int>> source,
    CipherWithAppendedMac cipher, SecretKey secretKey, Nonce nonce) async* {
  i = 0;
  int internalI = 0;
  // Wait until a new chunk is available, then process it.
  await for (var chunk in source) {
    internalI++;
    while (i < internalI - 1) {
      await Future.delayed(Duration(milliseconds: 20));
    }
    yield await cipher.encrypt(
      chunk,
      secretKey: secretKey,
      nonce: nonce,
    );
  }
  print('done');
}

void encryptAndUpload(
  File file,
) async {
  setState('Encrypting and uploading file...');
  // print(file.type);

  // Choose the cipher
  final cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

  // Choose some 256-bit secret key
  final secretKey = SecretKey.randomBytes(32);

  // Choose some unique (non-secret) nonce (max 16 bytes).
  // The same (secretKey, nonce) combination should not be used twice!
  final nonce = Nonce.randomBytes(16);

  final totalChunks = (file.size / (chunkSize + 32)).abs().toInt() + 1;

  final metadata = {
    'filename': file.name,
    'type': file.type,
    'chunksize': chunkSize,
    'totalchunks': totalChunks,
  };

/*   final md = json.encode(metadata);

  final mdBytes = utf8.encode(md); */

  //int mdL = mdBytes.length;

  // Metadata start (mdL + 32)

  final stream =
      encryptStreamInBlocks(getStreamOfFile(file), cipher, secretKey, nonce);

  final chunkSkylinks = await uploadChunkedStreamToSkynet(
      file.size, stream /* .asBroadcastStream() */

      );

  print(chunkSkylinks);

  setState('Encrypting and uploading chunk index...');

  final links = await cipher.encrypt(
    utf8.encode(json.encode({
      'chunks': chunkSkylinks,
      'metadata': metadata,
    })),
    secretKey: secretKey,
    nonce: nonce,
  );

  final skylink = await uploadFileToSkynet(links);

  // Encrypt

  final secret =
      base64.encode([...(await secretKey.extract()), ...nonce.bytes]);

  final link =
      '${window.location.protocol}//${window.location.host}${window.location.pathname}#a-$skylink+$secret';

  setState('Secure Download Link for ${file.name}: <a href="$link">$link</a>');
}

String getRandomPortal() {
  return publicPortals[Random().nextInt(publicPortals.length)];
}

Future<List<String>> uploadChunkedStreamToSkynet(
    int fileSize, Stream<List<int>> byteUploadStream) async {
  final totalChunks = (fileSize / (chunkSize + 32)).abs().toInt() + 1;

  final uploaderFileId = Uuid().v4();
  print('send $uploaderFileId');

  setState(
      'Encrypting and uploading first chunk... $totalChunks Chunks total (16 MB each)');

  List<String> skylinks = [];

  // TODO Parallel chunk uploading to multiple portals
  await for (final chunk in byteUploadStream) {
    String skylink;

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

    skylinks.add(skylink);
    i++;

    setState(
        'Encrypting and uploading file... $i/$totalChunks Chunks uploaded (16 MB each)');
  }
  return skylinks;
}

Future<String> uploadFileToSkynet(List<int> chunk) async {
  var byteStream = new http.ByteStream.fromBytes(chunk);

  var uri = Uri.parse(getRandomPortal() + '/skynet/skyfile');

  print(uri);

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
