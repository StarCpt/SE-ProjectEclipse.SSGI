#ifndef LIB_SSR_DEFS_BINDINGS
#define LIB_SSR_DEFS_BINDINGS

#include "../math.hlsli"
#include "../random.hlsli"
#include "brdf_ggx.hlsli"

#define REFLECT_GLOSS_THRESHOLD 0
#define MIRROR_REFLECTION_THRESHOLD 0.95
#define REFLECTION_ONLY 0
#define INVERTED_DEPTH 1 // inverted if bigger = closer
#define NUM_THREADS_XY 8 // only used in compute shaders
#define BRDF_BIAS 0

#define RT_FULL 0
#define RT_HALF 1
#define RT_QUARTER 2

#ifndef RT_RES // for development only, use shader define for release
#define RT_RES RT_FULL
#endif

struct SSRInput
{
    float3 Color;
    float3 NormalView;
    float Depth;
    float Metalness;
    float Gloss;
    
    bool IsForeground;
    
    float3 PositionView;
    float3 RayDirView;
};

struct PackedReservoir
{
    float3 CreatedPos;
    uint CreatedNormalOctPacked;
    float3 LightPos;
    uint LightNormalOctPacked;
    uint2 LightRadiancePacked;
    uint M_Age;
    float AvgWeight;
};

struct RestirReservoir
{
    float3 CreatedPos;
    float3 CreatedNormal;
    float3 LightPos;
    float3 LightNormal;
    float3 LightRadiance;
    uint M;
    float AvgWeight;
    uint Age;
    
    static RestirReservoir CreateEmpty()
    {
        RestirReservoir res;
        res.CreatedPos = 0;
        res.CreatedNormal = float3(0, 0, 1);
        res.LightPos = float3(0, 0, 1);
        res.LightNormal = float3(0, 0, -1);
        res.LightRadiance = 0;
        res.M = 0;
        res.AvgWeight = 1;
        res.Age = 0;
        return res;
    }
    
    PackedReservoir Pack()
    {
        PackedReservoir packed;
        packed.CreatedPos = CreatedPos;
        packed.LightPos = LightPos;
        
        float2 createdNormalOct = EncodeOctNormal(CreatedNormal);
        float2 lightNormalOct = EncodeOctNormal(LightNormal);
        packed.CreatedNormalOctPacked = f32tof16(createdNormalOct.x) | (f32tof16(createdNormalOct.y) << 16);
        packed.LightNormalOctPacked = f32tof16(lightNormalOct.x) | (f32tof16(lightNormalOct.y) << 16);
        
        // don't encode radiance bruh
        packed.LightRadiancePacked = uint2(f32tof16(LightRadiance.x) | (f32tof16(LightRadiance.y) << 16), asuint(LightRadiance.z));
        
        packed.M_Age = (M << 16) | (Age & 0xffff);
        packed.AvgWeight = AvgWeight;
        return packed;
    }
    
    static RestirReservoir Unpack(const PackedReservoir packed)
    {
        RestirReservoir res;
        res.CreatedPos = packed.CreatedPos;
        res.LightPos = packed.LightPos;
        
        res.CreatedNormal = DecodeOctNormal(float2(f16tof32(packed.CreatedNormalOctPacked), f16tof32(packed.CreatedNormalOctPacked >> 16)));
        res.LightNormal = DecodeOctNormal(float2(f16tof32(packed.LightNormalOctPacked), f16tof32(packed.LightNormalOctPacked >> 16)));
        
        res.LightRadiance = float3(f16tof32(packed.LightRadiancePacked.x), f16tof32(packed.LightRadiancePacked.x >> 16), asfloat(packed.LightRadiancePacked.y));
        
        res.M = (packed.M_Age >> 16);
        res.AvgWeight = packed.AvgWeight;
        res.Age = (packed.M_Age & 0xffff);
        return res;
    }
};

SamplerState PointSampler     : register(s1);
SamplerState LinearSampler    : register(s2);

Texture2D<float> DepthBuffer  : register(t0);
Texture2D<float4> Gbuffer0    : register(t1);
Texture2D<float4> Gbuffer1    : register(t2);
Texture2D<float4> Gbuffer2    : register(t3);
Texture2D<float> HZB          : register(t4);

Texture2D<float3> FrameBuffer : register(t5);

