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

The result is always floats sorted ascending. It is a heuristic: a reasonably
shaped small container, not a proven minimum.

## Development

```
bundle install
bundle exec rspec easy-box-packer_spec.rb
```

## Changelog

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
