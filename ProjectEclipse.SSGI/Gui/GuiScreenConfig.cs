using ProjectEclipse.SSGI.Config;
using ProjectEclipse.SSGI.Gui.Controls;
using Sandbox;
using Sandbox.Graphics.GUI;
using System;
using VRage.Utils;
using VRageMath;

namespace ProjectEclipse.SSGI.Gui
{
    public class GuiScreenConfig : MyGuiScreenBase
    {
        private MyGuiControlCheckbox _cEnablePlugin, _cEnableDenoiser, _cEnablePrefiltering, _cEnableRestir;
        private MyGuiControlSlider _sMaxTraceIterations, _sRaysPerPixel, _sIndirectLightMulti, _sDiffuseTemporalWeight, _sSpecularTemporalWeight, _sDiffuseAtrousIterations, _sSpecularAtrousIterations;

        private readonly SSGIConfig _config;

        public GuiScreenConfig(SSGIConfig config)
            : base(new Vector2(0.5f), MyGuiConstants.SCREEN_BACKGROUND_COLOR, new Vector2(0.6f, 0.7f), false, null, MySandboxGame.Config.UIBkOpacity, MySandboxGame.Config.UIOpacity)
        {
            _config = config;

            EnabledBackgroundFade = true;
            m_closeOnEsc = true;
            m_drawEvenWithoutFocus = true;
            CanHideOthers = true;
            CanBeHidden = true;
            CloseButtonEnabled = true;
        }

        public override string GetFriendlyName()
        {
            return typeof(GuiScreenConfig).FullName;
        }

        public override void LoadContent()
        {
            base.LoadContent();
            RecreateControls(false);
        }

