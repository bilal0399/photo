import 'package:diwan_archive/features/tasks/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Task.copyWith preserves createdAt and overrides entity', () {
    const task = Task(
      id: 'abc',
      taskNumber: '5',
      entity: 'فوج الهندسة',
      attachmentPath: '',
      createdAt: '2026-01-01',
    );
    final moved = task.copyWith(entity: 'الفرع المالي');
    expect(moved.entity, 'الفرع المالي');
    expect(moved.createdAt, '2026-01-01');
    expect(moved.taskNumber, '5');
  });
}
