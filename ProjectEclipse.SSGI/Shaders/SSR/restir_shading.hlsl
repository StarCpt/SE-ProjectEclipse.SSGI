#define RESTIR_CS

#include "common.hlsli"
#include "brdf_ggx.hlsli"
#include "trace_hiz.hlsli"
#include "../sampler_sobol.hlsli"
#include "../lighting.hlsli"

RestirReservoir LoadCandidateReservoir(uint2 pixelPos)
{
#if RT_RES == RT_HALF
    pixelPos.x &= ~0x1;
#elif RT_RES == RT_QUARTER
    pixelPos.xy &= ~0x1;
#endif
    return _LoadReservoir(CandidateReservoirs, pixelPos);
}

RestirReservoir LoadSpatialReservoir(uint2 pixelPos)
{
    return _LoadReservoir(SpatialReservoirs, pixelPos);
}

RestirReservoir LoadTemporalReservoir(uint2 pixelPos)
{
    return _LoadReservoir(TemporalReservoirs, pixelPos);
}

void StorePrevReservoir(uint2 pixelPos, RestirReservoir res)
{
    _StoreReservoir(PrevReservoirs, pixelPos, res);
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

//bool ValidateReservoir(const float2 uv, const SSRInput input, inout RestirReservoir reservoir)
//{
//    float2 uvHit;
//    float hitConfidence = TraceRayHiZ(uv, input, normalize(reservoir.LightPos - input.PositionView), uvHit);
//    
//    float oldHitDist = length(reservoir.LightPos - input.PositionView);
//    float newHitDist = length(ReconstructViewPosition(uvHit) - input.PositionView);
//    
//    if (hitConfidence == 0 || abs(newHitDist - oldHitDist) < (oldHitDist * 0.1))
//    {
//        reservoir.LightRadiance = LoadFrameColor(LinearSampler, uvHit);
//        return true;
//    }
//    else
//    {
//        reservoir = RestirReservoir::CreateEmpty();
//        return false;
//    }
//}

[numthreads(NUM_THREADS_XY, NUM_THREADS_XY, 1)]
void cs(const uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 pixelPos = dispatchThreadId.xy;
    const uint pixelIndex = pixelPos.y * ScreenSize.x + pixelPos.x;
    const float2 uv = (pixelPos + 0.5) / GetScreenSize();
    uint randState = pixelIndex * RandomSeed;
    SSRInput input = LoadSSRInput(pixelPos);
    float3 pixelColor = FrameBuffer[pixelPos];
    
    [branch]
    if (!input.IsForeground || input.Gloss < REFLECT_GLOSS_THRESHOLD)
    {
        ReflectionDepths[pixelPos] = 0;
        RestirOutputTexture[pixelPos] = 0;
        RestirOutputTexture2[pixelPos] = 0;
        StorePrevReservoir(pixelPos, RestirReservoir::CreateEmpty());
        return;
    }
    
    float3 diffuse = 0;
    float3 specular = 0;
    
    RestirReservoir reuseReservoir;
    
    //RestirReservoir candidateReservoir = LoadCandidateReservoir(pixelPos);
    RestirReservoir spatialReservoir = LoadSpatialReservoir(pixelPos);
    RestirReservoir temporalReservoir = LoadTemporalReservoir(pixelPos);
    
    //candidateReservoir.AvgWeight = clamp(candidateReservoir.AvgWeight, 0, 100);
    spatialReservoir.AvgWeight = clamp(spatialReservoir.AvgWeight, 0, 100);
    temporalReservoir.AvgWeight = clamp(temporalReservoir.AvgWeight, 0, 100);
    
    //const float3 candidateLightDir = normalize(candidateReservoir.LightPos - input.PositionView);
    const float3 spatialLightDir = normalize(spatialReservoir.LightPos - input.PositionView);
    const float3 temporalLightDir = normalize(temporalReservoir.LightPos - input.PositionView);
    
    //float candidateW = candidateReservoir.M;
    float spatialW = spatialReservoir.M;
    float temporalW = temporalReservoir.M;
    
    //candidateW *= candidateReservoir.AvgWeight;
    spatialW *= spatialReservoir.AvgWeight;
    temporalW *= temporalReservoir.AvgWeight;
    
    //candidateW *= evalTargetFunction(input, input.NormalView, input.PositionView, candidateReservoir.LightRadiance, candidateReservoir.LightPos);
    spatialW *= evalTargetFunction(input, input.NormalView, input.PositionView, spatialReservoir.LightRadiance, spatialReservoir.LightPos);
    temporalW *= evalTargetFunction(input, input.NormalView, input.PositionView, temporalReservoir.LightRadiance, temporalReservoir.LightPos);
    
    //candidateW = 0;
    //spatialW = 0;
    //temporalW = 0;
    
    float totalW = /*candidateW +*/ spatialW + temporalW;
    
    //float3 candidateDiffuse, candidateSpecular;
    //Brdf(1 - input.Gloss, input.Metalness, input.Color, -input.RayDirView, candidateLightDir, input.NormalView, candidateDiffuse, candidateSpecular);
    //candidateDiffuse *= candidateReservoir.LightRadiance * candidateReservoir.AvgWeight * (candidateReservoir.M > 0);
    //candidateSpecular *= candidateReservoir.LightRadiance * candidateReservoir.AvgWeight * (candidateReservoir.M > 0);
    
    float3 spatialDiffuse, spatialSpecular;
    Brdf(1 - input.Gloss, input.Metalness, input.Color, -input.RayDirView, spatialLightDir, input.NormalView, spatialDiffuse, spatialSpecular);
    spatialDiffuse *= spatialReservoir.LightRadiance * spatialReservoir.AvgWeight * (spatialReservoir.M > 0);
    spatialSpecular *= spatialReservoir.LightRadiance * spatialReservoir.AvgWeight * (spatialReservoir.M > 0);
    
    float3 temporalDiffuse, temporalSpecular;
    Brdf(1 - input.Gloss, input.Metalness, input.Color, -input.RayDirView, temporalLightDir, input.NormalView, temporalDiffuse, temporalSpecular);
    temporalDiffuse *= temporalReservoir.LightRadiance * temporalReservoir.AvgWeight * (temporalReservoir.M > 0);
    temporalSpecular *= temporalReservoir.LightRadiance * temporalReservoir.AvgWeight * (temporalReservoir.M > 0);
    
    diffuse += totalW <= 0 ? 0 : (/*candidateDiffuse * (candidateW / totalW) +*/ spatialDiffuse * (spatialW / totalW) + temporalDiffuse * (temporalW / totalW));
    specular += totalW <= 0 ? 0 : (/*candidateSpecular * (candidateW / totalW) +*/ spatialSpecular * (spatialW / totalW) + temporalSpecular * (temporalW / totalW));
    
    reuseReservoir = temporalReservoir;
    
    //float candidateRayLength = length(candidateReservoir.LightPos - input.PositionView);
    float spatialRayLength = length(spatialReservoir.LightPos - input.PositionView);
    float temporalRayLength = length(temporalReservoir.LightPos - input.PositionView);
    
    // extend the ray into the surface and get the depth
    //bool candidateValid = candidateW > 0;
    bool spatialValid = spatialW > 0;
    bool temporalValid = temporalW > 0;
    //float3 candidatePSRHitPos = input.PositionView + input.RayDirView * candidateRayLength;
    float3 spatialPSRHitPos = input.PositionView + input.RayDirView * spatialRayLength;
    float3 temporalPSRHitPos = input.PositionView + input.RayDirView * temporalRayLength;
    float div = 1.0 / (/*candidateValid +*/ spatialValid + temporalValid);
    ReflectionDepths[pixelPos] = div > 0 ?
        (/*candidateValid * ViewToClip(candidatePSRHitPos).z*/ + spatialValid * ViewToClip(spatialPSRHitPos).z + temporalValid * ViewToClip(temporalPSRHitPos).z) * div : ViewToClip(input.PositionView).z;
    
    //reuseReservoir = RestirReservoir::CreateEmpty();
    //reuseReservoir.CreatedPos = input.PositionView;
    //reuseReservoir.CreatedNormal = input.NormalView;
    //
    //float pTemporal = evalTargetFunction(input, input.NormalView, input.PositionView, temporalReservoir.LightRadiance, temporalReservoir.LightPos);
    //float pSpatial = evalTargetFunction(input, input.NormalView, input.PositionView, spatialReservoir.LightRadiance, spatialReservoir.LightPos);
    //
    //float wiSpatial = clamp(spatialReservoir.AvgWeight * pSpatial * spatialReservoir.M, 0, 1e20);
    //float wiTemporal = clamp(temporalReservoir.AvgWeight * pTemporal * temporalReservoir.M, 0, 1e20);
    //
    //float wSum = 0;
    //updateReservoir(wiSpatial, spatialReservoir, reuseReservoir, wSum, randState);
    //updateReservoir(wiTemporal, temporalReservoir, reuseReservoir, wSum, randState);
    //
    //float m = reuseReservoir.M == 0 ? 0 : 1.0 / float(reuseReservoir.M);
    //float pNew = evalTargetFunction(input, input.NormalView, input.PositionView, reuseReservoir.LightRadiance, reuseReservoir.LightPos);
    //float mWeight = pNew <= 0 ? 0 : (1.0 / pNew * m);
    //float W = wSum * mWeight;
    //reuseReservoir.AvgWeight = clamp(W, 0, 1e20);
    
    //ValidateReservoir(uv, input, reuseReservoir);
    
    DemodulateRadiance(input.Color, input.NormalView, input.Metalness, 1 - input.Gloss, -input.RayDirView, diffuse, specular);
    
    StorePrevReservoir(pixelPos, reuseReservoir);
    RestirOutputTexture[pixelPos] = float4(diffuse, 1); // irradiance only
    RestirOutputTexture2[pixelPos] = float4(specular, 1); // irradiance only
}
