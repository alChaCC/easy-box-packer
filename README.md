# EasyBoxPacker

Ref from [box_packer](https://github.com/mushishi78/box_packer)

and inspired by [A genetic algorithm for the three-dimensional bin packing problem with heterogeneous bins](https://www.researchgate.net/publication/273121476_A_genetic_algorithm_for_the_three-dimensional_bin_packing_problem_with_heterogeneous_bins) and [A New Heuristic Algorithm for the 3D Bin Packing Problem](https://www.researchgate.net/publication/226249396_A_New_Heuristic_Algorithm_for_the_3D_Bin_Packing_Problem)

## Installation

Add to gemfile:

``` ruby
gem  'easy-box-packer'
```

## Usage

### Check all items can be packed in a container

``` ruby
require 'easy-box-packer'

cont = EasyBoxPacker.pack(
  container: { dimensions: [15, 20, 13], weight_limit: 50 },
  items: [
    { dimensions: [2, 3, 5], weight: 47 },
    { dimensions: [2, 3, 5], weight: 47 },
    { dimensions: [3, 3, 1], weight: 24 },
    { dimensions: [1, 1, 4], weight: 7 },
  ]
)

cont[:packings].length # 3
cont[:packings][0][:weight] # 47.0
cont[:packings][0][:placements].length # 1
cont[:packings][0][:placements][0][:dimensions] # [2, 3, 5]
cont[:packings][0][:placements][0][:position] # [0, 0, 0]
cont[:packings][1][:weight] # 47.0
cont[:packings][1][:placements].length # 1
cont[:packings][1][:placements][0][:dimensions] # [2, 3, 5]
cont[:packings][1][:placements][0][:position] # [0, 0, 0]
cont[:packings][2][:weight] # 31.0
cont[:packings][2][:placements].length # 2
cont[:packings][2][:placements][0][:dimensions] # [1, 1, 4]
cont[:packings][2][:placements][0][:position] # [0, 0, 0]
cont[:packings][2][:placements][1][:dimensions] # [1, 3, 3]
cont[:packings][2][:placements][1][:position] # [0, 1, 0]
cont[:errors] # []
```

Notes:

- `weight_limit` and `weight` are optional; without `weight_limit` there is no weight restriction.
- Positions and dimensions of placements are in the container's frame with its
  dimensions sorted descending (e.g. `[20, 15, 13]` for the container above).
- Items that are too heavy, too big or have invalid dimensions (not three positive numbers)
  are reported in `errors` instead of being placed. An invalid container raises `ArgumentError`.

### Get a reasonable smallest container by given boxes

```ruby
container = EasyBoxPacker.find_smallest_container(
    items: Array.new(1000) {{ dimensions: [1, 1, 1] }}
  )
container # [10.0, 10.0, 10.0]
```

All sizes are in **cm**. The result is always floats sorted ascending, or `nil`
when no container satisfies the limits below. It is a heuristic: a small
container, not a proven minimum.

It works in two steps:

1. A quick heuristic that grows a container item by item.
2. A refining search over side lengths built from sums of item sides, which keeps
   the best container found until `time_limit` runs out. It is never worse than step 1.

```ruby
EasyBoxPacker.find_smallest_container(
  items: items,
  time_limit: 0.5,              # seconds (default 0.5). nil = no limit, 0 = step 1 only
  max_attempts: nil,            # max candidates test-packed; same result on every machine
  max_length: 120,              # longest side allowed (cm), e.g. your carrier's limit
  max_length_plus_girth: 300,   # length + 2 * (width + height) allowed (cm)
  cost: nil                     # custom cost, see below
)
```

`time_limit` is a soft limit for the whole call: step 1 always finishes, and
the test pack already running when the time runs out also finishes.

By default the cheapest container is the one with the smallest volume, then the
smallest length + girth. Carriers charge on dimensional weight (volume) plus
surcharges for long parcels, so pass your own `cost` to model your carrier.
It receives `[a, b, c]` in cm (sorted ascending), returns anything comparable
(lower is better), and must not decrease when a side grows:

```ruby
# dimensional weight (divisor 5000) + a surcharge when the longest side is over 60 cm
cost = ->(d) { (d.inject(:*) / 5000.0).ceil + (d.max > 60 ? 20 : 0) }
EasyBoxPacker.find_smallest_container(items: items, cost: cost)
```

### Choose boxes from the boxes you have

```ruby
result = EasyBoxPacker.select_box(
  boxes: [
    { id: 'S', dimensions: [20, 15, 10], weight_limit: 5,  cost: 10 },   # inside size in cm, kg
    { id: 'M', dimensions: [30, 25, 20], weight_limit: 10, cost: 18 },
    { id: 'L', dimensions: [45, 35, 30], weight_limit: 20, cost: 30 }
  ],
  items: [
    { id: 'mug',  dimensions: [12, 9, 9],  weight: 0.4 },
    { id: 'book', dimensions: [24, 17, 3], weight: 0.6 }
  ]
)

result[:boxes].first[:box][:id]                       # "M"
result[:boxes].first[:placements].map { |p| p[:item][:id] } # ["book", "mug"]
result[:boxes].first[:placements].first[:position]    # where to put it
result[:total_cost]                                   # 18
result[:unpacked]                                     # [] or [{ item:, reason: :too_big }]
```

It returns the cheapest single box that holds everything; when none does, it
fills the box that packs the most item volume per cost and repeats.

| option | default | meaning |
|---|---|---|
| `allow_multiple_boxes` | `true` | split items over several boxes when no single box fits |
| `padding` | `0` | cm of cushioning kept free on every side (a box's own `:padding` wins) |
| `cost` | `box[:cost]` or volume | lambda `box -> number`, lower is better |
| `max_items` | `nil` | raise `ArgumentError` when more items are given |
| `time_limit` | `nil` | soft limit in seconds; after it only the fastest strategy is used |
| `split_strategies`, `greedy_fallback` | | passed to `pack` |

`unpacked` reasons: `:invalid_dimensions`, `:too_big`, `:too_heavy`, `:no_single_box`.

Each box in the result also has `container_dimensions` (the frame the positions are in,
the third axis is up) and every placement has `step:` and `support:`, see below.

### Shipping with DIM weight couriers (FedEx, DHL Express, Aramex, ...)

These couriers charge the bigger of the actual weight and the dimensional weight
(outer length x width x height / divisor). `chargeable_weight_cost` builds a `cost`
for `select_box` that does this:

```ruby
cost = EasyBoxPacker.chargeable_weight_cost(
  divisor: 5000,            # cm3 per kg
  weight_increment: 0.5,    # round the chargeable weight up to 0.5 kg
  dimension_increment: 1,   # round each side up to a whole cm first
  rate: nil                 # optional ->(kg) { price }, otherwise the cost is the kg
)

EasyBoxPacker.select_box(
  boxes: [
    { id: 'M', dimensions: [30, 25, 20], outer_dimensions: [31, 26, 21.5], weight: 0.3 } # weight = empty box, kg
  ],
  items: items,
  cost: cost
)[:total_cost] # total chargeable kg (or price with rate:)
```

The divisor and rounding differ by carrier, service and contract. 5000 cm3/kg is
the common one, but some services use 6000. Check the numbers on your own account.

Any `cost` lambda that takes two arguments `(box, weight)` is called with the weight
packed in that box; a one-argument lambda gets only the box.

### Upright and fragile items

```ruby
{ dimensions: [8, 8, 25], upright: true }  # dimensions[2] is the height and stays vertical
{ dimensions: [20, 15, 6], fragile: true } # nothing is placed on top of it
```

The box may be stood on another side to fit upright items; the frame used is returned
as `container_dimensions` (`pack`) and the third axis is up. With constraints the flat
stacking fallback is not used.

### Loading order

`EasyBoxPacker.loading_order(placements)` sorts placements bottom layer first, then
from the back corner, and adds `step:` (1, 2, ...) and `support:`, the share of the
item's bottom resting on the floor or on items below. `support` below 1.0 means the
item overhangs empty space, fill it with cushioning or warn the packer.
`select_box` already adds both keys to its placements.

### Tuning options

| option | methods | default | meaning |
|---|---|---|---|
| `split_strategies` | all | `EasyBoxPacker::SPLIT_STRATEGIES` | free space split strategies tried in order (`:legacy`, `:max_space`, `0`..`5`). `[:legacy]` is fastest |
| `greedy_fallback` | all | `true` | return all items stacked flat when that fits but packing needs more containers |
| `beam_width` | `find_smallest_container` | `1` | candidates kept per step of the heuristic search |
| `max_side_values` | `find_smallest_container` | `1000` | max distinct side lengths tried per axis while refining |

Every placement includes `item:`, the item hash you passed in, so you can tell
which item goes where.

### Using it from a web API

- All state is passed in, nothing global is changed, so it is safe to call from
  several threads.
- Keys must be symbols: parse JSON with `JSON.parse(body, symbolize_names: true)`.
- It is CPU bound. Set `max_items` and `time_limit`, and run it outside the request
  thread (a job queue) or with a request timeout.

## Development

```
bundle install
bundle exec rspec easy-box-packer_spec.rb
```

## Changelog

### 0.4.0

- Item constraints: `upright: true` and `fragile: true`.
- `loading_order` with `step:` and `support:`; `select_box` placements include them.
- `chargeable_weight_cost` for DIM weight couriers, boxes take `outer_dimensions` and `weight`.
- `cost` lambdas taking `(box, weight)` get the packed weight.
- `pack` and `select_box` results include `container_dimensions`.

### 0.3.0

- New `select_box`: choose boxes from your own box list (cost, weight limit, padding,
  several boxes when needed) and get the placements.
- Placements include the original `item:`.
- `split_strategies`, `greedy_fallback`, `beam_width` and `max_side_values` can be passed in.

### 0.2.0

- `find_smallest_container` refines its first answer with a search over side lengths,
  e.g. case 7 goes from 30 x 30 x 220 to 30 x 55 x 110 (smaller and much shorter).
- New options: `time_limit`, `max_attempts`, `max_length`, `max_length_plus_girth`, `cost`.
- Sizes are documented as cm.

### 0.1.0

- Fix: the stacking fallback returned overlapping / out-of-bounds placements.
- Fix: a missing `weight_limit` rejected every item that had a weight.
- Fix: the stacked ("greedy") container height was rounded down (e.g. 1.04 -> 1.0), producing a container that is too small.
- Fix: `find_smallest_container` crashed on empty items or when no candidate fit.
- Fix: invalid dimensions (zero, negative, non numeric) were silently "placed".
- Fix: float tolerance when comparing sizes.
- Improve: try more ways of splitting free space, so fewer containers are needed and
  `find_smallest_container` finds smaller containers.
- Change: `find_smallest_container` always returns floats sorted ascending.
- Require Ruby >= 2.7, rspec ~> 3.13, drop pry.
