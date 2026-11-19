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

  UNPACKED_MESSAGES = {
    invalid_dimensions: 'has invalid dimensions',
    too_big: 'is too big for every box',
    too_heavy: 'is too heavy for every box',
    no_single_box: 'does not fit in a single box with the other items'
  }.freeze

  class << self
    # Pack items into as few copies of `container` as possible.
    #
    # All placements are expressed in the container's frame with its
    # dimensions sorted descending (length >= width >= height). Each placement
    # has `item:`, the item hash that was given, so callers can tell which item goes where.
    #
    # split_strategies - free space split strategies to try, in order, until one needs a single
    #                    container. Any of :legacy, :max_space, 0..5. Default: SPLIT_STRATEGIES.
    #                    [:legacy] is the fastest and reproduces 0.0.x results.
    # greedy_fallback  - when more than one container is needed but all items stacked flat
    #                    would fit, return that stack instead (default true).
    #
    # Item constraints (optional):
    #   upright: true - dimensions[2] is the item's height and must stay vertical
    #                   (it can still turn around the vertical axis).
    #   fragile: true - nothing may be placed on top of it.
    # The vertical axis is the third axis of the result. Without constraints the frame is
    # the container sorted descending; with them the container may be stood on another
    # side, the frame used is returned as :container_dimensions.
    def pack(container:, items:, split_strategies: SPLIT_STRATEGIES, greedy_fallback: true)
      validate_container!(container)
      validate_split_strategies!(split_strategies)
      weight_limit = weight_limit_of(container)
      constrained = constrained?(items)
      frames = constrained ? container_frames(container[:dimensions]) : [container[:dimensions].sort.reverse]

      best = nil
      frames.each do |frame|
        split_strategies.each do |strategy|
          result = pack_with_strategy(frame, items, weight_limit, strategy)
          if best.nil? || ([result[:errors].size, result[:packings].size] <=> [best[:errors].size, best[:packings].size]) < 0
            best = result
          end
          break if best[:packings].size <= 1
        end
        break if best[:packings].size <= 1 && best[:errors].empty?
      end

      # the flat stack ignores constraints, so it is only used without them
      if greedy_fallback && !constrained && best[:packings].size > 1 && check_container_is_bigger_than_greedy_box(container, items)
        { packings: generate_packing_for_greedy_box(container, items), errors: [],
          container_dimensions: container[:dimensions].sort.reverse }
      else
        best
      end
    end

    # Placements in the order to put them in the box: bottom layer first, then from
    # the back corner. Each gets step: (1, 2, ...) and support: the share of its
    # bottom resting on the box floor or on items below (1.0 = fully supported).
    def loading_order(placements)
      with_steps(placements).sort_by { |pl| pl[:step] }
    end

    # Choose boxes from the boxes you have and show how to pack the items in them.
    #
    # boxes                - [{ dimensions: [l, w, h] (cm, inside), weight_limit: kg (optional),
    #                          cost: number (optional, default volume), padding: cm (optional),
    #                          any other keys such as id: are returned untouched }]
    # items                - [{ dimensions: [l, w, h] (cm), weight: kg (optional), id: ... }]
    # allow_multiple_boxes - split the items over several boxes when no single box fits (default true).
    # padding              - cushioning in cm kept free on every side of every box (default 0).
    #                        A box's own :padding overrides it.
    # cost                 - lambda taking a box hash and returning a number, lower is better.
    #                        Default: box[:cost], or the box volume when it has none.
    # max_items            - raise ArgumentError when more items are given (default nil, no limit).
    # time_limit           - soft limit in seconds (default nil). After it only the first split
    #                        strategy is used: still valid, maybe one more box than needed.
    # split_strategies,
    # greedy_fallback      - passed to #pack.
    #
    # Returns { boxes: [{ box:, placements:, weight:, cost: }], total_cost:,
    #           unpacked: [{ item:, reason: }], errors: [String] }.
    # reason is one of :invalid_dimensions, :too_big, :too_heavy, :no_single_box.
    # Placements are in the box's usable space (inside dimensions minus padding), sorted descending.
    def select_box(boxes:, items:, allow_multiple_boxes: true, padding: 0, cost: nil, max_items: nil,
                   time_limit: nil, split_strategies: SPLIT_STRATEGIES, greedy_fallback: true)
      raise ArgumentError, 'boxes must not be empty' if boxes.nil? || boxes.empty?
      raise ArgumentError, 'items must be an array' unless items.is_a?(Array)
      validate_non_negative!(:padding, padding)
      validate_non_negative!(:time_limit, time_limit)
      validate_non_negative!(:max_items, max_items)
      raise ArgumentError, "too many items: #{items.size} (max_items: #{max_items})" if max_items && items.size > max_items
      raise ArgumentError, 'cost must respond to #call' if cost && !cost.respond_to?(:call)
      validate_split_strategies!(split_strategies)
      pack_options = { split_strategies: split_strategies, greedy_fallback: greedy_fallback }

      candidates = boxes.map do |box|
        raise ArgumentError, "invalid box dimensions: #{box.inspect}" unless box.is_a?(Hash) && valid_dimensions?(box[:dimensions])
        box_padding = box.key?(:padding) ? box[:padding] : padding
        validate_non_negative!(:padding, box_padding)
        usable = box[:dimensions].map { |d| d - 2 * box_padding }
        next unless usable.all? { |d| d > EPSILON }
        box_cost = cost ? cost.call(box) : (box[:cost] || volume(box[:dimensions]))
        raise ArgumentError, "box cost must be a non-negative number: #{box.inspect}" unless box_cost.is_a?(Numeric) && box_cost >= 0
        { box: box, container: { dimensions: usable, weight_limit: box[:weight_limit] }, cost: box_cost }
      end.compact

      unpacked  = []
      remaining = []
      items.each do |item|
        if !item.is_a?(Hash) || !valid_dimensions?(item[:dimensions])
          unpacked << { item: item, reason: :invalid_dimensions }
        elsif candidates.none? { |c| fits_in_one?(c[:container][:dimensions], [item], pack_options.merge(weight_limit: c[:container][:weight_limit])) }
          fits_by_size = candidates.any? { |c| fits_in_one?(c[:container][:dimensions], [item], pack_options) }
          unpacked << { item: item, reason: fits_by_size ? :too_heavy : :too_big }
        else
          remaining << item
        end
      end

      deadline = time_limit && Process.clock_gettime(Process::CLOCK_MONOTONIC) + time_limit
      chosen = []
      until remaining.empty?
        remaining_volume = remaining.sum { |i| volume(i[:dimensions]) }
        remaining_weight = remaining.sum { |i| i[:weight].to_f }

        results = candidates.map do |cand|
          # a box too small or too weak for everything can not be the single box,
          # so only the fastest strategy is needed to rank it for filling
          could_hold_all = volume(cand[:container][:dimensions]) + EPSILON >= remaining_volume &&
                           weight_limit_of(cand[:container]) + EPSILON >= remaining_weight
          out_of_time = deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          options = could_hold_all && !out_of_time ? pack_options : pack_options.merge(split_strategies: [split_strategies.first])
          [cand, pack(container: cand[:container], items: remaining, **options)]
        end

        # cheapest single box that holds everything left
        single = results
          .select { |_, r| r[:packings].size == 1 && r[:errors].empty? }
          .min_by { |c, _| [c[:cost], volume(c[:container][:dimensions])] }
        if single
          chosen << box_result(single[0], single[1])
          break
        end
        unless allow_multiple_boxes
          remaining.each { |item| unpacked << { item: item, reason: :no_single_box } }
          break
        end

        # otherwise fill the box that packs the most item volume per cost, then repeat
        c, packing, r = results.map do |cand, res|
          [cand, res[:packings].max_by { |p| packed_volume(p) }, res]
        end.reject { |_, p, _| p.nil? }.max_by do |cand, p, _|
          [cand[:cost].zero? ? Float::INFINITY : packed_volume(p) / cand[:cost], packed_volume(p), -cand[:cost]]
        end
        chosen << box_result(c, r.merge(packings: [packing]))
        packed = packing[:placements].map { |pl| pl[:item] }
        remaining = remaining.reject { |item| packed.any? { |p| p.equal?(item) } }
      end

      {
        boxes: chosen,
        total_cost: chosen.sum { |b| b[:cost] },
        unpacked: unpacked,
        errors: unpacked.map { |u| "Item: #{u[:item]} #{UNPACKED_MESSAGES[u[:reason]]}" }
      }
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
    # beam_width            - candidates kept per step of the heuristic search (default 1).
    # max_side_values       - max distinct side lengths tried per axis while refining (default 1000).
    # split_strategies,
    # greedy_fallback       - passed to #pack.
    #
    # Returns nil when no container satisfies max_length / max_length_plus_girth.
    def find_smallest_container(items:, time_limit: DEFAULT_TIME_LIMIT, max_attempts: nil,
                                max_length: nil, max_length_plus_girth: nil, cost: nil,
                                beam_width: SEARCH_BEAM_WIDTH, max_side_values: MAX_SIDE_VALUES,
                                split_strategies: SPLIT_STRATEGIES, greedy_fallback: true)
      raise ArgumentError, 'items must not be empty' if items.nil? || items.empty?
      items.each do |item|
        raise ArgumentError, "invalid dimensions for item: #{item}" unless valid_dimensions?(item[:dimensions])
      end
      validate_non_negative!(:time_limit, time_limit)
      validate_non_negative!(:max_attempts, max_attempts)
      validate_non_negative!(:max_length, max_length)
      validate_non_negative!(:max_length_plus_girth, max_length_plus_girth)
      raise ArgumentError, 'cost must respond to #call' if cost && !cost.respond_to?(:call)
      raise ArgumentError, 'beam_width must be a positive integer' unless beam_width.is_a?(Integer) && beam_width > 0
      raise ArgumentError, 'max_side_values must be a positive integer' unless max_side_values.is_a?(Integer) && max_side_values > 0
      validate_split_strategies!(split_strategies)
      pack_options = { split_strategies: split_strategies, greedy_fallback: greedy_fallback }

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limits = { max_length: max_length, max_length_plus_girth: max_length_plus_girth }
      start = heuristic_smallest_container(items, beam_width, pack_options)
      start = nil unless within_limits?(start, limits)
      return start && normalize(start) if items.size == 1

      best = refine_container(
        items, start,
        deadline: time_limit && started_at + time_limit, max_attempts: max_attempts, limits: limits, cost: cost,
        max_side_values: max_side_values, pack_options: pack_options
      )
      best && normalize(best)
    end

    private

    # Original search: grow a container item by item, then compare with the greedy box.
    def heuristic_smallest_container(items, beam_width, pack_options)
      # order items from biggest to smallest
      sorted_items = items.sort_by { |h| h[:dimensions].sort }.reverse
      return sorted_items.first[:dimensions] if sorted_items.size == 1

      min_vol = items.map { |h| h[:dimensions].inject(:*) }.inject(:+)
      possible_containers = find_possible_containers(
        container: sorted_items.first[:dimensions],
        items: sorted_items.map { |i| i[:dimensions] },
        min_vol: min_vol,
        beam_width: beam_width
      )

      select_container = possible_containers
        .sort_by { |a| [volume(a), a.inject(:+)] }
        .find { |c| fits_in_one?(c, items, pack_options) }

      if constrained?(items)
        # the flat stack breaks upright / fragile items: fall back to the items in one row
        return select_container if select_container
        row = row_box(items)
        return fits_in_one?(row, items, pack_options) ? row : nil
      end

      # The greedy box (all items laid flat and stacked) always fits.
      greedy_box = item_greedy_box(items)
      prefer_greedy_box?(greedy_box, select_container) ? greedy_box : select_container
    end

    # All items side by side in one layer (nothing on top of anything), upright ones standing.
    def row_box(items)
      sides = items.map do |i|
        d = i[:dimensions]
        if i[:upright]
          w, l = d[0..1].sort
          [w, l, d[2]]
        else
          d.sort
        end
      end
      [sides.sum { |s| s[0] }.round(6), sides.map { |s| s[1] }.max, sides.map { |s| s[2] }.max]
    end

    # Every container side is (at most) a sum of item sides, so enumerate sides
    # (a <= b <= c) from those sums and test-pack candidates that would be cheaper
    # than the best one found so far. Starts from `best` so it is never worse.
    def refine_container(items, best, deadline:, max_attempts:, limits:, cost:, max_side_values:, pack_options:)
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
      values = side_values(sorted, cap, max_side_values)
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
            next unless fits_in_one?(candidate, items, pack_options)

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
    def side_values(sorted_dims, cap, max_values)
      sums = { 0.0 => true }
      grid = nil
      sorted_dims.flatten.each do |d|
        sums.keys.each do |v|
          nv = v + d
          next if nv > cap + EPSILON
          nv = grid ? ((nv / grid).ceil * grid) : nv
          sums[nv.round(6)] = true
        end
        if !grid && sums.size > max_values * 10
          grid = cap / max_values
          sums = sums.keys.map { |v| ((v / grid).ceil * grid).round(6) }.uniq.map { |v| [v, true] }.to_h
        end
      end
      values = sums.keys.reject(&:zero?).sort
      # keep the search bounded: at most max_values values spread over the range
      values = values.each_slice((values.size.to_f / max_values).ceil).map(&:first) if values.size > max_values
      values
    end

    # pack_options: split_strategies:, greedy_fallback: and optionally weight_limit:
    def fits_in_one?(dimensions, items, pack_options = {})
      options = pack_options.dup
      container = { dimensions: dimensions, weight_limit: options.delete(:weight_limit) }
      packing = pack(container: container, items: items, **options)
      packing[:packings].size == 1 && packing[:errors].empty?
    end

    # result is a #pack result whose first packing is the one used for this box
    def box_result(candidate, result)
      packing = result[:packings].first
      {
        box: candidate[:box],
        container_dimensions: result[:container_dimensions],
        placements: with_steps(packing[:placements]),
        weight: packing[:weight],
        cost: candidate[:cost]
      }
    end

    # placements in their original order, each with step: and support: added
    def with_steps(placements)
      order = placements.each_index.sort_by do |i|
        pos = placements[i][:position]
        [pos[2].round(6), pos[0].round(6), pos[1].round(6), i]
      end
      step = {}
      order.each_with_index { |i, s| step[i] = s + 1 }
      placements.each_with_index.map { |pl, i| pl.merge(step: step[i], support: support_ratio(pl, placements)) }
    end

    def packed_volume(packing)
      packing[:placements].sum { |pl| volume(pl[:dimensions]) }
    end

    def validate_split_strategies!(strategies)
      allowed = [:legacy, :max_space, 0, 1, 2, 3, 4, 5]
      unless strategies.is_a?(Array) && !strategies.empty? && strategies.all? { |s| allowed.include?(s) }
        raise ArgumentError, "split_strategies must be a non-empty array of #{allowed.inspect}"
      end
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


    def pack_with_strategy(container_dimensions, items, weight_limit, strategy)
      packings = []
      errors   = []

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
            next unless placement = place(item, space, packing[:placements])
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

      { packings: packings, errors: errors, container_dimensions: container_dimensions }
    end

    def constrained?(items)
      items.any? { |i| i.is_a?(Hash) && (i[:upright] || i[:fragile]) }
    end

    # The container stood on each of its sides: [length, width, up], longest first.
    def container_frames(dimensions)
      l, w, h = dimensions.sort.reverse
      [[l, w, h], [l, h, w], [w, h, l]].uniq
    end

    def footprint_overlap(a_pos, a_dims, b_pos, b_dims)
      (0..1).map do |k|
        [[a_pos[k] + a_dims[k], b_pos[k] + b_dims[k]].min - [a_pos[k], b_pos[k]].max, 0].max
      end.inject(:*)
    end

    # true when a box at position/dims would be on top of a fragile item,
    # or below anything when the item itself is fragile
    def blocked_by_fragile?(item, position, dims, placements)
      placements.any? do |pl|
        next false unless footprint_overlap(position, dims, pl[:position], pl[:dimensions]) > EPSILON
        top_of_pl   = pl[:position][2] + pl[:dimensions][2]
        top_of_item = position[2] + dims[2]
        (pl[:item].is_a?(Hash) && pl[:item][:fragile] && position[2] >= top_of_pl - EPSILON) ||
          (item[:fragile] && pl[:position][2] >= top_of_item - EPSILON)
      end
    end

    def support_ratio(placement, placements)
      z = placement[:position][2]
      return 1.0 if z <= EPSILON
      area = placement[:dimensions][0] * placement[:dimensions][1]
      supported = placements.sum do |pl|
        next 0 if pl.equal?(placement) || (pl[:position][2] + pl[:dimensions][2] - z).abs > EPSILON
        footprint_overlap(placement[:position], placement[:dimensions], pl[:position], pl[:dimensions])
      end
      [supported / area.to_f, 1.0].min.round(4)
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
    def find_possible_containers(container:, items:, min_vol:, beam_width: SEARCH_BEAM_WIDTH)
      possible_containers = []
      frontier = [container.sort]

      items.drop(1).each do |item|
        candidates = frontier.flat_map { |c| grow_container(c, item) }.uniq
        candidates.each { |c| possible_containers << c if volume(c) >= min_vol }

        frontier = candidates.sort_by { |a| [std(a), volume(a), a.inject(:+)] }.first(beam_width)
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

    def place(item, space, placements = [])
      item_length, item_width, item_height = item[:dimensions].sort.reverse

      permutations = [
        [item_width, item_height, item_length],
        [item_width, item_length, item_height],
        [item_height, item_width, item_length],
        [item_height, item_length, item_width],
        [item_length, item_width, item_height],
        [item_length, item_height, item_width]
      ]

      if item[:upright]
        up = item[:dimensions][2]
        permutations = permutations.select { |perm| (perm[2] - up).abs <= EPSILON }
      end

      possible_rotations_and_margins = []

      permutations.each do |perm|
        # Skip if the item does not fit with this orientation
        next unless (0..2).all? { |i| perm[i] <= space[:dimensions][i] + EPSILON }

        possible_margin = (0..2).map { |i| space[:dimensions][i] - perm[i] }
        possible_rotations_and_margins << { margin: possible_margin, rotation: perm }
      end

      # select rotation with smallest margin
      ranked = possible_rotations_and_margins.sort_by { |a| a[:margin].sort }
      check_fragile = item[:fragile] || placements.any? { |pl| pl[:item].is_a?(Hash) && pl[:item][:fragile] }
      final = check_fragile ? ranked.find { |a| !blocked_by_fragile?(item, space[:position], a[:rotation], placements) } : ranked.first
      return unless final
      {
        dimensions: final[:rotation],
        position: space[:position],
        weight: item[:weight].to_f,
        item: item
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
          weight: i[:weight].to_f,
          item: i
        }
        return_h[:weight] += i[:weight].to_f
        height += dims[2]
      end
      [return_h]
    end
  end
end
