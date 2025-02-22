#include "common.hlsli"
#include "brdf_unity.hlsli"

#define THREADS_XY 8

RWTexture2D<float4> outputTex          : register(u0);
RWTexture2D<float4> intermediateTexUav : register(u1);
Texture2D<float4> intermediateTexSrv   : register(t6); // same as above bound as srv
Texture2D<float3> reflectionTex        : register(t7);
Texture2D<float3> prevReflectionTex    : register(t8);

[numthreads(THREADS_XY, THREADS_XY, 1)]
void cs_trace(const uint3 dispatchThreadId : SV_DispatchThreadID)
{
    // sssr sample generation (ray tracing) pass
    
    const uint2 pixelPos = dispatchThreadId.xy;
    const uint pixelIndex = pixelPos.y * GetScreenSize().x + pixelPos.x;
    const float2 uv = (dispatchThreadId.xy + 0.5) / GetScreenSize();
    uint randSeed = pixelIndex * RandomSeed;
    
    SSRInput input = LoadSSRInput(pixelPos);
    
    float3 reflectDir;
    float pdf;
    GenerateGGXRayAndPdf(input, reflectDir, pdf, randSeed);
    
    float2 rayHitUV;
    float rayPdf = pdf;
    float rayHitConfidence;
    rayHitConfidence = TraceRayHiZ(uv, input, reflectDir, rayHitUV);
    
    intermediateTexUav[pixelPos] = float4(rayHitUV, rayPdf, rayHitConfidence);
}

float2 ComputePrevUV(float2 currentUV)
{
    float3 worldPos = TexToWorld(currentUV, HZB.SampleLevel(PointSampler, currentUV, 0));
    worldPos += CameraDelta;
    float4 prevClipPos = mul(float4(worldPos, 1), PrevViewProjMatrix);
    return ClipToTex(prevClipPos.xy / prevClipPos.w);
}

static const float2 offset[4] = // why are there 2 very similarly named variables...
{
    float2(0, 0),
	float2(2, -2),
	float2(-2, -2),
	float2(0, 2)
};

#define USE_WEIGHT_NORMALIZATION 0
#define REMOVE_FIREFLIES 0

[numthreads(THREADS_XY, THREADS_XY, 1)]
void cs_resolve(const uint3 dispatchThreadId : SV_DispatchThreadID)
{
    // sssr resolve with multiple neighbor pixels
    
    const uint2 pixelPos = dispatchThreadId.xy;
    const uint pixelIndex = pixelPos.y * GetScreenSize().x + pixelPos.x;
    const float2 uv = (dispatchThreadId.xy + 0.5) / GetScreenSize();
    uint randSeed = pixelIndex * RandomSeed;
    
    //outputTex[pixelPos] = float4(FrameBuffer.SampleLevel(LinearSampler, uv, 4).xyz, 1);
    //return;
    
    SSRInput input = LoadSSRInput(pixelPos);
    
    float2 rand2 = NextFloat2(randSeed) * 2.0 - 1.0; // better if blue noise but this will do for now. interleaved gradient noise might be ok as well?
    float2x2 offsetRotationMatrix = float2x2(rand2.x, rand2.y, -rand2.y, rand2.x);
    
    float n_dot_v = saturate(dot(input.NormalView, -input.RayDirView));
    float roughness = 1.0 - input.Gloss;
    float brdfBias = BRDF_BIAS;
    float coneTangent = lerp(0, roughness * (1.0 - brdfBias), n_dot_v * sqrt(roughness));
    
    float maxMipLevel = 4;
    
    float3 result = 0;
    float weightSum = 0;
    
    static const uint numResolveSamples = 1; // 4 to enable reuse
    
    for (uint i = 0; i < numResolveSamples; i++)
    {
        float2 offsetUV = offset[i] * (1.0 / GetScreenSize());
        offsetUV = mul(offsetRotationMatrix, offsetUV);

        float2 neighborUV = uv + offsetUV;
        
        float4 hitPacked = intermediateTexSrv.SampleLevel(PointSampler, neighborUV, 0);
        float2 hitUV = hitPacked.xy;
        float rayPdf = hitPacked.z;
        float hitConfidence = hitPacked.w;
        
        float3 hitPosView = ReconstructViewPosition(hitUV);
        
        float weight = 1.0;
        
#if USE_WEIGHT_NORMALIZATION
        weight = BRDF_Unity_Weight(normalize(-input.RayDirView), normalize(hitPosView - input.PositionView), input.NormalView, 1.0 - input.Gloss) / max(1e-5, rayPdf);
#endif
        
        float intersectionCircleRadius = coneTangent * length(hitUV - uv);
        float mip = clamp(log2(intersectionCircleRadius * max(GetScreenSize().x, GetScreenSize().y)), 0, maxMipLevel);
        
        float3 hitColor = 0;
        hitColor = FrameBuffer.SampleLevel(LinearSampler, hitUV, mip);
        
#if REMOVE_FIREFLIES
        hitColor /= 1 + luminance(hitColor);
#endif
        
        result += hitColor * weight * hitConfidence;
        weightSum += weight;
    }
    
    result /= weightSum;
    
#if REMOVE_FIREFLIES
    result /= 1 - luminance(result);
#endif
    
    result = max(1e-5, result);
    
    float3 combinedColor;
    
    float3 albedo = input.Color * (1 - input.Metalness);
    float3 specular = lerp(DIELECTRIC_REFLECTANCE_F0, input.Color, input.Metalness);
    
    float oneMinusReflectivity;
    albedo = EnergyConservationBetweenDiffuseAndSpecular(albedo, specular, oneMinusReflectivity);
    
    UnityLight light;
    light.color = 0;
    light.dir = 0;
    light.ndotl = 0;

    UnityIndirect ind;
    ind.diffuse = 0;
    ind.specular = result;
    
    combinedColor = BRDF1_Unity_PBS(0, specular, oneMinusReflectivity, input.Gloss, input.NormalView, -input.RayDirView, light, ind).xyz;
    //combinedColor += FrameBuffer[pixelPos];

    outputTex[pixelPos] = float4(combinedColor, 1);
}

