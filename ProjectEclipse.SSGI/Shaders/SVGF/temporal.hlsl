#include "../math.hlsli"
#include "../color.hlsli"

SamplerState PointSampler : register(s1);
SamplerState LinearSampler : register(s2);

Texture2D<float3> CurrentFrame      : register(t0);
Texture2D<float3> History           : register(t1);
Texture2D<float> DepthBuffer        : register(t2);
Texture2D<float> PrevDepthBuffer    : register(t3);
Texture2D<float4> HistoryAndMoments : register(t4);
Texture2D<float> ReflectionDepths   : register(t5);
Texture2D<float4> GBuffer1          : register(t6);

cbuffer TemporalConstants : register(b0)
{
    float2 ScreenSize;
    float MaxHistoryLength;
    float InvViewDistance;
    
    float3 CameraDelta;
    float _padding2;
    
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

float2 ClipToTex(float2 clipPos)
{
    clipPos.xy *= float2(0.5, -0.5);
    clipPos.xy += 0.5;
    return clipPos;
}

float2 TexToClip(float2 texPos)
{
    texPos -= 0.5;
    texPos *= float2(2, -2);
    return texPos;
}

float3 TexToWorld(float2 texPos, float depth)
{
    float4 clipPos = float4(TexToClip(texPos.xy), depth, 1);
    float4 worldPos = mul(clipPos, InvViewProjMatrix);
    return worldPos.xyz / worldPos.w;
}

float3 ClipToWorld(float3 clipPos)
{
    float4 worldPos = mul(float4(clipPos, 1), InvViewProjMatrix);
    return worldPos.xyz / worldPos.w;
}

float3 GetPrevUVAndDepth(float2 currentUV, float currentDepth)
{
    float3 worldPos = TexToWorld(currentUV, currentDepth);
    worldPos += CameraDelta;
    float4 prevClipPos = mul(float4(worldPos, 1), PrevViewProjMatrix);
    prevClipPos.xyz /= prevClipPos.w;
    return float3(ClipToTex(prevClipPos.xy), prevClipPos.z);
}

bool IsDepthForeground(float depth)
{
    return depth > 0;
}

float ComputeLinearDepth(float depth)
{
    return ProjMatrix._43 / (max(depth, 1e-36) + ProjMatrix._33);
}

void LoadHistoryBuffer(float2 prevUV, out float3 historyColor, out float historyLength, out float2 prevMoments)
{
    historyColor = History.SampleLevel(PointSampler, prevUV, 0).xyz;
    
    const float3 historyAndMoments = HistoryAndMoments.SampleLevel(PointSampler, prevUV, 0);
    historyLength = historyAndMoments.x;
    prevMoments = historyAndMoments.yz;
}

float3 LoadViewNormal(int2 pixelPos)
{
    return normalize(unpack_normals2(GBuffer1[pixelPos].xy));
}

//float3 ReprojectPrevUvAndDepth(float2 prevUv, float prevDepth)
//{
//    
//}

float2 ComputeMotionWithRespectToHitDepth(float2 currentUv, float hitDepthRaw /*, out float2 prevUV*/)
{
    float3 clipPos = float3(TexToClip(currentUv), hitDepthRaw);
    float3 worldPos = ClipToWorld(clipPos);
    
    float4 prevClipPos = mul(float4(worldPos + CameraDelta, 1), PrevViewProjMatrix);
    //float4 currClipPos = mul(float4(worldPos, 1), ViewProjMatrix); // isn't this just clipPos from above?
    
    float2 prevTexPos = ClipToTex(prevClipPos.xy / prevClipPos.w);
    //float2 currTexPos = ClipToTex(currClipPos.xy / currClipPos.w);
    
    //prevUV = prevTexPos;
    return currentUv - prevTexPos;
}

float DistanceToPlane(float3 pos, float3 planePos, float3 planeNormal)
{
    return length(pos - planePos) * abs(dot(normalize(planePos - pos), planeNormal));
}

// store accumulated sample count in the output's w component
float4 main(const float4 position : SV_Position, const float2 uv : TEXCOORD0, out float4 newHistoryAndMomentsAndDepthDerivative : SV_Target1) : SV_Target0
{
    const uint2 pixelPos = position.xy;
    const float depth = DepthBuffer[pixelPos];
    float3 prevUVAndDepth = GetPrevUVAndDepth(uv, depth);
    uint2 prevPixelPos = prevUVAndDepth.xy * ScreenSize;
    
    const float reprojectedLinearDepth = ComputeLinearDepth(prevUVAndDepth.z);
    const float prevLinearDepth = ComputeLinearDepth(PrevDepthBuffer[prevPixelPos]);
    const float depthDiff = abs(prevLinearDepth - reprojectedLinearDepth) / reprojectedLinearDepth;
    
    const float viewDistInv = 1.0 / 15000.0; // temp, create variable in cbuffer
    float linearDepth = ComputeLinearDepth(depth) * viewDistInv;
    float depthDerivative = max(abs(ddx_fine(linearDepth)), abs(ddy_fine(linearDepth)));
    
    const float3 currentColor = CurrentFrame[pixelPos].xyz;
    
    if (depthDiff >= 1e-2 || !IsDepthForeground(depth) || !all(saturate(prevUVAndDepth.xy) == prevUVAndDepth.xy))
    {
        float2 moments;
        moments.x = luminance(currentColor);
        moments.y = moments.x * moments.x;
        
        newHistoryAndMomentsAndDepthDerivative = IsDepthForeground(depth) ? float4(1, moments.xy, depthDerivative) : 0;
        return IsDepthForeground(depth) ? float4(currentColor, 0) : 0;
    }
    
    //const float reflectionDepth = ReflectionDepths[pixelPos];
    //if (reflectionDepth != 0)
    //{
    //    float2 parallaxCorrectPrevUv = uv - ComputeMotionWithRespectToHitDepth(uv, reflectionDepth);
    //    int2 parallaxCorrectPrevPixelPos = parallaxCorrectPrevUv * ScreenSize;
    //    //float diff = abs(ComputeLinearDepth(PrevDepthBuffer[parallaxCorrectPrevPixelPos]) - reprojectedLinearDepth) / reprojectedLinearDepth;
    //    //if (diff < 0.01)
    //    if (dot(LoadViewNormal(pixelPos), LoadViewNormal(parallaxCorrectPrevPixelPos)) > 0.99)
    //    {
    //        prevUVAndDepth.xy = parallaxCorrectPrevUv;
    //        prevPixelPos = parallaxCorrectPrevPixelPos;
    //    }
    //}
    
    float3 historyColor;
    float historyLength;
    float2 prevMoments;
    LoadHistoryBuffer(prevUVAndDepth.xy, historyColor, historyLength, prevMoments);
    
    float totalSampleCount = clamp(historyLength + 1, 1.0, MaxHistoryLength); // history count + new sample
    float currentFrameWeight = 1.0 / totalSampleCount;
    
    float2 moments;
    moments.x = luminance(currentColor);
    moments.y = moments.x * moments.x;
    moments = lerp(prevMoments, moments, currentFrameWeight);
    
    float variance = max(0, moments.y - moments.x * moments.x);
    
    newHistoryAndMomentsAndDepthDerivative = float4(totalSampleCount, moments.xy, depthDerivative);
    
    float3 blendedColor = lerp(historyColor.xyz, currentColor.xyz, currentFrameWeight);
    blendedColor = !isnan(blendedColor) ? blendedColor : 0; // TODO: find out what's causing NaN values
    return float4(blendedColor, variance);
}