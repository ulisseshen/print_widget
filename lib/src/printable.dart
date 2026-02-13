import 'package:flutter/widgets.dart';

enum PrintType { page, widget }

mixin Printable on Widget {
  String get printName;
  PrintType get printType;
}
