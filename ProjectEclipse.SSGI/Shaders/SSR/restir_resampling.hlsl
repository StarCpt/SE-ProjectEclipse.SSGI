#define RESTIR_CS

#include "common.hlsli"

// modified version of https://github.com/DQLin/ReSTIR_PT

#define MAX_HISTORY 25
#define DYNAMIC_REUSE_RADIUS 1

RestirReservoir LoadPrevReservoir(uint2 pixelPos)
{
    return _LoadReservoir(PrevReservoirs, pixelPos);
}

RestirReservoir LoadCandidateReservoir(uint2 pixelPos)
{
    return _LoadReservoir(CandidateReservoirs, pixelPos);
}

void StoreSpatialReservoir(uint2 pixelPos, RestirReservoir res)
{
    _StoreReservoir(SpatialReservoirs, pixelPos, res);
}

void StoreTemporalReservoir(uint2 pixelPos, RestirReservoir res)
{
    _StoreReservoir(TemporalReservoirs, pixelPos, res);
}

float evalNdfGGX(float alpha, float cosTheta)
{
    float a2 = alpha * alpha;
    float d = ((cosTheta * a2 - cosTheta) * cosTheta + 1);
    return a2 / (d * d * PI);
}

float evalLambdaGGX(float alphaSqr, float cosTheta)
{
    if (cosTheta <= 0)
        return 0;
    float cosThetaSqr = cosTheta * cosTheta;
    float tanThetaSqr = max(1 - cosThetaSqr, 0) / cosThetaSqr;
    return 0.5 * (-1 + sqrt(1 + alphaSqr * tanThetaSqr));
}

float evalMaskingSmithGGXSeparable(float alpha, float cosThetaI, float cosThetaO)
{
    float alphaSqr = alpha * alpha;
    float lambdaI = evalLambdaGGX(alphaSqr, cosThetaI);
    float lambdaO = evalLambdaGGX(alphaSqr, cosThetaO);
    return 1 / ((1 + lambdaI) * (1 + lambdaO));
}

float evalBRDF(SSRInput input, float3 L)
{
    float3 N = input.NormalView;
    float3 V = -input.RayDirView;
    
    float NdotL = saturate(dot(N, L));
    float3 H = normalize(V + L);
    float NdotH = saturate(dot(N, H));
    float LdotH = saturate(dot(L, H));
    float VdotH = LdotH; // LdotH == VdotH since H is halfway between L and V

    float roughness = 1.0 - input.Gloss;
    float ggxAlpha = roughness * roughness;
    float NdotV = saturate(dot(input.NormalView, -input.RayDirView));
    
    //float D = evalNdfGGX(ggxAlpha, NdotH);
    //float G = evalMaskingSmithGGXSeparable(ggxAlpha, NdotV, NdotL);
    //float F = specularWeight < 1e-8f ? 0.f : evalFresnelSchlick(specularWeight, 1.f, LdotH) / specularWeight;
    
    float diffuseWeight = luminance(input.Color * (1 - input.Metalness)); // not sure if correct
    float specularWeight = luminance(lerp(DIELECTRIC_REFLECTANCE_F0, input.Color, input.Metalness)); // also not sure if correct
    float weightSum = diffuseWeight + specularWeight;
    float diffuseSpecularMix = weightSum > 1e-7 ? (diffuseWeight / weightSum) : 1.0;

    float D = evalNdfGGX(ggxAlpha, NdotH);
    float G = evalMaskingSmithGGXSeparable(ggxAlpha, NdotV, NdotL);
    float F = luminance(fresnel(input.Color, input.Metalness, VdotH));
    //float F = fresnel_schlick(specularWeight, 1, VdotH);
    
    float diffuse = NdotL * (1.0 / PI);
    float specular = max(0.f, D * G * F / (4.f * NdotV));
    return NdotL > 0.f ? lerp(specular, diffuse, diffuseSpecularMix) : 0.f;
}

float evalTargetFunction(SSRInput input, float3 normal, float3 position, float3 radiance, float3 samplePosition)
{
    input.NormalView = normal;
    input.PositionView = position;
    float3 L = normalize(samplePosition - input.PositionView);
    float3 fCos = max(0.1f, evalBRDF(input, L) * saturate(dot(input.NormalView, L)));
    float pdf = luminance(radiance * fCos);
    return pdf;
}

float lengthSquared(float3 vec)
{
    return dot(vec, vec);
}