float2 ComputeMotionWithRespectToHitDepth(float2 currentUv, float hitDepthRaw/*, out float2 prevUV*/)
{
    float3 clipPos = float3(TexToClip(currentUv), hitDepthRaw);
    float3 worldPos = ClipToWorld(clipPos);
    
    float4 prevClipPos = mul(float4(worldPos + CameraDelta, 1), PrevViewProjMatrix);
    float4 currClipPos = mul(float4(worldPos, 1), ViewProjMatrix); // isn't this just clipPos from above?
    
    float2 prevTexPos = ClipToTex(prevClipPos.xy / prevClipPos.w);
    float2 currTexPos = ClipToTex(currClipPos.xy / currClipPos.w);
    
    //prevUV = prevTexPos;
    return currTexPos - prevTexPos;
}

void ps_temporal(const float4 position : SV_Position, const float2 uv : TEXCOORD0, out float3 reflectionOutput : SV_Target0, out float3 blendedOutput : SV_Target1)
{
    const uint2 pixelPos = position.xy;
    
    float depth = LoadDepthPixel(pixelPos);
    if (!IsDepthForeground(depth))
    {
        reflectionOutput = 0;
        blendedOutput = FrameBuffer[pixelPos];
        return;
    }
        
    const float scale = 2; // config
    const float response = 0.9; // also config
    
    float4 hitPacked = intermediateTexSrv[pixelPos];
    float2 hitUV = hitPacked.xy;
    float rayPdf = hitPacked.z;
    float hitConfidence = hitPacked.w;
    float hitDepth = HZB.SampleLevel(PointSampler, hitUV, 0);
    
    float2 velocity = ComputeMotionWithRespectToHitDepth(uv, hitConfidence != 0 ? hitDepth : depth);
    float2 prevUV = uv - velocity;
    
    //float2 prevUV = ComputePrevUV(uv);
    //float2 velocity = uv - prevUV;
    
    SamplerState _sampler = PointSampler;
    
    float3 current = reflectionTex.SampleLevel(_sampler, uv, 0);
    float3 previous = prevReflectionTex.SampleLevel(_sampler, prevUV, 0); // keep prev reflection-only framebuffer and sample from that
    
    float2 du = float2(1.0 / GetScreenSize().x, 0);
    float2 dv = float2(0, 1.0 / GetScreenSize().y);
    
    float3 currentTopLeft = reflectionTex.SampleLevel(_sampler, uv - dv - du, 0);
    float3 currentTopCenter = reflectionTex.SampleLevel(_sampler, uv - dv, 0);
    float3 currentTopRight = reflectionTex.SampleLevel(_sampler, uv - dv + du, 0);
    float3 currentMiddleLeft = reflectionTex.SampleLevel(_sampler, uv - du, 0);
    float3 currentMiddleCenter = reflectionTex.SampleLevel(_sampler, uv, 0);
    float3 currentMiddleRight = reflectionTex.SampleLevel(_sampler, uv + du, 0);
    float3 currentBottomLeft = reflectionTex.SampleLevel(_sampler, uv + dv - du, 0);
    float3 currentBottomCenter = reflectionTex.SampleLevel(_sampler, uv + dv, 0);
    float3 currentBottomRight = reflectionTex.SampleLevel(_sampler, uv + dv + du, 0);
    
    float3 currentMin = min(currentTopLeft, min(currentTopCenter, min(currentTopRight, min(currentMiddleLeft, min(currentMiddleCenter, min(currentMiddleRight, min(currentBottomLeft, min(currentBottomCenter, currentBottomRight))))))));
    float3 currentMax = max(currentTopLeft, max(currentTopCenter, max(currentTopRight, max(currentMiddleLeft, max(currentMiddleCenter, max(currentMiddleRight, max(currentBottomLeft, max(currentBottomCenter, currentBottomRight))))))));
    
    float3 center = (currentMin + currentMax) * 0.5f;
    currentMin = (currentMin - center) * scale + center;
    currentMax = (currentMax - center) * scale + center;
    
    //previous = clamp(previous, currentMin, currentMax); // TODO: find out why this line makes the image look awful
    
    reflectionOutput = lerp(current, previous, saturate(response * (1 - length(velocity) * 8))); // reflection only
    blendedOutput = FrameBuffer[pixelPos] + reflectionOutput;
}
