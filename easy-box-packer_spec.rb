require 'easy-box-packer'

# Checks a pack result is physically possible: inside the container, no overlaps,
# within the weight limit and every item is either placed or reported.
def geometry_problems(container, items, result)
  eps = 1e-9
  c = container[:dimensions].sort.reverse
  problems = []
  result[:packings].each do |packing|
    placements = packing[:placements]
    placements.each do |pl|
      3.times do |k|
        problems << "out of bounds: #{pl}" if pl[:position][k] < -eps || pl[:position][k] + pl[:dimensions][k] > c[k] + eps
      end
    end
    placements.combination(2).each do |a, b|
      overlap = (0..2).all? do |k|
        a[:position][k] < b[:position][k] + b[:dimensions][k] - eps &&
          b[:position][k] < a[:position][k] + a[:dimensions][k] - eps
      end
      problems << "overlap: #{a} #{b}" if overlap
    end
    problems << "overweight: #{packing[:weight]}" if container[:weight_limit] && packing[:weight] > container[:weight_limit] + eps
  end
  placed = result[:packings].sum { |pk| pk[:placements].size }
  problems << 'item count mismatch' if placed + result[:errors].size != items.size
  problems
end

describe '.pack' do
  it do
    packings = EasyBoxPacker.pack(
      container: { dimensions: [15, 20, 13], weight_limit: 50 },
      items: [
        { dimensions: [2, 3, 5], weight: 47 },
        { dimensions: [2, 3, 5], weight: 47 },
        { dimensions: [3, 3, 1], weight: 24 },
        { dimensions: [1, 1, 4], weight: 7 },
      ]
    )

    expect(packings[:packings].length).to eql(3)
    expect(packings[:packings][0][:weight]).to eql(47.0)
    expect(packings[:packings][0][:placements].length).to eql(1)
    expect(packings[:packings][0][:placements][0][:dimensions]).to eql([2, 3, 5])
    expect(packings[:packings][0][:placements][0][:position]).to eql([0, 0, 0])
    expect(packings[:packings][1][:weight]).to eql(47.0)
    expect(packings[:packings][1][:placements].length).to eql(1)
    expect(packings[:packings][1][:placements][0][:dimensions]).to eql([2, 3, 5])
    expect(packings[:packings][1][:placements][0][:position]).to eql([0, 0, 0])
    expect(packings[:packings][2][:weight]).to eql(31.0)
    expect(packings[:packings][2][:placements].length).to eql(2)
    expect(packings[:packings][2][:placements][0][:dimensions]).to eql([1, 1, 4])
    expect(packings[:packings][2][:placements][0][:position]).to eql([0, 0, 0])
    expect(packings[:packings][2][:placements][1][:dimensions]).to eql([1, 3, 3])
    expect(packings[:packings][2][:placements][1][:position]).to eql([0, 1, 0])
  end

  it 'no weight given' do
     packings = EasyBoxPacker.pack(
      container: { dimensions: [13, 15, 20] },
      items: [
        { dimensions: [2, 3, 5] },
        { dimensions: [2, 3, 5] },
        { dimensions: [3, 3, 1] },
        { dimensions: [1, 1, 4] },
      ]
    )
    expect(packings[:packings].length).to eql(1)
    expect(packings[:packings][0][:weight]).to eql(0.0)
    expect(packings[:packings][0][:placements].length).to eql(4)
  end

  context 'it can be packed' do
    it 'case 1' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [40, 34, 88] },
        items: [
          { dimensions: [40, 30, 34] },
          { dimensions: [40, 30, 34] },
          { dimensions: [40, 28, 30] }
        ]
      )
      expect(packings[:packings].length).to eql(1)
      expect(packings[:packings][0][:weight]).to eql(0.0)
      expect(packings[:packings][0][:placements].length).to eql(3)
    end

    it 'case 1 - will not be affected by different order' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [40, 34, 88] },
        items: [
          { dimensions: [40, 30, 34] },
          { dimensions: [40, 28, 30] },
          { dimensions: [40, 30, 34] }
        ]
      )
      expect(packings[:packings].length).to eql(1)
      expect(packings[:packings][0][:weight]).to eql(0.0)
      expect(packings[:packings][0][:placements].length).to eql(3)
    end

    it 'case 2' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [40, 34, 13] },
        items: [
          { dimensions: [40, 10, 34] },
          { dimensions: [40, 2, 30]  },
          { dimensions: [40, 3,  4]  },
          { dimensions: [40, 1, 30]  }
        ]
      )
      expect(packings[:packings].length).to eql(1)
    end

    it 'case 3' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [10, 10, 10] },
        items: Array.new(1000) {{ dimensions: [1, 1, 1] }}
      )
      expect(packings[:packings].length).to eql(1)
    end

    it 'case 4' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [20, 30, 10] },
        items: [
          { dimensions: [40, 10, 34] },
          { dimensions: [10, 20, 10] },
          { dimensions: [20, 20, 5]  },
          { dimensions: [20, 20, 4]  },
          { dimensions: [20, 20, 1]  }
        ]
      )
      expect(packings[:packings].length).to eql(1)
      expect(packings[:errors].size).to eql(1)
      expect(packings[:errors].first).to match(/\AItem: .*40, 10, 34.* cannot be placed in container\z/)
    end

    it 'case 5' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [20, 30, 10] },
        items: [
          { dimensions: [10, 20, 11] },
          { dimensions: [20, 20, 5]  },
          { dimensions: [20, 20, 4]  },
          { dimensions: [20, 20, 1]  }
        ]
      )
      expect(packings[:packings].length).to eql(2)
    end

    it 'case 6' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [39, 33.5, 58] },
        items: [
          {dimensions: [26.0, 26.0, 26.5]},
          {dimensions: [18.0, 23.0, 39.0]},
          {dimensions: [39.0, 14.0, 33.5]}
        ]
      )
      expect(packings[:packings].length).to eql(1)
    end

    it 'case 7' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [139, 50, 40] },
        items: [
          {dimensions: [10, 30, 139]},
          {dimensions: [16, 24, 105]},
          {dimensions: [12, 50, 103]}
        ]
      )
      expect(packings[:packings].length).to eql(1)
    end

    it 'case 8' do
      packings = EasyBoxPacker.pack(
        container: { dimensions: [46.5, 32, 15] },
        items: [
          {dimensions: [7, 8, 9]},
          {dimensions: [2, 2, 3]},
          {dimensions: [5, 31, 45]}
        ]
      )
      expect(packings[:packings].length).to eql(1)
    end
  end
