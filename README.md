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
cont[:packings][0][:weight] # 47
cont[:packings][0][:placements].length # 1
cont[:packings][0][:placements][0][:dimensions] # [2, 3, 5]
cont[:packings][0][:placements][0][:position] # [0, 0, 0]
cont[:packings][1][:weight] # 47
cont[:packings][1][:placements].length # 1
cont[:packings][1][:placements][0][:dimensions] # [2, 3, 5]
cont[:packings][1][:placements][0][:position] # [0, 0, 0]
cont[:packings][2][:weight] # 31
cont[:packings][2][:placements].length # 2
cont[:packings][2][:placements][0][:dimensions] # [1, 3, 3]
cont[:packings][2][:placements][0][:position] # [0, 0, 0]
cont[:packings][2][:placements][1][:dimensions] # [4, 1, 1]
cont[:packings][2][:placements][1][:position] # [3, 0, 0]
```

### Get a reasonable smallest container by given boxes

```
container = EasyBoxPacker.find_smallest_container(
    items: Array.new(1000) {{ dimensions: [1, 1, 1] }}
  )
container # [10, 10, 10]
```
