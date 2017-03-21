module EasyBoxPacker
  class << self
    def pack(container:, items:)
      packings = []
      errors   = []
      # pack from biggest to smallest
      items.sort_by { |h| h[:dimensions].sort }.reverse.each do |item|
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

    def place(item, space)
      item_width, item_height, item_length = item[:dimensions].sort.reverse

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
      ]
    end

    def find_smallest_container(items:)
      array_of_lwh            = items.map { |i| i[:dimensions].sort.reverse }
      items_max_length        = array_of_lwh.max { |x, y| x[0] <=> y[0] }[0]
      items_max_width         = array_of_lwh.max { |x, y| x[1] <=> y[1] }[1]
      items_min_height        = array_of_lwh.max { |x, y| x[2] <=> y[2] }[2]
      items_total_height      = array_of_lwh.inject(0) { |sum, x| sum + x[2] }.round(1)
      miminum_box = {}
      (items_min_height..items_total_height.ceil).step(0.1).to_a.bsearch do |i|
        packing = pack(
          container: { dimensions: [items_max_length, items_max_width, i] },
          items: array_of_lwh.map { |a| { dimensions: a }})

        if packing[:packings].size == 1
          miminum_box = {
                          length: items_max_length,
                          width: items_max_width,
                          height: i
                        }
          true
        else
          false
        end
      end
      miminum_box
    end
  end
end
