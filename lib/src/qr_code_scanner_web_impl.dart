// Note: only work over https or localhost
//
// thanks:
// - https://medium.com/@mk.pyts/how-to-access-webcam-video-stream-in-flutter-for-web-1bdc74f2e9c7
// - https://kevinwilliams.dev/blog/taking-photos-with-flutter-web
// - https://github.com/cozmo/jsQR
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'dart:ui' as ui;

///
///call global function jsQR
/// import https://github.com/cozmo/jsQR/blob/master/dist/jsQR.js on your index.html at web folder
///
dynamic _jsQR(d, w, h, o) {
  return js.context.callMethod('jsQR', [d, w, h, o]);
}

class QrCodeCameraWebImpl extends StatefulWidget {
  final void Function(String qrValue) qrCodeCallback;
  final Widget? child;
  final BoxFit fit;
  final Widget Function(BuildContext context, Object error)? onError;

  QrCodeCameraWebImpl({
    Key? key,
    required this.qrCodeCallback,
    this.child,
    this.fit = BoxFit.cover,
    this.onError,
  }) : super(key: key);

  @override
  _QrCodeCameraWebImplState createState() => _QrCodeCameraWebImplState();
}

class _QrCodeCameraWebImplState extends State<QrCodeCameraWebImpl> {
//  final double _width = 1000;
//  final double _height = _width / 4 * 3;
  final String _uniqueKey = UniqueKey().toString();

  //see https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/readyState
  static const _HAVE_ENOUGH_DATA = 4;

  // Webcam widget to insert into the tree
  late Widget _videoWidget;

  // VideoElement
  late html.VideoElement _video;
  late html.CanvasElement _canvasElement;
  html.CanvasRenderingContext2D? _canvas;
  html.MediaStream? _stream;

  List<html.MediaDeviceInfo> availableDevices = [];
  html.MediaDeviceInfo? currentDevice;

  var _loading = false;

  @override
  void initState() {
    super.initState();
    // Create a video element which will be provided with stream source
    _video = html.VideoElement();
    // Register an webcam
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
        'webcamVideoElement$_uniqueKey', (int viewId) => _video);
    // Create video widget
    _videoWidget = HtmlElementView(
        key: UniqueKey(), viewType: 'webcamVideoElement$_uniqueKey');
    // Access the webcam stream
    getVideoDevices();
  }

  getVideoDevices() async {
    setState(() {
      _loading = true;
    });
    var devices = await html.window.navigator.mediaDevices?.enumerateDevices();
    devices?.forEach((element) {
      if (element.kind == 'videoinput') {
        setState(() {
          availableDevices.add(element);
        });
      }
    });
    if (availableDevices.length > 1) {
      setState(() {
        currentDevice = availableDevices[1];
      });
    } else {
      setState(() {
        currentDevice = availableDevices.first;
      });
    }
    await Future.delayed(const Duration(seconds: 1));
    setCurrentCamera(currentDevice!);
  }

  setCurrentCamera(html.MediaDeviceInfo device) {
    if (_stream?.active ?? false) {
      _video.pause();
      _stream?.getTracks().forEach((track) => track.stop());
    }
    setState(() {
      _loading = true;
    });
    try {
      html.window.navigator.mediaDevices?.getUserMedia({
        'video': {'deviceId': device.deviceId}
      }).then((html.MediaStream stream) {
        _stream = stream;
        _video.srcObject = stream;
        _video.setAttribute('playsinline',
            'true'); // required to tell iOS safari we don't want fullscreen
        _video.play();
      });
    } catch (err) {
      print(err);
      //Fallback
      try {
        html.window.navigator
            .getUserMedia(video: {'facingMode': 'environment'}).then(
                (html.MediaStream stream) {
          _stream = stream;
          _video.srcObject = stream;
          _video.setAttribute('playsinline',
              'true'); // required to tell iOS safari we don't want fullscreen
          _video.play();
        });
      } catch (e) {
        print(e);
      }
    }

    _canvasElement = html.CanvasElement();
    _canvas = _canvasElement.getContext("2d") as html.CanvasRenderingContext2D?;
    Future.delayed(Duration(milliseconds: 20), () {
      tick();
    });
    setState(() {
      _loading = false;
    });
  }

  tick() {
    if (_video.readyState == _HAVE_ENOUGH_DATA) {
      _canvasElement.width = _video.videoWidth;
      _canvasElement.height = _video.videoHeight;
      _canvas?.drawImage(_video, 0, 0);
      var imageData = _canvas?.getImageData(
        0,
        0,
        _canvasElement.width ?? 0,
        _canvasElement.height ?? 0,
      );
      if (imageData is html.ImageData) {
        js.JsObject? code = _jsQR(
          imageData.data,
          imageData.width,
          imageData.height,
          {
            'inversionAttempts': 'dontInvert',
          },
        );
        if (code != null) {
          String value = code['data'];
          this.widget.qrCodeCallback(value);
        }
      }
    }
    Future.delayed(Duration(milliseconds: 10), () => tick());
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const CircularProgressIndicator.adaptive()
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  availableDevices.isNotEmpty
                      ? DropdownButton(
                          value: currentDevice,
                          onChanged: (dynamic newValue) {
                            setState(() {
                              currentDevice = newValue!;
                            });
                            setCurrentCamera(currentDevice!);
                          },
                          items: availableDevices
                              .map<DropdownMenuItem>(
                                  (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text('${value.label}'),
                                      ))
                              .toList(),
                        )
                      : Container(),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  height: double.infinity,
                  width: double.infinity,
                  child: FittedBox(
                    fit: widget.fit,
                    child: SizedBox(
                      width: 400,
                      height: 300,
                      child: _videoWidget,
                    ),
                  ),
                ),
              ),
            ],
          );
  }

  @override
  void dispose() {
    _stream?.getTracks().forEach((track) => track.stop());
    _video.pause();
    super.dispose();
  }
}
