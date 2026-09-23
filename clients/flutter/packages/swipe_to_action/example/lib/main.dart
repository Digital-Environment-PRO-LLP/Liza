import 'package:flutter/material.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({final Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _text = 'Swipe some tiles!';

  @override
  Widget build(final BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Plugin example app'),
          ),
          body: ListView(
            children: [
              Swipeable(
                key: const ValueKey(1),
                onSwipe: (final direction) {
                  if (direction == SwipeDirection.startToEnd) {
                    setState(() {
                      _text = 'Swiped to right!';
                    });
                  } else {
                    setState(() {
                      _text = 'Swiped to left!';
                    });
                  }
                },
                child: const ListTile(
                  title: Text('Tile one'),
                ),
              ),
              Swipeable(
                key: const ValueKey(2),
                onSwipe: (final direction) {
                  setState(() {
                    _text = 'This one can only be swiped to right!';
                  });
                },
                background: Container(color: Colors.orange),
                direction: SwipeDirection.startToEnd,
                child: const ListTile(
                  title: Text('Tile one'),
                ),
              ),
              Swipeable(
                key: const ValueKey(3),
                onSwipe: (final direction) {
                  setState(() {
                    _text = 'This one was confirmed with a function!';
                  });
                },
                background: Container(color: Colors.green),
                secondaryBackground: Container(color: Colors.teal),
                confirmSwipe: (final direction) async => true,
                child: const ListTile(
                  title: Text('Tile three'),
                ),
              ),
              Center(child: Text(_text)),
            ],
          ),
        ),
      );
}
