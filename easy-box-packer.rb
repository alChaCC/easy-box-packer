module EasyBoxPacker
  # Tolerance for floating point comparisons (e.g. 0.1 + 0.2 vs 0.3).
  EPSILON = 1e-9

  # Ways of choosing how the free space around a placement is split.
  # :legacy is the original heuristic and is always tried first so results
  # that already fit in one container are unchanged; the others are only
  # tried when :legacy needs more than one container.
  SPLIT_STRATEGIES = [:legacy, :max_space, 0, 1, 2, 3, 4, 5].freeze

  # Number of candidates kept at each step of the smallest container search.
  # 1 reproduces the original search (follow the most cube-like candidate).
  SEARCH_BEAM_WIDTH = 1

  # Default seconds find_smallest_container spends refining its first answer.
  DEFAULT_TIME_LIMIT = 0.5

  # Max distinct side lengths tried per axis while refining.
  MAX_SIDE_VALUES = 1000

  class << self
    # All placements are expressed in the container's frame with its
    # dimensions sorted descending (length >= width >= height).
    def pack(container:, items:)
      validate_container!(container)
      weight_limit = weight_limit_of(container)

      best = nil
      SPLIT_STRATEGIES.each do |strategy|
        result = pack_with_strategy(container, items, weight_limit, strategy)
        best = result if best.nil? || result[:packings].size < best[:packings].size
        break if best[:packings].size <= 1
      end

      if best[:packings].size > 1 && check_container_is_bigger_than_greedy_box(container, items)
        { packings: generate_packing_for_greedy_box(container, items), errors: [] }
      else
        best
      end
    end

    # Find a small container (dimensions in cm, floats sorted ascending) that holds all items.
    #
    # time_limit            - soft limit in seconds for the whole call (default 0.5): no new
    #                         candidate is tried after it, the first heuristic answer is always
    #                         computed. nil = no time limit, 0 = skip refining (0.1.0 behaviour).
    # max_attempts          - max number of candidate containers test-packed while refining.
    #                         Unlike time_limit it gives the same result on every machine. nil = no limit.
    # max_length            - longest side allowed (cm), e.g. a carrier limit.
    # max_length_plus_girth - max length + 2 * (width + height) allowed (cm).
    # cost                  - lambda taking [a, b, c] (sorted ascending, cm) and returning a Comparable,
    #                         lower is better. It must not decrease when a side grows.
    #                         Default: [volume, length + girth].
    #
    # Returns nil when no container satisfies max_length / max_length_plus_girth.
    def find_smallest_container(items:, time_limit: DEFAULT_TIME_LIMIT, max_attempts: nil,
                                max_length: nil, max_length_plus_girth: nil, cost: nil)
      raise ArgumentError, 'items must not be empty' if items.nil? || items.empty?
      items.each do |item|
        raise ArgumentError, "invalid dimensions for item: #{item}" unless valid_dimensions?(item[:dimensions])
      end
      validate_non_negative!(:time_limit, time_limit)
      validate_non_negative!(:max_attempts, max_attempts)
      validate_non_negative!(:max_length, max_length)
      validate_non_negative!(:max_length_plus_girth, max_length_plus_girth)
      raise ArgumentError, 'cost must respond to #call' if cost && !cost.respond_to?(:call)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limits = { max_length: max_length, max_length_plus_girth: max_length_plus_girth }
      start = heuristic_smallest_container(items)
      start = nil unless within_limits?(start, limits)
      return start && normalize(start) if items.size == 1

      best = refine_container(
        items, start,
        deadline: time_limit && started_at + time_limit, max_attempts: max_attempts, limits: limits, cost: cost
      )
      best && normalize(best)
    end

    private

    # Original search: grow a container item by item, then compare with the greedy box.
    def heuristic_smallest_container(items)
      # order items from biggest to smallest
      sorted_items = items.sort_by { |h| h[:dimensions].sort }.reverse
      return sorted_items.first[:dimensions] if sorted_items.size == 1

      min_vol = items.map { |h| h[:dimensions].inject(:*) }.inject(:+)
      possible_containers = find_possible_containers(
        container: sorted_items.first[:dimensions],
        items: sorted_items.map { |i| i[:dimensions] },
        min_vol: min_vol
      )

      select_container = possible_containers
        .sort_by { |a| [volume(a), a.inject(:+)] }
        .find { |c| fits_in_one?(c, items) }

      # The greedy box (all items laid flat and stacked) always fits.
      greedy_box = item_greedy_box(items)
      prefer_greedy_box?(greedy_box, select_container) ? greedy_box : select_container
    end

    # Every container side is (at most) a sum of item sides, so enumerate sides
    # (a <= b <= c) from those sums and test-pack candidates that would be cheaper
    # than the best one found so far. Starts from `best` so it is never worse.
    def refine_container(items, best, deadline:, max_attempts:, limits:, cost:)
      return best if max_attempts == 0
      return best if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      cost_of  = cost || method(:default_cost)

      sorted = items.map { |i| i[:dimensions].sort }
      min_a, min_b, min_c = (0..2).map { |k| sorted.map { |d| d[k] }.max }
      min_vol = sorted.sum { |d| volume(d) }

      best      = best && best.map(&:to_f).sort
      best_cost = best && cost_of.call(best)
      beats_best = ->(dims) { best.nil? || (cost_of.call(dims) <=> best_cost) < 0 }

      # longest side worth trying: stacking every item end to end always fits,
      # and a longer side can not beat the best cost found so far
      cap = sorted.sum { |d| d[2] }
      cap = [cap, limits[:max_length]].min if limits[:max_length]
      cap = largest_side_beating(cap, min_a, min_b, min_c, beats_best) if best
      values = side_values(sorted, cap)
      attempts = 0

      # Try the smallest side closest to a cube first, so that when the time limit
      # stops the search early the answer is compact rather than long and thin.
      cube_side = Math.cbrt(min_vol)
      a_values  = values.select { |a| a >= min_a - EPSILON }.sort_by { |a| [(a - cube_side).abs, a] }

      # cost never decreases when a side grows, so cost(a, b, c) with the smallest
      # sides still allowed is a lower bound for the remaining loop iterations
      a_values.each do |a|
        next unless beats_best.call([a, [a, min_b].max, [a, min_b, min_c].max])
        values.each do |b|
          next if b < [a, min_b].max - EPSILON
          break unless beats_best.call([a, b, [b, min_c].max])
          values.each do |c|
            next if c < [b, min_c].max - EPSILON || a * b * c < min_vol - EPSILON
            candidate = [a, b, c]
            # c only grows from here, so neither limits nor cost can get better
            break unless within_limits?(candidate, limits)
            break unless beats_best.call(candidate)

            return best if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            return best if max_attempts && attempts >= max_attempts
            attempts += 1
            next unless fits_in_one?(candidate, items)

            best, best_cost = candidate, cost_of.call(candidate)
            break
          end
        end
      end
      best
    end

    # Binary search the largest c in [min_c, cap] for which [min_a, min_b, c] still beats the best.
    def largest_side_beating(cap, min_a, min_b, min_c, beats_best)
      return min_c unless beats_best.call([min_a, min_b, min_c].sort)
      lo, hi = min_c.to_f, cap.to_f
      40.times do
        mid = (lo + hi) / 2
        beats_best.call([min_a, min_b, mid].sort) ? lo = mid : hi = mid
      end
      [hi, cap].min
    end

    # Possible container side lengths: subset sums of item sides up to `cap`.
    # When there are too many (lots of different float sizes) they are rounded up
    # to a grid, which only makes candidates slightly bigger, never invalid.
    def side_values(sorted_dims, cap)
      sums = { 0.0 => true }
      grid = nil
      sorted_dims.flatten.each do |d|
        sums.keys.each do |v|
          nv = v + d
          next if nv > cap + EPSILON
          nv = grid ? ((nv / grid).ceil * grid) : nv
          sums[nv.round(6)] = true
        end
        if !grid && sums.size > MAX_SIDE_VALUES * 10
          grid = cap / MAX_SIDE_VALUES
          sums = sums.keys.map { |v| ((v / grid).ceil * grid).round(6) }.uniq.map { |v| [v, true] }.to_h
        end
      end
      values = sums.keys.reject(&:zero?).sort
      # keep the search bounded: at most MAX_SIDE_VALUES values spread over the range
      values = values.each_slice((values.size.to_f / MAX_SIDE_VALUES).ceil).map(&:first) if values.size > MAX_SIDE_VALUES
      values
    end

    def fits_in_one?(dimensions, items)
      packing = pack(container: { dimensions: dimensions }, items: items)
      packing[:packings].size == 1 && packing[:errors].empty?
    end

    def length_plus_girth(dimensions)
      a, b, c = dimensions.sort
      c + 2 * (a + b)
    end

    def default_cost(dimensions)
      [volume(dimensions).round(6), length_plus_girth(dimensions).round(6)]
    end

    def within_limits?(dimensions, limits)
      return false if dimensions.nil?
      return false if limits[:max_length] && dimensions.max > limits[:max_length] + EPSILON
      return false if limits[:max_length_plus_girth] && length_plus_girth(dimensions) > limits[:max_length_plus_girth] + EPSILON
      true
    end

    def validate_non_negative!(name, value)
      return if value.nil?
      raise ArgumentError, "#{name} must be a non-negative number" unless value.is_a?(Numeric) && value >= 0
    end


    def pack_with_strategy(container, items, weight_limit, strategy)
      packings = []
      errors   = []
      container_dimensions = container[:dimensions].sort.reverse

      # pack from biggest to smallest
      items.sort_by { |h| valid_dimensions?(h[:dimensions]) ? h[:dimensions].sort.reverse : [] }.reverse.each do |item|
        unless valid_dimensions?(item[:dimensions])
          errors << "Item: #{item} has invalid dimensions"
          next
        end

        item_weight = item[:weight].to_f
        # If the item is just too heavy for the container lets give up on this
        if item_weight > weight_limit
          errors << "Item: #{item} is too heavy for container"
          next
        end

        item_has_been_packed = false

        packings.each do |packing|
          # If this packing is going to be too heavy with this
          # item as well then skip on to the next packing
          next if packing[:weight] + item_weight > weight_limit + EPSILON

          # try minimum space first
          packing[:spaces].sort_by { |h| h[:dimensions].sort }.each do |space|
            next unless placement = place(item, space)
            packing[:placements] << placement
            packing[:weight] += item_weight
            packing[:spaces].delete(space)
            packing[:spaces].concat(break_up_space(space, placement, strategy))
            item_has_been_packed = true
            break
          end
          break if item_has_been_packed
        end
        next if item_has_been_packed

        # Can't fit in any of the spaces for the current packings
        # so lets try a new space the size of the container
        space = { dimensions: container_dimensions, position: [0, 0, 0] }
        placement = place(item, space)

        unless placement
          errors << "Item: #{item} cannot be placed in container"
          next
        end

        packings << {
          placements: [placement],
          weight: item_weight,
          spaces: break_up_space(space, placement, strategy)
        }
      end

      { packings: packings, errors: errors }
    end

    def validate_container!(container)
      unless container.is_a?(Hash) && valid_dimensions?(container[:dimensions])
        raise ArgumentError, "invalid container dimensions: #{container.inspect}"
      end
    end

    def valid_dimensions?(dimensions)
      dimensions.is_a?(Array) && dimensions.size == 3 &&
        dimensions.all? { |d| d.is_a?(Numeric) && d.finite? && d > 0 }
    end

    def weight_limit_of(container)
      # No weight_limit means no weight restriction.
      container[:weight_limit].nil? ? Float::INFINITY : container[:weight_limit].to_f
    end

    # Containers are returned as floats sorted ascending, e.g. [2.0, 2.0, 3.0].
    def normalize(dimensions)
      dimensions.map(&:to_f).sort
    end

    def aspect_ratio(dimensions)
      dimensions.max.to_f / dimensions.min
    end

    # Use the greedy box when nothing else was found, when it fits inside the
    # selected container, or when it is both smaller and no more elongated.
    def prefer_greedy_box?(greedy_box, selected)
      return true if selected.nil?
      g = greedy_box.sort
      s = selected.sort
      return true if (0..2).all? { |i| s[i] + EPSILON >= g[i] }
      volume(g) <= volume(s) + EPSILON && aspect_ratio(g) <= aspect_ratio(s) + EPSILON
    end

    def volume(dimensions)
      dimensions.inject(:*)
    end

    def std(contents)
      n = contents.size
      values = contents.map(&:to_f)
      mean = values.sum / n
      sum_sqr = values.map { |x| x * x }.sum
      Math.sqrt(((sum_sqr - n * mean * mean) / (n - 1)).abs)
    end

    # Grow a container by adding items one at a time on each face, keeping
    # the most "cube like" and the smallest candidates at each step (beam search).
    def find_possible_containers(container:, items:, min_vol:)
      possible_containers = []
      frontier = [container.sort]

      items.drop(1).each do |item|
        candidates = frontier.flat_map { |c| grow_container(c, item) }.uniq
        candidates.each { |c| possible_containers << c if volume(c) >= min_vol }

        frontier = candidates.sort_by { |a| [std(a), volume(a), a.inject(:+)] }.first(SEARCH_BEAM_WIDTH)
      end

      possible_containers.uniq
    end

    def grow_container(container, item)
      c_length, c_width, c_height = container.sort.reverse
      b_length, b_width, b_height = item.sort.reverse
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

      result = []
      c_permutations.each do |c_perm|
        b_permutations.each do |b_perm|
          result << [ c_perm[0] + b_perm[0],     [c_perm[1], b_perm[1]].max, [c_perm[2], b_perm[2]].max]
          result << [[c_perm[0], b_perm[0]].max,  c_perm[1] + b_perm[1],     [c_perm[2], b_perm[2]].max]
          result << [[c_perm[0], b_perm[0]].max, [c_perm[1], b_perm[1]].max,  c_perm[2] + b_perm[2]]
        end
      end
      result.map { |a| a.map(&:to_f).sort }
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
        next unless (0..2).all? { |i| perm[i] <= space[:dimensions][i] + EPSILON }

        possible_margin = (0..2).map { |i| space[:dimensions][i] - perm[i] }
        possible_rotations_and_margins << { margin: possible_margin, rotation: perm }
      end

      # select rotation with smallest margin
      final = possible_rotations_and_margins.sort_by { |a| a[:margin].sort }.first
      return unless final
      {
        dimensions: final[:rotation],
        position: space[:position],
        weight: item[:weight].to_f
      }
    end

    def break_up_space(space, placement, strategy = :legacy)
      options = split_options(space, placement)
      # original heuristic: compare the sorted dimensions of each option's spaces
      ranked = options.sort_by { |a| a.map { |aa| aa[:dimensions].sort } }
      chosen =
        case strategy
        when :legacy    then ranked.last
        # keep the largest single free block; ties fall back to :legacy order
        when :max_space then ranked.reverse.max_by { |a| a.map { |aa| volume(aa[:dimensions]) }.max }
        else options[strategy]
        end
      # drop empty (zero / float-noise) spaces, they can never hold anything
      chosen.reject { |s| s[:dimensions].any? { |d| d <= EPSILON } }
    end

    def split_options(space, placement)
      [
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
    end

    # Smallest box that holds every item laid flat and stacked on top of each other.
    def item_greedy_box(items)
      array_of_lwh       = items.map { |i| i[:dimensions].sort.reverse }
      items_max_length   = array_of_lwh.map { |x| x[0] }.max
      items_max_width    = array_of_lwh.map { |x| x[1] }.max
      # round only to remove float noise (e.g. 20.099999999999998), never truncate real size
      items_total_height = array_of_lwh.map { |x| x[2] }.sum.round(6)
      [items_max_length, items_max_width, items_total_height]
    end

    def check_container_is_bigger_than_greedy_box(container, items)
      c = container[:dimensions].sort.reverse
      greedy_box = item_greedy_box(items).sort.reverse
      (0..2).all? { |i| c[i] + EPSILON >= greedy_box[i] } &&
        weight_limit_of(container) + EPSILON >= items.sum { |i| i[:weight].to_f }
    end

    # Stack items flat along the greedy box's height, then map the result into
    # the container's frame (dimensions sorted descending) like #pack does.
    def generate_packing_for_greedy_box(container, items)
      greedy_box = item_greedy_box(items)
      # axis_map[k] = greedy box axis that lies along container axis k
      axis_map = [0, 1, 2].sort_by { |i| [-greedy_box[i], i] }

      return_h = { placements: [], weight: 0.0, spaces: [] }
      height   = 0
      items.each do |i|
        dims     = i[:dimensions].sort.reverse
        position = [0, 0, height]
        return_h[:placements] << {
          dimensions: axis_map.map { |a| dims[a] },
          position: axis_map.map { |a| position[a] },
          weight: i[:weight].to_f
        }
        return_h[:weight] += i[:weight].to_f
        height += dims[2]
      end
      [return_h]
    end
  end
end
