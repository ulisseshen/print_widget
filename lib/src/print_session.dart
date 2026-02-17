import 'app_wrapper.dart';
import 'device_frame.dart';
import 'print_state.dart';

class PrintSession {
  PrintSession({
    required this.appWrapper,
    this.defaultDevice,
    this.outputDir = 'print_widget/output',
    this.generateManifest = true,
    this.stateOutputMode = StateOutputMode.prefix,
  });

  final AppWrapper appWrapper;
  final DeviceFrame? defaultDevice;
  final String outputDir;
  final bool generateManifest;
  final StateOutputMode stateOutputMode;
}
