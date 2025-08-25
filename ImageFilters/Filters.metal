


#include <metal_stdlib>
using namespace metal;


// Clamp helper for integer coords
inline uint clampCoord(int v, uint lo, uint hi) {
    return (uint) max((int)lo, min(v, (int)hi));
}

kernel void fx_invert(texture2d<float, access::read>  inTex  [[texture(0)]],
                      texture2d<float, access::write> outTex [[texture(1)]],
                      uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 c = inTex.read(gid);
    outTex.write(float4(1.0 - c.rgb, c.a), gid);
}

kernel void fx_moreblue(texture2d<float, access::read>  inTex  [[texture(0)]],
                        texture2d<float, access::write> outTex [[texture(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    float4 c = inTex.read(gid);          // read texel at integer coord
    c.b = clamp(c.b + 0.2, 0.0, 1.0);    // add blue, clamp
    outTex.write(c, gid);
}



kernel void fx_grayscale(texture2d<float, access::read>  inTex  [[texture(0)]],
                         texture2d<float, access::write> outTex [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 c = inTex.read(gid);
    float g = dot(c.rgb, float3(0.299, 0.587, 0.114));
    outTex.write(float4(g, g, g, c.a), gid);
}


kernel void fx_box3x3(texture2d<float, access::read>  inTex  [[texture(0)]],
                      texture2d<float, access::write> outTex [[texture(1)]],
                      uint2 gid [[thread_position_in_grid]])
{
    const uint W = outTex.get_width();
    const uint H = outTex.get_height();
    if (gid.x >= W || gid.y >= H) return;

    float4 acc = float4(0.0);
    int2 base = int2(gid);

    // 3x3 neighborhood offsets
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            uint sx = clampCoord(base.x + i, 0, W - 1);
            uint sy = clampCoord(base.y + j, 0, H - 1);
            acc += inTex.read(uint2(sx, sy));
        }
    }

    outTex.write(acc / 9.0, gid);
}