bool updateReservoir(float weight, RestirReservoir srcReservoir, inout RestirReservoir dstReservoir, inout float weightSum, inout uint randState)
{
    weightSum += weight;
    dstReservoir.M += srcReservoir.M;

    // Conditionally update reservoir.
    float random = NextFloat(randState);
    bool isUpdate = random * weightSum <= weight;
    if (isUpdate)
    {
        dstReservoir.LightPos = srcReservoir.LightPos;
        dstReservoir.LightNormal = srcReservoir.LightNormal;
        dstReservoir.LightRadiance = srcReservoir.LightRadiance;
        dstReservoir.Age = srcReservoir.Age;
    }
    return isUpdate;
}

//float3 ReprojectViewPos(float3 prevViewPos)
//{
//    float3 prevWorldPos = mul(PrevViewMatrix, float4(prevViewPos, 1)).xyz;
//    prevWorldPos -= CameraDelta;
//    return world_to_view(prevWorldPos);
//}

void ReprojectPrevReservoir(inout RestirReservoir reservoir)
{
    float3 createdWorldPos = mul(PrevViewMatrix, float4(reservoir.CreatedPos, 1)).xyz;
    float3 createdWorldNormal = mul(PrevViewMatrix, float4(reservoir.CreatedNormal, 0)).xyz;
    float3 lightWorldPos = mul(PrevViewMatrix, float4(reservoir.LightPos, 1)).xyz;
    float3 lightWorldNormal = mul(PrevViewMatrix, float4(reservoir.LightNormal, 0)).xyz;
    
    createdWorldPos -= CameraDelta;
    lightWorldPos -= CameraDelta;
    
    reservoir.CreatedPos = mul(float4(createdWorldPos, 1), ViewMatrix).xyz;
    reservoir.CreatedNormal = mul(float4(createdWorldNormal, 0), ViewMatrix).xyz;
    reservoir.LightPos = mul(float4(lightWorldPos, 1), ViewMatrix).xyz;
    reservoir.LightNormal = mul(float4(lightWorldNormal, 0), ViewMatrix).xyz;
    
    //reservoir.LightRadiance = LoadFrameColor(LinearSampler, ViewToTex(reservoir.LightPos), 0);
}

RestirReservoir TemporalResampling(const int2 pixelPos, const float2 uv, const SSRInput input, const RestirReservoir canonicalReservoir, out bool isPrevValid, inout uint randState)
{
    const float2 prevUV = GetPrevUV(uv, input.RawDepth);
    const int2 prevPixelPos = (prevUV * GetScreenSize());
    
    isPrevValid = all(saturate(prevUV) == prevUV);
    
    if (!isPrevValid)
    {
        return canonicalReservoir;
    }
    
    RestirReservoir temporalReservoir = LoadPrevReservoir(prevPixelPos);
    float prevPrimaryHitDist = length(temporalReservoir.CreatedPos);
    ReprojectPrevReservoir(temporalReservoir);
    
    isPrevValid = isPrevValid && length(temporalReservoir.CreatedPos - input.PositionView) < 0.1 && dot(temporalReservoir.CreatedNormal, input.NormalView) > 0.8;
    bool isReprojectionValid = !(prevPrimaryHitDist / length(input.PositionView) < 0.98 && NextFloat(randState) < 0.15) && lengthSquared(temporalReservoir.CreatedPos - input.PositionView) < (1 * 1);
    if (!isPrevValid || !isReprojectionValid)
    {
        return canonicalReservoir;
    }
    
    temporalReservoir.M = min(temporalReservoir.M, max(MAX_HISTORY, canonicalReservoir.M * MAX_HISTORY));
    
    //if (temporalReservoir.Age > MAX_HISTORY)
    //{
    //    temporalReservoir.M = 0;
    //}
    
    float tf = evalTargetFunction(input, input.NormalView, input.PositionView, temporalReservoir.LightRadiance, temporalReservoir.LightPos);
    
    bool enableTemporalJacobian = any(prevPixelPos != pixelPos);
    if (enableTemporalJacobian)
    {
        float3 offsetB = temporalReservoir.LightPos - temporalReservoir.CreatedPos;
        float3 offsetA = temporalReservoir.LightPos - input.PositionView;
        
        float RB2 = lengthSquared(offsetB);
        float RA2 = lengthSquared(offsetA);
        offsetB = normalize(offsetB);
        offsetA = normalize(offsetA);
        float cosA = dot(input.NormalView, offsetA);
        float cosB = dot(temporalReservoir.CreatedNormal, offsetB);
        float cosPhiA = -dot(offsetA, temporalReservoir.LightNormal);
        float cosPhiB = -dot(offsetB, temporalReservoir.LightNormal);
        
        if (cosA <= 0 || cosPhiA <= 0 || RA2 <= 0 || RB2 <= 0 || cosB <= 0 || cosPhiB <= 0)
        {
            tf = 0;
        }
        
        const float largeFloat = 1e20;
        const float maxJacobian = 10;
        float jacobian = RA2 * cosPhiB <= 0 ? 0 : clamp(RB2 * cosPhiA / (RA2 * cosPhiB), 0, maxJacobian);
        
        tf *= jacobian;
    }
    
    float wSum = max(0, temporalReservoir.AvgWeight) * temporalReservoir.M * tf;
    float pNew = evalTargetFunction(input, input.NormalView, input.PositionView, canonicalReservoir.LightRadiance, canonicalReservoir.LightPos);
    float wi = canonicalReservoir.AvgWeight <= 0 ? 0 : pNew * canonicalReservoir.AvgWeight * canonicalReservoir.M;
    wi = max(0, wi);
    
    bool selectedNew = updateReservoir(wi, canonicalReservoir, temporalReservoir, wSum, randState);
    
    float avgWSum = temporalReservoir.M == 0 ? 0 : wSum / temporalReservoir.M;
    pNew = evalTargetFunction(input, temporalReservoir.CreatedNormal, temporalReservoir.CreatedPos, temporalReservoir.LightRadiance, temporalReservoir.LightPos);
    temporalReservoir.AvgWeight = pNew <= 0 ? 0 : avgWSum / pNew;
    temporalReservoir.Age++;
    temporalReservoir.CreatedPos = input.PositionView;
    temporalReservoir.CreatedNormal = input.NormalView;
    
    temporalReservoir.M = min(temporalReservoir.M, canonicalReservoir.M * MAX_HISTORY);
    
    return temporalReservoir;
}

