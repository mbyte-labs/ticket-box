import 'package:json_annotation/json_annotation.dart';

enum ListType {
  /// It means that this user is the owner of the list
  personal,

  /// It means that the user was added by somebody as collaborator to the given
  /// list
  collaboration,
}

enum ListPrivacyType {
  /// Only you can see the list.
  @JsonValue('private')
  private,

  /// Anyone with the share_link can see the list.
  @JsonValue('link')
  link,

  /// Only your friends can see the list.
  @JsonValue('friends')
  friends,

  /// Anyone can see the list.
  @JsonValue('public')
  public,
}