end

# Heuristic only (no refining), deterministic on every machine.
def heuristic_container(items:)
  EasyBoxPacker.find_smallest_container(items: items, time_limit: 0)
end

describe '.find_smallest_container (heuristic, time_limit: 0)' do
  it 'can get smallest container- with 10 items' do
    container = heuristic_container(
        items: Array.new(10) {{ dimensions: [1, 1, 1] }}
      )
    expect(container).to eql([2.0, 2.0, 3.0])
  end

  it 'can get smallest container - with 100 items' do
    container = heuristic_container(
        items: Array.new(100) {{ dimensions: [1, 1, 1] }}
      )
    expect(container).to eql([4.0, 5.0, 5.0])
  end

  it 'can get smallest container - with 100 items' do
    container = heuristic_container(
        items: Array.new(100) {{ dimensions: [10, 5, 4] }}
      )
    # was [26.0, 29.0, 36.0] before more split strategies were tried
    expect(container).to eql([26.0, 29.0, 30.0])
  end

  it 'can get smallest container - with 100 items' do
    container = heuristic_container(
        items: Array.new(100) {{ dimensions: [4, 5, 5] }}
      )
    # was [21.0, 24.0, 26.0]
    expect(container).to eql([21.0, 21.0, 28.0])
  end

  it 'can get smallest container - with 1000 items' do
    container = heuristic_container(
        items: Array.new(1000) {{ dimensions: [1, 1, 1] }}
      )
    expect(container).to eql([10.0, 10.0, 10.0])
  end

  it 'case 1' do
    container = heuristic_container(
      items: [
        { dimensions: [4, 7, 9] },
        { dimensions: [5, 8, 9] },
        { dimensions: [11, 20, 40] },
        { dimensions: [1, 2, 3] }
      ]
    )
    expect(container).to eql([11.0, 20.0, 45.0])
  end

   it 'case 2' do
    container = heuristic_container(
      items: [
        { dimensions: [4, 7, 9] },
        { dimensions: [3, 2, 1] }
      ]
    )
    expect(container).to eql([4.0, 7.0, 10.0])
  end

  it 'case 3' do
    container = heuristic_container(
      items: [
        { dimensions: [4, 7, 9] },
        { dimensions: [3, 2, 1] },
        { dimensions: [7, 7, 5] }
      ]
    )
    expect(container).to eql([5.0, 7.0, 16.0])
  end

  it 'case 5' do
    container = heuristic_container(
      items: [
        { dimensions: [10, 20, 11] },
        { dimensions: [20, 20, 5]  },
        { dimensions: [20, 20, 4]  },
        { dimensions: [20, 20, 1]  }
      ]
    )

    expect(container).to eq([10.0, 20.0, 31.0])
    packings = EasyBoxPacker.pack(
      container: { dimensions: [10.0, 20.0, 31.0] },
      items: [
        { dimensions: [10, 20, 11] },
        { dimensions: [20, 20, 5]  },
        { dimensions: [20, 20, 4]  },
        { dimensions: [20, 20, 1]  }
      ]
    )
    expect(packings[:packings].length).to eql(1)
  end

  it 'case 6' do
    container = heuristic_container(
      items: [
        { dimensions: [10, 20, 11] }
      ]
    )

    expect(container).to eql([10.0, 11.0, 20.0])
  end

  it 'case 7' do
    container = heuristic_container(
      items: [
        {dimensions: [110, 30, 10]}, {dimensions: [110, 20, 10]}, {dimensions: [110, 10, 5]},
        {dimensions: [110, 30, 10]}, {dimensions: [110, 20, 10]}, {dimensions: [110, 10, 5]},
        {dimensions: [110, 30, 10]}, {dimensions: [110, 20, 10]}, {dimensions: [110, 10, 5]}
      ]
    )
    # the heuristic alone returns an elongated box; refining fixes it (see below)
    expect(container).to eql([30.0, 30.0, 220.0])
  end

  it 'case 8' do
    container = heuristic_container(
      items: [
        {dimensions: [26.0, 26.0, 26.5]},
        {dimensions: [18.0, 23.0, 39.0]},
        {dimensions: [39.0, 14.0, 33.5]}
      ]
    )
    expect(container).to eq([33.5, 39.0, 58.0])
  end

  it 'case 9' do
    container = heuristic_container(
        items: Array.new(67) {{ dimensions: [36.0, 27.0, 0.3] }}
      )

    expect(container).to eql([20.1, 27.0, 36.0])
  end

  it 'case 10' do
    container = heuristic_container(
        items: [
          { dimensions: [13, 23.5, 48] },
          { dimensions: [13, 23.5, 48] },
          { dimensions: [13, 23.5, 48] }
        ]
      )
    expect(container).to eql([23.5, 39.0, 48.0])
  end


  it 'case 11' do
    container = heuristic_container(
        items: [
          { dimensions: [73, 8, 4] },
          { dimensions: [39, 34, 4] },
          { dimensions: [40, 7, 5] },
          { dimensions: [21, 8, 7] },
          { dimensions: [27, 27, 17] }
        ]
      )
    # was [34.0, 34.0, 79.0]
    expect(container).to eql([27.0, 34.0, 79.0])
  end


  it 'case 12' do
    container = heuristic_container(
        items: [
          { dimensions: [22, 19, 27] },
          { dimensions: [22, 19, 27] },
          { dimensions: [22, 19, 27] },
          { dimensions: [22, 19, 27] },
          { dimensions: [22, 19, 27] }
        ]
      )
    expect(container).to eql([27.0, 46.0, 57.0])
  end
