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

describe '.find_smallest_container' do
  it 'can get smallest container- with 10 items' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(10) {{ dimensions: [1, 1, 1] }}
      )
    expect(container).to eql([2.0, 2.0, 3.0])
  end

  it 'can get smallest container - with 100 items' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(100) {{ dimensions: [1, 1, 1] }}
      )
    expect(container).to eql([4.0, 5.0, 5.0])
  end

  it 'can get smallest container - with 100 items' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(100) {{ dimensions: [10, 5, 4] }}
      )
    expect(container).to eql([26.0, 29.0, 36.0])
  end

  it 'can get smallest container - with 100 items' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(100) {{ dimensions: [4, 5, 5] }}
      )
    expect(container).to eql([21.0, 24.0, 26.0])
  end

  it 'can get smallest container - with 1000 items' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(1000) {{ dimensions: [1, 1, 1] }}
      )
    expect(container).to eql([10.0, 10.0, 10.0])
  end

  it 'case 1' do
    container = EasyBoxPacker.find_smallest_container(
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
    container = EasyBoxPacker.find_smallest_container(
      items: [
        { dimensions: [4, 7, 9] },
        { dimensions: [3, 2, 1] }
      ]
    )
    expect(container).to eql([4.0, 7.0, 10.0])
  end

  it 'case 3' do
    container = EasyBoxPacker.find_smallest_container(
      items: [
        { dimensions: [4, 7, 9] },
        { dimensions: [3, 2, 1] },
        { dimensions: [7, 7, 5] }
      ]
    )
    expect(container).to eql([5.0, 7.0, 16.0])
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
    container = EasyBoxPacker.find_smallest_container(
      items: [
        { dimensions: [10, 20, 11] }
      ]
    )

    expect(container).to eq([10.0, 20.0, 11.0])
  end

  it 'case 7' do
    container = EasyBoxPacker.find_smallest_container(
      items: [
        {dimensions: [110, 30, 10]}, {dimensions: [110, 20, 10]}, {dimensions: [110, 10, 5]},
        {dimensions: [110, 30, 10]}, {dimensions: [110, 20, 10]}, {dimensions: [110, 10, 5]},
        {dimensions: [110, 30, 10]}, {dimensions: [110, 20, 10]}, {dimensions: [110, 10, 5]}
      ]
    )
    expect(container).to eq([30.0, 60.0, 110.0])
  end

  it 'case 8' do
    container = EasyBoxPacker.find_smallest_container(
      items: [
        {dimensions: [26.0, 26.0, 26.5]},
        {dimensions: [18.0, 23.0, 39.0]},
        {dimensions: [39.0, 14.0, 33.5]}
      ]
    )
    expect(container).to eq([33.5, 39.0, 58.0])
  end

  it 'case 9' do
    container = EasyBoxPacker.find_smallest_container(
        items: Array.new(67) {{ dimensions: [36.0, 27.0, 0.3] }}
      )

    expect(container).to eql([36.0, 27.0, 20.1])
  end

  it 'case 10' do
    container = EasyBoxPacker.find_smallest_container(
        items: [
          { dimensions: [13, 23.5, 48] },
          { dimensions: [13, 23.5, 48] },
          { dimensions: [13, 23.5, 48] }
        ]
      )
    expect(container).to eql([48, 23.5, 39.0])
  end


  it 'case 11' do
    container = EasyBoxPacker.find_smallest_container(
        items: [
          { dimensions: [73, 8, 4] },
          { dimensions: [39, 34, 4] },
          { dimensions: [40, 7, 5] },
          { dimensions: [21, 8, 7] },
          { dimensions: [27, 27, 17] }
        ]
      )
    expect(container).to eql([34.0, 34.0, 79.0])
  end


  it 'case 12' do
    container = EasyBoxPacker.find_smallest_container(
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
