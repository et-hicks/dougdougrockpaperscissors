local flags = {}

flags.SHIELD_COLOR = { 0.3, 0.6, 1.0, 0.9 }
flags.SHIELD_LINE_WIDTH = 2
flags.SPAWN_DELAY = 0.1
flags.DEFAULT_SPEED = 45
flags.WIN_SPEED = 100
flags.PADDING = 24
flags.TEXT_GAP = 6
flags.SIDEBAR_WIDTH = 400
flags.SIDEBAR_GAP = 8
flags.SURVIVOR_PATH = "players/survivors.txt"

flags.CLASS_BASE_SPEED_BONUS = {
  Rock = 0.05,
  Paper = 0.10,
  Scissors = 0.20,
}

flags.JITTER_DISTANCE = 8
flags.BEATS = {
  Rock = "Scissors",
  Paper = "Rock",
  Scissors = "Paper",
}
flags.BASE_SHIELD_BONUS = 1
flags.ROCK_BONUS_SHIELD = 2
flags.PAPER_SPEED_MULTIPLIER = 0.30
flags.SCISSORS_SHIELD_TWO_CHANCE = 0.5
flags.SCISSORS_SHIELD_ONE_THRESHOLD = 0.8
flags.SCISSORS_SHIELD_TWO_VALUE = 2
flags.SCISSORS_SHIELD_ONE_VALUE = 1
flags.SCISSORS_SHIELD_THREE_VALUE = 3
flags.SCISSORS_SPEED_DURATION = 0.10
flags.SCISSORS_SHRINK_PERCENT = 0.05
flags.DEFAULT_SPEED_BONUS = 0.05

return flags
