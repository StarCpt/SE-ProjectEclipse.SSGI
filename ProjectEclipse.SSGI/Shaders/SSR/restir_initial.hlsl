#define RESTIR_CS

#include "../random.hlsli"
#include "common.hlsli"
#include "brdf_ggx.hlsli"
#include "trace_hiz.hlsli"
#include "../sampler_sobol.hlsli"

void StoreReservoir(uint2 pixelPos, RestirReservoir res)
{
    _StoreReservoir(CandidateReservoirs, pixelPos, res);
}

// specific to initial sampling
bool UpdateReservoir(inout RestirReservoir reservoir, float w, float3 lightPos, float3 lightNormal, float3 lightRadiance, inout float wSum, inout uint randState)
{
    wSum += w;
    reservoir.M++;
    
    bool selected = NextFloat(randState) * wSum <= w;
    if (selected)
    {
        reservoir.LightPos = lightPos;
        reservoir.LightNormal = lightNormal;
        reservoir.LightRadiance = lightRadiance;
    }
    return selected;
}

[numthreads(NUM_THREADS_XY, NUM_THREADS_XY, 1)]
void cs(const uint3 dispatchThreadId : SV_DispatchThreadID)
{
#if RT_RES == RT_HALF
    const uint2 pixelPos = dispatchThreadId.xy * uint2(2, 1);
    if (pixelPos.x > ScreenSize.x) // skip odd x pixels
        return;
#elif RT_RES == RT_QUARTER
    const uint2 pixelPos = dispatchThreadId.xy * uint2(2, 2);
    if (any(pixelPos > ScreenSize)) // skip odd pixels
        return;
#else
    const uint2 pixelPos = dispatchThreadId.xy;
#endif
    const uint pixelIndex = pixelPos.y * ScreenSize.x + pixelPos.x;
    const float2 uv = (pixelPos + 0.5) / float2(ScreenSize);
    uint randState = pixelIndex * RandomSeed;
    SSRInput input = LoadSSRInput(pixelPos);
    
    [branch]
    if (!input.IsForeground || input.Gloss < REFLECT_GLOSS_THRESHOLD)
    {
        return;
    }
    
    const bool isMirror = input.Gloss > MIRROR_REFLECTION_THRESHOLD;
    
    RestirReservoir reservoir = RestirReservoir::CreateEmpty();
    reservoir.CreatedPos = input.PositionView;
    reservoir.CreatedNormal = input.NormalView;
    
    float wSum = 0;
    
    [branch]
    if (isMirror)
    {
        // only trace one ray for mirror surfaces
        // mirror surfaces also skips spatial reuse for the same reason
        input.Gloss = 0.95; // bigger glossiness values cause some issues with the brdf/pdf becoming too big or small
        
        float3 reflectDir = reflect(input.RayDirView, input.NormalView);
        float pdf = PdfGGXVNDF(-input.RayDirView, input.NormalView, reflectDir, 1 - input.Gloss);
        
        float2 uvHit;
        float hitConfidence = TraceRayHiZ(uv, input, reflectDir, uvHit);
        
        [branch]
        if (hitConfidence != 0)
        {
            float3 hitPos = ReconstructViewPosition(uvHit);
            float3 hitNormal = LoadNormalInViewSpace(uvHit);
            float3 hitColor = LoadFrameColor(LinearSampler, uvHit);
            
            float samplePdf = ComputeReflectionPdf(input, hitColor, reflectDir);
            float w = samplePdf * (1.0 / pdf) * hitConfidence;
            
            // causes some very bright pixels
            //UpdateReservoir(reservoir, w, hitPos, hitNormal, hitColor, wSum, randState);
        }
        else
        {
            reservoir.M++;
        }
    }
    else
    {
        const float2 prevUv = GetPrevUV(uv, input.Depth);
        const bool disoccluded = any(saturate(prevUv) != prevUv);
        const uint raysPerPixel = disoccluded ? (RaysPerPixel * 2) : RaysPerPixel;
        
        SobolOwenSampler qrng;
        qrng.Init(FrameIndex * raysPerPixel, uint2(PCG_Rand(randState), PCG_Rand(randState)));
        
        // for filtered sampling
        const float roughness = 1.0 - input.Gloss;
        const float n_dot_v = saturate(dot(input.NormalView, -input.RayDirView));
        const float coneTangent = lerp(0, roughness, n_dot_v * sqrt(roughness));
        
        for (uint r = 0; r < raysPerPixel; r++)
        {
            float pdf = 0;
            float3 reflectDir = 0;
            
            // contribution is 0 if ray reflect dir is below the surface
            // try to generate a valid reflect ray up to 5 times
            float n_dot_l = 0;
            for (uint j = 0; j < 3 && n_dot_l <= 0; j++)
            {
                float2 qRand2 = qrng.Next();
                reflectDir = SampleGGXVNDF(-input.RayDirView, input.NormalView, 1 - input.Gloss, qRand2);
                pdf = PdfGGXVNDF(-input.RayDirView, reflectDir, input.NormalView, 1.0 - input.Gloss);
                n_dot_l = dot(input.NormalView, reflectDir);
            }
            
            if (n_dot_l <= 0)
            {
                // sample with zero contribution
                reservoir.M++;
                continue;
            }
            
            float2 uvHit;
            float hitConfidence = TraceRayHiZ(uv, input, reflectDir, uvHit);
            
            if (hitConfidence != 0)
            {
                const float intersectionCircleRadius = coneTangent * length(uvHit - uv);
                const float mip = max(log2(intersectionCircleRadius * max(GetScreenSize().x, GetScreenSize().y)), 0);
                
                float3 hitPos = ReconstructViewPosition(uvHit);
                float3 hitNormal = LoadNormalInViewSpace(uvHit);
                float3 hitColor = LoadFrameColor(LinearSampler, uvHit, mip);
                //hitColor = clamp(hitColor, 0, 50);
                
                float samplePdf = ComputeReflectionPdf(input, hitColor, reflectDir);
                float w = samplePdf * (1.0 / pdf) * hitConfidence;
                
                UpdateReservoir(reservoir, w, hitPos, hitNormal, hitColor, wSum, randState);
            }
            else
            {
                // sample with zero contribution
                reservoir.M++;
            }
        }
    }
    
    float3 lightDir = normalize(reservoir.LightPos - input.PositionView);
    float selectedSamplePdf = ComputeReflectionPdf(input, reservoir.LightRadiance, lightDir);
    reservoir.AvgWeight = (selectedSamplePdf * reservoir.M > 0) ? (wSum / (selectedSamplePdf * reservoir.M)) : 0;
    
    StoreReservoir(pixelPos, reservoir);
}
