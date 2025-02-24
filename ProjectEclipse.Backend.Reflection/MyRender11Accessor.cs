using HarmonyLib;
using ProjectEclipse.Backend.Reflection.Wrappers;
using ProjectEclipse.Common;
using SharpDX.Direct3D11;
using System;
using System.Runtime.CompilerServices;
using VRageMath;

namespace ProjectEclipse.Backend.Reflection
{
    public static class MyRender11Accessor
    {
        public class MyEnvironmentMatrices
        {
            public Vector3D CameraPosition;
            public Matrix ViewAt0;
            public Matrix InvViewAt0;
            public Matrix ViewProjectionAt0;
            public Matrix InvViewProjectionAt0;
            public Matrix Projection;
            public Matrix ProjectionForSkybox;
            public Matrix InvProjection;
            public MatrixD ViewD;
            public MatrixD InvViewD;
            public Matrix OriginalProjection;
            public Matrix OriginalProjectionFar;
            public MatrixD ViewProjectionD;
            public MatrixD InvViewProjectionD;
            public BoundingFrustumD ViewFrustumClippedD;
            public BoundingFrustumD ViewFrustumClippedFarD;
            public float NearClipping;
            public float LargeDistanceFarClipping;
            public float FarClipping;
            public float FovH;
            public float FovV;
            public bool LastUpdateWasSmooth;
        }

        private static readonly Type _MyRender11 = AccessTools.TypeByName("VRageRender.MyRender11");
        private static readonly Type _MyEnvironment = AccessTools.TypeByName("VRageRender.MyEnvironment");
        private static readonly Type _MyEnvironmentMatrices = AccessTools.TypeByName("VRageRender.MyEnvironmentMatrices");
        private static readonly Func<object> _MyRender11_Environment_Getter = _MyRender11.Field("Environment").CreateGenericStaticGetter<object>();
        private static readonly Func<object, object> _MyEnvironment_Matrices_Getter = _MyEnvironment.Field("Matrices").CreateGenericGetter<object, object>();
        //private static readonly Func<int> _MyRender11_GameplayFrameCounter_Getter = _MyRender11.PropertyGetter("GameplayFrameCounter").CreateGenericStaticFunc<int>();
        private static readonly Func<Vector2I> _MyRender11_ViewportResolution_Getter = _MyRender11.PropertyGetter("ViewportResolution").CreateGenericStaticFunc<Vector2I>();
        private static readonly Func<object> _MyRender11_RC_Getter = _MyRender11.PropertyGetter("RC").CreateGenericStaticFunc<object>();
        private static readonly Func<Device1> _MyRender11_DeviceInstance_Getter = _MyRender11.PropertyGetter("DeviceInstance").CreateGenericStaticFunc<Device1>();

        public static MyEnvironmentMatrices GetEnvironmentMatrices()
        {
            var myEnvironmentInstance = _MyRender11_Environment_Getter.Invoke();
            var myEnvironmentMatricesInstance = _MyEnvironment_Matrices_Getter.Invoke(myEnvironmentInstance);
            return Unsafe.As<MyEnvironmentMatrices>(myEnvironmentMatricesInstance);
        }

        //public static int GetGameplayFrameCounter() => _MyRender11_GameplayFrameCounter_Getter.Invoke();
        public static Vector2I GetViewportResolution() => _MyRender11_ViewportResolution_Getter.Invoke();
        public static MyRenderContextWrapper GetRC() => new MyRenderContextWrapper(_MyRender11_RC_Getter.Invoke());
        public static Device1 GetDeviceInstance() => _MyRender11_DeviceInstance_Getter.Invoke();
    }
}
