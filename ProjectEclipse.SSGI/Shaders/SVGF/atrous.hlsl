#include "../math.hlsli"
#include "../color.hlsli"
#include "common.hlsli"

Texture2D<float4> Source     : register(t0);
Texture2D<float> DepthBuffer : register(t1);
Texture2D<float4> GBuffer1   : register(t2);
Texture2D<float4> HistoryMomentsDepthDerivatives : register(t3);

cbuffer AtrousConstants : register(b0)
{
    int2 ScreenSize;
    int StepSize;
    float InvViewDistance;
    
    float4x4 ProjMatrix;
};

//static const float kernelWeights[5] = { 0.0614, 0.2448, 0.3877, 0.2448, 0.0614 };

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

// computes a 3x3 gaussian blur of the variance, centered around
// the current pixel
float computeVarianceCenter(const int2 pixelPos)
{
    float sum = 0.f;

    const float kernel[2][2] =
    {
        { 1.0 / 4.0, 1.0 / 8.0 },
        { 1.0 / 8.0, 1.0 / 16.0 },
    };

    const int radius = 1;
    for (int yy = -radius; yy <= radius; yy++)
    {
        for (int xx = -radius; xx <= radius; xx++)
        {
            const int2 p = pixelPos + int2(xx, yy);
            const float k = kernel[abs(xx)][abs(yy)];
            sum += Source[p].a * k;
        }
    }
    
    return sum;
}

float4 main(const float4 position : SV_Position, const float2 uv : TEXCOORD0) : SV_Target0
{
    const int2 pixelPos = position.xy;
    
    float centerDepth = DepthBuffer[pixelPos];
    if (!IsDepthForeground(centerDepth))
    {
        return 0;
    }
    
    float centerLinearDepth = ComputeLinearDepth(centerDepth) /** InvViewDistance*/;
    float centerDepthDerivative = HistoryMomentsDepthDerivatives[pixelPos].w;
    float4 centerColorAndVariance = Source[pixelPos]; // w comp contains variance calculated in the temporal stage
    float centerLum = luminance(centerColorAndVariance.xyz);
    float3 centerNormal = LoadViewSpaceNormal(pixelPos);
    
    float centerVarianceFiltered = computeVarianceCenter(pixelPos);
    
    const float varianceEpsilon = 1e-10; 
    const float phiColor = 10;
    const float phiNormal = 128;
    
    const float phiLIllumination = phiColor * sqrt(max(varianceEpsilon, centerVarianceFiltered));
    const float phiDepth = max(centerDepthDerivative, 1e-8) * StepSize;
    
    float sumWeight = 1;
    float4 sumColorAndVariance = centerColorAndVariance;
    
    static const int kernelRadius = 2;
    static const float kernelWeights[5] = { (1.0 / 6.0), (2.0 / 3.0), 1.0, (2.0 / 3.0), (1.0 / 6.0) };
    for (int yy = -kernelRadius; yy <= kernelRadius; yy++)
    {
        for (int xx = -kernelRadius; xx <= kernelRadius; xx++)
        {
            int2 nPos = pixelPos + int2(xx, yy) * StepSize;
            bool isValid = all(nPos >= 0 && nPos < ScreenSize);
            bool isCenter = xx == 0 && yy == 0;
            
            [branch]
            if (isCenter)
                continue;
            
            if (isValid)
            {
                float kernelWeight = kernelWeights[xx + kernelRadius] * kernelWeights[yy + kernelRadius];
            
                float nLinearDepth = ComputeLinearDepth(DepthBuffer[nPos]) /** InvViewDistance*/;
                float3 nNormal = LoadViewSpaceNormal(nPos);
                float4 nColorAndVariance = Source[nPos];
                float nLum = luminance(nColorAndVariance.xyz);
            
                float w = computeWeight(centerLinearDepth, nLinearDepth, phiDepth * length(float2(xx, yy)), centerNormal, nNormal, phiNormal, centerLum, nLum, phiLIllumination);
            
                float weight = kernelWeight * w;
            
                sumWeight += weight;
                sumColorAndVariance += float4(weight.xxx, weight * weight) * nColorAndVariance;
            }
        }
    }
    
    float4 normalizedColorAndVariance = sumColorAndVariance / float4(sumWeight.xxx, sumWeight * sumWeight);
    return normalizedColorAndVariance;
}