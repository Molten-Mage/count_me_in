/// An objective a generated challenge can draw from, with a target range
/// so generated challenges don't all feel identical.
class ObjectiveTemplate {
  final String name;
  final int minTarget;
  final int maxTarget;

  const ObjectiveTemplate(this.name, this.minTarget, this.maxTarget);
}

/// A themed pool of objectives, reusable names, and reusable descriptions
/// the admin "generate a challenge" tool draws from — see
/// lib/pages/settings_page.dart's `_GenerateChallengeTile`. Descriptions
/// are picked independently of the flavor name, so two challenges from the
/// same category (a likely occurrence once several get generated) don't
/// read as identical besides the name.
class ChallengeCategory {
  final String name;
  final List<String> flavorNames;
  final List<String> descriptions;
  final List<ObjectiveTemplate> objectives;

  const ChallengeCategory({
    required this.name,
    required this.flavorNames,
    required this.descriptions,
    required this.objectives,
  });
}

const challengeCategories = [
  ChallengeCategory(
    name: 'Fitness',
    flavorNames: [
      'Move More Week',
      'Fitness Sprint',
      'The Grind',
      'Get Moving Days',
      'Power Hour Week',
      'Strength Sprint',
      'Sweat Sesh',
      'Rise & Move',
      'Full Send Week',
      'Iron Will Sprint',
      'Momentum Week',
      'Burn It Up',
    ],
    descriptions: [
      'A fitness sampler — a little of everything.',
      'Movement, your way — mix and match as you go.',
      'Get the body moving, one rep at a time.',
    ],
    objectives: [
      ObjectiveTemplate('Push-ups', 50, 150),
      ObjectiveTemplate('Squats', 50, 150),
      ObjectiveTemplate('Minutes of walking', 60, 200),
      ObjectiveTemplate('Pull-ups', 20, 50),
      ObjectiveTemplate('Workouts', 8, 20),
    ],
  ),
  ChallengeCategory(
    name: 'Health',
    flavorNames: [
      'Hydrate & Feel Great',
      'Small Habits Week',
      'Reset Days',
      'Fresh Start Week',
      'Clean Slate Week',
      'Wellness Reset',
      'Balance Sprint',
      'Feel Good Days',
      'Recharge Week',
      'Steady Habits',
      'Nourish & Rest',
      'New Rhythm Week',
    ],
    descriptions: [
      'Small daily habits, stacked up over the challenge.',
      'Little resets, repeated until they stick.',
      'Everyday choices that add up over time.',
    ],
    objectives: [
      ObjectiveTemplate('Glasses of water', 30, 70),
      ObjectiveTemplate('Minutes of stretching', 30, 100),
      ObjectiveTemplate('Steps', 10000, 50000),
      ObjectiveTemplate('Alcohol-free days', 15, 25),
      ObjectiveTemplate('Days without unnecessary purchases', 15, 25),
    ],
  ),
  ChallengeCategory(
    name: 'Mind',
    flavorNames: [
      'Reading Sprint',
      'Quiet Mind Week',
      'Mindful Month',
      'Slow Down Week',
      'Deep Focus Days',
      'Still Waters Week',
      'Page Turner Sprint',
      'Clear Head Week',
      'Bookworm Sprint',
      'Calm Mind Days',
      'Reflection Week',
      'Wind Down Sprint',
    ],
    descriptions: [
      'For the reflective and the well-read.',
      'Slow down and make space to think.',
      'Words, quiet, and a little reflection.',
    ],
    objectives: [
      ObjectiveTemplate('Pages read', 100, 300),
      ObjectiveTemplate('Minutes reading', 150, 400),
      ObjectiveTemplate('Minutes meditating', 60, 200),
      ObjectiveTemplate('Gratitude entries', 7, 30),
      ObjectiveTemplate('Books finished', 2, 6),
    ],
  ),
  ChallengeCategory(
    name: 'Productivity',
    flavorNames: [
      'Get It Done Week',
      'Deep Work Sprint',
      'Side Project Sprint',
      'Inbox Zero Sprint',
      'Momentum Sprint',
      'Clear the Decks',
      'Focus Fortnight',
      'Ship It Week',
      'Task Force Sprint',
      'Grind Time Week',
      'Output Sprint',
      'No Excuses Week',
    ],
    descriptions: [
      'Get things done, one tally at a time.',
      'Turn intentions into finished things.',
      'For clearing the list and making progress.',
    ],
    objectives: [
      ObjectiveTemplate('Tasks completed', 10, 40),
      ObjectiveTemplate('Minutes of focused work', 200, 600),
      ObjectiveTemplate('Hours on a side project', 5, 30),
    ],
  ),
  ChallengeCategory(
    name: 'Culture',
    flavorNames: [
      'Watch Party Week',
      'Screen Time Sprint',
      'Binge & Play',
      'Culture Club Week',
      'Popcorn Sprint',
      'Game Night Week',
      'Marathon Week',
      'Double Feature Week',
      'Session Sprint',
      'Story Mode Week',
      'Rewatch Sprint',
      "Chef's Table Week",
    ],
    descriptions: [
      'For the movie buffs, show bingers, and gamers.',
      'Screens, stories, and a little escapism.',
      "For catching up on everything you've been meaning to watch or play.",
    ],
    objectives: [
      ObjectiveTemplate('Series episodes watched', 10, 50),
      ObjectiveTemplate('Movies watched', 3, 15),
      ObjectiveTemplate('Hours of gaming', 10, 50),
      ObjectiveTemplate('Meals cooked', 5, 21),
    ],
  ),
  ChallengeCategory(
    name: 'Leisure',
    flavorNames: [
      'Hobby Hours',
      'Passion Project Week',
      'Me-Time Sprint',
      'Slow Living Week',
      'Craft Corner Week',
      'Play Time Sprint',
      'Creative Hours',
      'Unwind Week',
      'Weekend Project Sprint',
      'Just Because Week',
      'Tinker Time',
      'Soul Refill Week',
    ],
    descriptions: [
      'Make time for the things you actually enjoy doing.',
      "For hobbies that don't need a good reason.",
      'A nudge to actually do the fun stuff.',
    ],
    objectives: [
      ObjectiveTemplate('Hours doing a hobby', 5, 30),
      ObjectiveTemplate('Board games played', 3, 15),
      ObjectiveTemplate('Sketches or drawings made', 5, 20),
      ObjectiveTemplate('Minutes gardening', 60, 300),
    ],
  ),
  ChallengeCategory(
    name: 'Outdoors',
    flavorNames: [
      'Fresh Air Week',
      'Trail Time',
      'Outdoor Streak',
      'Get Outside Sprint',
      'Nature Fix Week',
      'Sunshine Sprint',
      'Wander Week',
      'Explore Days',
      'Open Air Sprint',
      'Horizon Week',
      'Trailblazer Sprint',
      'Step Outside Days',
    ],
    descriptions: [
      'For time spent outside, wherever that takes you.',
      'Fresh air, one outing at a time.',
      'An excuse to get outside more often.',
    ],
    objectives: [
      ObjectiveTemplate('Walks', 8, 20),
      ObjectiveTemplate('Minutes outside', 120, 400),
      ObjectiveTemplate('Hikes', 2, 10),
      ObjectiveTemplate('Bike rides', 3, 15),
    ],
  ),
  ChallengeCategory(
    name: 'Social',
    flavorNames: [
      'Stay Connected Week',
      'Reach Out Sprint',
      'Together Time',
      'Catch Up Week',
      'Check-In Week',
      'Circle Time Sprint',
      'Community Days',
      'Friends First Week',
      'Ring Them Up Sprint',
      'Gather Round Week',
      'Close the Distance',
      'Show Up Week',
    ],
    descriptions: [
      'For staying close to the people who matter.',
      'A nudge to reach out more often.',
      'For keeping in touch, on purpose.',
    ],
    objectives: [
      ObjectiveTemplate('Calls to family or friends', 4, 12),
      ObjectiveTemplate('Get-togethers or visits', 2, 8),
      ObjectiveTemplate('Messages sent to catch up', 5, 20),
    ],
  ),
];

/// Duration options a generated challenge's deadline is randomly picked
/// from.
const challengeDurationDaysOptions = [7, 14, 30];
