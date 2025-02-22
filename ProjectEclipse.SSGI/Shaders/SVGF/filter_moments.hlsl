#include "../math.hlsli"
#include "../color.hlsli"
#include "common.hlsli"

Texture2D<float4> CurrentFrame : register(t0);
Texture2D<float4> Buffer1      : register(t1);
Texture2D<float> DepthBuffer   : register(t2);
Texture2D<float4> GBuffer1     : register(t3);

cbuffer FilterMomentsConstants : register(b0)
{
    int2 ScreenSize;
    float InvViewDistance;
    uint _padding1;
    
    float4x4 ProjMatrix;
};

bool IsDepthForeground(float depth)
{
    return depth > 0;
}

float ComputeLinearDepth(float depth)
{
    return ProjMatrix._43 / (max(depth, 1e-36) + ProjMatrix._33);
}

float3 LoadViewSpaceNormal(uint2 pixelPos)
{
    return normalize(unpack_normals2(GBuffer1[pixelPos].xy));
}

float4 main(const float4 position : SV_Position, const float2 uv : TEXCOORD0) : SV_Target0
{
    const uint2 pixelPos = position.xy;
    
    float4 buffer1 = Buffer1[pixelPos];
    float historyLength = buffer1.x;
    float2 moments = buffer1.yz;
    float depthDerivative = buffer1.w;
    
    const float4 centerColorAndVariance = CurrentFrame[pixelPos];
    
    if (historyLength < 4)
    {
        const float centerLum = luminance(centerColorAndVariance.xyz);
        const float centerDepth = DepthBuffer[pixelPos];
        const float centerLinearDepth = ComputeLinearDepth(centerDepth) /** InvViewDistance*/;
        
        if (!IsDepthForeground(centerDepth))
        {
            return centerColorAndVariance;
        }

        const float3 centerNormal = LoadViewSpaceNormal(pixelPos);
        
        const float varianceEpsilon = 1e-4;
        const float phiColor = 10;
        const float phiNormal = 128;
        
        const float phiLIllumination = phiColor;
        const float phiDepth = max(depthDerivative, varianceEpsilon) * 3.0;
        
        float sumWeights = 0;
        float3 sumColor = 0;
        float2 sumMoments = 0;
        
        // center pixel
        sumWeights += 1;
        sumColor += centerColorAndVariance.xyz;
        sumMoments += moments;

        static const int radius = 3;
        for (int yy = -radius; yy <= radius; yy++)
        {
            for (int xx = -radius; xx <= radius; xx++)
            {
                int2 nPos = pixelPos + int2(xx, yy);
                bool isValidPixel = all(nPos >= 0 && nPos < ScreenSize);
                bool isCenterPixel = yy == 0 && xx == 0;

                if (isValidPixel && !isCenterPixel)
                {
                    float3 nColor = CurrentFrame[nPos].xyz;
                    float nLum = luminance(nColor);
                    float2 nMoments = Buffer1[nPos].yz;
                    float nLinearDepth = ComputeLinearDepth(DepthBuffer[nPos]) /** InvViewDistance*/;
                    float3 nNormal = LoadViewSpaceNormal(nPos);
                    
                    float w = computeWeight(centerLinearDepth, nLinearDepth, phiDepth, centerNormal, nNormal, phiNormal, centerLum, nLum, phiLIllumination);
                    
                    sumWeights += w;
                    sumColor += nColor * w;
                    sumMoments += nMoments * w;
                }
            }
        }
        
        sumWeights = max(sumWeights, 1e-6);
        sumColor /= sumWeights;
        sumMoments /= sumWeights;
        
        float variance = sumMoments.y - sumMoments.x * sumMoments.x;
        variance *= 4.0 / historyLength;
        
        return float4(sumColor, variance);
    }
    else
    {
        return centerColorAndVariance;
    }
}