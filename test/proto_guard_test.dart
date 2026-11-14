import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/online/netcode.dart';

void main() {
  test('v4 peers only -> compatible', () {
    expect(protoCheck(me: 'a', online: {'a': (true, 4), 'b': (true, 4)}), isNull);
  });
  test('v3 Flutter peer (no pv) -> they must update', () {
    expect(protoCheck(me: 'a', online: {'a': (true, 4), 'b': (true, null)}), kMsgUpdateThem);
  });
  test('newer peer -> I must update', () {
    expect(protoCheck(me: 'a', online: {'a': (true, 4), 'b': (true, 5)}), kMsgUpdateMe);
  });
  test('RN/Godot peer (no c:fl) keeps the legacy classic path', () {
    expect(protoCheck(me: 'a', online: {'b': (false, null)}), isNull);
  });
  test('host snapshot check', () {
    expect(snapProtoCheck({'pf': 'stars', 'pv': 4}), isNull);
    expect(snapProtoCheck({'pf': 'stars'}), kMsgUpdateThem); // v3 Flutter host
    expect(snapProtoCheck({'pf': 'stars', 'pv': 9}), kMsgUpdateMe);
    expect(snapProtoCheck({'q': 1}), isNull); // RN host
  });
}
