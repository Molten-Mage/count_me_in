// Mirrors lib/data/challenge_templates.dart - keep both in sync if the
// template pool changes. Duplicated here (rather than shared) because
// Cloud Functions run on Node, not Dart; there's no cross-runtime way to
// share this data source.
const challengeCategories = [
  {
    name: "Fitness",
    flavorNames: [
      "Fitness Sprint",
      "The Grind",
      "Strength Sprint",
      "Sweat Sesh",
      "Rise & Move",
      "Iron Will Sprint",
      "Burn It Up",
    ],
    descriptions: [
      "A fitness sampler - a little of everything.",
      "Movement, your way - mix and match as you go.",
      "Get the body moving, one rep at a time.",
    ],
    objectives: [
      {name: "Push-ups", minTarget: 50, maxTarget: 150},
      {name: "Squats", minTarget: 50, maxTarget: 150},
      {name: "Minutes of walking", minTarget: 60, maxTarget: 200},
      {name: "Pull-ups", minTarget: 20, maxTarget: 50},
      {name: "Lunges", minTarget: 50, maxTarget: 150},
      {name: "Burpees", minTarget: 20, maxTarget: 60},
      {name: "Jumping jacks", minTarget: 50, maxTarget: 150},
      {name: "Minutes planking", minTarget: 10, maxTarget: 40},
    ],
  },
  {
    name: "Health",
    flavorNames: [
      "Hydrate & Feel Great",
      "Wellness Reset",
      "Balance Sprint",
      "Steady Habits",
      "Nourish & Rest",
    ],
    descriptions: [
      "Small daily habits, stacked up over the challenge.",
      "Little resets, repeated until they stick.",
      "Everyday choices that add up over time.",
    ],
    objectives: [
      {name: "Glasses of water", minTarget: 30, maxTarget: 70},
      {name: "Minutes of stretching", minTarget: 30, maxTarget: 100},
      {name: "Steps", minTarget: 10000, maxTarget: 50000},
      {name: "Alcohol-free days", minTarget: 15, maxTarget: 25},
      {
        name: "Days without unnecessary purchases",
        minTarget: 15,
        maxTarget: 25,
      },
    ],
  },
  {
    name: "Mind",
    flavorNames: [
      "Reading Sprint",
      "Page Turner Sprint",
      "Bookworm Sprint",
      "Wind Down Sprint",
    ],
    descriptions: [
      "For the reflective and the well-read.",
      "Slow down and make space to think.",
      "Words, quiet, and a little reflection.",
    ],
    objectives: [
      {name: "Pages read", minTarget: 100, maxTarget: 300},
      {name: "Minutes reading", minTarget: 150, maxTarget: 400},
      {name: "Minutes meditating", minTarget: 60, maxTarget: 200},
      {name: "Gratitude entries", minTarget: 7, maxTarget: 30},
      {name: "Books finished", minTarget: 2, maxTarget: 6},
    ],
  },
  {
    name: "Productivity",
    flavorNames: [
      "Deep Work Sprint",
      "Side Project Sprint",
      "Inbox Zero Sprint",
      "Momentum Sprint",
      "Clear the Decks",
      "Task Force Sprint",
      "Output Sprint",
    ],
    descriptions: [
      "Get things done, one tally at a time.",
      "Turn intentions into finished things.",
      "For clearing the list and making progress.",
    ],
    objectives: [
      {name: "Tasks completed", minTarget: 10, maxTarget: 40},
      {name: "Minutes of focused work", minTarget: 200, maxTarget: 600},
      {name: "Hours on a side project", minTarget: 5, maxTarget: 30},
      {name: "Emails cleared", minTarget: 20, maxTarget: 100},
      {name: "Errands completed", minTarget: 5, maxTarget: 20},
    ],
  },
  {
    name: "Culture",
    flavorNames: [
      "Full Indulgence",
      "Popcorn Sprint",
      "Session Sprint",
      "Rewatch Sprint",
    ],
    descriptions: [
      "For the movie buffs, show bingers, and gamers.",
      "Screens, stories, and a little escapism.",
      "For catching up on everything you've been meaning to watch or " +
        "play.",
    ],
    objectives: [
      {name: "Series episodes watched", minTarget: 10, maxTarget: 50},
      {name: "Movies watched", minTarget: 3, maxTarget: 15},
      {name: "Hours of gaming", minTarget: 10, maxTarget: 50},
      {name: "Meals cooked", minTarget: 5, maxTarget: 21},
      {name: "Podcast episodes listened to", minTarget: 10, maxTarget: 30},
      {name: "New recipes tried", minTarget: 2, maxTarget: 10},
    ],
  },
  {
    name: "Leisure",
    flavorNames: [
      "Hobby Hours",
      "Me-Time Sprint",
      "Play Time Sprint",
      "Creative Hours",
      "Tinker Time",
    ],
    descriptions: [
      "Make time for the things you actually enjoy doing.",
      "For hobbies that don't need a good reason.",
      "A nudge to actually do the fun stuff.",
    ],
    objectives: [
      {name: "Hours doing a hobby", minTarget: 5, maxTarget: 30},
      {name: "Board games played", minTarget: 3, maxTarget: 15},
      {name: "Sketches or drawings made", minTarget: 5, maxTarget: 20},
      {name: "Minutes gardening", minTarget: 60, maxTarget: 300},
    ],
  },
  {
    name: "Outdoors",
    flavorNames: [
      "Trail Time",
      "Outdoor Streak",
      "Get Outside Sprint",
      "Sunshine Sprint",
      "Open Air Sprint",
      "Trailblazer Sprint",
    ],
    descriptions: [
      "For time spent outside, wherever that takes you.",
      "Fresh air, one outing at a time.",
      "An excuse to get outside more often.",
    ],
    objectives: [
      {name: "Walks", minTarget: 8, maxTarget: 20},
      {name: "Minutes outside", minTarget: 120, maxTarget: 400},
      {name: "Hikes", minTarget: 2, maxTarget: 10},
      {name: "Bike rides", minTarget: 3, maxTarget: 15},
    ],
  },
  {
    name: "Social",
    flavorNames: [
      "Reach Out Sprint",
      "Together Time",
      "Circle Time Sprint",
      "Ring Them Up Sprint",
      "Close the Distance",
    ],
    descriptions: [
      "For staying close to the people who matter.",
      "A nudge to reach out more often.",
      "For keeping in touch, on purpose.",
    ],
    objectives: [
      {name: "Calls to family or friends", minTarget: 4, maxTarget: 12},
      {name: "Get-togethers or visits", minTarget: 2, maxTarget: 8},
      {name: "Messages sent to catch up", minTarget: 5, maxTarget: 20},
    ],
  },
];

const challengeDurationDaysOptions = [7, 14, 30];

module.exports = {challengeCategories, challengeDurationDaysOptions};