        public override void RecreateControls(bool constructor)
        {
            base.RecreateControls(constructor);

            const float columnWidth = 0.27f;
            const float rowHeight = 0.05f;

            var grid = new UniformGrid
            {
                MinColumns = 2,
                MinRows = 1,
                ColumnWidth = columnWidth,
                RowHeight = rowHeight,
            };

            int row = 0;

            grid.AddLabel(0, row, "Enable Plugin", HorizontalAlignment.Left);
            _cEnablePlugin = grid.AddCheckbox(1, row, true, _config.Data.Enabled, null, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Max Ray March Steps", HorizontalAlignment.Left);
            _sMaxTraceIterations = grid.AddIntegerSlider(1, row, true, _config.Data.MaxTraceIterations, 10, 200, SSGIConfig.ConfigData.Default.MaxTraceIterations, true, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Rays Per Pixel", HorizontalAlignment.Left);
            _sRaysPerPixel = grid.AddIntegerSlider(1, row, true, _config.Data.RaysPerPixel, 1, 32, SSGIConfig.ConfigData.Default.RaysPerPixel, true, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Prefilter Input Frame", HorizontalAlignment.Left);
            _cEnablePrefiltering = grid.AddCheckbox(1, row, true, _config.Data.EnableInputPrefiltering, null, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Indirect Light Multiplier", HorizontalAlignment.Left);
            _sIndirectLightMulti = grid.AddFloatSlider(1, row, true, _config.Data.IndirectLightMulti, 0, 10, SSGIConfig.ConfigData.Default.IndirectLightMulti, true, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Use ReSTIR GI", HorizontalAlignment.Left);
            _cEnableRestir = grid.AddCheckbox(1, row, true, _config.Data.Restir_Enabled, null, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Use Denoiser", HorizontalAlignment.Left);
            _cEnableDenoiser = grid.AddCheckbox(1, row, true, _config.Data.Svgf_Enabled, null, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Denoiser Diffuse Temporal Weight", HorizontalAlignment.Left);
            _sDiffuseTemporalWeight = grid.AddFloatSlider(1, row, true, _config.Data.Svgf_DiffuseTemporalWeight, 0, 1, SSGIConfig.ConfigData.Default.Svgf_DiffuseTemporalWeight, true, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Denoiser Specular Temporal Weight", HorizontalAlignment.Left);
            _sSpecularTemporalWeight = grid.AddFloatSlider(1, row, true, _config.Data.Svgf_SpecularTemporalWeight, 0, 1, SSGIConfig.ConfigData.Default.Svgf_SpecularTemporalWeight, true, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Denoiser Diffuse Atrous Iterations", HorizontalAlignment.Left);
            _sDiffuseAtrousIterations = grid.AddIntegerSlider(1, row, true, _config.Data.Svgf_DiffuseAtrousIterations, 0, 10, SSGIConfig.ConfigData.Default.Svgf_DiffuseAtrousIterations, true, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Denoiser Specular Atrous Iterations", HorizontalAlignment.Left);
            _sSpecularAtrousIterations = grid.AddIntegerSlider(1, row, true, _config.Data.Svgf_SpecularAtrousIterations, 0, 10, SSGIConfig.ConfigData.Default.Svgf_SpecularAtrousIterations, true, HorizontalAlignment.Left);
            row++;

            this.Size = new Vector2(0.6f, (rowHeight * row) + 0.2f);

            grid.AddControlsToScreen(this, new Vector2(0f, -0.01f), false);

            AddCaption("SSGI Config");
            AddFooterButtons(new FooterButtonDesc("Save", OnSaveButtonClick), new FooterButtonDesc("Default", OnDefaultButtonClick));
        }

        private struct FooterButtonDesc
        {
            public string Text;
            public Action<MyGuiControlButton> OnButtonClick;

            public FooterButtonDesc(string text, Action<MyGuiControlButton> onButtonClick)
            {
                Text = text;
                OnButtonClick = onButtonClick;
            }
        }

        private void AddFooterButtons(params FooterButtonDesc[] descs)
        {
            float yPos = (Size.Value.Y * 0.5f) - (MyGuiConstants.SCREEN_CAPTION_DELTA_Y / 2f);
            float xInterval = 0.22f;
            float firstButtonPosX = -((descs.Length - 1.0f) * xInterval) * 0.5f;
            for (int i = 0; i < descs.Length; i++)
            {
                FooterButtonDesc desc = descs[i];
                float xPos = firstButtonPosX + (xInterval * i);
                var button = new MyGuiControlButton(onButtonClick: desc.OnButtonClick)
                {
                    Position = new Vector2(xPos, yPos),
                    Text = desc.Text,
                    OriginAlign = MyGuiDrawAlignEnum.HORISONTAL_CENTER_AND_VERTICAL_BOTTOM,
                };

                Controls.Add(button);
            }
        }

        private void OnDefaultButtonClick(MyGuiControlButton btn)
        {
            _cEnablePlugin.IsChecked = SSGIConfig.ConfigData.Default.Enabled;
            _sMaxTraceIterations.Value = SSGIConfig.ConfigData.Default.MaxTraceIterations;
            _sRaysPerPixel.Value = SSGIConfig.ConfigData.Default.RaysPerPixel;
            _cEnablePrefiltering.IsChecked = SSGIConfig.ConfigData.Default.EnableInputPrefiltering;
            _sIndirectLightMulti.Value = SSGIConfig.ConfigData.Default.IndirectLightMulti;
            _cEnableRestir.IsChecked = SSGIConfig.ConfigData.Default.Restir_Enabled;
            _cEnableDenoiser.IsChecked = SSGIConfig.ConfigData.Default.Svgf_Enabled;
            _sDiffuseTemporalWeight.Value = SSGIConfig.ConfigData.Default.Svgf_DiffuseTemporalWeight;
            _sSpecularTemporalWeight.Value = SSGIConfig.ConfigData.Default.Svgf_SpecularTemporalWeight;
            _sDiffuseAtrousIterations.Value = SSGIConfig.ConfigData.Default.Svgf_DiffuseAtrousIterations;
            _sSpecularAtrousIterations.Value = SSGIConfig.ConfigData.Default.Svgf_SpecularAtrousIterations;
        }

        private void OnSaveButtonClick(MyGuiControlButton btn)
        {
            _config.Data.Enabled = _cEnablePlugin.IsChecked;
            _config.Data.MaxTraceIterations = (int)_sMaxTraceIterations.Value;
            _config.Data.RaysPerPixel = (int)_sRaysPerPixel.Value;
            _config.Data.EnableInputPrefiltering = _cEnablePrefiltering.IsChecked;
            _config.Data.IndirectLightMulti = _sIndirectLightMulti.Value;
            _config.Data.Restir_Enabled = _cEnableRestir.IsChecked;
            _config.Data.Svgf_Enabled = _cEnableDenoiser.IsChecked;
            _config.Data.Svgf_DiffuseTemporalWeight = _sDiffuseTemporalWeight.Value;
            _config.Data.Svgf_SpecularTemporalWeight = _sSpecularTemporalWeight.Value;
            _config.Data.Svgf_DiffuseAtrousIterations = (int)_sDiffuseAtrousIterations.Value;
            _config.Data.Svgf_SpecularAtrousIterations = (int)_sSpecularAtrousIterations.Value;

            _config.Save();
        }
    }
}
