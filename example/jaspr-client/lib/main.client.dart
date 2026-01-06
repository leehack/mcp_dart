/// The entrypoint for the **client** (browser) app.
///
/// This file is compiled to JavaScript and executed in the browser.
library;

// Client-specific Jaspr import
import 'package:jaspr/client.dart';

// Import the main App component
import 'app.dart';

void main() {
  // Attach the App component to the document body
  runApp(const App());
}