end

CASE_7_ITEMS = ([[110, 30, 10], [110, 20, 10], [110, 10, 5]] * 3).map { |d| { dimensions: d } }
CASE_12_ITEMS = Array.new(5) { { dimensions: [22, 19, 27] } }

# Refining without a time limit, so results do not depend on machine speed.
def refined_container(items:, **options)
  EasyBoxPacker.find_smallest_container(items: items, time_limit: nil, **options)
end

def expect_fits(container, items)
  result = EasyBoxPacker.pack(container: { dimensions: container }, items: items)
  expect(result[:packings].size).to eql(1)
  expect(result[:errors]).to eql([])
  expect(geometry_problems({ dimensions: container }, items, result)).to eql([])
end

describe '.find_smallest_container (refined)' do
  {
    'case 7'  => [CASE_7_ITEMS, [30.0, 55.0, 110.0]],
    'case 8'  => [[[26.0, 26.0, 26.5], [18.0, 23.0, 39.0], [39.0, 14.0, 33.5]].map { |d| { dimensions: d } }, [32.0, 33.5, 65.0]],
    'case 11' => [[[73, 8, 4], [39, 34, 4], [40, 7, 5], [21, 8, 7], [27, 27, 17]].map { |d| { dimensions: d } }, [17.0, 38.0, 79.0]],
    'case 12' => [CASE_12_ITEMS, [22.0, 27.0, 95.0]],
    '10 cubes' => [Array.new(10) { { dimensions: [1, 1, 1] } }, [1.0, 2.0, 5.0]]
  }.each do |name, (items, expected)|
    it "#{name} finds a smaller valid container" do
      container = refined_container(items: items)
      expect(container).to eql(expected)
      expect_fits(container, items)
      expect(container.inject(:*)).to be <= heuristic_container(items: items).inject(:*)
    end
  end

  it 'is the default (time_limit 0.5s) and finds case 7 in time' do
    expect(EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS)).to eql([30.0, 55.0, 110.0])
  end

  it 'max_attempts: 0 skips refining' do
    expect(EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, max_attempts: 0)).to eql([30.0, 30.0, 220.0])
  end

  it 'max_attempts gives the same answer regardless of time' do
    first  = EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, time_limit: nil, max_attempts: 5)
    second = EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, time_limit: nil, max_attempts: 5)
    expect(first).to eql(second)
    expect_fits(first, CASE_7_ITEMS)
  end

  it 'stops soon after time_limit' do
    items = Array.new(100) { { dimensions: [10, 5, 4] } }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    container = EasyBoxPacker.find_smallest_container(items: items, time_limit: 0.1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    # the first heuristic answer (~0.5s here) is always computed, plus one test pack
    expect(elapsed).to be < 3
    expect_fits(container, items)
  end

  it 'respects max_length (cm)' do
    container = refined_container(items: CASE_12_ITEMS, max_length: 60)
    expect(container.max).to be <= 60
    expect(container).to eql([22.0, 46.0, 57.0])
    expect_fits(container, CASE_12_ITEMS)
  end

  it 'respects max_length_plus_girth (cm)' do
    container = refined_container(items: CASE_7_ITEMS, max_length_plus_girth: 300)
    a, b, c = container
    expect(c + 2 * (a + b)).to be <= 300
    expect_fits(container, CASE_7_ITEMS)
  end

  it 'returns nil when the limits can not be met' do
    expect(refined_container(items: CASE_7_ITEMS, max_length: 100)).to be_nil
    expect(EasyBoxPacker.find_smallest_container(items: [{ dimensions: [10, 10, 80] }], max_length: 60)).to be_nil
  end

  it 'accepts a custom cost (e.g. dimensional weight + a long parcel surcharge)' do
    cost = ->(d) { (d.inject(:*) / 5000.0).ceil + (d.max > 60 ? 20 : 0) }
    container = refined_container(items: CASE_12_ITEMS, cost: cost)
    expect(container.max).to be <= 60
    expect_fits(container, CASE_12_ITEMS)
  end

  it 'raises on invalid options' do
    expect { EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, time_limit: -1) }.to raise_error(ArgumentError)
    expect { EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, max_length: 'x') }.to raise_error(ArgumentError)
    expect { EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, cost: 1) }.to raise_error(ArgumentError)
  end
