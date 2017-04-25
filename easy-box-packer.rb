module EasyBoxPacker
  class << self
    def pack(container:, items:)
      packings = []
      errors   = []
      # pack from biggest to smallest
      items.sort_by { |h| h[:dimensions].sort.reverse }.reverse.each do |item|
        # If the item is just too big for the container lets give up on this
        if item[:weight].to_f > container[:weight_limit].to_f
          errors << "Item: #{item} is too heavy for container"
          next
        end

        # Need a bool so we can break out nested loops once it's been packed
        item_has_been_packed = false

        packings.each do |packing|
          # If this packings going to be too big with this
          # item as well then skip on to the next packing
          next if packing[:weight].to_f + item[:weight].to_f > container[:weight_limit].to_f

          # remove volume size = 0 (not possible to pack)
          packing[:spaces].reject! { |space| space[:dimensions].inject(:*) == 0 }
          # try minimum space first
          packing[:spaces].sort_by { |h| h[:dimensions].sort }.each do |space|
            # Try placing the item in this space,
            # if it doesn't fit skip on the next space
            next unless placement = place(item, space)
            # Add the item to the packing and
            # break up the surrounding spaces
            packing[:placements] += [placement]
            packing[:weight] += item[:weight].to_f
            packing[:spaces] -= [space]
            packing[:spaces] += break_up_space(space, placement)
            item_has_been_packed = true
            break
          end
          break if item_has_been_packed
        end
        next if item_has_been_packed

        # Can't fit in any of the spaces for the current packings
        # so lets try a new space the size of the container
        space = {
          dimensions: container[:dimensions].sort.reverse,
          position: [0, 0, 0]
        }
        placement = place(item, space)

        # If it can't be placed in this space, then it's just
        # too big for the container and we should abandon hope
        unless placement
          errors << "Item: #{item} cannot be placed in container"
          next
        end
        # Otherwise lets put the item in a new packing
        # and break up the remaing free space around it
        packings += [{
          placements: [placement],
          weight: item[:weight].to_f,
          spaces: break_up_space(space, placement)
        }]
      end

      { packings: packings, errors: errors }
    end

    def find_smallest_container(items:)
      possible_containers = []
      invalid_containers  = []

      min_vol = items.map { |h| h[:dimensions].inject(&:*) }.inject(&:+)
      # order items from biggest to smallest
      sorted_items = items.sort_by { |h| h[:dimensions].sort }.reverse

      # base_container = sorted_items.first
      based_container = sorted_items.first

      if sorted_items.size == 1
        return based_container[:dimensions]
      end

      find_possible_container(
        possible_containers: possible_containers,
        invalid_containers: invalid_containers,
        container: based_container[:dimensions],
        items: sorted_items.map {|i| i[:dimensions]},
        item_index: 1,
        min_vol: min_vol)

      possible_containers.map { |a| a.sort }.sort_by { |a| [a.inject(&:*), a.inject(&:+)] }.each do |c|
        packing = pack(
          container: { dimensions: c },
          items: items)
        return c if packing[:packings].size == 1
      end
    end

    private

    def std(contents)
      n = contents.size
      contents.map!(&:to_f)
      mean = contents.reduce(&:+)/n
      sum_sqr = contents.map {|x| x * x}.reduce(&:+)
      Math.sqrt((sum_sqr - n * mean * mean)/(n-1))
    end

    def find_possible_container(possible_containers:,invalid_containers:,container:, items:, item_index:, min_vol:)
      return unless items[item_index]
      c_length, c_width, c_height = container.sort.reverse
      b_length, b_width, b_height = items[item_index].sort.reverse
      c_permutations = [
        [c_width,  c_height, c_length],
        [c_length, c_width,  c_height],
        [c_length, c_height, c_width]
      ]
      b_permutations = [
        [b_width,  b_height, b_length],
        [b_length, b_width,  b_height],
        [b_length, b_height, b_width]
      ]

      tmp_possible_containers = []
      # (1) loops base_container 3 rotations
      c_permutations.each do |c_perm|
        # (2) try to puts items to 3 points, then it will create 3 different possible containers
        b_permutations.each do |b_perm|
          tmp_possible_containers << [  c_perm[0] + b_perm[0],     [c_perm[1], b_perm[1]].max, [c_perm[2], b_perm[2]].max]
          tmp_possible_containers << [ [c_perm[0], b_perm[0]].max,  c_perm[1] + b_perm[1],     [c_perm[2], b_perm[2]].max]
          tmp_possible_containers << [ [c_perm[0], b_perm[0]].max, [c_perm[1], b_perm[1]].max,  c_perm[2]+ b_perm[2]]
        end
      end
      removed_tried_container = tmp_possible_containers.map { |a| a.sort }.uniq - possible_containers - invalid_containers

      return unless removed_tried_container.any?
      # (3) loop all container from smallest spaces to biggest space
      removed_tried_container.sort_by { |a| [a.inject(&:*), a.inject(&:+)] }.each do |cont|
        # (4) next unless l * w * h >= minimum_space
        if cont.inject(&:*) >= min_vol
          possible_containers << cont
        # else
          # puts "invalid: #{cont}"
          # invalid_containers << cont
          # find_possible_container(possible_containers: possible_containers, invalid_containers: invalid_containers, container: cont, items: items, item_index: item_index + 1, min_vol: min_vol)
        end
      end
      # minimum_space = (removed_tried_container).sort_by { |a| [a.inject(&:*), a.inject(&:+)] }.first
      minimum_std = removed_tried_container.sort_by { |a| [std(a), a.inject(&:*), a.inject(&:+)] }.first
      [minimum_std].uniq.compact.each do |cont|
        find_possible_container(possible_containers: possible_containers, invalid_containers: invalid_containers, container: cont, items: items, item_index: item_index + 1, min_vol: min_vol)
      end
    end

    def place(item, space)
      item_length, item_width, item_height = item[:dimensions].sort.reverse

      permutations = [
        [item_width, item_height, item_length],
        [item_width, item_length, item_height],
        [item_height, item_width, item_length],
        [item_height, item_length, item_width],
        [item_length, item_width, item_height],
        [item_length, item_height, item_width]
      ]

      possible_rotations_and_margins = []

      permutations.each do |perm|
        # Skip if the item does not fit with this orientation
        next unless perm[0] <= space[:dimensions][0] &&
          perm[1] <= space[:dimensions][1] &&
          perm[2] <= space[:dimensions][2]

        possible_margin   = [space[:dimensions][0] - perm[0], space[:dimensions][1] - perm[1], space[:dimensions][2] - perm[2]]
        possible_rotations_and_margins << { margin: possible_margin, rotation: perm }
      end

      # select rotation with smallest margin
      final = possible_rotations_and_margins.sort_by { |a| a[:margin].sort }.first
      return unless final
      return {
        dimensions: final[:rotation],
        position: space[:position],
        weight: item[:weight].to_f
      }
    end

    def break_up_space(space, placement)
      return_possible_spaces = [
        # HEIGHT SPACE => WIDTH  => LENGTH
        [
          {
            dimensions: [
              space[:dimensions][0],
              space[:dimensions][1],
              space[:dimensions][2] - placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1],
              space[:position][2] + placement[:dimensions][2]
            ]
          },
          {
            dimensions: [
              space[:dimensions][0],
              space[:dimensions][1] - placement[:dimensions][1],
              placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1] + placement[:dimensions][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              space[:dimensions][0] - placement[:dimensions][0],
              placement[:dimensions][1],
              placement[:dimensions][2]
            ],
            position: [
              space[:position][0] + placement[:dimensions][0],
              space[:position][1],
              space[:position][2]
            ]
          }
        ],
        # HEIGHT SPACE => LENGTH => WIDTH
        [
          {
            dimensions: [
              space[:dimensions][0],
              space[:dimensions][1],
              space[:dimensions][2] - placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1],
              space[:position][2] + placement[:dimensions][2]
            ]
          },
          {
            dimensions: [
              space[:dimensions][0] - placement[:dimensions][0],
              space[:dimensions][1],
              placement[:dimensions][2]
            ],
            position: [
              space[:position][0] + placement[:dimensions][0],
              space[:position][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              placement[:dimensions][0],
              space[:dimensions][1] - placement[:dimensions][1],
              placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1] + placement[:dimensions][1],
              space[:position][2]
            ]
          }
        ],
        # LENGTH SPACE => HEIGHT => WIDTH
        [
          {
            dimensions: [
              space[:dimensions][0] - placement[:dimensions][0],
              space[:dimensions][1],
              space[:dimensions][2]
            ],
            position: [
              space[:position][0] + placement[:dimensions][0],
              space[:position][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              placement[:dimensions][0],
              space[:dimensions][1],
              space[:dimensions][2] - placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1],
              space[:position][2] + placement[:dimensions][2]
            ]
          },
          {
            dimensions: [
              placement[:dimensions][0],
              space[:dimensions][1] - placement[:dimensions][1],
              placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1] + placement[:dimensions][1],
              space[:position][2]
            ]
          }
        ],
        # LENGTH SPACE => WIDTH  => HEIGHT
        [
          {
            dimensions: [
              space[:dimensions][0] - placement[:dimensions][0],
              space[:dimensions][1],
              space[:dimensions][2]
            ],
            position: [
              space[:position][0] + placement[:dimensions][0],
              space[:position][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              placement[:dimensions][0],
              space[:dimensions][1] - placement[:dimensions][1],
              space[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1] + placement[:dimensions][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              placement[:dimensions][0],
              placement[:dimensions][1],
              space[:dimensions][2] - placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1],
              space[:position][2] + placement[:dimensions][2]
            ]
          }
        ],
        # WIDTH SPACE  => LENGTH => HEIGHT
        [
          {
            dimensions: [
              space[:dimensions][0],
              space[:dimensions][1] - placement[:dimensions][1],
              space[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1] + placement[:dimensions][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              space[:dimensions][0] - placement[:dimensions][0],
              placement[:dimensions][1],
              space[:dimensions][2]
            ],
            position: [
              space[:position][0] + placement[:dimensions][0],
              space[:position][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              placement[:dimensions][0],
              placement[:dimensions][1],
              space[:dimensions][2] - placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1],
              space[:position][2] + placement[:dimensions][2]
            ]
          }
        ],
        # WIDTH SPACE  => HEIGHT => LENGTH
        [
          {
            dimensions: [
              space[:dimensions][0],
              space[:dimensions][1] - placement[:dimensions][1],
              space[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1] + placement[:dimensions][1],
              space[:position][2]
            ]
          },
          {
            dimensions: [
              space[:dimensions][0],
              placement[:dimensions][1],
              space[:dimensions][2] - placement[:dimensions][2]
            ],
            position: [
              space[:position][0],
              space[:position][1],
              space[:position][2] + placement[:dimensions][2]
            ]
          },
          {
            dimensions: [
              space[:dimensions][0] - placement[:dimensions][0],
              placement[:dimensions][1],
              placement[:dimensions][2]
            ],
            position: [
              space[:position][0] + placement[:dimensions][0],
              space[:position][1],
              space[:position][2]
            ]
          }
        ]
      ]
      # PICK biggest
      return_possible_spaces.sort_by { |a| a.map {|aa| aa[:dimensions].sort}}.last
    end
  end
end
