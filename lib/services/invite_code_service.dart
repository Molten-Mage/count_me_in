import '../models/challenge.dart';
import '../models/group.dart';
import 'challenge_service.dart';
import 'group_service.dart';

/// Joins a group by [code], falling back to joining a challenge with the
/// same code if no group matches. Codes are generated with a "G-"/"C-"
/// prefix as a hint (see GroupService/ChallengeService), but a code typed
/// into the wrong "Join a ___" dialog still works instead of just failing
/// with "not found". Exactly one of the two fields is set on success;
/// throws StateError if neither a group nor a challenge matches.
Future<({Group? group, Challenge? challenge})> joinGroupOrChallengeByCode(
  String code,
) async {
  try {
    return (group: await GroupService().joinGroupByCode(code), challenge: null);
  } on StateError {
    try {
      return (
        group: null,
        challenge: await ChallengeService().joinChallengeByCode(code),
      );
    } on StateError {
      throw StateError('No group or challenge found with that code.');
    }
  }
}

/// Same as [joinGroupOrChallengeByCode], but tries the challenge first -
/// used by the "Join a challenge" dialog.
Future<({Group? group, Challenge? challenge})> joinChallengeOrGroupByCode(
  String code,
) async {
  try {
    return (
      group: null,
      challenge: await ChallengeService().joinChallengeByCode(code),
    );
  } on StateError {
    try {
      return (
        group: await GroupService().joinGroupByCode(code),
        challenge: null,
      );
    } on StateError {
      throw StateError('No group or challenge found with that code.');
    }
  }
}
