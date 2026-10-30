import 'api.dart';
import 'session.dart';

// App-wide singletons instead of a DI/state package; swap for Provider if the screen count grows.
final session = Session();
final api = Api(session);
