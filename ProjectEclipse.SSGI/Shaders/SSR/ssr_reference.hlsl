#include "../random.hlsli"
#include "brdf_ggx.hlsli"
#include "common.hlsli"
#include "trace_hiz.hlsli"
#include "../sampling_ggx.hlsli"
#include "../sampler_sobol.hlsli"
#include "../lighting.hlsli"

void main(float4 position : SV_Position, float2 uv : TEXCOORD0, out float3 diffuseIrradiance : SV_Target0, out float3 specularIrradiance : SV_Target1, out float rayExtendedDepth : SV_Target2)
{
    const uint2 pixelPos = uint2(position.xy);
    const uint pixelIndex = pixelPos.y * GetScreenSize().x + pixelPos.x;
    const SSRInput input = LoadSSRInput(pixelPos);
    
    diffuseIrradiance = 0;
    specularIrradiance = 0;
    rayExtendedDepth = 0; // TODO: not implemented
    
    [branch]
    if (!input.IsForeground || input.Gloss < REFLECT_GLOSS_THRESHOLD)
    {
        return;
    }
    
    const bool isMirror = input.Gloss > MIRROR_REFLECTION_THRESHOLD;
    
    [branch]
    if (isMirror) // fast 1rpp path for mirror reflections
    {
        //input.Gloss = 0.95;
        
        float3 reflectDir = reflect(input.RayDirView, input.NormalView);
        
        float2 uvHit;
        float hitConfidence = TraceRayHiZ(uv, input, reflectDir, uvHit);
        
        [branch]
        if (hitConfidence != 0)
        {
            const float3 hitColor = FrameBuffer.SampleLevel(LinearSampler, uvHit, 0).xyz;
            const float3 brdfSpecular = BrdfSpecular(1 - input.Gloss, input.Metalness, input.Color, -input.RayDirView, reflectDir, input.NormalView);
            const float pdf = PdfGGXVNDF(-input.RayDirView, reflectDir, input.NormalView, 1 - input.Gloss);
            specularIrradiance += hitColor * hitConfidence * brdfSpecular / pdf;
        }
    }
    else
    {
        uint randState = asuint(InterleavedGradientNoise(pixelPos)) * RandomSeed;
        const uint raysPerPixel = RaysPerPixel;
        const float contributionPerRay = 1.0 / raysPerPixel;
        
        SobolOwenSampler qrng;
        qrng.Init(FrameIndex * raysPerPixel, uint2(PCG_Rand(randState), PCG_Rand(randState)));
        
        // for filtered sampling
        const float roughness = 1.0 - input.Gloss;
        const float n_dot_v = saturate(dot(input.NormalView, -input.RayDirView));
        const float coneTangent = lerp(0, roughness, n_dot_v * sqrt(roughness));
        
        for (uint i = 0; i < raysPerPixel; i++)
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
                continue;
            }
            
            float2 uvHit;
            float hitConfidence = TraceRayHiZ(uv, input, reflectDir, uvHit);
            
            if (hitConfidence != 0)
            {
                const float intersectionCircleRadius = coneTangent * length(uvHit - uv);
                const float mip = max(log2(intersectionCircleRadius * max(GetScreenSize().x, GetScreenSize().y)), 0);
                
                const float3 hitColor = LoadFrameColor(LinearSampler, uvHit, mip).xyz;
                float3 brdfDiffuse, brdfSpecular;
                Brdf(1 - input.Gloss, input.Metalness, input.Color, -input.RayDirView, reflectDir, input.NormalView, brdfDiffuse, brdfSpecular);
                diffuseIrradiance += hitColor * hitConfidence * brdfDiffuse / pdf * contributionPerRay;
                specularIrradiance += hitColor * hitConfidence * brdfSpecular / pdf * contributionPerRay;
            }
        }
    }
    
    DemodulateRadiance(input.Color, input.NormalView, input.Metalness, 1 - input.Gloss, -input.RayDirView, diffuseIrradiance, specularIrradiance);
}