// ReSTIR buffers
#ifdef RESTIR_CS
RWTexture2D<float4> RestirOutputTexture                 : register(u0);
RWTexture2D<float4> RestirOutputTexture2                : register(u1);
RWStructuredBuffer<PackedReservoir> PrevReservoirs      : register(u2);
RWStructuredBuffer<PackedReservoir> CandidateReservoirs : register(u3);
RWStructuredBuffer<PackedReservoir> TemporalReservoirs  : register(u4);
RWStructuredBuffer<PackedReservoir> SpatialReservoirs   : register(u5);
RWTexture2D<float> ReflectionDepths                     : register(u6);
#endif

cbuffer constants : register(b1)
{
    uint FrameIndex;
    int2 ScreenSize;
    uint RandomSeed;
    
    float3 CameraDelta;
    uint _padding1;
    
    uint MaxTraceIterations;
    uint RaysPerPixel;
    float IndirectLightMulti;
    uint _padding3;
    
    float4x4 ViewMatrix;
    float4x4 ProjMatrix;
    float4x4 ViewProjMatrix;
    float4x4 InvProjMatrix;
    float4x4 InvViewProjMatrix;
    
    float4x4 PrevViewMatrix;
    float4x4 PrevProjMatrix;
    float4x4 PrevViewProjMatrix;
    float4x4 PrevInvProjMatrix;
    float4x4 PrevInvViewProjMatrix;
};

bool IsDepthForeground(float depth)
{
#if INVERTED_DEPTH
    return depth > 0;
#else
    return depth < 1;
#endif
}

float2 ViewToTex(float3 viewPos)
{
    float4 clipPos = mul(float4(viewPos, 1), ProjMatrix);
    clipPos.xy /= clipPos.w;
    
    float2 texPos = clipPos.xy * float2(0.5, -0.5) + 0.5;
    return texPos;
}

float3 ViewToClip(float3 viewPos)
{
    float4 clipPos = mul(float4(viewPos, 1), ProjMatrix);
    return clipPos.xyz /= clipPos.w;
}

float3 ViewToTexAndLinearDepth(float3 viewPos)
{
    float4 clipPos = mul(float4(viewPos, 1), ProjMatrix);
    clipPos.xy /= clipPos.w;
    
    float2 texPos = clipPos.xy * float2(0.5, -0.5) + 0.5;
    float depth = -viewPos.z;
    
    return float3(texPos, depth);
}

float2 ClipToTex(float2 clipPos)
{
    // transform clip space to tex space
    // top left -> bottom right
    // clip space: (-1, 1) -> (1, -1)
    // tex space: (0, 0) -> (1, 1)
    
    clipPos.xy *= float2(0.5, -0.5);
    clipPos.xy += 0.5;
    return clipPos;
}

float2 TexToClip(float2 texPos)
{
    // transform clip space to tex space
    // top left -> bottom right
    // clip space: (-1, 1) -> (1, -1)
    // tex space: (0, 0) -> (1, 1)
    
    texPos -= 0.5;
    texPos *= float2(2, -2);
    return texPos;
}

float3 TexToView(float2 texPos, float depth)
{
    float4 clipPos = float4(TexToClip(texPos.xy), depth, 1);
    float4 viewPos = mul(clipPos, InvProjMatrix);
    return viewPos.xyz / viewPos.w;
}

float3 ClipToWorld(float3 clipPos)
{
    float4 worldPos = mul(float4(clipPos, 1), InvViewProjMatrix);
    return worldPos.xyz / worldPos.w;
}

float3 TexToWorld(float2 texPos, float depth)
{
    float4 clipPos = float4(TexToClip(texPos.xy), depth, 1);
    float4 worldPos = mul(clipPos, InvViewProjMatrix);
    return worldPos.xyz / worldPos.w;
}

float3 compute_screen_ray(float2 uv)
{
    const float ray_x = 1. / ProjMatrix._11;
    const float ray_y = 1. / ProjMatrix._22;
    float3 projOffset = float3(ProjMatrix._31 / ProjMatrix._11,
		ProjMatrix._32 / ProjMatrix._22, 0);
    return projOffset + float3(lerp(-ray_x, ray_x, uv.x), -lerp(-ray_y, ray_y, uv.y), -1.);
}

float compute_depth(float hw_depth)
{
    return ProjMatrix._43 / (max(hw_depth, 1e-36) + ProjMatrix._33);
}

