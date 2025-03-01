﻿using ProjectEclipse.Common.Interfaces;
using SharpDX.Direct3D11;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Buffer = SharpDX.Direct3D11.Buffer;

namespace ProjectEclipse.Common.Impl
{
    internal readonly struct BufferSrvUavImpl : IBufferSrvUav
    {
        public Buffer Buffer { get; }
        public ShaderResourceView Srv { get; }
        public UnorderedAccessView Uav { get; }

        public BufferSrvUavImpl(Device device, BufferDescription bufferDesc)
        {
            Buffer = new Buffer(device, bufferDesc);
            Srv = new ShaderResourceView(device, Buffer);
            Uav = new UnorderedAccessView(device, Buffer);
        }

        public void Dispose()
        {
            Buffer.Dispose();
            Srv.Dispose();
            Uav.Dispose();
        }
    }
}
