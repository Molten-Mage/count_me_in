/// An objective a generated challenge can draw from, with a target range
/// so generated challenges don't all feel identical.
class ObjectiveTemplate {
  final String name;
  final int minTarget;
  final int maxTarget;

  const ObjectiveTemplate(this.name, this.minTarget, this.maxTarget);
}

/// A themed pool of objectives, reusable names, and a reusable description
/// the admin "generate a challenge" tool draws from — see
/// lib/pages/settings_page.dart's `_GenerateChallengeTile`.
class ChallengeCategory {
  final String name;
  final List<String> flavorNames;
  final String description;
  final List<ObjectiveTemplate> objectives;

  const ChallengeCategory({
    required this.name,
    required this.flavorNames,
    required this.description,
    required this.objectives,
  });
}

const challengeCategories = [
  ChallengeCategory(
    name: 'Fitness',
    flavorNames: ['Move More Week', 'Fitness Sprint', 'The Grind'],
    description: 'A light fitness sampler — a little of everything.',
    objectives: [
      ObjectiveTemplate('Push-ups', 50, 150),
      ObjectiveTemplate('Squats', 50, 150),
      ObjectiveTemplate('Minutes of walking', 60, 200),
      ObjectiveTemplate('Pull-ups', 20, 50),
    ],
  ),
  ChallengeCategory(
    name: 'Health',
    flavorNames: ['Hydrate & Feel Great', 'Small Habits Week', 'Reset Days'],
    description: 'Small daily habits, stacked up over the challenge.',
    objectives: [
      ObjectiveTemplate('Glasses of water', 30, 70),
      ObjectiveTemplate('Minutes of stretching', 30, 100),
      ObjectiveTemplate('Steps', 10000, 50000),
    ],
  ),
  ChallengeCategory(
    name: 'Mind',
    flavorNames: ['Reading Sprint', 'Quiet Mind Week', 'Mindful Month'],
    description: 'For the reflective and the well-read.',
    objectives: [
      ObjectiveTemplate('Pages read', 100, 300),
      ObjectiveTemplate('Minutes reading', 150, 400),
      ObjectiveTemplate('Minutes meditating', 60, 200),
      ObjectiveTemplate('Gratitude entries', 7, 30),
    ],
  ),
  ChallengeCategory(
    name: 'Productivity',
    flavorNames: ['Get It Done Week', 'Deep Work Sprint', 'Side Project Sprint'],
    description: 'Get things done, one tally at a time.',
    objectives: [
      ObjectiveTemplate('Tasks completed', 10, 40),
      ObjectiveTemplate('Minutes of focused work', 200, 600),
      ObjectiveTemplate('Hours on a side project', 5, 30),
    ],
  ),
  ChallengeCategory(
    name: 'Culture',
    flavorNames: ['Watch Party Week', 'Screen Time Sprint', 'Binge & Play'],
    description: 'For the movie buffs, show bingers, and gamers.',
    objectives: [
      ObjectiveTemplate('Series episodes watched', 10, 50),
      ObjectiveTemplate('Movies watched', 3, 15),
      ObjectiveTemplate('Hours of gaming', 10, 50),
      ObjectiveTemplate('Meals cooked', 5, 21),
    ],
  ),
  ChallengeCategory(
    name: 'Leisure',
    flavorNames: ['Hobby Hours', 'Passion Project Week', 'Me-Time Sprint'],
    description: 'Make time for the things you actually enjoy doing.',
    objectives: [
      ObjectiveTemplate('Hours doing a hobby', 5, 30),
      ObjectiveTemplate('Board games played', 3, 15),
      ObjectiveTemplate('Sketches or drawings made', 5, 20),
      ObjectiveTemplate('Minutes gardening', 60, 300),
    ],
  ),
];

/// Duration options a generated challenge's deadline is randomly picked
/// from.
const challengeDurationDaysOptions = [7, 14, 30];