RestirReservoir SpatialResampling(const int2 pixelPos, const float2 uv, const SSRInput input, const RestirReservoir canonicalReservoir, bool isPrevValid, inout uint randState)
{
    const float2 prevUV = GetPrevUV(uv, input.RawDepth);
    const int2 prevPixelPos = (prevUV * GetScreenSize());
    
    const float linearDepth = compute_depth(input.RawDepth);
    RestirReservoir spatialReservoir = LoadPrevReservoir(prevPixelPos);
    
    spatialReservoir.M = min(spatialReservoir.M, canonicalReservoir.M * MAX_HISTORY);
    
    if (!isPrevValid || spatialReservoir.Age > MAX_HISTORY)
    {
        spatialReservoir.M = 0;
    }
    
    float wSumS = max(0, spatialReservoir.AvgWeight) * spatialReservoir.M * evalTargetFunction(input, spatialReservoir.CreatedNormal, spatialReservoir.CreatedPos, spatialReservoir.LightRadiance, spatialReservoir.LightPos);
    
    spatialReservoir.CreatedPos = input.PositionView;
    spatialReservoir.CreatedNormal = input.NormalView;
    
    const uint reuseCount = 4;
#if DYNAMIC_REUSE_RADIUS
    float reuseRadius = GetScreenSize().x * 0.01;
#else
    float reuseRadius = 16;
#endif
    
    for (uint i = 0; i < reuseCount; i++)
    {
#if DYNAMIC_REUSE_RADIUS
        const float radiusShrinkRatio = 0.5;
        const float minReuseRadius = 10.0;
        reuseRadius = max(reuseRadius * radiusShrinkRatio, minReuseRadius);
#endif
        int2 neighborPixel = RandomPixelInDisk(isPrevValid ? prevPixelPos : pixelPos, reuseRadius, randState);
        //neighborPixel = clamp(neighborPixel, 0, int2(frame_.Screen.resolution - 1));
        
#if RT_RES == RT_HALF
        neighborPixel.x &= ~0x1;
#elif RT_RES == RT_QUARTER
        neighborPixel.xy &= ~0x1;
#endif
        
        if (any(neighborPixel < 0 || neighborPixel >= ScreenSize))
            continue;
        
        float neighborDepth = LoadDepthPixel(neighborPixel);
        float3 neighborNormal = LoadNormalInViewSpacePixel(neighborPixel);
        bool isNeighborValid = dot(input.NormalView, neighborNormal) > 0.8 && abs(linearDepth - compute_depth(neighborDepth)) < (0.1 * linearDepth);
        
        if (!isNeighborValid)
            continue;
        
        RestirReservoir reservoir;
        if (isPrevValid)
        {
            reservoir = LoadPrevReservoir(neighborPixel);
            ReprojectPrevReservoir(reservoir);
        }
        else
        {
            reservoir = LoadCandidateReservoir(neighborPixel);
        }
            
        if (reservoir.M == 0)
            continue;
        
        float3 offsetB = reservoir.LightPos - reservoir.CreatedPos;
        float3 offsetA = reservoir.LightPos - input.PositionView;
        
        float pNewTN = evalTargetFunction(input, input.NormalView, input.PositionView, reservoir.LightRadiance, reservoir.LightPos);
        if (dot(input.NormalView, offsetA) <= 0)
        {
            pNewTN = 0;
        }
        
        float RB2 = lengthSquared(offsetB);
        float RA2 = lengthSquared(offsetA);
        offsetB = normalize(offsetB);
        offsetA = normalize(offsetA);
        float cosA = dot(input.NormalView, offsetA);
        float cosB = dot(reservoir.CreatedNormal, offsetB);
        float cosPhiA = -dot(offsetA, reservoir.LightNormal);
        float cosPhiB = -dot(offsetB, reservoir.LightNormal);

        if (cosB <= 0 || cosPhiB <= 0)
            continue;

        if (cosA <= 0 || cosPhiA <= 0 || RA2 <= 0 || RB2 <= 0)
        {
            pNewTN = 0;
        }
        
        bool isVisible = true; // assume visible
        if (!isVisible)
        {
            pNewTN = 0;
        }
        
        const float largeFloat = 1e20;
        const float maxJacobian = 10; // idk some big number
        float jacobian = RA2 * cosPhiB <= 0 ? 0 : clamp(RB2 * cosPhiA / (RA2 * cosPhiB), 0, maxJacobian);
        float wiTN = clamp(reservoir.AvgWeight * pNewTN * reservoir.M * jacobian, 0, largeFloat);
        
        bool selected = updateReservoir(wiTN, reservoir, spatialReservoir, wSumS, randState);
        
#if DYNAMIC_REUSE_RADIUS
        const float radiusExpandRatio = 3.0;
        reuseRadius *= radiusExpandRatio;
#endif
    }
    
    float m = spatialReservoir.M == 0 ? 0 : 1.0 / float(spatialReservoir.M); // biased balanced heuristic
    float pNew = evalTargetFunction(input, input.NormalView, input.PositionView, spatialReservoir.LightRadiance, spatialReservoir.LightPos);
    float mWeight = pNew <= 0 ? 0 : (1.0 / pNew * m);
    static const uint spatialMaxSamples = 200;
    spatialReservoir.M = clamp(spatialReservoir.M, 0, spatialMaxSamples);
    float W = wSumS * mWeight;
    const float maxSpatialWeight = 1e20;
    spatialReservoir.AvgWeight = clamp(W, 0, maxSpatialWeight);
    spatialReservoir.Age++;
    
    return spatialReservoir;
}

