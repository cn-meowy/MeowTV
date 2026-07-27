import 'package:logger/logger.dart';

// final appLogger = Logger(
//   printer: PrettyPrinter(
//     methodCount: 2,
//     errorMethodCount: 8,
//     lineLength: 120,
//     colors: true,
//     printEmojis: true,
//     dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
//   ),
// );
final appLogger = Logger(
  printer: SimplePrinter(printTime: true),
);