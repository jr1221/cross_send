import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:jaguar/serve/server.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';

void main() {
  HttpOverrides.global = CertOverride();
  runApp(MaterialApp(
    home: Home(),
  ));
}

class CertOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Future<dynamic> _runJag() async {
    FilePickerResult? pickResult =
        await FilePicker.platform.pickFiles(allowMultiple: true);
    if (pickResult == null) return 'Nothing chosen';
    String pickPath;
    String qrData;

    await RunServe.createServer();

    if (pickResult.isSinglePick) {
      try {
        pickPath = pickResult.files.single.path!;
      } catch (e) {
        return 'File not found \n $e';
      }
      qrData = await RunServe.startServer(pickPath);
    } else {
      try {
        print(pickResult.paths.first);
        pickPath = pickResult.paths.first!
            .substring(0, pickResult.paths.first!.lastIndexOf('/') + 1);
        print(pickPath);
      } catch (e) {
        return 'Files not found \n $e';
      }

      List<String> copied = List.empty(growable: true);
      pickResult.paths.forEach((element) {
        if (element != null)
          copied.add(element);
        else
          return;
      });
      qrData = await RunServe.startServer(pickPath,
          multiple: true, uploadFilesList: copied);
    }

    return QrImage(
      data: qrData,
    );
  }

  Future<void> _runRec() async {
    final barcodeResult = await FlutterBarcodeScanner.scanBarcode(
        "#000000", "Cancel", true, ScanMode.QR);
    if (!barcodeResult.startsWith(r'+')) {
      final savePath =
          '${(await getTemporaryDirectory()).path}/${barcodeResult.substring(barcodeResult.lastIndexOf('/'))}';
      await Dio().download(barcodeResult, savePath);
      await ImageGallerySaver.saveFile(savePath);
    } else {
      String baseUrl = barcodeResult.substring(1, barcodeResult.indexOf('*'));
      print(baseUrl);
      String basePath = (await getTemporaryDirectory()).path + '/';
      List<String> listOfItems =
          barcodeResult.substring(barcodeResult.indexOf('*') + 1).split(r'?');
      for (String s in listOfItems) {
        print(s);
      }
      listOfItems.removeLast();
      for (String req in listOfItems) {
        String savePath = basePath + req;
        print(savePath);
        print(baseUrl + req);
        await Dio().download(baseUrl + req, savePath);
        await ImageGallerySaver.saveFile(savePath);
      }
    }
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
                  child: Text("Start Sender"),
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
                  child: Text("Scan Code to Receive"),
                  onPressed: () {
                    _runRec();
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
        (utf8.encode(await rootBundle.loadString('ssl/cert1.pem'))));
    security.usePrivateKeyBytes(
        (utf8.encode(await rootBundle.loadString('ssl/privkey1.pem'))));
    server = Jaguar(port: 8080, securityContext: security);
  }

  static Future<String> startServer(String uploadFileRef,
      {bool multiple = false, List<String>? uploadFilesList}) async {
    if (multiple) {
      print('zz' + uploadFileRef);
      server.staticFiles('dirSend/*', uploadFileRef);
    } else {
      server.staticFile('/${basename(uploadFileRef)}', uploadFileRef);
    }
    await server.serve();
    final String ip = (await (NetworkInfo().getWifiIP()))!;
    String url;
    if (multiple) {
      url = '+https://$ip:8080/dirSend/*';
      for (String pathOf in uploadFilesList!) {
        url += basename(pathOf) + '?';
      }
      return url;
    } else {
      url = 'https://$ip:8080/${basename(uploadFileRef)}';
    }
    return url;
  }
}
