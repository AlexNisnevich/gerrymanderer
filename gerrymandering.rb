require 'descriptive_statistics'
require 'statsample'

NUM_DISTRICTS = 18

MIN_REPUBLICAN_SEATS = 11
MEAN_MEDIAN_DIFF_CUTOFF = 0.3
T_TEST_P_CUTOFF = 0.05
MIN_VOTE = 0.15
MAX_VOTE = 0.85
MIN_TOTAL_SHARE = 0.494999
MAX_TOTAL_SHARE = 0.505001

SEATS_WEIGHT = 0.5
EVASION_WEIGHT = 2
DURABILITY_TIL_10_PCT_WEIGHT = 4
DURABILITY_PAST_10_PCT_WEIGHT = 1

INSUFFICIENT_SEATS_PENALTY = -100
VOTE_SHARE_NOT_IN_RANGE_PENALTY = -10

MAX_ITERATIONS = 100000
NUM_MUTATIONS_PER_ITERATION = 10

class Array
  def n_valid
    length
  end
end

def dem_wins(dem_vote_pct)
  dem_vote_pct.select {|v| v > 0.5}
end

def rep_wins(dem_vote_pct)
  dem_vote_pct.select {|v| v < 0.5}
              .map {|v| 1.0 - v}
end

def num_rep_seats(dem_vote_pct)
  rep_wins(dem_vote_pct).length
end

def total_dem_vote_share(dem_vote_pct)
  dem_vote_pct.mean
end

def mean_median_difference(vote_pct)
  n = vote_pct.length
  mean = vote_pct.mean
  median = vote_pct.median
  sum_sqr = vote_pct.map {|x| x ** 2}.reduce(&:+)
  std_dev = Math.sqrt((sum_sqr - n * mean * mean)/(n-1))
  (mean - median) / std_dev
end

def t_test_p(vote_pct)
  d, r = dem_wins(vote_pct), rep_wins(vote_pct)
  t = Statsample::Test.t_two_samples_independent(r, d, tails: :left)
  t.probability_equal_variance
rescue
  0
end

def durability_score(vote_pct)
  vote_pct.map {|v| (v - 0.5).abs }.min * 2
end

def evasion_score(vote_pct)
  [(MEAN_MEDIAN_DIFF_CUTOFF - mean_median_difference(vote_pct)), t_test_p(vote_pct) - T_TEST_P_CUTOFF].min
rescue
  -100
end

def score(vote_pct)
  seats = num_rep_seats(vote_pct)
  dem_vote_share = total_dem_vote_share(vote_pct)
  durability = durability_score(vote_pct)
  evasion = evasion_score(vote_pct)

  pcts_valid = vote_pct.all? {|p| p >= MIN_VOTE && p <= MAX_VOTE}
  vote_share_valid = dem_vote_share >= MIN_TOTAL_SHARE && dem_vote_share <= MAX_TOTAL_SHARE
  num_tests_passed = evasion > 0 ? 2 :
    (mean_median_difference(vote_pct) <= MEAN_MEDIAN_DIFF_CUTOFF ? 1 : 0) + (t_test_p(vote_pct) >= T_TEST_P_CUTOFF ? 1 : 0)

  seats_component = (seats < MIN_REPUBLICAN_SEATS) ? INSUFFICIENT_SEATS_PENALTY : (seats - MIN_REPUBLICAN_SEATS) * SEATS_WEIGHT
  test_component = vote_share_valid ? (pcts_valid ? num_tests_passed : 0) : VOTE_SHARE_NOT_IN_RANGE_PENALTY
  durability_component = durability < 0.03 ? -1 :
    ([durability, 0.1].min * DURABILITY_TIL_10_PCT_WEIGHT) + [(durability - 0.1), 0].min * DURABILITY_PAST_10_PCT_WEIGHT
  evasion_component = evasion < 0.02 ? -1 : evasion * EVASION_WEIGHT

  seats_component + test_component + durability_component + evasion_component
end

def mutate(dem_vote_pct, total_num_mutations, alpha = 0.5)
  new_vote_pct = dem_vote_pct.clone
  num_mutations = 0

  while num_mutations < total_num_mutations
    idx = Random.rand(NUM_DISTRICTS)
    delta = ((Random.rand - 0.5) * alpha).round(3)
    new_val = new_vote_pct[idx] + delta

    if new_val >= MIN_VOTE && new_val <= MAX_VOTE
      new_vote_pct[idx] = new_val
      num_mutations += 1
    end
  end

  new_vote_pct
end

def print_summary(dem_vote_pct)
  puts "-----------"
  puts score(dem_vote_pct)
  p dem_vote_pct.sort.map {|p| p.round(3) }
  puts "Seats: #{num_rep_seats(dem_vote_pct)}, " +
    "Durability: #{durability_score(dem_vote_pct).round(6)}, " +
    "Evasion: #{evasion_score(dem_vote_pct).round(6)}"
end

start_pct = Array.new(NUM_DISTRICTS, 0.5)

# Pennsylvania 2012
# start_pct = [84.9, 90.5, 42.8, 36.6, 37.1, 42.9, 40.6, 43.4, 38.3, 34.4, 41.5, 48.3, 69.1, 76.9, 43.2, 41.6, 60.3, 36.0].map {|p| p / 100}

iter = 0
current_pct = start_pct
current_score = score(current_pct)
print_summary(current_pct)

loop do
  iter += 1
  alpha = 1.0 / ((iter / (MAX_ITERATIONS / 10)) + 1)
  new_pct = mutate(current_pct, NUM_MUTATIONS_PER_ITERATION, alpha)

  if score(new_pct) > current_score
    current_pct = new_pct
    current_score = score(current_pct)
    print_summary(current_pct)
    iter = 0
  elsif iter > MAX_ITERATIONS
    current_pct = start_pct
    current_score = score(current_pct)
    puts ""
    puts "-- RESTARTING --"
    puts ""
    iter = 0
  end
end