end

describe 'regressions' do
  it 'greedy fallback returns physically valid placements' do
    [
      [{ dimensions: [9, 19, 8] }, [{ dimensions: [9, 11, 4] }, { dimensions: [19, 6, 1] }]],
      [{ dimensions: [17, 15, 20] }, [[3, 20, 6], [16, 9, 1], [1, 15, 14], [11, 11, 2], [14, 7, 1], [17, 3, 19]].map { |d| { dimensions: d } }],
      [{ dimensions: [7, 14, 8] }, [[0.1, 4, 2.1], [11.0, 0.8, 6.6], [2.2, 10, 0.9], [1.8, 3.3, 5.5], [8, 10, 0.6]].map { |d| { dimensions: d } }]
    ].each do |container, items|
      result = EasyBoxPacker.pack(container: container, items: items)
      expect(result[:packings].size).to eql(1)
      expect(geometry_problems(container, items, result)).to eql([])
    end
  end

  it 'random packings are always physically valid' do
    rng = Random.new(42)
    300.times do
      container = { dimensions: Array.new(3) { rng.rand(5..30) + [0, 0.1, 0.5].sample(random: rng) }, weight_limit: [nil, rng.rand(10..50)].sample(random: rng) }
      items = Array.new(rng.rand(1..10)) { { dimensions: Array.new(3) { (rng.rand(1..12) * [0.1, 1, 1.1].sample(random: rng)).round(2) }, weight: rng.rand(0..15) } }
      result = EasyBoxPacker.pack(container: container, items: items)
      expect(geometry_problems(container, items, result)).to eql([]), "container=#{container} items=#{items}"
    end
  end

  it 'treats a missing weight_limit as no limit' do
    result = EasyBoxPacker.pack(container: { dimensions: [10, 10, 10] }, items: [{ dimensions: [1, 1, 1], weight: 5 }])
    expect(result[:errors]).to eql([])
    expect(result[:packings].first[:weight]).to eql(5.0)
  end

  it 'reports items with invalid dimensions instead of placing them' do
    result = EasyBoxPacker.pack(container: { dimensions: [5, 5, 5] }, items: [{ dimensions: [0, 1, 1] }, { dimensions: [-1, 1, 1] }, { dimensions: [1, 1, 1] }])
    expect(result[:errors].size).to eql(2)
    expect(result[:packings].first[:placements].size).to eql(1)
  end

  it 'raises on an invalid container' do
    expect { EasyBoxPacker.pack(container: { dimensions: [5, 5] }, items: []) }.to raise_error(ArgumentError)
  end

  it 'raises on empty items for find_smallest_container' do
    expect { EasyBoxPacker.find_smallest_container(items: []) }.to raise_error(ArgumentError)
  end

  it 'greedy box height is never rounded down below the real stack height' do
    container = EasyBoxPacker.find_smallest_container(items: [{ dimensions: [10, 10, 0.04] }, { dimensions: [10, 10, 1.0] }])
    expect(container).to eql([1.04, 10.0, 10.0])
    container = EasyBoxPacker.find_smallest_container(items: Array.new(3) { { dimensions: [10, 10, 0.35] } })
    expect(container).to eql([1.05, 10.0, 10.0])
  end

  it 'does not mutate the given items' do
    items = [{ dimensions: [3, 1, 2] }, { dimensions: [1, 1, 1] }]
    EasyBoxPacker.find_smallest_container(items: items)
    expect(items).to eql([{ dimensions: [3, 1, 2] }, { dimensions: [1, 1, 1] }])
  end