SSRInput LoadSSRInput(uint2 pixelPos)
{
    const float hw_depth = DepthBuffer[pixelPos];
    const float4 gbuffer0 = Gbuffer0[pixelPos];
    const float4 gbuffer1 = Gbuffer1[pixelPos];
    const float4 gbuffer2 = Gbuffer2[pixelPos];
    
    float ambientOcclusion = gbuffer1.b;
    
    SSRInput input;
    input.Color = gbuffer0.xyz /** ambientOcclusion*/;
    
    float3 viewNormal = normalize(unpack_normals2(gbuffer1.xy));
    input.NormalView = all(!isnan(viewNormal)) ? viewNormal : float3(0, 0, 1);
    
    input.Depth = hw_depth;
    input.Metalness = gbuffer2.x;
    input.Gloss = gbuffer2.y;
    
    input.IsForeground = IsDepthForeground(hw_depth);
    
    float2 uv = (pixelPos + 0.5) / float2(ScreenSize);
    float3 screenRay = compute_screen_ray(uv); // I guess this has a z length of 1? (so it needs to be normalized)
    
    input.PositionView = TexToView(uv, hw_depth);
    input.RayDirView = normalize(screenRay);
    
    return input;
}

float3 LoadNormalInViewSpace(float2 uv)
{
    float4 gbuffer1 = Gbuffer1.SampleLevel(PointSampler, uv, 0);
    float3 viewNormal = unpack_normals2(gbuffer1.xy);
    return viewNormal;
}

float3 LoadNormalInViewSpacePixel(int2 pixel)
{
    float4 gbuffer1 = Gbuffer1[pixel];
    float3 viewNormal = unpack_normals2(gbuffer1.xy);
    return viewNormal;
}

float LoadDepth(float2 uv)
{
    return HZB.SampleLevel(PointSampler, uv, 0);
}

float LoadDepthPixel(int2 pixel)
{
    return HZB[pixel];
}

float3 LoadFrameColor(SamplerState s, float2 uv, float mip = 1)
{
    return FrameBuffer.SampleLevel(s, uv, mip).xyz;
}

float3 ReconstructViewPosition(float2 uv)
{
    return TexToView(uv, HZB.SampleLevel(PointSampler, uv, 0));
}

#ifdef RESTIR_CS
RestirReservoir _LoadReservoir(RWStructuredBuffer<PackedReservoir> buffer, uint2 pixelPos)
{
    const uint screenResX = ScreenSize.x;
    PackedReservoir packed = buffer[pixelPos.y * screenResX + pixelPos.x];
    return RestirReservoir::Unpack(packed);
}

void _StoreReservoir(RWStructuredBuffer<PackedReservoir> buffer, uint2 pixelPos, RestirReservoir res)
{
    const uint screenResX = ScreenSize.x;
    buffer[pixelPos.y * screenResX + pixelPos.x] = res.Pack();
}
#endif

float2 NextFloat2(inout uint randState)
{
    return float2(NextFloat(randState), NextFloat(randState));
}

float InterleavedGradientNoise(float2 position_screen)
{
    float3 magic = float3(0.06711056f, 0.00583715f, 52.9829189f);
    return frac(magic.z * frac(dot(position_screen, magic.xy)));
}

uint2 ComputeMipSize(const uint2 textureSize, const uint mip)
{
    return max(1, textureSize >> mip);
}

//#include "brdf_unity.hlsli"

float ComputeReflectionPdf(SSRInput input, float3 lightColor, float3 lightDirView)
{
    //return luminance(BRDF_Unity_Weight(-input.RayDirView, lightDirView, input.NormalView, 1 - input.Gloss) * lightColor);
    float3 brdf = Brdf(1 - input.Gloss, input.Metalness, input.Color, -input.RayDirView, lightDirView, input.NormalView);
    float3 estimatedPdf = brdf * lightColor;
    return luminance(estimatedPdf);
}

// input must be 65535 or less (uint16)
// it's uint32 here because 16 bit scalars are not available in this version of hlsl
uint2 DecodeMortonIndex(const uint mortonCode)
{
    uint t = (mortonCode & 0x5555) | ((mortonCode & 0xAAAA) << 15);
    t = (t ^ (t >> 1)) & 0x33333333;
    t = (t ^ (t >> 2)) & 0x0F0F0F0F;
    t = (t ^ (t >> 4));
    
    return uint2(t, t >> 16) & 0xFF;
}

int2 RandomPixelInDisk(float2 pixelCenter, float radiusInPixels, inout uint rand)
{
    // test removing the sqrt to deliberately weigh the 'random' position closer to pixelCenter
    float r = lerp(1, radiusInPixels, sqrt(NextFloat(rand)));
    float theta = NextFloat(rand) * PI_2;
    
    float2 pos;
    sincos(theta, pos.y, pos.x);
    pos *= r;
    pos += pixelCenter;
    return (int2) round(pos);
}

inline float2 GetScreenSize()
{
    return float2(ScreenSize);
}

#endif
