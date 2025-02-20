void vs(const uint vertexId : SV_VertexID, out float4 position : SV_Position, out float2 uv : TEXCOORD0)
{
    uv = float2((vertexId << 1) & 2, vertexId & 2);
    position = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
}