end

BOXES = [
  { id: 'S', dimensions: [20, 15, 10], weight_limit: 5,  cost: 10 },
  { id: 'M', dimensions: [30, 25, 20], weight_limit: 10, cost: 18 },
  { id: 'L', dimensions: [45, 35, 30], weight_limit: 20, cost: 30 }
].freeze

def placed_ids(result)
  result[:boxes].flat_map { |b| b[:placements].map { |p| p[:item][:id] } }
end

def expect_valid_boxes(result, padding: 0)
  result[:boxes].each do |b|
    usable = b[:box][:dimensions].map { |d| d - 2 * padding }
    items  = b[:placements].map { |p| p[:item] }
    packing = { packings: [{ placements: b[:placements], weight: b[:weight] }], errors: [] }
    expect(geometry_problems({ dimensions: usable, weight_limit: b[:box][:weight_limit] }, items, packing)).to eql([])
  end
end

describe '.select_box' do
  it 'picks the cheapest single box that fits everything' do
    items = [{ id: 'mug', dimensions: [12, 9, 9], weight: 0.4 }, { id: 'book', dimensions: [24, 17, 3], weight: 0.6 }]
    result = EasyBoxPacker.select_box(boxes: BOXES, items: items)
    expect(result[:boxes].map { |b| b[:box][:id] }).to eql(['M'])
    expect(result[:total_cost]).to eql(18)
    expect(placed_ids(result).sort).to eql(%w[book mug])
    expect(result[:unpacked]).to eql([])
    expect_valid_boxes(result)
  end

  it 'splits over several boxes when no single box fits' do
    items = Array.new(6) { |i| { id: i, dimensions: [33, 22, 12], weight: 1.2 } }
    result = EasyBoxPacker.select_box(boxes: BOXES, items: items)
    expect(result[:boxes].map { |b| b[:box][:id] }).to eql(%w[L L])
    expect(placed_ids(result).sort).to eql((0..5).to_a)
    expect_valid_boxes(result)
  end

  it 'respects box weight limits' do
    items = Array.new(4) { |i| { id: i, dimensions: [5, 5, 5], weight: 4 } }
    result = EasyBoxPacker.select_box(boxes: BOXES, items: items)
    result[:boxes].each { |b| expect(b[:weight]).to be <= b[:box][:weight_limit] }
    expect(placed_ids(result).sort).to eql((0..3).to_a)
  end

  it 'allow_multiple_boxes: false reports items instead of splitting' do
    items = Array.new(6) { |i| { id: i, dimensions: [33, 22, 12] } }
    result = EasyBoxPacker.select_box(boxes: BOXES, items: items, allow_multiple_boxes: false)
    expect(result[:boxes]).to eql([])
    expect(result[:unpacked].map { |u| u[:reason] }.uniq).to eql([:no_single_box])
  end

  it 'reports why items can not be packed' do
    items = [
      { id: 'heavy', dimensions: [10, 10, 10], weight: 25 },
      { id: 'pole', dimensions: [100, 5, 5] },
      { id: 'flat', dimensions: [0, 5, 5] },
      { id: 'ok', dimensions: [5, 5, 5] }
    ]
    result = EasyBoxPacker.select_box(boxes: BOXES, items: items)
    reasons = result[:unpacked].map { |u| [u[:item][:id], u[:reason]] }.to_h
    expect(reasons).to eql('heavy' => :too_heavy, 'pole' => :too_big, 'flat' => :invalid_dimensions)
    expect(result[:errors].size).to eql(3)
    expect(placed_ids(result)).to eql(['ok'])
  end

  it 'keeps padding free on every side' do
    result = EasyBoxPacker.select_box(boxes: BOXES, items: [{ id: 'x', dimensions: [19, 14, 9] }], padding: 2)
    expect(result[:boxes].first[:box][:id]).to eql('M')
    expect_valid_boxes(result, padding: 2)
  end

  it 'uses a custom cost' do
    by_volume = ->(box) { box[:dimensions].inject(:*) }
    free_large = ->(box) { box[:id] == 'L' ? 0 : 100 }
    items = [{ id: 1, dimensions: [5, 5, 5] }]
    expect(EasyBoxPacker.select_box(boxes: BOXES, items: items, cost: by_volume)[:boxes].first[:box][:id]).to eql('S')
    expect(EasyBoxPacker.select_box(boxes: BOXES, items: items, cost: free_large)[:boxes].first[:box][:id]).to eql('L')
  end

  it 'enforces max_items' do
    items = Array.new(51) { { dimensions: [1, 1, 1] } }
    expect { EasyBoxPacker.select_box(boxes: BOXES, items: items, max_items: 50) }.to raise_error(ArgumentError, /too many items/)
  end

  it 'returns valid packings for random input within the time limit' do
    rng = Random.new(3)
    20.times do
      boxes = Array.new(10) { |i| { id: i, dimensions: Array.new(3) { rng.rand(10..60) }, weight_limit: [nil, rng.rand(5..30)].sample(random: rng) } }
      items = Array.new(rng.rand(1..50)) { |i| { id: i, dimensions: Array.new(3) { rng.rand(2..30) + [0, 0.5].sample(random: rng) }, weight: rng.rand(0.1..3.0) } }
      result = EasyBoxPacker.select_box(boxes: boxes, items: items, time_limit: 0.5)
      expect((placed_ids(result) + result[:unpacked].map { |u| u[:item][:id] }).sort).to eql((0...items.size).to_a)
      expect_valid_boxes(result)
    end
  end

  it 'raises on invalid boxes and options' do
    expect { EasyBoxPacker.select_box(boxes: [], items: []) }.to raise_error(ArgumentError)
    expect { EasyBoxPacker.select_box(boxes: [{ dimensions: [1, 2] }], items: []) }.to raise_error(ArgumentError)
    expect { EasyBoxPacker.select_box(boxes: BOXES, items: [], padding: -1) }.to raise_error(ArgumentError)
    expect { EasyBoxPacker.select_box(boxes: BOXES, items: [], split_strategies: [:nope]) }.to raise_error(ArgumentError)
  end
