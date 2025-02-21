# SE-ProjectEclipse.SSGI

Plugin for Space Engineers that adds single-bounce screen space global illumination.
This is a work-in-progress meaning it doesn't look anywhere near marketable currently.
It might be usable for taking screenshots when used in a static scene.

#### How to install:  
1. Clone the repo on your computer.
2. Go to the root directory (where the .sln file is), click on the address bar, type cmd and press enter.
3. Run the following command: mklink /J Bin64 \<insert game bin64 path in double quotes here\>  
for example: mklink /J Bin64 "C:\Program Files (x86)\Steam\steamapps\common\SpaceEngineers\Bin64"  
There should now be folder with a shortcut-looking icon called Bin64 in the root directory that leads to the game's bin64 folder where SpaceEngineers.exe is.
4. Open the solution and build solution. (Build > Build Solution)
5. Copy the resulting files in ProjectEclipse.SSGI/bin/Debug/net48 to Bin64/Plugins/Local/SSGI. Create the folder if it doesn't exist already.
6. Copy files and folders in ProjectEclipse.SSGI/Shaders/ to SpaceEngineers(where bin64 is)/Content/Shaders/ProjectEclipse/
7. Launch the game, search ProjectEclipse.SSGI in the plugin browser and enable it.
8. Restart the game when prompted.

#### Installation using precompiled files:  
1. Download ssgi-plugin.zip in the latest release
2. Extract the zip using WinRAR or 7-zip so the files aren't blocked (otherwise you will have to unblock each file in file's properties)
3. Copy the files in the extracted folder other than the ones in Shaders/ to SpaceEngineers/Bin64/Plugins/Local/SSGI
4. Copy everything in the Shaders folder to SpaceEngineers/Content/Shaders/ProjectEclipse/
5. Launch the game, search ProjectEclipse.SSGI in the plugin browser and enable it.
6. Restart the game when prompted.

#### Settings:
- Max Ray March Steps: Leave at default value
- Rays Per Pixel: Higher = Slower but more stable lighting
- Indirect Light Multiplier: Higher = makes SSGI brighter
- Use Denoiser/denoiser settings: Use default values unless you're just exploring

#### Things to fix:
- Does not work when the lit surface is moving
- Causes specular reflection ghosting when the camera moves
- Lighting on voxels look noticeably bad when the LOD changes
