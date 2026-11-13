// https://developers.themoviedb.org/3/getting-started/introduction

class TmDbApi {
  static const String url = 'api.themoviedb.org';

  static final _singleton = TmDbApi._internal();

  TmDbApi._internal();

  factory TmDbApi() {
    return _singleton;
  }
}
