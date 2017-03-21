require 'easy-box-packer'
require 'pry'
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
    expect(packings[:packings][2][:placements][0][:dimensions]).to eql([1, 3, 3])
    expect(packings[:packings][2][:placements][0][:position]).to eql([0, 0, 0])
    expect(packings[:packings][2][:placements][1][:dimensions]).to eql([4, 1, 1])
    expect(packings[:packings][2][:placements][1][:position]).to eql([1, 0, 0])
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
      expect(packings[:errors]).to eql(["Item: {:dimensions=>[40, 10, 34]} cannot be placed in container"])
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
  end
end

describe '.find_smallest_container' do
  it 'can get smallest container' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(10) {{ dimensions: [1, 1, 1] }}
      )
    expect(container).to eql({length: 1, width: 1, height: 10.0})
  end

  it 'can get smallest container' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(100) {{ dimensions: [1, 1, 1] }} + [{ dimensions: [10, 5, 1] }]
      )
    expect(container).to eql({length: 10, width: 5, height: 3.0})
  end

  it 'case 5' do
    container = EasyBoxPacker.find_smallest_container(
      items: [
        { dimensions: [10, 20, 11] },
        { dimensions: [20, 20, 5]  },
        { dimensions: [20, 20, 4]  },
        { dimensions: [20, 20, 1]  }
      ]
    )
    expect(container).to eq({length: 20, width: 20, height: 20})
    packings = EasyBoxPacker.pack(
      container: { dimensions: [20, 20, 20] },
      items: [
        { dimensions: [10, 20, 11] },
        { dimensions: [20, 20, 5]  },
        { dimensions: [20, 20, 4]  },
        { dimensions: [20, 20, 1]  }
      ]
    )
    expect(packings[:packings].length).to eql(1)
  end
end
