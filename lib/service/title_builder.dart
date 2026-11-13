import 'package:ticketbox/common/model/media_ref.dart';

class ConfirmationTitleBuilder {
  static String showTitle(ShowRef show) {
    return show.title ?? '-No title available-';
  }

  static String seasonTitle(int season) {
    if (season == 0) {
      return 'Specials';
    }
    return 'Season $season';
  }

  static String seasonShortTitle(int season) {
    if (season == 0) {
      return 'Special';
    }
    return 'S$season';
  }

  static String episodeTitle(EpisodeRef episode) {
    return episodeTitleFromParts(episode.season, episode.episode, episode.title);
  }

  /// Same as [episodeTitle] for callers that hold the numbering and title separately rather than
  /// a whole [EpisodeRef] — the details pages, whose state is flattened.
  static String episodeTitleFromParts(int season, int number, String? title) {
    final titleComposer = StringBuffer();
    titleComposer.write(seasonShortTitle(season));
    titleComposer.write('xE');
    titleComposer.write(number.toString());
    titleComposer.write(' ');
    titleComposer.write(title ?? '-No title available-');

    return titleComposer.toString();
  }
}
