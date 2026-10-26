import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 显式使用应用的 Material 页面，让转场和系统返回共用同一套主题。
/// go_router 的独立 Material 库无法识别本应用的 Flutter MaterialApp。
GoRoute appMaterialRoute({
  required String path,
  String? name,
  required Widget Function(BuildContext, GoRouterState) builder,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  name: name,
  routes: routes,
  pageBuilder: (context, state) => MaterialPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    restorationId: state.pageKey.value,
    arguments: {...state.pathParameters, ...state.uri.queryParameters},
    child: builder(context, state),
  ),
);