[numthreads(NUM_THREADS_XY, NUM_THREADS_XY, 1)]
void cs(const uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 pixelPos = dispatchThreadId.xy;
    const uint pixelIndex = pixelPos.y * ScreenSize.x + pixelPos.x;
    const float2 uv = (pixelPos + 0.5) / float2(ScreenSize);
    uint randState = pixelIndex * RandomSeed;
    SSRInput input = LoadSSRInput(pixelPos);
    
    const bool isMirror = input.Gloss > MIRROR_REFLECTION_THRESHOLD;
    
#if RT_RES == RT_HALF
    const RestirReservoir canonicalReservoir = LoadCandidateReservoir(pixelPos & uint2(~0x1, ~0x0));
#elif RT_RES == RT_QUARTER
    const RestirReservoir canonicalReservoir = LoadCandidateReservoir(pixelPos & ~0x1);
#else
    const RestirReservoir canonicalReservoir = LoadCandidateReservoir(pixelPos);
#endif
    
    [branch]
    if (!input.IsForeground || input.Gloss < REFLECT_GLOSS_THRESHOLD || isMirror || input.Gloss > 0.6)
    {
        StoreSpatialReservoir(pixelPos, canonicalReservoir);
        StoreTemporalReservoir(pixelPos, canonicalReservoir);
        return;
    }
    
    bool isPrevReservoirValid;
    RestirReservoir temporalReservoir = TemporalResampling(pixelPos, uv, input, canonicalReservoir, isPrevReservoirValid, randState);
    RestirReservoir spatialReservoir = SpatialResampling(pixelPos, uv, input, canonicalReservoir, isPrevReservoirValid, randState);
    
    StoreTemporalReservoir(pixelPos, temporalReservoir);
    StoreSpatialReservoir(pixelPos, spatialReservoir);
}
