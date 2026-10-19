# Art sources

Blender sources (`.blend`) live here and are stored in Git LFS (see
`.gitattributes`; run `git lfs install` once). Export each model as glTF
binary (`.glb`) into `assets/`, where Godot imports it with LODs generated
(the `[importer_defaults]` in `project.godot`). `tests/test_assets.gd` fails
if a model in `assets/` imports without LODs.

The two container models in `assets/` are made by `tools/make_containers.gd`
until the art pass replaces them with modelled ones.
