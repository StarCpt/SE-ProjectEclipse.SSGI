using SharpDX.Direct3D;
using SharpDX.Direct3D11;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace ProjectEclipse.Common.Interfaces
{
    public interface IShaderCompiler
    {
        VertexShader CompileVertex(Device device, string id, string entryPoint);
        PixelShader CompilePixel(Device device, string id, string entryPoint);
        ComputeShader CompileCompute(Device device, string id, string entryPoint);

        VertexShader CompileVertex(Device device, string id, string entryPoint, params ShaderMacro[] defines);
        PixelShader CompilePixel(Device device, string id, string entryPoint, params ShaderMacro[] defines);
        ComputeShader CompileCompute(Device device, string id, string entryPoint, params ShaderMacro[] defines);
    }
}