end

describe 'tuning options' do
  it 'pack places every item hash so callers know which item goes where' do
    items = [{ id: 'a', dimensions: [2, 2, 2] }, { id: 'b', dimensions: [1, 1, 1] }]
    result = EasyBoxPacker.pack(container: { dimensions: [5, 5, 5] }, items: items)
    expect(result[:packings].first[:placements].map { |p| p[:item][:id] }.sort).to eql(%w[a b])
  end

  it 'split_strategies: [:legacy] reproduces the original packer' do
    container = { dimensions: [9, 19, 8] }
    items = [{ dimensions: [9, 11, 4] }, { dimensions: [19, 6, 1] }]
    legacy = EasyBoxPacker.pack(container: container, items: items, split_strategies: [:legacy], greedy_fallback: false)
    expect(legacy[:packings].size).to eql(2)
    expect(EasyBoxPacker.pack(container: container, items: items)[:packings].size).to eql(1)
  end

  it 'find_smallest_container accepts beam_width and max_side_values' do
    container = EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, time_limit: nil, beam_width: 2, max_side_values: 50)
    expect_fits(container, CASE_7_ITEMS)
    expect { EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, beam_width: 0) }.to raise_error(ArgumentError)
    expect { EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, max_side_values: 0) }.to raise_error(ArgumentError)
  end
end

