import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quickdesk_android/controller/touch_input.dart';
import 'package:quickdesk_android/protocol/datachannel_handler.dart';
import 'package:quickdesk_android/protocol/proto/protobuf_messages.dart';

class _RecordingDataChannelHandler extends DataChannelHandler {
  final List<MouseEventMsg> mouseEvents = [];

  @override
  void sendMouseEvent(MouseEventMsg mouseEvent) {
    mouseEvents.add(mouseEvent);
  }
}

PointerDownEvent _down(Offset position, {int pointer = 1}) =>
    PointerDownEvent(pointer: pointer, position: position);

PointerMoveEvent _move(Offset position, {int pointer = 1}) =>
    PointerMoveEvent(pointer: pointer, position: position);

PointerUpEvent _up(Offset position, {int pointer = 1}) =>
    PointerUpEvent(pointer: pointer, position: position);

void _tap(TouchInputController controller, Offset position) {
  controller.onPointerDown(_down(position), 1);
  controller.onPointerUp(_up(position), 0);
}

void main() {
  late _RecordingDataChannelHandler channel;
  late TouchInputController controller;

  setUp(() {
    channel = _RecordingDataChannelHandler();
    controller = TouchInputController(channel)
      ..setRemoteResolution(1000, 800)
      ..setViewportSize(400, 800);
  });

  tearDown(() async {
    controller.dispose();
    await channel.dispose();
  });

  test('single tap emits an immediate left click', () {
    _tap(controller, const Offset(100, 100));

    expect(channel.mouseEvents, hasLength(2));
    expect(channel.mouseEvents[0].button, MouseButton.left.value);
    expect(channel.mouseEvents[0].buttonDown, isTrue);
    expect(channel.mouseEvents[1].button, MouseButton.left.value);
    expect(channel.mouseEvents[1].buttonDown, isFalse);
  });

  test('tap released before long-press threshold is not dropped', () async {
    controller.onPointerDown(_down(const Offset(100, 100)), 1);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.onPointerUp(_up(const Offset(100, 100)), 0);

    expect(channel.mouseEvents, hasLength(2));
    expect(channel.mouseEvents[0].buttonDown, isTrue);
    expect(channel.mouseEvents[1].buttonDown, isFalse);
  });

  test('long press emits only a right click', () async {
    controller.onPointerDown(_down(const Offset(100, 100)), 1);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    controller.onPointerUp(_up(const Offset(100, 100)), 0);

    expect(channel.mouseEvents, hasLength(2));
    expect(channel.mouseEvents[0].button, MouseButton.right.value);
    expect(channel.mouseEvents[0].buttonDown, isTrue);
    expect(channel.mouseEvents[1].button, MouseButton.right.value);
    expect(channel.mouseEvents[1].buttonDown, isFalse);
  });

  test('double tap emits two complete left clicks', () {
    _tap(controller, const Offset(100, 100));
    _tap(controller, const Offset(100, 100));

    expect(
      channel.mouseEvents.map((event) => event.buttonDown),
      [true, false, true, false],
    );
    expect(controller.leftButtonHeld, isFalse);
  });

  test('second tap movement holds left button until pointer up', () {
    _tap(controller, const Offset(100, 100));

    controller.onPointerDown(_down(const Offset(100, 100)), 1);
    controller.onPointerMove(_move(const Offset(120, 110)), 1);
    controller.onPointerUp(_up(const Offset(120, 110)), 0);

    expect(channel.mouseEvents, hasLength(5));
    expect(channel.mouseEvents[2].button, MouseButton.left.value);
    expect(channel.mouseEvents[2].buttonDown, isTrue);
    expect(channel.mouseEvents[3].button, isNull);
    expect(channel.mouseEvents[4].button, MouseButton.left.value);
    expect(channel.mouseEvents[4].buttonDown, isFalse);
    expect(controller.leftButtonHeld, isFalse);
  });

  test('rapid taps at different positions do not start a drag', () {
    _tap(controller, const Offset(100, 100));

    controller.onPointerDown(_down(const Offset(250, 250)), 1);
    controller.onPointerMove(_move(const Offset(270, 260)), 1);
    controller.onPointerUp(_up(const Offset(270, 260)), 0);

    expect(channel.mouseEvents, hasLength(3));
    expect(channel.mouseEvents[2].button, isNull);
    expect(controller.leftButtonHeld, isFalse);
  });

  test('pointer cancellation releases an active drag', () {
    _tap(controller, const Offset(100, 100));
    controller.onPointerDown(_down(const Offset(100, 100)), 1);
    controller.onPointerMove(_move(const Offset(120, 110)), 1);

    controller.onPointerCancel(0);

    expect(channel.mouseEvents.last.button, MouseButton.left.value);
    expect(channel.mouseEvents.last.buttonDown, isFalse);
    expect(controller.leftButtonHeld, isFalse);
  });

  test('pointer cancellation does not turn a pending tap into a click', () {
    controller.onPointerDown(_down(const Offset(100, 100)), 1);

    controller.onPointerCancel(0);

    expect(channel.mouseEvents, isEmpty);
  });

  test('adding a second pointer cancels drag without re-pressing left', () {
    _tap(controller, const Offset(100, 100));
    controller.onPointerDown(_down(const Offset(100, 100)), 1);
    controller.onPointerMove(_move(const Offset(120, 110)), 1);

    controller.onPointerDown(
      _down(const Offset(200, 200), pointer: 2),
      2,
    );
    controller.onPointerUp(
      _up(const Offset(200, 200), pointer: 2),
      1,
      remainingPosition: const Offset(160, 130),
    );
    controller.onPointerMove(_move(const Offset(170, 130)), 1);

    expect(
      channel.mouseEvents.where((event) => event.buttonDown == true),
      hasLength(2),
    );
    expect(channel.mouseEvents.last.x, 575);
    expect(controller.leftButtonHeld, isFalse);
  });
}
