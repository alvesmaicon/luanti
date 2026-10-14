# Roadmap of the handheld branch

What is left on `handheld/5.17`, and what was already found out on the way, so none of it needs investigating again. State on 2026-10-14, after `5.17.0-handheld.1`.

## Next release: 5.17.0-handheld.2

- Settings open on a Video page with the render distance in chunks (eae1c6698). Builtin Lua only.
- Then whatever the next round of play testing brings: the testers' reports drive this list.
- Releasing: goodluckOS raises `-DVERSION_EXTRA` (in `package/luanti/luanti.mk`), builds, and the fork commit the binary came from gets an annotated tag `5.17.0-handheld.N` saying in a few lines what it brings.

## Known problems

- Luanti exits with SIGSEGV every time on the handheld (seen on 2026-10-12, with Mesa's stock lima too). Not investigated yet.
- The on-screen keyboard is tested on the world name and the creative inventory's search; signs, books (textarea), settings fields and password boxes are still to test.
- The keyboard's header shows the text with `_` at the end, not where the caret is.
- A formspec dropdown shows at most five rows (`CGUIComboBox`'s `MaxSelectionRows`), so the render distance has five choices.

## Engine work in this fork

- [#8](https://github.com/alvesmaicon/luanti/issues/8): waving leaves keep their inner faces when waving is off (72 % of a forest's vertices). Fix it in the engine; goodluckOS's `goodluck_solid_leaves` mod can go then.
- [#1](https://github.com/alvesmaicon/luanti/issues/1): per-vertex fog gained nothing measurable. Drop it at the 5.18 rebase unless a measurement says otherwise.
- LuaJIT is off. Buildroot's luajit needs a host compiler with the target's word size (32 bits), which an Apple M1 can't run (no AArch32); an x86 Linux host with multilib can.
- Measured and parked (numbers in the commit messages):
  - After the simplified far meshes, the lake view is still bound by vertex work on the GPU. The levers left: fewer bytes per vertex (the nodes shader passes 6 varyings, 4 of them highp, and lima writes 80-96 B per vertex per draw) and software occlusion for open terrain (a 96x72 depth map needs 4x4 rays per texel to be safe, ~14 ms per frame on the A33: too slow as it is).
  - Culling faces by direction: a loss on lima, which shades the whole vertex range of each draw.
  - Capping Mesa lima's BO cache: costs 10-15 % FPS, and one GPU hang at 128 MB. Rejected.
  - Freeing the CPU copy of a mesh after the upload: it removes what lets expired GPU buffers come back without meshing again. Only if memory gets short again.

## Upstream

Luanti's [AI policy](../developing/ai_policy.md) doesn't take substantial AI-written code, and issue and PR text has to be written by the person. So only the small fixes can go upstream, written up by the owner, with the AI use disclosed.

- [#2](https://github.com/alvesmaicon/luanti/issues/2), GLES 2.0 menus without text: very likely the cause of upstream issue 15447 (Amazon Fire, Mali-450, open since 2024-11, a core developer said it couldn't be fixed). The best first contribution.
- [#3](https://github.com/alvesmaicon/luanti/issues/3) UCS-4, [#4](https://github.com/alvesmaicon/luanti/issues/4) fixed-size formspecs, [#6](https://github.com/alvesmaicon/luanti/issues/6) mediump fog, [#7](https://github.com/alvesmaicon/luanti/issues/7) blocks starved below 5 FPS: small, each with its measurement in the commit.
- [#5](https://github.com/alvesmaicon/luanti/issues/5), index buffers: upstream fixed it on its own (PR 17637, merged 2026-10-10). Our commit goes away at the 5.18 rebase.
- Far meshes: upstream has an open PR for mapblock mesh LOD (16594, open since 2025-10, backed by a core developer, stalled on the design of a general LOD system). Our numbers (lake 1.52 M to 0.53 M vertices) could help there, in the owner's words.
- Pace, measured on 2026-10-13: merged PRs take 4 days at the median (75 % within 14 days, 90 % within 29). Small fixes move fast, big features stall.
- Never write upstream references as `owner/repo#N` in this fork: GitHub would link them.

## CI

- `.github/workflows/handheld.yml`: the handheld's build (goodluckOS's CMake options, Cortex-A7 flags) cross-compiled for armhf in Debian trixie, installed as on the console, then `--run-unittests` under qemu-arm (347 tests, about 30 s). One difference is left: Debian's armhf has a 64-bit `time_t`, the console's Buildroot a 32-bit one. Docker's `::1 localhost` line is dropped before the tests, since the console has none and `TestAddress` fails with it.
- Upstream's workflows kept on the fork: linux (ASan, the multiplayer tests, and a singleplayer run with `ogles2` under Xvfb), lua (luacheck, busted), cpp_lint, and the whitespace and PNG checks. Turned off: android, macos, windows, docker_image (it would publish an image for every tag) and lua_api_deploy.
- Next: the main menu with `menu_handheld` at 640x480 under Xvfb with GLES 2.0, its screenshot kept as an artifact, so the handheld's menus can be seen without a console.

## Rebase on 5.18

When 5.18.0 is tagged: a new branch `handheld/5.18` from the tag, this branch's commits cherry-picked, the index-buffer commit dropped (upstream has it) and #1 decided. Measure the forest and the lake again. goodluckOS then moves `LUANTI_VERSION`, regenerates its patches and starts over at `5.18.0-handheld.1`.
