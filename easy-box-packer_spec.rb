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
