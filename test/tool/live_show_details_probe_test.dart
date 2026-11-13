// Diagnostic: fetches one show from TMDB for real and prints how the appended seasons parse.
// Run: flutter test test/tool/live_show_details_probe_test.dart --dart-define=LIVE=1
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details.dart';

void main() {
  const live = String.fromEnvironment('LIVE');
  test('live appended seasons parse', () async {
    if (live.isEmpty) {
      markTestSkipped('set LIVE=1');
      return;
    }
    final uri = tmdbUri('/3/tv/1396', {'append_to_response': 'external_ids,season/1,season/2'});
    final response = await TmdbHttpClient.instance.get(uri);
    final raw = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    // ignore: avoid_print
    print('status ${response.statusCode}; keys with season: ${raw.keys.where((k) => k.startsWith('season')).toList()}');
    final s1 = raw['season/1'];
    // ignore: avoid_print
    print('season/1 type ${s1.runtimeType}; id ${s1 is Map ? s1['id'] : null} (${s1 is Map ? s1['id'].runtimeType : null}); season_number ${s1 is Map ? s1['season_number'] : null}');
    final details = TmdbShowDetails.fromJson(raw);
    // ignore: avoid_print
    print('appended parsed: ${details.appendedSeasons.keys.toList()}');
    expect(details.appendedSeasons.keys, containsAll([1, 2]));
  });
}
