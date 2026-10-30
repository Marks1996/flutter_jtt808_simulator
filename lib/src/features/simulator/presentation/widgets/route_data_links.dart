import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sim_ui.dart';

/// Public OSM-derived routing services require visible data credit and a way
/// to report map errors, independent of the currently selected basemap.
class RouteDataLinks extends StatelessWidget {
  const RouteDataLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: SimSpace.md,
    runSpacing: SimSpace.ms,
    children: [
      for (final (label, url) in [
        ('sim.keyless.data_license', 'https://www.openstreetmap.org/copyright'),
        ('sim.keyless.fix_map', 'https://www.openstreetmap.org/fixthemap'),
      ])
        ShadButton.link(
          height: 0,
          padding: EdgeInsets.zero,
          onPressed: () => simRun(context, () async {
            if (!await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            )) {
              throw StateError('Unable to open map data reference');
            }
          }),
          child: Text(tr(label), style: context.textTheme.bodySmall),
        ),
    ],
  );
}
