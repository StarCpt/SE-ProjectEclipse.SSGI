using Newtonsoft.Json;
using System;
using System.IO;
using VRage.Utils;
using VRageMath;

namespace ProjectEclipse.SSGI.Config
{
    public class SSGIConfig
    {
        public struct ConfigData
        {
            public bool Enabled { get; set; }
            public int MaxTraceIterations
            {
                get => _maxTraceIterations;
                set => _maxTraceIterations = MathHelper.Clamp(value, 10, 200);
            }
            public int RaysPerPixel
            {
                get => _raysPerPixel;
                set => _raysPerPixel = MathHelper.Clamp(value, 1, 32);
            }
            public bool EnableInputPrefiltering { get; set; }
            public bool UseGaussianPrefiltering { get; set; }
            public float IndirectLightMulti
            {
                get => _indirectLightMulti;
                set => _indirectLightMulti = MathHelper.Clamp(value, 0, 10);
            }
            public bool Restir_Enabled { get; set; }
            //public int Restir_Temporal_MaxHistory { get; set; }
            //public int Restir_Spatial_ReuseCount { get; set; }
            //public float Restir_Spatial_ReuseRadiusMultiplier { get; set; }
            public bool Svgf_Enabled { get; set; }
            public float Svgf_DiffuseTemporalWeight
            {
                get => _svgf_DiffuseTemporalWeight;
                set => _svgf_DiffuseTemporalWeight = MathHelper.Clamp(value, 0, 1);
            }
            public float Svgf_SpecularTemporalWeight
            {
                get => _svgf_SpecularTemporalWeight;
                set => _svgf_SpecularTemporalWeight = MathHelper.Clamp(value, 0, 1);
            }
            public int Svgf_DiffuseAtrousIterations
            {
                get => _svgf_DiffuseAtrousIterations;
                set => _svgf_DiffuseAtrousIterations = MathHelper.Clamp(value, 0, 10);
            }
            public int Svgf_SpecularAtrousIterations
            {
                get => _svgf_SpecularAtrousIterations;
                set => _svgf_SpecularAtrousIterations = MathHelper.Clamp(value, 0, 10);
            }

            private int _maxTraceIterations;
            private int _raysPerPixel;
            private float _indirectLightMulti;
            private float _svgf_DiffuseTemporalWeight;
            private float _svgf_SpecularTemporalWeight;
            private int _svgf_DiffuseAtrousIterations;
            private int _svgf_SpecularAtrousIterations;

            public static ConfigData Default { get; } = new ConfigData
            {
                Enabled = true,
                MaxTraceIterations = 80,
                RaysPerPixel = 1,
                EnableInputPrefiltering = true,
                UseGaussianPrefiltering = false,
                IndirectLightMulti = 1.0f,
                Restir_Enabled = true,
                //Restir_Temporal_MaxHistory = 20,
                //Restir_Spatial_ReuseCount = 4,
                //Restir_Spatial_ReuseRadiusMultiplier = 1.0f,
                Svgf_Enabled = true,
                Svgf_DiffuseTemporalWeight = 0.95f,
                Svgf_SpecularTemporalWeight = 0.95f,
                Svgf_DiffuseAtrousIterations = 4,
                Svgf_SpecularAtrousIterations = 3,
            };

            public ConfigData Validate()
            {
                return new ConfigData
                {
                    Enabled = Enabled,
                    MaxTraceIterations = MaxTraceIterations,
                    RaysPerPixel = RaysPerPixel,
                    EnableInputPrefiltering = EnableInputPrefiltering,
                    UseGaussianPrefiltering = UseGaussianPrefiltering,
                    IndirectLightMulti = IndirectLightMulti,
                    Restir_Enabled = Restir_Enabled,
                    Svgf_Enabled = Svgf_Enabled,
                    Svgf_DiffuseTemporalWeight = Svgf_DiffuseTemporalWeight,
                    Svgf_SpecularTemporalWeight = Svgf_SpecularTemporalWeight,
                    Svgf_DiffuseAtrousIterations = Svgf_DiffuseAtrousIterations,
                    Svgf_SpecularAtrousIterations = Svgf_SpecularAtrousIterations,
                };
            }
        }

        public ref ConfigData Data => ref _data;

        private ConfigData _data;

        private readonly string _filePath;

        public SSGIConfig(string filePath)
        {
            _filePath = filePath;

            InitDefault();
            Load();
        }

        public void Load()
        {
            if (!File.Exists(_filePath))
            {
                MyLog.Default.Info($"{nameof(SSGIConfig)}: Config not found, initializing default values. path={_filePath}.");
                InitDefault();
                Save();
                return;
            }

            try
            {
                JsonSerializer serializer = new JsonSerializer();
                using (var sr = new StreamReader(_filePath))
                using (var jr = new JsonTextReader(sr))
                {
                    Data = serializer.Deserialize<ConfigData>(jr);
                }
                Validate();
            }
            catch (Exception e)
            {
                MyLog.Default.Info($"{nameof(SSGIConfig)}: Could not load config, initializing default values. path={_filePath}, {e}");
                InitDefault();
            }
        }

        private void Validate()
        {
            _data = _data.Validate();
        }

        public void Save()
        {
            try
            {
                JsonSerializer serializer = new JsonSerializer
                {
                    Formatting = Formatting.Indented,
                };

                Directory.CreateDirectory(Path.GetDirectoryName(_filePath));

                using (var sw = new StreamWriter(_filePath, false))
                {
                    serializer.Serialize(sw, Data);
                }
            }
            catch (Exception e)
            {
                MyLog.Default.Info($"{nameof(SSGIConfig)}: Could not save config. {e}");
            }
        }

        public void InitDefault()
        {
            _data = ConfigData.Default;
        }
    }
}
