Decompiled version of LithTools by HeyThereCoffeee

- primarily fixed is the NOLF PS2 stuff like Level, Model and Texture viewing  
- LTA exporting of levels PC and PS2, works best with NOLF1
- viewing of Models in ABC/LTB/LTB ABC/LTB D3D format (tested with Blood2, NOLF1, NOLF2, Die Hard Nakatomi Plaza)  
- viewing of Levels DAT and LTB format (Blood2, Die Hard, NOLF1 PS2, NOLF1 PC, NOLF2)
- skipping lightmap reading stuff since it's not used by Godot, which makes it very fast in loading and saving LTA

Set up folder containing textures (tex folder) in settings.cfg in LTDatReader root folder.

Setting export_to_lta_on_load =true exports the level to an LTA level file (NOLF1 format), now via Menu.
<img width="383" height="232" alt="grafik" src="https://github.com/user-attachments/assets/730379ed-23ae-4507-83c6-1d99b06797a6" />

Texture viewer is  tested for BBP_8P, BPP_32 and BPP_32P textures. Needs verification for other types.

Use >= Godot_v3.6.2-stable_win64.exe with this project

# Lithtech versions
```text
Lithtech 1.0 (DAT v56), uses DTX v1, ABCv6
    Shogo: Mobile Armor Division
    Blood II: The Chosen

Lithtech 1.0 (DAT v57), uses DTX v1, ABCv6
    TNN Outdoors Pro Hunter 2
    Sanity: Aiken's Artifact (had some Lithtech 2.0 enhancements)

Custom 1.5 (DAT v127), uses DTX v1.5, ABCv6
    KISS: Psycho Circus: The Nightmare Child

Lithtech 1.5 (DAT v66), uses DTX v2, ABCv13
The engine is 1.5 but textures and levels are packed as LithTech 2x resources
    Might and Magic IX

Lithtech 2.x (DAT v66), uses DTX v2
    The Operative: No One Lives Forever ABCv12
    Legends of Might and Magic, ABCv13
    Die Hard: Nakatomi Plaza, LTB ABC and LTB D3D

Lithtech PS2 (LTB v66), uses DTX v2 (mainly BPP_32P), LTB V16
    The Operative: No One Lives Forever (PS2)

Lithtech Talon (DAT v70), uses DTX v2, ABCv12
    Aliens versus Predator 2

Lithtech Jupiter (DAT v85), uses DTX v2, LTB Models
    No One Lives Forever 2: A Spy In H.A.R.M.'s Way
    Contract J.A.C.K.
    Tron 2.0
```


