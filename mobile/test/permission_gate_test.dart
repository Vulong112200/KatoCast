import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/permissions/permission_gate.dart';

/// Hàng đợi xin quyền — thứ tự và tính "không bao giờ chạy chồng" là toàn bộ giá
/// trị của lớp này: Android thả im lặng lời xin quyền thứ hai khi hộp thoại đầu
/// còn hiển thị (và KHÔNG gửi callback), nên chạy chồng = future treo vĩnh viễn.
void main() {
  test('hai lượt gọi song song KHÔNG chạy chồng nhau', () async {
    final events = <String>[];
    final first = Completer<void>();

    final a = PermissionGate.run(() async {
      events.add('a-start');
      await first.future;
      events.add('a-end');
      return 'a';
    });
    final b = PermissionGate.run(() async {
      events.add('b-start');
      return 'b';
    });

    // Lượt b PHẢI chưa bắt đầu khi a còn đang chờ người dùng.
    await Future<void>.delayed(Duration.zero);
    expect(events, ['a-start']);

    first.complete();
    expect(await a, 'a');
    expect(await b, 'b');
    expect(events, ['a-start', 'a-end', 'b-start']);
  });

  test('thứ tự chạy đúng thứ tự GỌI (FIFO)', () async {
    final order = <int>[];
    final futures = [
      for (var i = 0; i < 5; i++)
        PermissionGate.run(() async {
          await Future<void>.delayed(Duration(milliseconds: (5 - i) * 5));
          order.add(i);
        }),
    ];
    await Future.wait(futures);
    expect(order, [0, 1, 2, 3, 4]);
  });

  test('một lượt NÉM LỖI không làm đứt hàng đợi', () async {
    final failed = PermissionGate.run<void>(() async => throw StateError('nope'));
    final after = PermissionGate.run(() async => 'vẫn chạy');

    await expectLater(failed, throwsStateError);
    expect(await after, 'vẫn chạy');
  });

  test('trả đúng giá trị của action cho từng lượt', () async {
    final results = await Future.wait([
      PermissionGate.run(() async => 1),
      PermissionGate.run(() async => 2),
      PermissionGate.run(() async => 3),
    ]);
    expect(results, [1, 2, 3]);
  });
}
