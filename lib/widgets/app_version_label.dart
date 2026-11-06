import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key});

  static const _fallbackVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.5.0+9',
  );

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final packageInfo = snapshot.data;
      final version = packageInfo == null
          ? _fallbackVersion
          : '${packageInfo.version}+${packageInfo.buildNumber}';
      return Text(
        'Versión $version',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    },
  );
}
