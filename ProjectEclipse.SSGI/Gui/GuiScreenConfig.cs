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
        private MyGuiControlCheckbox _cEnablePlugin, _cEnableDenoiser, _cEnablePrefiltering, _cEnableRestir, _cTraceFull, _cTraceHalf, _cTraceQuarter;
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
            _sRaysPerPixel = grid.AddIntegerSlider(1, row, _config.Data.TraceRes == SSGIConfig.ConfigData.RtRes.Full, _config.Data.RaysPerPixel, 1, 32, SSGIConfig.ConfigData.Default.RaysPerPixel, true, HorizontalAlignment.Left);
            row++;

            grid.AddLabel(0, row, "Lower Quality RT (Faster)", HorizontalAlignment.Left);
            _cTraceQuarter = grid.AddCheckbox(1, row, true, _config.Data.TraceRes == SSGIConfig.ConfigData.RtRes.Quarter, "0.25 rays per pixel.\nDoesn't work when ReSTIR is off", HorizontalAlignment.Left);
            _cTraceHalf = grid.AddCheckbox(1, row, true, _config.Data.TraceRes == SSGIConfig.ConfigData.RtRes.Half, "0.5 rays per pixel.\nDoesn't work when ReSTIR is off", HorizontalAlignment.Left);
            _cTraceFull = grid.AddCheckbox(1, row, true, _config.Data.TraceRes == SSGIConfig.ConfigData.RtRes.Full, "Use RPP slider value", HorizontalAlignment.Left);
            var labelTraceQuarter = grid.AddLabel(1, row, "Quarter", HorizontalAlignment.Left);
            var labelTraceHalf = grid.AddLabel(1, row, "Half", HorizontalAlignment.Left);
            var labelTraceFull = grid.AddLabel(1, row, "Full", HorizontalAlignment.Left);
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

            labelTraceQuarter.OriginAlign = MyGuiDrawAlignEnum.HORISONTAL_RIGHT_AND_VERTICAL_CENTER;
            labelTraceHalf.OriginAlign    = MyGuiDrawAlignEnum.HORISONTAL_RIGHT_AND_VERTICAL_CENTER;
            labelTraceFull.OriginAlign    = MyGuiDrawAlignEnum.HORISONTAL_RIGHT_AND_VERTICAL_CENTER;
            
            labelTraceQuarter.PositionX += columnWidth / 3.7f * 0 + 0.055f - 0.005f;
            labelTraceHalf.PositionX    += columnWidth / 3.7f * 1 + 0.055f - 0.005f;
            labelTraceFull.PositionX    += columnWidth / 3.7f * 2 + 0.055f - 0.005f;
            _cTraceQuarter.PositionX    += columnWidth / 3.7f * 0 + 0.055f;
            _cTraceHalf.PositionX       += columnWidth / 3.7f * 1 + 0.055f;
            _cTraceFull.PositionX       += columnWidth / 3.7f * 2 + 0.055f;

            _cTraceQuarter.IsCheckedChanged += OnTraceResCheckboxChanged;
            _cTraceHalf.IsCheckedChanged += OnTraceResCheckboxChanged;
            _cTraceFull.IsCheckedChanged += OnTraceResCheckboxChanged;

            void OnTraceResCheckboxChanged(MyGuiControlCheckbox checkbox)
            {
                if (checkbox.IsChecked)
                {
                    _cTraceQuarter.IsChecked = checkbox == _cTraceQuarter;
                    _cTraceHalf.IsChecked = checkbox == _cTraceHalf;
                    _cTraceFull.IsChecked = checkbox == _cTraceFull;

                    _sRaysPerPixel.Enabled = checkbox == _cTraceFull;
                }
                else if (!_cTraceQuarter.IsChecked && !_cTraceHalf.IsChecked && !_cTraceFull.IsChecked)
                {
                    checkbox.IsChecked = true;
                }
            }

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

            _cTraceQuarter.IsChecked = SSGIConfig.ConfigData.Default.TraceRes == SSGIConfig.ConfigData.RtRes.Quarter;
            _cTraceHalf.IsChecked = SSGIConfig.ConfigData.Default.TraceRes == SSGIConfig.ConfigData.RtRes.Half;
            _cTraceFull.IsChecked = SSGIConfig.ConfigData.Default.TraceRes == SSGIConfig.ConfigData.RtRes.Full;

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

            if (_cTraceQuarter.IsChecked) _config.Data.TraceRes = SSGIConfig.ConfigData.RtRes.Quarter;
            if (_cTraceHalf.IsChecked) _config.Data.TraceRes = SSGIConfig.ConfigData.RtRes.Half;
            if (_cTraceFull.IsChecked) _config.Data.TraceRes = SSGIConfig.ConfigData.RtRes.Full;

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
