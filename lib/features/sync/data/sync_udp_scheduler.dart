import 'dart:async';

/// 一次调度任务的边界：可查询是否仍有效，可取消。
abstract interface class SyncUdpScheduledTask {
  bool get isActive;
  void cancel();
}

/// 调度器边界：一次性与周期任务，测试可注入手动调度器。
abstract interface class SyncUdpScheduler {
  SyncUdpScheduledTask schedule(Duration delay, void Function() callback);

  SyncUdpScheduledTask periodic(Duration interval, void Function() callback);
}

/// 生产调度器：用 [Timer] / [Timer.periodic] 实现。
final class TimerSyncUdpScheduler implements SyncUdpScheduler {
  const TimerSyncUdpScheduler();

  @override
  SyncUdpScheduledTask schedule(Duration delay, void Function() callback) =>
      _TimerSyncUdpTask(Timer(delay, callback));

  @override
  SyncUdpScheduledTask periodic(Duration interval, void Function() callback) =>
      _TimerSyncUdpTask(Timer.periodic(interval, (_) => callback()));
}

/// [Timer] 的适配任务；isActive 与 cancel 直接委托给底层 Timer。
final class _TimerSyncUdpTask implements SyncUdpScheduledTask {
  _TimerSyncUdpTask(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