describe 'item constraints' do
  def on_top?(lower, upper)
    xy = (0..1).all? do |k|
      lower[:position][k] < upper[:position][k] + upper[:dimensions][k] &&
        upper[:position][k] < lower[:position][k] + lower[:dimensions][k]
    end
    xy && upper[:position][2] >= lower[:position][2] + lower[:dimensions][2]
  end

  it 'keeps upright items standing, standing the box on another side when needed' do
    bottle = { id: 'bottle', dimensions: [10, 10, 30], upright: true }
    result = EasyBoxPacker.pack(container: { dimensions: [40, 35, 20] }, items: [bottle])
    expect(result[:errors]).to eq([])
    expect(result[:container_dimensions][2]).to be >= 30
    expect(result[:packings][0][:placements][0][:dimensions][2]).to eq(30)
  end

  it 'reports an upright item that is too tall on every side' do
    result = EasyBoxPacker.pack(container: { dimensions: [25, 20, 20] }, items: [{ dimensions: [5, 5, 30], upright: true }])
    expect(result[:errors].size).to eq(1)
  end

  it 'never puts anything on top of a fragile item' do
    egg  = { id: 'egg',  dimensions: [10, 10, 5], fragile: true }
    book = { id: 'book', dimensions: [10, 10, 5] }
    result = EasyBoxPacker.pack(container: { dimensions: [10, 10, 10] }, items: [egg, book])
    expect(result[:packings].size).to eq(1)
    placements = result[:packings][0][:placements]
    egg_pl  = placements.find { |p| p[:item].equal?(egg) }
    book_pl = placements.find { |p| p[:item].equal?(book) }
    expect(on_top?(egg_pl, book_pl)).to be(false)

    # stacking is the only way two of these fit, and a fragile one can not take that
    big_egg  = { dimensions: [10, 10, 6], fragile: true, upright: true }
    two_eggs = EasyBoxPacker.pack(container: { dimensions: [10, 10, 12] }, items: [big_egg, big_egg.dup])
    expect(two_eggs[:packings].size).to eq(2)
  end

  it 'find_smallest_container keeps the constraints' do
    items = [
      { dimensions: [10, 10, 30], upright: true },
      { dimensions: [20, 20, 5], fragile: true },
      { dimensions: [15, 10, 8] }
    ]
    dims = EasyBoxPacker.find_smallest_container(items: items, time_limit: nil)
    result = EasyBoxPacker.pack(container: { dimensions: dims }, items: items)
    expect(result[:packings].size).to eq(1)
    expect(result[:errors]).to eq([])
  end
end

describe '.loading_order' do
  it 'numbers placements bottom up and reports how well each is supported' do
    result = EasyBoxPacker.pack(
      container: { dimensions: [10, 10, 10] },
      items: [{ id: 'top', dimensions: [10, 10, 5] }, { id: 'small', dimensions: [5, 5, 5] }],
      split_strategies: [:legacy]
    )
    steps = EasyBoxPacker.loading_order(result[:packings][0][:placements])
    expect(steps.map { |s| s[:step] }).to eq([1, 2])
    expect(steps.first[:position][2]).to eq(0)
    expect(steps.first[:support]).to eq(1.0)
    steps.each_cons(2) { |a, b| expect(a[:position][2]).to be <= b[:position][2] }
  end

  it 'select_box adds step and support to every placement' do
    result = EasyBoxPacker.select_box(
      boxes: [{ dimensions: [30, 25, 20] }],
      items: Array.new(6) { { dimensions: [10, 10, 10] } }
    )
    placements = result[:boxes][0][:placements]
    expect(placements.map { |p| p[:step] }.sort).to eq((1..6).to_a)
    expect(placements.all? { |p| p[:support].between?(0, 1) }).to be(true)
  end
end

