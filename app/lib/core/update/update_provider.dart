import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'update_service.dart';

final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) => checkForUpdate());
