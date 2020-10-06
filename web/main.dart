import 'dart:convert';
import 'dart:html';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

void main() {
  /*  try { */
  String hash = window.location.hash;

  if (hash.startsWith('#')) {
    hash = hash.substring(1);
  }

  if (hash.isNotEmpty) {
    setState('Downloading file...');

    final lengthSep = hash.indexOf('-');

    final mdLength = int.parse(hash.substring(0, lengthSep));

    hash = hash.substring(lengthSep + 1);

    final sep = hash.indexOf('+');

    final skylink = hash.substring(0, sep);
    final key = hash.substring(sep + 1);
/* 
    print(skylink);
    print(key); */

    downloadAndDecrypt(skylink, key, mdLength);
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

    final reader = FileReader();

    reader.onLoad.listen((progressEvent) {
      // print("file read");

      //print(reader.result.runtimeType);

      encryptAndUpload(file, reader.result);
    });
    reader.onError.listen((event) {
      print("error ${reader.error.name}");
    });

    /* reader.onProgress.listen((event) { 
    }); */
    reader.readAsArrayBuffer(file);
  });
/*   } catch (e, st) {
    print(e);
    print(st);
  } */
}

void setState(String s) {
  querySelector('#output').setInnerHtml(s, validator: TrustedNodeValidator());
}

class TrustedNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(element, attributeName, value) => true;
}

final String skynetPortal = 'https://siasky.net';
String get skynetPortalUploadUrl => '$skynetPortal/skynet/skyfile';

void downloadAndDecrypt(String skylink, String key, int mdLength) async {
  final res = await http.get('$skynetPortal/$skylink');

  final cryptParts = base64.decode(key);

  // Choose the cipher
  final cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

  // Choose some 256-bit secret key
  final secretKey = SecretKey(cryptParts.sublist(0, 32));

  // Choose some unique (non-secret) nonce (max 16 bytes).
  // The same (secretKey, nonce) combination should not be used twice!
  final nonce = Nonce(cryptParts.sublist(32, 32 + 16));

  // print(key);

/*     final metadata = {
    'filename': file.name,
    'type': file.type,
  };

  final md = json.encode(metadata);

  final mdBytes = utf8.encode(md); */

  setState('Decrypting file...');

  final decrypted = await cipher.decrypt(
    res.bodyBytes,
    secretKey: secretKey,
    nonce: nonce,
  );

  final contentBytes = decrypted.sublist(mdLength);

  //print(contentBytes.sublist(0, 10));

  final metadataBytes = decrypted.sublist(0, mdLength);

  final mdText = utf8.decode(metadataBytes);

  // print('%$mdText%');

  final Map metadata = json.decode(mdText);

  final blob = Blob([contentBytes], metadata['type']);

  downloadBlob(blob, metadata['filename']);
}

void downloadBlob(Blob blob, String filename) {
  // Create an object URL for the blob object

  setState('<a id="downloadLink">Save File ${filename}</a>');

  window.document.querySelector("#downloadLink")
    ..setAttribute('href', Url.createObjectUrlFromBlob(blob))
    ..setAttribute('download', filename);
}

void encryptAndUpload(File file, Uint8List result) async {
  // print(file.type);

  setState('Encrypting file...');

  //final unencryptedContentBytes = result.codeUnits;

  final metadata = {
    'filename': file.name,
    'type': file.type,
  };

  final md = json.encode(metadata);

  final mdBytes = utf8.encode(md);

  int mdL = mdBytes.length;

  final unencryptedBytes = [...mdBytes, ...result];

  // Choose the cipher
  final cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

  // Choose some 256-bit secret key
  final secretKey = SecretKey.randomBytes(32);

  // Choose some unique (non-secret) nonce (max 16 bytes).
  // The same (secretKey, nonce) combination should not be used twice!
  final nonce = Nonce.randomBytes(16);

  

  // Encrypt
  final encrypted = await cipher.encrypt(
    unencryptedBytes,
    secretKey: secretKey,
    nonce: nonce,
  );

  final skylink = await uploadFileToSkynet(
      file.size, encrypted, MediaType('application', 'octet-stream'));

  print(skylink);

  final secret =
      base64.encode([...(await secretKey.extract()), ...nonce.bytes]);

  final link =
      '${window.location.protocol}//${window.location.host}${window.location.pathname}#$mdL-$skylink+$secret';

  setState('Secure Download Link for ${file.name}: <a href="$link">$link</a>');
}

Future<String> uploadFileToSkynet(
    int fileSize, Uint8List bytes, MediaType contentType) async {
  var stream = new http.ByteStream.fromBytes(bytes);

  var uri = Uri.parse(skynetPortalUploadUrl);

  var request = new http.MultipartRequest("POST", uri);
  var multipartFile = new http.MultipartFile(
    'file',
    stream,
    fileSize,
    filename: 'blob',
    /*  contentType: MediaType(primaryType, subType) */
    contentType: contentType,
  );
  //contentType: new MediaType('image', 'png'));

  request.files.add(multipartFile);

  setState('Uploading encrypted file...');

  var response = await request.send();

  setState('Uploaded encrypted file!');

  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }

  final res = await response.stream.transform(utf8.decoder).join();

  final resData = json.decode(res);

  if (resData['skylink'] == null) throw Exception('Skynet Upload Fail');

  final skylink = resData['skylink'];

  return skylink;
}

Future<void> uploadFile() async {
/*   print('Encrypted: $encrypted');

  // Decrypt


  print('Decrypted: $decrypted'); */
}
