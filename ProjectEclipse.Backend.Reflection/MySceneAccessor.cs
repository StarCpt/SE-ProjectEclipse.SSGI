using HarmonyLib;
using ProjectEclipse.Common;
using System;

namespace ProjectEclipse.Backend.Reflection
{
    public static class MySceneAccessor
    {
        private static readonly Type _MyScene = AccessTools.TypeByName("VRage.Render.Scene.MyScene");
        private static readonly Func<long> _MySceneFrameCounter_Getter = _MyScene.Field("FrameCounter").CreateGenericStaticGetter<long>();

        public static long GetFrameCounter() => _MySceneFrameCounter_Getter.Invoke();
    }
}
