import 'app_wrapper.dart';
import 'device_frame.dart';

class PrintSession {
  PrintSession({
    required this.appWrapper,
    this.defaultDevice,
    this.outputDir = 'test/prints/output',
    this.generateManifest = true,
  });

  final AppWrapper appWrapper;
  final DeviceFrame? defaultDevice;
  final String outputDir;
  final bool generateManifest;
}
