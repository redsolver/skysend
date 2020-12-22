import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:skynet_send/ansi_pens.dart';
import 'package:skynet_send/config.dart';
import 'package:skynet_send/download.dart';
import 'package:skynet_send/upload.dart';

void main(List<String> args) async {
  if (args.length != 2) {
    exitWithHelp();
  }

  final command = args.first;

  if (['download', 'dl', 'd', 'down'].contains(command)) {
    print('Using portal ${SkynetConfig.portal}');
    print('Downloading metadata...');

    String hash = args[1];

    hash = hash.substring(hash.indexOf('#') + 1);
/* 
    print(hash); */

    if (hash.startsWith(RegExp(r'[0-9]'))) {
      print('Unsupported version. Please use the Web UI.');
      return;
    }

    // hash = hash.substring(1);
    // setState('Downloading file index...');

    final lengthSep = hash.indexOf('-');

    final version = hash.substring(0, lengthSep);
    if (version == 'a') {
      print('Unsupported version. Please use the Web UI.');
      return;
    }

    hash = hash.substring(lengthSep + 1);

    final sep = hash.indexOf('+');

    final skylink = hash.substring(0, sep);
    final key = hash.substring(sep + 1);
/* 
    print(skylink);
    print(key); */
    // print(skylink);

    final dlTask = DownloadTask();

    dlTask.progress.stream.listen((event) {
      print(event);
    });

    await dlTask.downloadAndDecryptMetadata(
      skylink,
      key,
    );

    print(
        'Do you want to download and decrypt ${greenBold(dlTask.metadata["filename"])}? (${magenta(filesize(dlTask.metadata['filesize']))}) [Y/n]');

    final s = stdin.readLineSync();

    if (!['yes', 'ja', 'y', 'Y', ''].contains(s)) {
      print('Aborted.');
      return;
    }

    int fIndex = 0;

    final String filename = dlTask.metadata["filename"];

    final seperator = filename.lastIndexOf('.');

    String name;
    String ext;

    if (seperator == -1) {
      name = filename;
      ext = '';
    } else {
      name = filename.substring(0, seperator);
      ext = filename.substring(seperator);
    }

    File file = File('$name$ext');

    while (file.existsSync()) {
      fIndex++;

      file = File('$name.$fIndex$ext');
    }

    final tmpFile = File('${file.path}.downloading');

    final sink = tmpFile.openWrite();

    dlTask.chunkCtrl.stream.listen((event) async {
      if (event == null) {
        await sink.flush();
        await sink.close();
        print('Renaming file...');

        await tmpFile.rename(file.path);

        print('Download successful');
      } else {
        sink.add(event);
      }
    });

    dlTask.downloadAndDecryptFile();
  } else if (['u', 'up', 'upload', 'send'].contains(command)) {
    final file = File(args[1]);

    if (!file.existsSync()) {
      print('File ${file.path} doesn\'t exist');
      exit(2);
    }

    await startEncryptAndUpload(file);
  }
}

void exitWithHelp() {
  print(greenBold('SkySend CLI v3.2'));

  print('');

  print(magenta('skysend upload') + ' path/to/file');
  print(magenta('skysend download') + ' https://skysend.hns...');

  print('');
  print(
      'You can also try aliases like ${magenta("u")}, ${magenta("d")}, ${magenta("up")} or ${magenta("down")}');

  exit(0);
}
