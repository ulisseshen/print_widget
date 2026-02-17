import 'package:flutter/widgets.dart';

import 'device_frame.dart';
import 'print_state.dart';
import 'printable.dart';

class PrintEntry {
  const PrintEntry({
    required this.name,
    required this.widget,
    required this.type,
    this.size,
    this.devices,
    this.states,
  });

  final String name;
  final Widget widget;
  final PrintType type;
  final Size? size;
  final List<DeviceFrame>? devices;
  final List<PrintState>? states;
}

PrintEntry page(String name, Widget widget, {List<DeviceFrame>? devices}) =>
    PrintEntry(
      name: name,
      widget: widget,
      type: PrintType.page,
      devices: devices,
    );

PrintEntry widget(String name, Widget widget,
        {Size? size, List<DeviceFrame>? devices}) =>
    PrintEntry(
      name: name,
      widget: widget,
      type: PrintType.widget,
      size: size,
      devices: devices,
    );

PrintEntry pages(String name,
        {required List<PrintState> states, List<DeviceFrame>? devices}) =>
    PrintEntry(
      name: name,
      widget: const SizedBox.shrink(),
      type: PrintType.page,
      devices: devices,
      states: states,
    );

PrintEntry widgets(String name,
        {required List<PrintState> states,
        Size? size,
        List<DeviceFrame>? devices}) =>
    PrintEntry(
      name: name,
      widget: const SizedBox.shrink(),
      type: PrintType.widget,
      size: size,
      devices: devices,
      states: states,
    );
