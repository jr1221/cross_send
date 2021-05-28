import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/adapter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:jaguar/serve/server.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';

import 'package:logging/logging.dart';

import 'constants.dart';

void main() {
  runApp(MaterialApp(
    home: Home(),
  ));
}

class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int counter = 0;
  int thirdCount = 0;
  int numOfFiles = 1;

  Dio dio = Dio();

  Future<dynamic> _runJag() async {
    counter = 0;
    thirdCount = 0;
    FilePickerResult? pickResult =
        await FilePicker.platform.pickFiles(allowMultiple: true);
    if (pickResult == null) return 'Nothing chosen';
    String pickPath;
    await RunServe.createServer();
    try {
      pickPath = pickResult.paths.first!
          .substring(0, pickResult.paths.first!.lastIndexOf('/') + 1);
    } catch (e) {
      return 'File (s) not found \n $e';
    }
    List<SendImage> copied = List.empty(growable: true);
    pickResult.paths.forEach((element) {
      if (element != null) {
        bool isImg = false;
        for (String imgExt in Constants.listOfImageCodecs) {
          if (extension(element) == imgExt) {
            isImg = true;
            break;
          }
        }
        copied.add(SendImage(basename(element), isImg));
      } else
        return;
    });
    numOfFiles = copied.length;
    final SendPack sendObj = await RunServe.startServer(pickPath, copied);
    return QrImage(
      data: jsonEncode(sendObj),
    );
  }

  Future<dynamic> _runRec() async {
    final barcodeResultObj = SendPack.fromJson(jsonDecode(
        await FlutterBarcodeScanner.scanBarcode(
            "#000000", "Cancel", true, ScanMode.QR)));
    String baseUrl =
        'https://${barcodeResultObj.ip}:${barcodeResultObj.port}/${barcodeResultObj.sendDir}/';
    String basePath = (await getTemporaryDirectory()).path + '/';
    for (SendImage imgObj in barcodeResultObj.imageList) {
      String savePath = basePath + imgObj.imgName;
      await dio.download(baseUrl + imgObj.imgName, savePath);
      if (imgObj.isImg)
        await ImageGallerySaver.saveFile(savePath);
      else
        await FileSaver.instance.saveFile(
            basename(imgObj.imgName),
            await File(savePath).readAsBytes(),
            extension(imgObj.imgName).substring(1));
    }
  }

  @override
  void initState() {
    super.initState();
    _configDio();
  }

  Future<void> _configDio() async {
    String certAsset = await rootBundle.loadString(Constants.certPath);

    (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
        (client) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        if (cert.pem == certAsset) {
          return true;
        }
        return false;
      };
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cross Send'),
        titleTextStyle: TextStyle(),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          child: ListView(
            children: [
              ElevatedButton(
                  child: Text("Send Files!"),
                  onPressed: () async {
                    final runJagResponse = await _runJag();

                    if (runJagResponse.runtimeType ==
                        QrImage(data: '1').runtimeType) {
                      showDialog(
                          context: context,
                          builder: (_) => SimpleDialog(
                                title: Text('Share QR Code'),
                                children: [
                                  Text(
                                      r'Click "Scan Code to Recieve" on the other device, and scan the below QR code'),
                                  runJagResponse,
                                  StreamBuilder<LogRecord>(
                                      stream: RunServe.server.log.onRecord,
                                      builder: (context, orderSnapshot) {
                                        if (!orderSnapshot.hasData) {
                                          return Text("No Downloads Yet...");
                                        } else {
                                          thirdCount++;
                                          if (thirdCount % numOfFiles == 0)
                                            counter++;
                                          return Text(
                                              "There have been $counter downloads");
                                        }
                                      }),
                                ],
                              ));
                    } else
                      showDialog(
                        context: context,
                        builder: (_) => SimpleDialog(
                          title: Text('Error!'),
                          children: [
                            Text(runJagResponse.toString()),
                          ],
                        ),
                      );
                  }),
              ElevatedButton(
                  child: Text("Recieve Files"),
                  onPressed: () async {
                    final runRecResponse = await _runRec();
                    if (runRecResponse != null)
                      showDialog(
                          context: context,
                          builder: (_) => SimpleDialog(
                                title: Text('Error!'),
                                children: [
                                  Text(runRecResponse.toString()),
                                ],
                              ));
                  }),
            ],
          ),
        ),
      ),
    );
  }
}

class RunServe {
  static Jaguar server = Jaguar();

  static Future<void> createServer() async {
    await server.close();
    final security = SecurityContext();
    security.useCertificateChainBytes(
        (utf8.encode(await rootBundle.loadString(Constants.certPath))));
    security.usePrivateKeyBytes(
        (utf8.encode(await rootBundle.loadString(Constants.privkeyPath))));
    server = Jaguar(port: 8080, securityContext: security);
  }

  static Future<SendPack> startServer(
      String uploadFileRef, List<SendImage> uploadFilesList) async {
    server.staticFiles(
      '${Constants.sendDir}/*',
      uploadFileRef,
    );
    await server.serve(logRequests: true);
    final String ip = (await (NetworkInfo().getWifiIP()))!;
    SendPack sender = SendPack(
        ip, Constants.sendPort.toString(), Constants.sendDir, uploadFilesList);
    return sender;
  }
}

class SendPack {
  String ip; // ip
  String port; // port
  String sendDir; // sendDir

  List<SendImage> imageList; // upload file list

  SendPack(this.ip, this.port, this.sendDir, this.imageList);

  SendPack.fromJson(Map<String, dynamic> json)
      : ip = json['i'],
        port = json['p'],
        sendDir = json['d'],
        imageList = (json['l'] as List)
            .map((element) => SendImage.fromJson(element))
            .toList();

  Map<String, dynamic> toJson() => {
        r'i': ip,
        r'p': port,
        r'd': sendDir,
        r'l': this.imageList.map((ab) => ab.toJson()).toList(),
      };
}

class SendImage {
  String imgName; // name of image
  bool isImg; // is image or video (media) or not, for location to store

  SendImage(this.imgName, this.isImg);

  SendImage.fromJson(Map<String, dynamic> json)
      : imgName = json['n'],
        isImg = json['m'];

  Map<String, dynamic> toJson() => {r'n': imgName, r'm': isImg};
}
