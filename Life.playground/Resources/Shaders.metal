using namespace metal;

struct Vertex {
  float4 position [[position]];
  float2 uv;
};

vertex Vertex vertex_shader(constant float4 *vertices [[buffer(0)]],
                            uint id [[vertex_id]]) {
  return {
    .position = vertices[id],
    .uv = (vertices[id].xy + float2(1)) / float2(2)
  };
}

fragment float4 fragment_shader(Vertex vtx [[stage_in]],
                                texture2d<uint> generation [[texture(0)]]) {
  constexpr sampler smplr(coord::normalized,
                          address::clamp_to_zero,
                          filter::nearest);
  uint cell = generation.sample(smplr, vtx.uv).r;
  return float4(cell);
}

kernel void generation(texture2d<uint, access::read> current [[texture(0)]],
                       texture2d<uint, access::write> next [[texture(1)]],
                       uint2 index [[thread_position_in_grid]]) {

  short live_neighbours = 0;
  
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      if (i != 0 || j != 0) {
        uint2 neighbour = index + uint2(i, j);
        if (1 == current.read(neighbour).r) {
          live_neighbours++;
        }
      }
    }
  }
  
  bool is_alive = 1 == current.read(index).r;
  
  if (is_alive) {
    if (live_neighbours < 2) {
      next.write(0, index);  // die from under-population
    } else if (live_neighbours > 3) {
      next.write(0, index);  // die from over-population
    } else {
      next.write(1, index);  // stay alive
    }
  } else {  // !is_alive
    if (live_neighbours == 3) {
      next.write(1, index);  // newborn cell
    } else {
      next.write(0, index);  // stay dead
    }
  }
}
