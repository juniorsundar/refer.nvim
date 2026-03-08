# Changelog

## [0.4.0](https://github.com/juniorsundar/refer.nvim/compare/v0.3.0...v0.4.0) (2026-03-08)


### Features

* Extension API to register custom :Refer commands ([07aa02a](https://github.com/juniorsundar/refer.nvim/commit/07aa02a95d7f6a7b3f11762464ef4efb35f7bb99))
* **keymaps:** Add descriptions to keymaps ([ded0ab3](https://github.com/juniorsundar/refer.nvim/commit/ded0ab3719d95c610ccf66944d95831a3ff626cf))
* **macros:** Macro editor with real-time preview ([aa45e92](https://github.com/juniorsundar/refer.nvim/commit/aa45e92ecab0e5b632744151a0e547f67ee66bf7))


### Bug Fixes

* **macros:** Robustness. Some edge cases with folds. ([eb9aa91](https://github.com/juniorsundar/refer.nvim/commit/eb9aa91b850e622697e8a0b5e91d83ad37a717ef))


### Documentation

* Add video for live Macro Editing + Preview ([725d253](https://github.com/juniorsundar/refer.nvim/commit/725d253b2efc25a7897e749735f5383ad4a8ba57))


### Code Refactoring

* **builtin:** Distribute due to heavy lua file ([1a8b689](https://github.com/juniorsundar/refer.nvim/commit/1a8b689ea341c280d535bac7a66367f491ecaa1e))

## [0.3.0](https://github.com/juniorsundar/refer.nvim/compare/v0.2.0...v0.3.0) (2026-02-24)


### Features

* **commands:** Live preview of substitution cmd ([b95e42e](https://github.com/juniorsundar/refer.nvim/commit/b95e42e72450483dc6bc5b279ecea1b832de033b))
* **files:** path-aware search w/ fd --full-path ([9e4268b](https://github.com/juniorsundar/refer.nvim/commit/9e4268b31cd4397949c59308465df284b8c544b5))
* **health:** `checkhealth refer` to get healtcheck ([75c6978](https://github.com/juniorsundar/refer.nvim/commit/75c6978f6f3ebc40b8062ddd3846b147f47b6c38))

## [0.2.0](https://github.com/juniorsundar/refer.nvim/compare/v0.1.0...v0.2.0) (2026-02-21)


### Features

* **LSP:** Toggle LSP clients ([22f0e60](https://github.com/juniorsundar/refer.nvim/commit/22f0e60a31ee1c1ea6296bfa72c97468cf2e0553))
* **providers:** Search selection (visual/cword) ([d27e698](https://github.com/juniorsundar/refer.nvim/commit/d27e698cbced8211ba378e66fea1fa37aeeb4237))
* **ui:** Input can be "top"/"bottom" of Results ([b7b729b](https://github.com/juniorsundar/refer.nvim/commit/b7b729bacd5ea2acaf7bd8583f1a45d184174b93))
* **ui:** Results can be reversed (top&lt;-&gt;bottom) ([d40f912](https://github.com/juniorsundar/refer.nvim/commit/d40f9126f444c860faef9af267288ccf5f924d29))


### Bug Fixes

* **completion:** Issue with range marks. ([8035f65](https://github.com/juniorsundar/refer.nvim/commit/8035f658abb89a80f6faded4297eb39e009b43e9))
* **completion:** Overlap in path completion ([2aa7cc0](https://github.com/juniorsundar/refer.nvim/commit/2aa7cc0596bb5a10c92f6ca5f50efd8a8b1a4853))
* Return focus to original window on close ([9817057](https://github.com/juniorsundar/refer.nvim/commit/98170578de45dcdb506777f06a4ef58d8eabafed))


### Documentation

* Update README with Refer Selection ([d9c1585](https://github.com/juniorsundar/refer.nvim/commit/d9c15852337e81bdda9414bfbcaff0e5088211e8))

## [0.1.0](https://github.com/juniorsundar/refer.nvim/compare/v0.1.0...v0.1.0) (2026-02-14)


### chore

* release 0.1.0 ([5653585](https://github.com/juniorsundar/refer.nvim/commit/5653585d4d74dc7b1d4c2618c5bb17156ecdf4a7))


### Features

* `Refer Commands` supports ranges now ([4f33be8](https://github.com/juniorsundar/refer.nvim/commit/4f33be872cafb166cf9dff691b282f0050d3a7c9))
* BYOF ([798ec03](https://github.com/juniorsundar/refer.nvim/commit/798ec03b5db3e11e389199320ac8dd562c59bc9d))
* Create async picker ([130c264](https://github.com/juniorsundar/refer.nvim/commit/130c264ca023921e93d6f0d539b968702743b829))
* Custom parsers ([422514d](https://github.com/juniorsundar/refer.nvim/commit/422514dfb36bffb7624640c39bd1725a2160d9c9))
* Enable/Disable preview option ([2971a6d](https://github.com/juniorsundar/refer.nvim/commit/2971a6db49684b0967ac2fffcc424bef64205aa8))
* Expose features for setup call ([b51c062](https://github.com/juniorsundar/refer.nvim/commit/b51c0624e05f333e993e0010dc961f79a7101029))
* Implement Implementations+Declarations picker ([2204def](https://github.com/juniorsundar/refer.nvim/commit/2204def2ffa91ea60336a8b3e2709c2e2b35e2a3))
* Scroll preview with C-u/C-d ([8312a78](https://github.com/juniorsundar/refer.nvim/commit/8312a78d3355dd52ad6efb2234f73de7e68abdb1))
* Select/Deselect all default actions ([5fdfbfc](https://github.com/juniorsundar/refer.nvim/commit/5fdfbfc12444c7f0913648a2843f9ef41d290428))
* vim.ui.select override ([0e173e5](https://github.com/juniorsundar/refer.nvim/commit/0e173e5515cea9e5da6eec7c41dc5acc07db5f46))


### Bug Fixes

* fd/fdfind compatibility + sub fd-&gt;find rg-&gt;grep ([372b2f9](https://github.com/juniorsundar/refer.nvim/commit/372b2f9f9bb266f9b3d42aad018febd311c65722))
* Send to quickfix formatting ([b49cced](https://github.com/juniorsundar/refer.nvim/commit/b49cced758306c06612ab57a5f42ca2cde146bce))


### Documentation

* Add screenshots ([cda1154](https://github.com/juniorsundar/refer.nvim/commit/cda11547e75d8113eefbb1b975ded1089472af5d))
* Example to create custom pickers ([8708720](https://github.com/juniorsundar/refer.nvim/commit/8708720175c45eec5aa3fcc2bdeefef3f8e51bd5))
* Selective previews ([a0689c7](https://github.com/juniorsundar/refer.nvim/commit/a0689c73607c201dfd3c4f5040e091e245a9a01b))
* Show how to enable previews for custom cases ([2b461aa](https://github.com/juniorsundar/refer.nvim/commit/2b461aa1158b85319147726181cfe7122cc61dcc))
* Update keymaps for scrolling preview ([a235270](https://github.com/juniorsundar/refer.nvim/commit/a235270fbbaa31af421a5fb0b0c0f372ff28330b))


### Code Refactoring

* Actions into separate file ([3bb6061](https://github.com/juniorsundar/refer.nvim/commit/3bb6061394ecbfee00ab62d34d086dae17dd00a7))
* LSP functions ([eb024a9](https://github.com/juniorsundar/refer.nvim/commit/eb024a9f0e51affc88339bc3e1d24c2a8a4ebc32))