describe 'time_limit is an upper bound' do
  def elapsed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
  end

  # inside the box frame, no overlaps, upright kept, nothing on a fragile item, weight limit
  def constraint_problems(result)
    eps = 1e-9
    result[:boxes].flat_map do |b|
      frame = b[:container_dimensions]
      pls = b[:placements]
      problems = pls.flat_map do |pl|
        p = (0..2).select { |k| pl[:position][k] < -eps || pl[:position][k] + pl[:dimensions][k] > frame[k] + eps }.map { 'out of bounds' }
        p << 'upright' if pl[:item][:upright] && (pl[:dimensions][2] - pl[:item][:dimensions][2]).abs > eps
        p
      end
      pls.combination(2).each do |a, o|
        problems << 'overlap' if (0..2).all? { |k| a[:position][k] < o[:position][k] + o[:dimensions][k] - eps && o[:position][k] < a[:position][k] + a[:dimensions][k] - eps }
        [[a, o], [o, a]].each do |f, u|
          next unless f[:item][:fragile]
          xy = (0..1).all? { |k| f[:position][k] < u[:position][k] + u[:dimensions][k] - eps && u[:position][k] < f[:position][k] + f[:dimensions][k] - eps }
          problems << 'on top of fragile' if xy && u[:position][2] >= f[:position][2] + f[:dimensions][2] - eps
        end
      end
      problems << 'overweight' if b[:box][:weight_limit] && b[:weight] > b[:box][:weight_limit] + eps
      problems
    end
  end

  def random_items(n, rng, constrained: false)
    Array.new(n) do |i|
      { id: i, dimensions: [rng.rand(3..15), rng.rand(3..15), rng.rand(2..10)], weight: rng.rand(0.1..3.0).round(2),
        upright: constrained && rng.rand < 0.3, fragile: constrained && rng.rand < 0.1 }
    end
  end

  let(:boxes) do
    [[20, 15, 10], [30, 20, 15], [40, 30, 20], [50, 40, 30], [60, 40, 40], [80, 60, 50]].each_with_index.map do |d, i|
      { id: "B#{i}", dimensions: d, cost: (d.inject(:*) / 1000.0 + 2).round(2), weight_limit: (i.odd? ? 40 : nil) }
    end
  end

  # 0.4.0 took 2-4 s for these with time_limit 0.5. Loose bounds for slow CI machines.
  [false, true].each do |constrained|
    it "select_box stops at time_limit with 200 items (constrained: #{constrained}), every item placed validly" do
      items = random_items(200, Random.new(constrained ? 2 : 1), constrained: constrained)
      result, seconds = elapsed { EasyBoxPacker.select_box(boxes: boxes, items: items, time_limit: 0.3) }
      expect(seconds).to be < 0.3 * 1.2 + 0.15
      expect(placed_ids(result).sort).to eql((0...200).to_a)
      expect(result[:unpacked]).to eql([])
      expect(constraint_problems(result)).to eql([])
    end
  end

  it 'select_box with time_limit 0 still returns a valid answer for every item' do
    items = random_items(60, Random.new(3), constrained: true) + [{ id: 'tall', dimensions: [10, 10, 45], upright: true }]
    result = EasyBoxPacker.select_box(boxes: boxes, items: items, time_limit: 0)
    expect(placed_ids(result).sort_by(&:to_s)).to eql(items.map { |i| i[:id] }.sort_by(&:to_s))
    expect(constraint_problems(result)).to eql([])
  end

  it 'select_box out of time puts items that need different boxes in different boxes' do
    big   = { id: 'big', dimensions: [75, 55, 45], weight: 1 }
    small = Array.new(30) { |i| { id: i, dimensions: [8, 8, 8], weight: 0.2 } }
    result = EasyBoxPacker.select_box(boxes: boxes, items: [big] + small, time_limit: 0)
    expect(placed_ids(result).sort_by(&:to_s)).to eql(([big] + small).map { |i| i[:id] }.sort_by(&:to_s))
    expect(constraint_problems(result)).to eql([])
  end

  it 'select_box without allow_multiple_boxes out of time: one box or every item no_single_box' do
    items = random_items(200, Random.new(4))
    result = EasyBoxPacker.select_box(boxes: boxes, items: items, time_limit: 0, allow_multiple_boxes: false)
    expect(result[:boxes].size + (result[:unpacked].empty? ? 0 : 1)).to eql(1)
    expect(result[:unpacked].map { |u| u[:reason] }.uniq).to eql([:no_single_box]) unless result[:unpacked].empty?
    expect(placed_ids(result).size + result[:unpacked].size).to eql(200)
    expect(constraint_problems(result)).to eql([])
  end

  it 'select_box gives the same answer with a generous time_limit as without one' do
    items = random_items(30, Random.new(5), constrained: true)
    expect(EasyBoxPacker.select_box(boxes: boxes, items: items, time_limit: 60))
      .to eql(EasyBoxPacker.select_box(boxes: boxes, items: items, time_limit: nil))
  end

  it 'find_smallest_container stops at time_limit with 200 items and the container holds them' do
    items = random_items(200, Random.new(6))
    container, seconds = elapsed { EasyBoxPacker.find_smallest_container(items: items, time_limit: 0.3) }
    expect(seconds).to be < 0.3 * 1.2 + 0.15
    expect_fits(container, items)
  end

  it 'find_smallest_container gives the same answer with a generous time_limit and max_attempts as with nil' do
    expect(EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, time_limit: 60, max_attempts: 50))
      .to eql(EasyBoxPacker.find_smallest_container(items: CASE_7_ITEMS, time_limit: nil, max_attempts: 50))
  end
end
