# DTX Reader

This will import Lithtech DTX files and allow Godot to read them as textures. 

## Supported Formats

This plugin currently supports DTX versions:
-  Lithtech 1.0     (-2)
-  Lithtech 1.5     (-3)
-  Lithtech 2.0+    (-5)

For Lithtech 2.0+ DTX files, the plugin currently supports loading 8-bit palettized, 32-bit palettized, 32-bit colour, and DXT1/3/5 textures. 

## Usage

The editor plugin included will allow you to import DTX files directly into your project. You can also use `TextureBuilder.gd`'s `build` function to import textures at runtime.

If an unsupported DTX (whether it be version or bytes per pixel) is loaded, an error message will be printed to your console. Feel free to open a ticket with a sample DTX so I can debug the issue when I find the time.

## Installation

Simply drop this into `<GodotProject>/Addons/DTXReader` and enable it from the plugins setting panel.